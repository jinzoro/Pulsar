"""
SPDX-License-Identifier: MIT
Runtime and offline VM modification via libvirt and XML manipulation.

Provides ``VMModify`` for hotplugging/unplugging hardware, editing the
domain XML tree, and tweaking boot order, serial consoles, and PCI
passthrough devices.
"""

from __future__ import annotations

import logging
import xml.etree.ElementTree as ET

import libvirt

from kvm_libvirt_client import LibvirtClient, LibvirtError, _wrap_libvirt_error

logger = logging.getLogger(__name__)

_NS = "http://libvirt.org/schemas/domain/qemu/1.0"


def _ensure_client(client: LibvirtClient | None) -> LibvirtClient:
    if client is not None:
        return client
    c = LibvirtClient()
    c.connect()
    return c


class VMModify:
    """Modify a VM's hardware configuration at runtime or offline.

    Args:
        client: Reuse an existing connection, or pass *None* to let
            each method create its own.

    Example::

        modifier = VMModify()
        modifier.hotplug_cpu("web01", vcpus=4)
        modifier.hotplug_disk("web01", "/data/disk2.qcow2", "vdb")
    """

    def __init__(self, client: LibvirtClient | None = None) -> None:
        self._client = client

    # ------------------------------------------------------------------
    # Hot-plug / unplug
    # ------------------------------------------------------------------

    def hotplug_cpu(self, name: str, vcpus: int) -> None:
        """Dynamically adjust the number of vCPUs for a running domain.

        Args:
            name: Domain name or id.
            vcpus: Desired *total* number of vCPUs.
        """
        conn = _ensure_client(self._client)
        dom = conn.get_domain(name)
        try:
            dom.setVcpus(vcpus)
            logger.info("Set vCPUs for '%s' to %d", name, vcpus)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc

    def hotplug_memory(self, name: str, memory_mb: int) -> None:
        """Dynamically set the memory size (MiB) for a running domain.

        Args:
            name: Domain name or id.
            memory_mb: Desired memory in MiB.
        """
        conn = _ensure_client(self._client)
        dom = conn.get_domain(name)
        try:
            dom.setMemory(memory_mb * 1024)
            logger.info("Set memory for '%s' to %d MiB", name, memory_mb)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc

    def hotplug_disk(self, name: str, disk_path: str, target: str) -> None:
        """Attach a new disk to a running or offline domain.

        Args:
            name: Domain name.
            disk_path: Full path to the disk image file.
            target: Target device name, e.g. ``vdb`` or ``sdb``.
        """
        disk_xml = (
            f"<disk type='file' device='disk'>"
            f"  <driver name='qemu' type='qcow2'/>"
            f"  <source file='{disk_path}'/>"
            f"  <target dev='{target}' bus='virtio'/>"
            f"  <address type='pci' domain='0x0000' bus='0x00' "
            f"slot='0x04' function='0x0'/>"
            f"</disk>"
        )
        conn = _ensure_client(self._client)
        dom = conn.get_domain(name)
        try:
            flags = 0 if dom.isActive() else libvirt.VIR_DOMAIN_AFFECT_CONFIG
            dom.attachDeviceFlags(disk_xml, flags=flags)
            logger.info("Attached disk '%s' to VM '%s'", disk_path, name)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc

    def hotplug_nic(self, name: str, network: str, model: str = "virtio") -> None:
        """Attach a new NIC to a running or offline domain.

        Args:
            name: Domain name.
            network: libvirt network name.
            model: NIC model (e.g. ``virtio``, ``e1000``, ``rtl8139``).
        """
        nic_xml = (
            f"<interface type='network'>"
            f"  <source network='{network}'/>"
            f"  <model type='{model}'/>"
            f"</interface>"
        )
        conn = _ensure_client(self._client)
        dom = conn.get_domain(name)
        try:
            flags = 0 if dom.isActive() else libvirt.VIR_DOMAIN_AFFECT_CONFIG
            dom.attachDeviceFlags(nic_xml, flags=flags)
            logger.info("Attached NIC (net=%s, model=%s) to VM '%s'", network, model, name)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc

    def unplug_device(self, name: str, mac_address: str) -> None:
        """Detach a device by its MAC address.

        This performs an XML walk to find the matching ``<interface>``
        element and removes it.

        Args:
            name: Domain name.
            mac_address: MAC address of the NIC to remove.
        """
        conn = _ensure_client(self._client)
        dom = conn.get_domain(name)
        try:
            xml_desc = dom.XMLDesc(0)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc

        root = ET.fromstring(xml_desc)
        for iface in root.findall(".//interface"):
            mac_el = iface.find("mac")
            if mac_el is not None and mac_el.get("address", "").lower() == mac_address.lower():
                device_xml = ET.tostring(iface, encoding="unicode")
                try:
                    flags = 0 if dom.isActive() else libvirt.VIR_DOMAIN_AFFECT_CONFIG
                    dom.detachDeviceFlags(device_xml, flags=flags)
                    logger.info("Detached device with MAC '%s' from VM '%s'", mac_address, name)
                    return
                except libvirt.libvirtError as exc:
                    raise _wrap_libvirt_error(exc) from exc

        raise LibvirtError(f"No device with MAC '{mac_address}' found on VM '{name}'")

    # ------------------------------------------------------------------
    # XML manipulation
    # ------------------------------------------------------------------

    def modify_xml(self, name: str, xpath: str, value: str) -> None:
        """Modify a single XML element by XPath.

        Args:
            name: Domain name.
            xpath: XPath expression selecting the element to modify.
            value: New text value for the element.
        """
        conn = _ensure_client(self._client)
        dom = conn.get_domain(name)
        try:
            xml_desc = dom.XMLDesc(libvirt.VIR_DOMAIN_XML_CONFIG)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc

        root = ET.fromstring(xml_desc)
        elements = root.findall(xpath)
        if not elements:
            raise LibvirtError(f"XPath '{xpath}' matched no elements")
        for el in elements:
            el.text = value

        ET.indent(root, space="  ")
        new_xml = ET.tostring(root, encoding="unicode")
        try:
            dom = conn.conn.defineXML(new_xml)
            logger.info("Modified XML for '%s': %s = %s", name, xpath, value)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc

    def set_boot_order(self, name: str, devices: list[str]) -> None:
        """Set the boot device order.

        Args:
            name: Domain name.
            devices: Ordered list of boot devices (e.g. ``["hd", "cdrom"]``).
        """
        conn = _ensure_client(self._client)
        dom = conn.get_domain(name)
        try:
            xml_desc = dom.XMLDesc(libvirt.VIR_DOMAIN_XML_CONFIG)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc

        root = ET.fromstring(xml_desc)
        os_el = root.find("os")
        if os_el is None:
            raise LibvirtError("Domain XML missing <os> element")

        # Remove existing boot entries
        for boot_el in os_el.findall("boot"):
            os_el.remove(boot_el)

        # Remove existing boot menu (re-add at end)
        for menu_el in os_el.findall("bootmenu"):
            os_el.remove(menu_el)

        # Add new boot devices
        for device in devices:
            ET.SubElement(os_el, "boot", dev=device)

        ET.indent(root, space="  ")
        new_xml = ET.tostring(root, encoding="unicode")
        try:
            conn.conn.defineXML(new_xml)
            logger.info("Set boot order for '%s' to %s", name, devices)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc

    def add_serial_console(self, name: str) -> None:
        """Add a serial console (pty) device to the domain XML.

        Args:
            name: Domain name.
        """
        conn = _ensure_client(self._client)
        dom = conn.get_domain(name)
        try:
            xml_desc = dom.XMLDesc(libvirt.VIR_DOMAIN_XML_CONFIG)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc

        root = ET.fromstring(xml_desc)
        devices = root.find("devices")
        if devices is None:
            devices = ET.SubElement(root, "devices")

        # Check for existing serial
        for serial in devices.findall("serial"):
            target = serial.find("target")
            if target is not None and target.get("port") == "0":
                logger.info("Serial console already present for '%s'", name)
                return

        serial = ET.SubElement(devices, "serial", type="pty")
        ET.SubElement(serial, "target", port="0")

        ET.indent(root, space="  ")
        new_xml = ET.tostring(root, encoding="unicode")
        try:
            conn.conn.defineXML(new_xml)
            logger.info("Added serial console to VM '%s'", name)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc

    def add_pci_passthrough(self, name: str, pci_address: str) -> None:
        """Add a PCI passthrough (hostdev) device to the domain.

        Args:
            name: Domain name.
            pci_address: PCI address in ``DDDD:BB:DD.F`` format
                (e.g. ``0000:01:00.0``).
        """
        parts = pci_address.split(":")
        if len(parts) != 3:
            raise LibvirtError(
                f"Invalid PCI address format '{pci_address}'. "
                "Expected DDDD:BB:DD.F"
            )
        bus_slot = parts[1].split(".")
        domain_id = parts[0]
        bus = bus_slot[0]
        slot_func = parts[1].split(".")
        slot = slot_func[0]
        function = slot_func[1] if len(slot_func) > 1 else "0"

        hostdev_xml = (
            f"<hostdev mode='subsystem' type='pci' managed='yes'>"
            f"  <source>"
            f"    <address domain='0x{domain_id}' bus='0x{bus}' "
            f"slot='0x{slot}' function='0x{function}'/>"
            f"  </source>"
            f"  <rom bar='off'/>"
            f"</hostdev>"
        )
        conn = _ensure_client(self._client)
        dom = conn.get_domain(name)
        try:
            flags = 0 if dom.isActive() else libvirt.VIR_DOMAIN_AFFECT_CONFIG
            dom.attachDeviceFlags(hostdev_xml, flags=flags)
            logger.info("Attached PCI device '%s' to VM '%s'", pci_address, name)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc
