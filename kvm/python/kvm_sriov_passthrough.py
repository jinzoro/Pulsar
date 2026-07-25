"""
SPDX-License-Identifier: MIT
SR-IOV NIC detection, VF creation, and passthrough.

Provides ``SRIOVPassthrough`` for enumerating SR-IOV capable NICs,
enabling VFs, binding/unbinding VFs to drivers, and inspecting IOMMU
groups via sysfs and lspci.
"""

from __future__ import annotations

import glob
import logging
import os
import re
import subprocess
from typing import Any

logger = logging.getLogger(__name__)


class SRIOVError(Exception):
    """Raised when an SR-IOV operation fails."""


class SRIOVPassthrough:
    """SR-IOV virtual-function management.

    Example::

        sriov = SRIOVPassthrough()
        nics = sriov.detect_devices()
        sriov.enable_sriov(nics[0]["pci"], 4)
        vfs = sriov.list_vfs(nics[0]["pci"])
    """

    SYSFS_PCI = "/sys/bus/pci"
    SYSFS_NET = "/sys/class/net"

    # ------------------------------------------------------------------
    # Detection
    # ------------------------------------------------------------------

    def detect_devices(self) -> list[dict[str, Any]]:
        """List physical NICs that support SR-IOV.

        Returns:
            List of dicts with ``pci``, ``name``, ``driver``,
            ``max_vfs``, ``current_vfs``.
        """
        results: list[dict[str, Any]] = []
        for iface in sorted(glob.glob(f"{self.SYSFS_NET}/*")):
            if not os.path.isdir(os.path.join(iface, "device")):
                continue
            pci_link = os.path.realpath(os.path.join(iface, "device"))
            pci_addr = pci_link.split("/")[-1]
            sriov_total = self._read_sysfs(
                os.path.join(pci_link, "sriov_totalvfs")
            )
            if sriov_total is None or int(sriov_total) == 0:
                continue

            driver = self._read_sysfs(
                os.path.join(pci_link, "driver", "module", "name")
            )
            sriov_num = self._read_sysfs(
                os.path.join(pci_link, "sriov_numvfs")
            )
            name = os.path.basename(iface)
            results.append({
                "pci": pci_addr,
                "name": name,
                "driver": driver,
                "max_vfs": int(sriov_total),
                "current_vfs": int(sriov_num) if sriov_num else 0,
            })
        logger.info("Found %d SR-IOV capable NICs", len(results))
        return results

    def enable_sriov(self, nic: str, num_vfs: int) -> None:
        """Enable SR-IOV and create *num_vfs* virtual functions on *nic*.

        Args:
            nic: PCI address of the PF (e.g. ``0000:01:00.0``).
            num_vfs: Number of VFs to create (up to max).
        """
        pf_path = os.path.join(self.SYSFS_PCI, "devices", nic)
        max_vfs_str = self._read_sysfs(os.path.join(pf_path, "sriov_totalvfs"))
        if max_vfs_str is None:
            raise SRIOVError(f"Cannot read sriov_totalvfs for {nic}")
        max_vfs = int(max_vfs_str)
        if num_vfs > max_vfs:
            raise SRIOVError(
                f"Requested {num_vfs} VFs but max is {max_vfs} for {nic}"
            )

        # Disable existing VFs first
        self._write_sysfs(os.path.join(pf_path, "sriov_numvfs"), "0")
        # Enable requested count
        self._write_sysfs(os.path.join(pf_path, "sriov_numvfs"), str(num_vfs))
        logger.info("Enabled %d VFs on %s", num_vfs, nic)

    def create_vfs(self, nic: str, num_vfs: int) -> None:
        """Alias for :meth:`enable_sriov`."""
        self.enable_sriov(nic, num_vfs)

    def list_vfs(self, nic: str | None = None) -> list[dict[str, Any]]:
        """List virtual functions, optionally filtered by a PF.

        Args:
            nic: PF PCI address to filter by.

        Returns:
            List of dicts with ``pci``, ``pf_pci``, ``driver``,
            ``iommu_group``.
        """
        vfs: list[dict[str, Any]] = []
        for vf_dir in sorted(glob.glob(f"{self.SYSFS_PCI}/*:*:*.*/sriov_vfs/*")):
            vf_pci = os.path.basename(vf_dir)
            if not re.match(r"[\da-fA-F]{4}:[\da-fA-F]{2}:[\da-fA-F]{2}\.\d", vf_pci):
                continue

            vf_real = os.path.realpath(vf_dir)
            # PF reference
            pf_link = os.path.join(vf_real, "physfn")
            pf_pci = None
            if os.path.isdir(pf_link):
                pf_real = os.path.realpath(pf_link)
                pf_pci = pf_real.split("/")[-1]

            if nic and pf_pci != nic:
                continue

            driver = self._read_sysfs(os.path.join(vf_real, "driver", "module", "name"))
            iommu = self._read_sysfs(
                os.path.join(self.SYSFS_PCI, "devices", vf_pci, "iommu_group")
            )
            vf_net = glob.glob(os.path.join(vf_real, "net", "*"))
            vf_name = os.path.basename(vf_net[0]) if vf_net else None

            vfs.append({
                "pci": vf_pci,
                "pf_pci": pf_pci,
                "driver": driver,
                "iommu_group": iommu,
                "interface": vf_name,
            })

        # Fallback: enumerate via lspci if sysfs glob is empty
        if not vfs:
            result = subprocess.run(
                ["lspci", "-nn", "-D"],
                capture_output=True, text=True, check=False,
            )
            for line in result.stdout.splitlines():
                if "Virtual Function" in line or "SR-IOV" in line:
                    parts = line.split()
                    if parts:
                        vfs.append({"pci": parts[0], "info": line.strip()})

        return vfs

    def bind_vf(
        self,
        vf_address: str,
        mac: str | None = None,
        vlan: str | None = None,
    ) -> None:
        """Bind a VF to a host driver.

        Args:
            vf_address: PCI address of the VF.
            mac: Optional MAC to set.
            vlan: Optional VLAN to set.
        """
        # Determine current driver
        vf_path = os.path.join(self.SYSFS_PCI, "devices", vf_address)
        driver_path = os.path.join(vf_path, "driver")
        if not os.path.islink(driver_path):
            # Bind to vfio-pci
            self._unbind_driver(vf_path)
            self._bind_to_driver(vf_address, "vfio-pci")
        else:
            driver = os.path.basename(os.readlink(driver_path))
            if driver == "vfio-pci":
                logger.debug("VF %s already bound to vfio-pci", vf_address)
            else:
                self._unbind_driver(vf_path)
                self._bind_to_driver(vf_address, "vfio-pci")

        # Set MAC / VLAN via ip link
        vf_net = glob.glob(os.path.join(vf_path, "net", "*"))
        if vf_net:
            iface = os.path.basename(vf_net[0])
            if mac:
                subprocess.run(
                    ["ip", "link", "set", iface, "vf", "0", "mac", mac],
                    check=False, capture_output=True,
                )
            if vlan:
                subprocess.run(
                    ["ip", "link", "set", iface, "vf", "0", "vlan", vlan],
                    check=False, capture_output=True,
                )
        logger.info("Bound VF %s to vfio-pci", vf_address)

    def unbind_vf(self, vf_address: str) -> None:
        """Unbind a VF from its current driver and return it to the PF."""
        vf_path = os.path.join(self.SYSFS_PCI, "devices", vf_address)
        if not os.path.isdir(vf_path):
            raise SRIOVError(f"VF {vf_address} not found in sysfs")
        self._unbind_driver(vf_path)
        logger.info("Unbound VF %s from driver", vf_address)

    def iommu_groups(self) -> dict[int, list[str]]:
        """Return a mapping of IOMMU group numbers to PCI device addresses.

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
    # Sysfs helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _read_sysfs(path: str) -> str | None:
        try:
            return open(path).read().strip()
        except (OSError, FileNotFoundError):
            return None

    @staticmethod
    def _write_sysfs(path: str, value: str) -> None:
        try:
            with open(path, "w") as fh:
                fh.write(value)
        except OSError as exc:
            raise SRIOVError(f"Failed to write {value} to {path}: {exc}") from exc

    @staticmethod
    def _unbind_driver(device_path: str) -> None:
        driver_path = os.path.join(device_path, "driver")
        if not os.path.islink(driver_path):
            return
        driver = os.path.basename(os.readlink(driver_path))
        unbind_path = os.path.join(device_path, "driver", "unbind")
        pci_addr = os.path.basename(device_path)
        try:
            with open(unbind_path, "w") as fh:
                fh.write(pci_addr)
        except OSError as exc:
            logger.warning("Failed to unbind %s from %s: %s", pci_addr, driver, exc)

    @staticmethod
    def _bind_to_driver(pci_addr: str, driver: str) -> None:
        bind_path = f"/sys/bus/pci/drivers/{driver}/bind"
        try:
            with open(bind_path, "w") as fh:
                fh.write(pci_addr)
        except OSError as exc:
            raise SRIOVError(
                f"Failed to bind {pci_addr} to {driver}: {exc}"
            ) from exc
