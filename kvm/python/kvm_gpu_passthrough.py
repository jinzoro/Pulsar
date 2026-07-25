"""
SPDX-License-Identifier: MIT
GPU detection, IOMMU, VFIO binding, and passthrough.

Provides ``GPUPassthrough`` for detecting GPUs, managing VFIO drivers,
and attaching a GPU to a KVM domain via libvirt ``hostdev`` elements.
"""

from __future__ import annotations

import glob
import logging
import os
import re
import subprocess
from typing import Any

import libvirt

from kvm_libvirt_client import LibvirtClient, LibvirtError, _wrap_libvirt_error

logger = logging.getLogger(__name__)


class GPUError(Exception):
    """Raised when a GPU passthrough operation fails."""


class GPUPassthrough:
    """GPU passthrough management for KVM virtual machines.

    Example::

        gpu = GPUPassthrough()
        gpus = gpu.detect_gpus()
        gpu.bind_vfio(gpus[0]["pci"])
        gpu.assign_to_domain("my-vm", gpus[0]["pci"])
    """

    SYSFS_PCI = "/sys/bus/pci"

    # ------------------------------------------------------------------
    # Detection
    # ------------------------------------------------------------------

    def detect_gpus(self) -> list[dict[str, Any]]:
        """Enumerate all GPUs on the host via lspci.

        Returns:
            List of dicts with ``pci``, ``vendor``, ``device``,
            ``driver``, ``iommu_group``, ``vfio_bound``.
        """
        result = subprocess.run(
            ["lspci", "-nn", "-D", "-d", "0300:", "-d", "0302:"],
            capture_output=True, text=True, check=False,
        )
        gpus: list[dict[str, Any]] = []
        for line in result.stdout.splitlines():
            parts = line.split(None, 2)
            if not parts:
                continue
            pci = parts[0]
            device_info = parts[2] if len(parts) > 2 else ""

            # Vendor/device from brackets
            vendor_match = re.search(r"\[([0-9a-f]{4}:[0-9a-f]{4})\]", device_info)
            vendor_id = vendor_match.group(1) if vendor_match else "unknown"

            # Driver
            driver_path = os.path.join(self.SYSFS_PCI, "devices", pci, "driver")
            driver = None
            vfio_bound = False
            if os.path.islink(driver_path):
                driver = os.path.basename(os.readlink(driver_path))
                vfio_bound = driver == "vfio-pci"

            # IOMMU group
            iommu_path = os.path.join(self.SYSFS_PCI, "devices", pci, "iommu_group")
            iommu_group = None
            if os.path.isfile(iommu_path):
                try:
                    iommu_group = int(open(iommu_path).read().strip())
                except (OSError, ValueError):
                    pass

            # Check for IOMMU support
            iommu_dir = os.path.join(self.SYSFS_PCI, "devices", pci, "iommu_group")
            has_iommu = os.path.isdir(iommu_dir)

            gpus.append({
                "pci": pci,
                "vendor": vendor_id,
                "device_name": device_info.strip(),
                "driver": driver,
                "vfio_bound": vfio_bound,
                "iommu_group": iommu_group,
                "iommu_supported": has_iommu,
            })

        logger.info("Detected %d GPUs", len(gpus))
        return gpus

    def iommu_groups(self) -> dict[int, list[str]]:
        """Return IOMMU group mapping for all PCI devices.

        Returns:
            Dict of ``{group_number: [pci_address, ...]}``
        """
        groups: dict[int, list[str]] = {}
        for pci_dir in sorted(glob.glob(f"{self.SYSFS_PCI}/*:*:*.*/iommu_group")):
            pci_addr = pci_dir.split("/")[-2]
            group_file = os.path.join(pci_dir, "group")
            if not os.path.isfile(group_file):
                continue
            try:
                group_num = int(open(group_file).read().strip())
            except (ValueError, OSError):
                continue
            groups.setdefault(group_num, []).append(pci_addr)
        return groups

    # ------------------------------------------------------------------
    # IOMMU / VFIO
    # ------------------------------------------------------------------

    def enable_iommu(self, vendor: str = "intel") -> None:
        """Print instructions for enabling IOMMU via kernel parameters.

        IOMMU requires a host reboot.  This method logs the steps
        needed.

        Args:
            vendor: ``intel`` for VT-d or ``amd`` for AMD-Vi.
        """
        if vendor.lower() == "intel":
            param = "intel_iommu=on iommu=pt"
        elif vendor.lower() == "amd":
            param = "amd_iommu=on iommu=pt"
        else:
            raise GPUError(f"Unknown vendor '{vendor}'. Use 'intel' or 'amd'.")

        logger.info(
            "To enable IOMMU, add to your kernel command line:\n"
            "  %s\n"
            "Then update the bootloader (e.g. grub) and reboot.\n"
            "Example for GRUB:\n"
            "  sudo sed -i 's/GRUB_CMDLINE_LINUX=\"\"/"
            "GRUB_CMDLINE_LINUX=\"%s\"/' /etc/default/grub\n"
            "  sudo update-grub && sudo reboot",
            param,
            param,
        )

    def bind_vfio(self, pci_address: str) -> None:
        """Bind a PCI device to the ``vfio-pci`` driver.

        Args:
            pci_address: PCI address in ``DDDD:BB:DD.F`` format.
        """
        self._check_device(pci_address)
        current_driver = self._get_driver(pci_address)
        if current_driver == "vfio-pci":
            logger.info("%s already bound to vfio-pci", pci_address)
            return

        # Ensure vfio-pci module is loaded
        self._load_module("vfio-pci")

        # Unbind from current driver
        self._unbind(pci_address)

        # Bind to vfio-pci
        self._bind(pci_address, "vfio-pci")
        logger.info("Bound %s to vfio-pci", pci_address)

    def unbind_vfio(self, pci_address: str) -> None:
        """Unbind a PCI device from ``vfio-pci``.

        Attempts to rebind to the original driver.
        """
        self._check_device(pci_address)
        current_driver = self._get_driver(pci_address)
        if current_driver != "vfio-pci":
            logger.info("%s is not bound to vfio-pci (current: %s)", pci_address, current_driver)
            return

        self._unbind(pci_address)

        # Try to restore original driver
        vendor_id, device_id = self._get_vendor_device_ids(pci_address)
        if vendor_id and device_id:
            for mod_dir in glob.glob("/sys/bus/pci/drivers/*/new_id"):
                driver_name = mod_dir.split("/")[-2]
                try:
                    with open(mod_dir, "w") as fh:
                        fh.write(f"{vendor_id} {device_id}")
                    self._bind(pci_address, driver_name)
                    logger.info("Rebound %s to %s", pci_address, driver_name)
                    return
                except OSError:
                    continue

        logger.warning("Could not restore original driver for %s", pci_address)

    def blacklist_driver(self, driver: str = "nouveau") -> None:
        """Add a kernel driver to the blacklist.

        Writes ``blacklist <driver>`` to ``/etc/modprobe.d/blacklist-<driver>.conf``.

        Args:
            driver: Driver module name to blacklist.
        """
        conf_path = f"/etc/modprobe.d/blacklist-{driver}.conf"
        try:
            with open(conf_path, "w") as fh:
                fh.write(f"blacklist {driver}\n")
            logger.info("Blacklisted driver '%s' in %s", driver, conf_path)
        except OSError as exc:
            raise GPUError(f"Failed to write blacklist file: {exc}") from exc

    # ------------------------------------------------------------------
    # Domain assignment
    # ------------------------------------------------------------------

    def assign_to_domain(
        self,
        domain_name: str,
        pci_address: str,
        rombar: bool = False,
    ) -> None:
        """Attach a GPU to a KVM domain via libvirt ``hostdev`` XML.

        Args:
            domain_name: Name of the target domain.
            pci_address: PCI address in ``DDDD:BB:DD.F`` format.
            rombar: Enable ROM BAR for the device.
        """
        self._check_device(pci_address)
        vendor_id, device_id = self._get_vendor_device_ids(pci_address)
        parts = pci_address.split(":")
        domain_hex = parts[0]
        bus_slot = parts[1].split(".")
        bus_hex = bus_slot[0]
        slot_hex = bus_slot[0]
        function_hex = bus_slot[1] if len(bus_slot) > 1 else "0"

        # Read IOMMU group
        iommu_group = self._get_iommu_group(pci_address)

        hostdev_xml = (
            f"<hostdev mode='subsystem' type='pci' managed='yes'>"
            f"  <source>"
            f"    <address domain='0x{domain_hex}' bus='0x{bus_hex}' "
            f"slot='0x{slot_hex}' function='0x{function_hex}'/>"
            f"  </source>"
            f"  <rom bar='{'on' if rombar else 'off'}'/>"
            f"</hostdev>"
        )

        client = LibvirtClient()
        client.connect()
        try:
            dom = client.get_domain(domain_name)
            try:
                xml_desc = dom.XMLDesc(libvirt.VIR_DOMAIN_XML_CONFIG)
            except libvirt.libvirtError as exc:
                raise _wrap_libvirt_error(exc) from exc

            import xml.etree.ElementTree as ET
            root = ET.fromstring(xml_desc)
            devices = root.find("devices")
            if devices is None:
                devices = ET.SubElement(root, "devices")

            # Check for existing assignment
            for hd in devices.findall("hostdev"):
                src = hd.find("source")
                if src is not None:
                    addr = src.find("address")
                    if addr is not None:
                        existing = (
                            f"{addr.get('domain')}:{addr.get('bus')}:"
                            f"{addr.get('slot')}:{addr.get('function')}"
                        )
                        if existing.lower() == pci_address.lower():
                            logger.info("GPU %s already assigned to %s", pci_address, domain_name)
                            return

            devices.append(ET.fromstring(hostdev_xml))
            ET.indent(root, space="  ")
            new_xml = ET.tostring(root, encoding="unicode")

            flags = 0 if dom.isActive() else libvirt.VIR_DOMAIN_AFFECT_CONFIG
            dom.attachDeviceFlags(new_xml, flags=flags)
            logger.info("Assigned GPU %s to VM '%s'", pci_address, domain_name)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc
        finally:
            client.disconnect()

    def verify(self, domain_name: str) -> dict[str, Any]:
        """Verify GPU passthrough assignment for a domain.

        Returns:
            Dict with ``domain``, ``hostdev_devices``, ``vfio_status``.
        """
        client = LibvirtClient()
        client.connect()
        try:
            dom = client.get_domain(domain_name)
            xml_desc = dom.XMLDesc(0)

            import xml.etree.ElementTree as ET
            root = ET.fromstring(xml_desc)
            hostdevs = []
            for hd in root.findall(".//hostdev"):
                if hd.get("type") == "pci":
                    src = hd.find("source")
                    if src is not None:
                        addr = src.find("address")
                        if addr is not None:
                            pci = (
                                f"{addr.get('domain')}:{addr.get('bus')}:"
                                f"{addr.get('slot')}:{addr.get('function')}"
                            )
                            driver = self._get_driver(pci.lstrip("0").replace("0x", ""))
                            hostdevs.append({
                                "pci": pci,
                                "driver": driver,
                                "managed": hd.get("managed"),
                            })

            return {
                "domain": domain_name,
                "hostdev_devices": hostdevs,
                "vfio_status": "active" if any(
                    h.get("driver") == "vfio-pci" for h in hostdevs
                ) else "inactive",
            }
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc
        finally:
            client.disconnect()

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _check_device(self, pci_address: str) -> None:
        dev_path = os.path.join(self.SYSFS_PCI, "devices", pci_address)
        if not os.path.isdir(dev_path):
            raise GPUError(f"PCI device {pci_address} not found")

    def _get_driver(self, pci_address: str) -> str | None:
        driver_path = os.path.join(self.SYSFS_PCI, "devices", pci_address, "driver")
        if os.path.islink(driver_path):
            return os.path.basename(os.readlink(driver_path))
        return None

    def _get_vendor_device_ids(self, pci_address: str) -> tuple[str | None, str | None]:
        dev_path = os.path.join(self.SYSFS_PCI, "devices", pci_address)
        vid = self._read_sys(os.path.join(dev_path, "vendor"))
        did = self._read_sys(os.path.join(dev_path, "device"))
        return (vid, did)

    def _get_iommu_group(self, pci_address: str) -> int | None:
        group_path = os.path.join(self.SYSFS_PCI, "devices", pci_address, "iommu_group", "group")
        if not os.path.isfile(group_path):
            return None
        try:
            return int(open(group_path).read().strip())
        except (OSError, ValueError):
            return None

    @staticmethod
    def _read_sys(path: str) -> str | None:
        try:
            return open(path).read().strip()
        except (OSError, FileNotFoundError):
            return None

    @staticmethod
    def _unbind(pci_address: str) -> None:
        unbind_path = os.path.join(
            GPUPassthrough.SYSFS_PCI, "devices", pci_address, "driver", "unbind"
        )
        try:
            with open(unbind_path, "w") as fh:
                fh.write(pci_address)
        except OSError as exc:
            raise GPUError(f"Failed to unbind {pci_address}: {exc}") from exc

    @staticmethod
    def _bind(pci_address: str, driver: str) -> None:
        bind_path = os.path.join(GPUPassthrough.SYSFS_PCI, "drivers", driver, "bind")
        try:
            with open(bind_path, "w") as fh:
                fh.write(pci_address)
        except OSError as exc:
            raise GPUError(f"Failed to bind {pci_address} to {driver}: {exc}") from exc

    @staticmethod
    def _load_module(module: str) -> None:
        result = subprocess.run(
            ["modprobe", module],
            capture_output=True, text=True, check=False,
        )
        if result.returncode != 0:
            raise GPUError(f"Failed to load module {module}: {result.stderr.strip()}")
