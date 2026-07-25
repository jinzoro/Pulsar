"""
SPDX-License-Identifier: MIT
Virtual network lifecycle management via libvirt.

Provides ``NetworkManager`` for creating, deleting, starting, stopping,
and configuring libvirt virtual networks with DHCP and static leases.
"""

from __future__ import annotations

import logging
import xml.etree.ElementTree as ET

import libvirt

from kvm_libvirt_client import LibvirtClient, LibvirtError, _wrap_libvirt_error

logger = logging.getLogger(__name__)


def _ensure_client(client: LibvirtClient | None) -> LibvirtClient:
    if client is not None:
        return client
    c = LibvirtClient()
    c.connect()
    return c


class NetworkManager:
    """High-level virtual network management.

    Args:
        client: Optional existing :class:`LibvirtClient`.

    Example::

        nm = NetworkManager()
        nm.create("mynet", mode="nat", subnet="192.168.122.0/24",
                  dhcp_range=("192.168.122.100", "192.168.122.200"))
        nm.start("mynet")
    """

    def __init__(self, client: LibvirtClient | None = None) -> None:
        self._client = client

    # ------------------------------------------------------------------
    # XML building
    # ------------------------------------------------------------------

    @staticmethod
    def _build_network_xml(
        name: str,
        mode: str = "nat",
        bridge: str | None = None,
        subnet: str | None = None,
        dhcp_range: tuple[str, str] | None = None,
        dns: str | None = None,
        domain: str | None = None,
        forward_dev: str | None = None,
    ) -> str:
        """Construct a libvirt network XML string."""
        root = ET.Element("network")
        ET.SubElement(root, "name").text = name

        if domain:
            ET.SubElement(root, "domain", name=domain)

        if forward_dev or mode in ("nat", "route", "bridge", "private", "vepa", "passthrough"):
            fwd_attrs: dict[str, str] = {"mode": mode}
            if forward_dev:
                fwd_attrs["dev"] = forward_dev
            ET.SubElement(root, "forward", **fwd_attrs)

        # Parse subnet
        ip_base = "192.168.122"
        netmask = "255.255.255.0"
        if subnet:
            parts = subnet.split("/")
            ip_base = parts[0].rsplit(".", 1)[0]
            cidr = int(parts[1]) if len(parts) > 1 else 24
            netmask_bits = (0xFFFFFFFF << (32 - cidr)) & 0xFFFFFFFF
            netmask = ".".join(str((netmask_bits >> s) & 0xFF) for s in (24, 16, 8, 0))

        bridge_name = bridge or f"virbr-{name}"
        bridge_el = ET.SubElement(root, "bridge", name=bridge_name, stp="on", delay="0")

        ip_attrs: dict[str, str] = {"address": f"{ip_base}.1", "netmask": netmask}
        ip_el = ET.SubElement(root, "ip", **ip_attrs)

        if dhcp_range:
            dhcp_el = ET.SubElement(ip_el, "dhcp")
            ET.SubElement(dhcp_el, "range", start=dhcp_range[0], end=dhcp_range[1])

        if dns:
            dns_el = ET.SubElement(root, "dns")
            ET.SubElement(dns_el, "forwarder", addr=dns)

        ET.indent(root, space="  ")
        return ET.tostring(root, encoding="unicode")

    # ------------------------------------------------------------------
    # Core operations
    # ------------------------------------------------------------------

    def create(
        self,
        name: str,
        mode: str = "nat",
        bridge: str | None = None,
        subnet: str | None = None,
        dhcp_range: tuple[str, str] | None = None,
        dns: str | None = None,
        domain: str | None = None,
        forward_dev: str | None = None,
    ) -> None:
        """Define a new virtual network.

        Args:
            name: Network name.
            mode: Forwarding mode (``nat``, ``route``, ``bridge``,
                ``isolated``).
            bridge: Bridge device name (auto-generated if omitted).
            subnet: CIDR subnet (e.g. ``192.168.122.0/24``).
            dhcp_range: ``(start_ip, end_ip)`` tuple.
            dns: Upstream DNS forwarder IP.
            domain: DNS domain name.
            forward_dev: Physical device for forwarding.
        """
        xml = self._build_network_xml(
            name,
            mode=mode,
            bridge=bridge,
            subnet=subnet,
            dhcp_range=dhcp_range,
            dns=dns,
            domain=domain,
            forward_dev=forward_dev,
        )
        conn = _ensure_client(self._client)
        try:
            conn.conn.networkDefineXML(xml)
            logger.info("Defined network '%s' (mode=%s)", name, mode)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc

    def delete(self, name: str) -> None:
        """Undefine and destroy a network.

        Args:
            name: Network name.
        """
        conn = _ensure_client(self._client)
        net = conn.get_network(name)
        try:
            if net.isActive():
                net.destroy()
            net.undefine()
            logger.info("Deleted network '%s'", name)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc

    def list_all(self, active: bool = True, inactive: bool = True) -> list[dict]:
        """List networks with summary information.

        Returns:
            List of dicts with ``name``, ``active``, ``bridge``,
            ``autostart``.
        """
        conn = _ensure_client(self._client)
        networks = conn.list_networks(active=active, inactive=inactive)
        result = []
        for net in networks:
            try:
                info: dict = {
                    "name": net.name(),
                    "active": bool(net.isActive()),
                    "bridge": net.bridgeName() if net.isActive() else None,
                    "autostart": bool(net.autostart()),
                }
                result.append(info)
            except libvirt.libvirtError:
                result.append({"name": net.name(), "error": "failed to query"})
        return result

    def start(self, name: str) -> None:
        """Start a defined network.

        Args:
            name: Network name.
        """
        conn = _ensure_client(self._client)
        net = conn.get_network(name)
        try:
            net.create()
            logger.info("Started network '%s'", name)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc

    def stop(self, name: str) -> None:
        """Stop (destroy) a running network.

        Args:
            name: Network name.
        """
        conn = _ensure_client(self._client)
        net = conn.get_network(name)
        try:
            net.destroy()
            logger.info("Stopped network '%s'", name)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc

    def set_autostart(self, name: str, enabled: bool = True) -> None:
        """Enable or disable autostart for a network."""
        conn = _ensure_client(self._client)
        net = conn.get_network(name)
        try:
            net.setAutostart(1 if enabled else 0)
            logger.info("Autostart for network '%s' set to %s", name, enabled)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc

    def add_static_lease(
        self,
        network: str,
        mac: str,
        ip: str,
        hostname: str | None = None,
    ) -> None:
        """Add a static DHCP lease to a network.

        Args:
            network: Network name.
            mac: MAC address for the lease.
            ip: IP address to assign.
            hostname: Optional hostname.
        """
        conn = _ensure_client(self._client)
        net = conn.get_network(network)
        try:
            xml_desc = net.XMLDesc(0)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc

        root = ET.fromstring(xml_desc)
        ip_el = root.find(".//ip")
        if ip_el is None:
            raise LibvirtError(f"Network '{network}' has no <ip> definition")

        dhcp_el = ip_el.find("dhcp")
        if dhcp_el is None:
            dhcp_el = ET.SubElement(ip_el, "dhcp")

        # Avoid duplicate leases
        for host in dhcp_el.findall("host"):
            if host.get("mac", "").lower() == mac.lower():
                host.set("ip", ip)
                if hostname:
                    host.set("name", hostname)
                logger.info("Updated static lease for MAC %s -> %s", mac, ip)
                break
        else:
            attrs: dict[str, str] = {"mac": mac, "ip": ip}
            if hostname:
                attrs["name"] = hostname
            ET.SubElement(dhcp_el, "host", **attrs)
            logger.info("Added static lease: MAC=%s IP=%s", mac, ip)

        ET.indent(root, space="  ")
        new_xml = ET.tostring(root, encoding="unicode")
        try:
            net.update(
                libvirt.VIR_NETWORK_UPDATE_AFFECT_LIVE | libvirt.VIR_NETWORK_UPDATE_AFFECT_CONFIG,
                libvirt.VIR_NETWORK_UPDATE_COMMAND_ADD_LAST,
                libvirt.VIR_NETWORK_SECTION_IP_DHCP_HOST,
                -1,
                new_xml,
            )
        except libvirt.libvirtError:
            # Fallback: redefine the network
            try:
                conn.conn.networkDefineXML(new_xml)
                logger.info("Redefined network '%s' with new lease", network)
            except libvirt.libvirtError as exc2:
                raise _wrap_libvirt_error(exc2) from exc2

    def get_leases(self, network: str) -> list[dict]:
        """Return active DHCP leases for a network.

        Returns:
            List of dicts with ``mac``, ``ip``, ``hostname``, ``expiry``.
        """
        conn = _ensure_client(self._client)
        net = conn.get_network(network)
        try:
            leases_xml = net.XMLDesc(0)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc

        root = ET.fromstring(leases_xml)
        result = []
        for ip_el in root.findall(".//ip"):
            dhcp_el = ip_el.find("dhcp")
            if dhcp_el is None:
                continue
            for host in dhcp_el.findall("host"):
                result.append({
                    "mac": host.get("mac"),
                    "ip": host.get("ip"),
                    "hostname": host.get("name"),
                    "type": "static",
                })
        return result

    def get_info(self, name: str) -> dict:
        """Return detailed information about a network.

        Returns:
            Dict with ``name``, ``uuid``, ``active``, ``bridge``,
            ``autostart``, ``persistent``, ``dhcp_range``, ``mode``.
        """
        conn = _ensure_client(self._client)
        net = conn.get_network(name)
        try:
            xml_desc = net.XMLDesc(0)
            root = ET.fromstring(xml_desc)

            mode_el = root.find("forward")
            mode = mode_el.get("mode", "none") if mode_el is not None else "none"

            ip_el = root.find(".//ip")
            dhcp_range = None
            if ip_el is not None:
                dhcp_el = ip_el.find("dhcp")
                if dhcp_el is not None:
                    range_el = dhcp_el.find("range")
                    if range_el is not None:
                        dhcp_range = (range_el.get("start"), range_el.get("end"))

            return {
                "name": net.name(),
                "uuid": net.UUIDString(),
                "active": bool(net.isActive()),
                "bridge": net.bridgeName() if net.isActive() else None,
                "autostart": bool(net.autostart()),
                "persistent": bool(net.isPersistent()),
                "mode": mode,
                "dhcp_range": dhcp_range,
            }
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc
