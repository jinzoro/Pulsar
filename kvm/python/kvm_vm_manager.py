"""
SPDX-License-Identifier: MIT
Virtual machine lifecycle management via libvirt.

Provides the ``VMManager`` class for creating, starting, stopping, cloning,
and otherwise managing the full lifecycle of KVM virtual machines.
"""

from __future__ import annotations

import logging
import xml.etree.ElementTree as ET

import libvirt

from kvm_libvirt_client import LibvirtClient, LibvirtError

logger = logging.getLogger(__name__)


def _ensure_client(client: LibvirtClient | None) -> LibvirtClient:
    """Return *client* if given, otherwise create an ephemeral connection."""
    if client is not None:
        return client
    c = LibvirtClient()
    c.connect()
    return c


class VMManager:
    """High-level VM lifecycle operations.

    Args:
        client: An existing :class:`LibvirtClient`.  When *None* a fresh
            connection is created per operation and closed afterwards.

    Example::

        manager = VMManager()
        name = manager.create("web01", ram_mb=2048, vcpus=2,
                              disk_path="/var/lib/libvirt/images/web01.qcow2")
        manager.start(name)
    """

    def __init__(self, client: LibvirtClient | None = None) -> None:
        self._client = client

    # ------------------------------------------------------------------
    # Creation helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _build_domain_xml(
        name: str,
        ram_mb: int,
        vcpus: int,
        disk_path: str,
        disk_format: str = "qcow2",
        disk_size_gb: int | None = None,
        network: str = "default",
        graphics: str = "vnc",
        os_variant: str | None = None,
        cpu_model: str = "host-passthrough",
        machine: str = "q35",
        uefi: bool = False,
        tpm: bool = False,
        cloud_init_iso: str | None = None,
    ) -> str:
        """Build a minimal domain XML string."""
        root = ET.Element("domain", type="kvm")
        ET.SubElement(root, "name").text = name

        mem = ET.SubElement(root, "memory", unit="MiB")
        mem.text = str(ram_mb)
        cur_mem = ET.SubElement(root, "currentMemory", unit="MiB")
        cur_mem.text = str(ram_mb)

        vcpu_el = ET.SubElement(root, "vcpu", placement="static")
        vcpu_el.text = str(vcpus)

        # CPU
        cpu_el = ET.SubElement(root, "cpu", mode="custom", match="exact")
        model_el = ET.SubElement(cpu_el, "model")
        model_el.text = cpu_model
        topo = ET.SubElement(cpu_el, "topology", sockets="1", cores=str(vcpus), threads="1")

        # OS
        os_el = ET.SubElement(root, "os")
        type_el = ET.SubElement(os_el, "type", arch="x86_64", machine=machine)
        type_el.text = "hvm"
        ET.SubElement(os_el, "boot", dev="hd")
        if uefi:
            loader = ET.SubElement(os_el, "loader", readonly="yes", type="pflash")
            loader.text = "/usr/share/OVMF/OVMF_CODE.fd"

        # Features
        features = ET.SubElement(root, "features")
        ET.SubElement(features, "acpi")
        ET.SubElement(features, "apic")
        ET.SubElement(features, "vmport", state="off")

        # Devices
        devices = ET.SubElement(root, "devices")

        # Disk
        disk_el = ET.SubElement(
            devices, "disk", type="file", device="disk", driver={"name": "qemu", "type": disk_format}
        )
        ET.SubElement(disk_el, "source", file=disk_path)
        target = ET.SubElement(disk_el, "target", dev="vda", bus="virtio")
        ET.SubElement(disk_el, "address", type="pci", domain="0x0000", bus="0x00", slot="0x04", function="0x0")

        # Cloud-init CDROM (optional)
        if cloud_init_iso:
            ci_disk = ET.SubElement(
                devices,
                "disk",
                type="file",
                device="cdrom",
                driver={"name": "qemu", "type": "raw"},
            )
            ET.SubElement(ci_disk, "source", file=cloud_init_iso)
            ET.SubElement(ci_disk, "target", dev="sda", bus="sata")

        # Network
        nic = ET.SubElement(devices, "interface", type="network")
        ET.SubElement(nic, "source", network=network)
        ET.SubElement(nic, "model", type="virtio")

        # Graphics
        if graphics == "vnc":
            ET.SubElement(
                devices,
                "graphics",
                type="vnc",
                port="-1",
                autoport="yes",
                listen="0.0.0.0",
            )
        elif graphics == "spice":
            ET.SubElement(
                devices,
                "graphics",
                type="spice",
                port="-1",
                autoport="yes",
                listen="0.0.0.0",
            )

        # Serial console
        serial = ET.SubElement(devices, "serial", type="pty")
        ET.SubElement(serial, "target", port="0")

        # TPM 2.0
        if tpm:
            tpm_el = ET.SubElement(
                devices, "tpm", model="tpm-crb"
            )
            tpm_backend = ET.SubElement(tpm_el, "backend", type="emulator")
            ET.SubElement(tpm_backend, "version").text = "2.0"

        # Clock / power off
        clock = ET.SubElement(root, "clock", offset="localtime")
        ET.SubElement(clock, "timer", name="rtc", tickpolicy="catchup")
        ET.SubElement(clock, "timer", name="pit", tickpolicy="delay")
        ET.SubElement(clock, "timer", name="hpet", present="no")

        ET.SubElement(root, "on_poweroff").text = "destroy"
        ET.SubElement(root, "on_reboot").text = "restart"
        ET.SubElement(root, "on_crash").text = "restart"

        if os_variant:
            os_el.set("os_variant", os_variant)

        ET.indent(root, space="  ")
        return ET.tostring(root, encoding="unicode", xml_declaration=False)

    # ------------------------------------------------------------------
    # Core operations
    # ------------------------------------------------------------------

    def create(
        self,
        name: str,
        ram_mb: int,
        vcpus: int,
        disk_path: str,
        disk_size_gb: int | None = None,
        disk_format: str = "qcow2",
        network: str = "default",
        graphics: str = "vnc",
        os_variant: str | None = None,
        cpu_model: str = "host-passthrough",
        machine: str = "q35",
        uefi: bool = False,
        tpm: bool = False,
        cloud_init_iso: str | None = None,
    ) -> str:
        """Create and optionally start a new VM.

        Args:
            name: VM name.
            ram_mb: Memory in MiB.
            vcpus: Number of virtual CPUs.
            disk_path: Full path for the disk image.
            disk_size_gb: Disk size in GiB (used with ``qemu-img create``).
            disk_format: Disk format (default ``qcow2``).
            network: libvirt network name.
            graphics: ``vnc`` or ``spice``.
            os_variant: ``osinfo-query os`` variant name.
            cpu_model: CPU model string.
            machine: Machine type (e.g. ``q35``, ``i440fx``).
            uefi: Enable UEFI boot.
            tpm: Attach a vTPM 2.0.
            cloud_init_iso: Path to a cloud-init ISO to attach.

        Returns:
            The domain name on success.

        Raises:
            LibvirtError: On any libvirt failure.
        """
        xml = self._build_domain_xml(
            name,
            ram_mb,
            vcpus,
            disk_path,
            disk_format=disk_format,
            disk_size_gb=disk_size_gb,
            network=network,
            graphics=graphics,
            os_variant=os_variant,
            cpu_model=cpu_model,
            machine=machine,
            uefi=uefi,
            tpm=tpm,
            cloud_init_iso=cloud_init_iso,
        )
        return self.define_from_xml(xml)

    def define_from_xml(self, xml: str) -> str:
        """Define a domain from raw XML and return its name.

        Args:
            xml: Valid libvirt domain XML.

        Returns:
            The domain name.

        Raises:
            LibvirtError: If definition fails.
        """
        conn = _ensure_client(self._client)
        try:
            dom = conn.conn.defineXML(xml)
            name = dom.name()
            logger.info("Defined VM '%s'", name)
            return name
        except libvirt.libvirtError as exc:
            from kvm_libvirt_client import _wrap_libvirt_error
            raise _wrap_libvirt_error(exc) from exc

    def start(self, name: str) -> None:
        """Start a defined domain.

        Args:
            name: Domain name or id.
        """
        conn = _ensure_client(self._client)
        dom = conn.get_domain(name)
        try:
            dom.create()
            logger.info("Started VM '%s'", name)
        except libvirt.libvirtError as exc:
            from kvm_libvirt_client import _wrap_libvirt_error
            raise _wrap_libvirt_error(exc) from exc

    def stop(self, name: str, graceful: bool = True, timeout: int = 30) -> None:
        """Stop a running domain.

        Args:
            name: Domain name or id.
            graceful: Issue an ACPI shutdown first; destroy if it doesn't
                stop within *timeout* seconds.
            timeout: Seconds to wait for graceful shutdown.
        """
        conn = _ensure_client(self._client)
        dom = conn.get_domain(name)
        try:
            if graceful:
                dom.shutdown()
                import time
                deadline = time.monotonic() + timeout
                while dom.isActive() and time.monotonic() < deadline:
                    time.sleep(1)
                if dom.isActive():
                    logger.warning(
                        "Graceful shutdown timed out after %ss for '%s'; "
                        "forcing destroy",
                        timeout,
                        name,
                    )
                    dom.destroy()
            else:
                dom.destroy()
            logger.info("Stopped VM '%s'", name)
        except libvirt.libvirtError as exc:
            from kvm_libvirt_client import _wrap_libvirt_error
            raise _wrap_libvirt_error(exc) from exc

    def destroy(self, name: str) -> None:
        """Force-stop a domain (equivalent to pulling the power cord)."""
        self.stop(name, graceful=False)

    def suspend(self, name: str) -> None:
        """Suspend a domain to RAM."""
        conn = _ensure_client(self._client)
        dom = conn.get_domain(name)
        try:
            dom.suspend()
            logger.info("Suspended VM '%s'", name)
        except libvirt.libvirtError as exc:
            from kvm_libvirt_client import _wrap_libvirt_error
            raise _wrap_libvirt_error(exc) from exc

    def resume(self, name: str) -> None:
        """Resume a suspended domain."""
        conn = _ensure_client(self._client)
        dom = conn.get_domain(name)
        try:
            dom.resume()
            logger.info("Resumed VM '%s'", name)
        except libvirt.libvirtError as exc:
            from kvm_libvirt_client import _wrap_libvirt_error
            raise _wrap_libvirt_error(exc) from exc

    def save(self, name: str, file_path: str) -> None:
        """Save a running domain's state to a file."""
        conn = _ensure_client(self._client)
        dom = conn.get_domain(name)
        try:
            dom.save(file_path)
            logger.info("Saved VM '%s' to %s", name, file_path)
        except libvirt.libvirtError as exc:
            from kvm_libvirt_client import _wrap_libvirt_error
            raise _wrap_libvirt_error(exc) from exc

    def restore(self, file_path: str) -> None:
        """Restore a domain from a save file."""
        conn = _ensure_client(self._client)
        try:
            conn.conn.restore(file_path)
            logger.info("Restored VM from %s", file_path)
        except libvirt.libvirtError as exc:
            from kvm_libvirt_client import _wrap_libvirt_error
            raise _wrap_libvirt_error(exc) from exc

    def undefine(self, name: str, remove_storage: bool = False, nvram: bool = False) -> None:
        """Undefine a domain.

        Args:
            name: Domain name.
            remove_storage: Also remove associated storage volumes.
            nvram: Also remove NVRAM (UEFI vars) file.
        """
        conn = _ensure_client(self._client)
        dom = conn.get_domain(name)
        flags = 0
        if remove_storage:
            flags |= libvirt.VIR_DOMAIN_UNDEFINE_STORAGE
        if nvram:
            flags |= libvirt.VIR_DOMAIN_UNDEFINE_NVRAM
        try:
            dom.undefineFlags(flags=flags)
            logger.info("Undefined VM '%s' (remove_storage=%s)", name, remove_storage)
        except libvirt.libvirtError as exc:
            from kvm_libvirt_client import _wrap_libvirt_error
            raise _wrap_libvirt_error(exc) from exc

    def list_all(self, active: bool = True, inactive: bool = True) -> list[dict]:
        """List all domains with summary info.

        Returns:
            List of dicts with ``name``, ``id``, ``active`` keys.
        """
        conn = _ensure_client(self._client)
        domains = conn.list_domains(active=active, inactive=inactive)
        result = []
        for dom in domains:
            result.append({
                "name": dom.name(),
                "id": dom.ID() if dom.isActive() else None,
                "active": bool(dom.isActive()),
            })
        return result

    def get_info(self, name: str) -> dict:
        """Return detailed info about a domain.

        Returns:
            Dict with ``name``, ``state``, ``vcpus``, ``memory_mb``,
            ``max_memory_mb``, ``autostart``, ``persistent``.
        """
        conn = _ensure_client(self._client)
        dom = conn.get_domain(name)
        try:
            info = dom.info()
            state_map = {
                1: "running",
                2: "blocked",
                3: "paused",
                4: "shutdown",
                5: "shut off",
                6: "crashed",
                7: "suspended",
            }
            state_code = info[0]
            return {
                "name": dom.name(),
                "state": state_map.get(state_code, f"unknown ({state_code})"),
                "vcpus": info[3],
                "memory_mb": info[2] // 1024,
                "max_memory_mb": info[1] // 1024,
                "autostart": bool(dom.autostart()),
                "persistent": bool(dom.isPersistent()),
            }
        except libvirt.libvirtError as exc:
            from kvm_libvirt_client import _wrap_libvirt_error
            raise _wrap_libvirt_error(exc) from exc

    def set_autostart(self, name: str, enabled: bool = True) -> None:
        """Enable or disable autostart for a domain."""
        conn = _ensure_client(self._client)
        dom = conn.get_domain(name)
        try:
            dom.setAutostart(1 if enabled else 0)
            logger.info("Autostart for '%s' set to %s", name, enabled)
        except libvirt.libvirtError as exc:
            from kvm_libvirt_client import _wrap_libvirt_error
            raise _wrap_libvirt_error(exc) from exc

    def get_xml(self, name: str) -> str:
        """Return the current domain XML."""
        conn = _ensure_client(self._client)
        dom = conn.get_domain(name)
        try:
            return dom.XMLDesc(0)
        except libvirt.libvirtError as exc:
            from kvm_libvirt_client import _wrap_libvirt_error
            raise _wrap_libvirt_error(exc) from exc

    def clone(self, name: str, new_name: str, full: bool = True) -> str:
        """Clone a domain.

        Args:
            name: Source domain name.
            new_name: Name for the clone.
            full: If *True* perform a full (deep) clone; otherwise a
                shallow/sparse clone.

        Returns:
            The new domain name.
        """
        conn = _ensure_client(self._client)
        src_dom = conn.get_domain(name)
        src_xml = src_dom.XMLDesc(0)

        root = ET.fromstring(src_xml)
        name_el = root.find("name")
        if name_el is not None:
            name_el.text = new_name

        # Handle disk paths
        for disk in root.findall(".//disk[@device='disk']"):
            source = disk.find("source")
            target = disk.find("target")
            if source is not None and target is not None:
                orig_path = source.get("file", "")
                new_path = orig_path.replace(name, new_name)
                source.set("file", new_path)
                # Update driver for full clone
                driver = disk.find("driver")
                if driver is not None and not full:
                    driver.set("type", "raw")
                    source.set("file", new_path)

        # Remove any uuid to let libvirt regenerate
        uuid_el = root.find("uuid")
        if uuid_el is not None:
            root.remove(uuid_el)

        ET.indent(root, space="  ")
        new_xml = ET.tostring(root, encoding="unicode")

        # Define from the modified XML
        try:
            new_dom = conn.conn.defineXML(new_xml)
            new_name_actual = new_dom.name()
            logger.info("Cloned '%s' -> '%s' (full=%s)", name, new_name_actual, full)
            return new_name_actual
        except libvirt.libvirtError as exc:
            from kvm_libvirt_client import _wrap_libvirt_error
            raise _wrap_libvirt_error(exc) from exc
