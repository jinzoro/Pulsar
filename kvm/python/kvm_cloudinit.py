"""
SPDX-License-Identifier: MIT
Cloud-init ISO generation and domain configuration.

Provides ``CloudInitManager`` for creating cloud-init ISOs, attaching
them to KVM domains, and injecting user-data, meta-data, and
network-config.
"""

from __future__ import annotations

import logging
import os
import subprocess
import tempfile
from typing import Any

import libvirt
import xml.etree.ElementTree as ET

from kvm_libvirt_client import LibvirtClient, LibvirtError, _wrap_libvirt_error

logger = logging.getLogger(__name__)


class CloudInitError(Exception):
    """Raised when a cloud-init operation fails."""


class CloudInitManager:
    """Manage cloud-init for KVM domains.

    Example::

        ci = CloudInitManager()
        iso = ci.create_iso("web01", user="root", password="changeme",
                            ip="192.168.122.100/24",
                            gateway="192.168.122.1")
        ci.attach_iso("web01", iso)
    """

    def __init__(self, client: LibvirtClient | None = None) -> None:
        self._client = client

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _run(cmd: list[str], check: bool = True) -> subprocess.CompletedProcess[str]:
        logger.debug("Running: %s", " ".join(cmd))
        result = subprocess.run(cmd, capture_output=True, text=True, check=False)
        if check and result.returncode != 0:
            raise CloudInitError(
                f"Command failed (rc={result.returncode}): "
                f"{result.stderr.strip() or result.stdout.strip()}"
            )
        return result

    @staticmethod
    def _ensure_client(client: LibvirtClient | None) -> LibvirtClient:
        if client is not None:
            return client
        c = LibvirtClient()
        c.connect()
        return c

    # ------------------------------------------------------------------
    # ISO creation
    # ------------------------------------------------------------------

    def create_iso(
        self,
        domain: str,
        user: str = "root",
        password: str | None = None,
        ssh_keys_file: str | None = None,
        hostname: str | None = None,
        ip: str | None = None,
        gateway: str | None = None,
        dns: str | None = None,
        output_path: str | None = None,
    ) -> str:
        """Generate a cloud-init NoCloud seed ISO.

        Creates ``meta-data``, ``user-data``, and optionally
        ``network-config`` then combines them into an ISO with
        ``genisoimage`` or ``mkisofs``.

        Args:
            domain: Domain name (used for default output path).
            user: Default user name.
            password: Default user password.
            ssh_keys_file: Path to an authorized_keys file.
            hostname: Guest hostname.
            ip: Static IP in CIDR notation (e.g. ``192.168.122.100/24``).
            gateway: Default gateway.
            dns: DNS server(s).
            output_path: ISO destination path.

        Returns:
            Path to the generated ISO.
        """
        if output_path is None:
            output_path = f"/var/lib/libvirt/images/{domain}-cloud-init.iso"

        with tempfile.TemporaryDirectory(prefix="cloudinit_") as tmpdir:
            # meta-data
            meta_lines = [
                "instance-id: {domain}".format(domain=domain),
                f"local-hostname: {hostname or domain}",
            ]
            if ip:
                # Parse CIDR
                ip_parts = ip.split("/")
                ip_addr = ip_parts[0]
                cidr = int(ip_parts[1]) if len(ip_parts) > 1 else 24
                netmask_bits = (0xFFFFFFFF << (32 - cidr)) & 0xFFFFFFFF
                netmask = ".".join(
                    str((netmask_bits >> s) & 0xFF) for s in (24, 16, 8, 0)
                )
                meta_lines.extend([
                    "network-interfaces: |",
                    f"  iface eth0 inet static",
                    f"    address {ip_addr}",
                    f"    netmask {netmask}",
                ])
                if gateway:
                    meta_lines.append(f"    gateway {gateway}")
                if dns:
                    meta_lines.append(f"    dns-nameservers {dns}")

            with open(os.path.join(tmpdir, "meta-data"), "w") as fh:
                fh.write("\n".join(meta_lines) + "\n")

            # user-data
            user_lines = [
                "#cloud-config",
                f"users:",
                f"  - name: {user}",
                f"    shell: /bin/bash",
                f"    lock_passwd: false",
                f"    sudo: ALL=(ALL) NOPASSWD:ALL",
            ]
            if password:
                user_lines.append(f"    passwd: {password}")

            if ssh_keys_file and os.path.isfile(ssh_keys_file):
                with open(ssh_keys_file) as kf:
                    keys = [line.strip() for line in kf if line.strip() and not line.startswith("#")]
                if keys:
                    user_lines.append("ssh_authorized_keys:")
                    for key in keys:
                        user_lines.append(f"  - {key}")

            if hostname:
                user_lines.extend([
                    "hostname: " + hostname,
                    "manage_etc_hosts: true",
                ])

            # Package updates
            user_lines.extend([
                "package_update: true",
                "package_upgrade: true",
                "packages:",
                "  - qemu-guest-agent",
                "  - open-vm-tools",
            ])

            with open(os.path.join(tmpdir, "user-data"), "w") as fh:
                fh.write("\n".join(user_lines) + "\n")

            # network-config (if static IP)
            if ip or gateway:
                net_config = {
                    "version": 2,
                    "ethernets": {
                        "eth0": {
                            "dhcp4": False,
                            "dhcp6": False,
                        },
                    },
                }
                ip_parts = ip.split("/") if ip else ["", "24"]
                net_config["ethernets"]["eth0"]["addresses"] = [ip]
                if gateway:
                    net_config["ethernets"]["eth0"]["routes"] = [
                        {"to": "default", "via": gateway}
                    ]
                if dns:
                    net_config["ethernets"]["eth0"]["nameservers"] = {
                        "addresses": [dns] if isinstance(dns, str) else dns,
                    }
                import yaml
                with open(os.path.join(tmpdir, "network-config"), "w") as fh:
                    yaml.dump(net_config, fh)

            # Create ISO
            iso_cmd = self._find_iso_tool()
            iso_cmd += [
                "-output", output_path,
                "-volid", "cidata",
                "-joliet",
                "-rock",
                "-input-charset", "utf-8",
                os.path.join(tmpdir, "meta-data"),
                os.path.join(tmpdir, "user-data"),
            ]
            net_config_path = os.path.join(tmpdir, "network-config")
            if os.path.isfile(net_config_path):
                iso_cmd.append(net_config_path)

            self._run(iso_cmd)

        logger.info("Created cloud-init ISO for '%s' -> %s", domain, output_path)
        return output_path

    @staticmethod
    def _find_iso_tool() -> list[str]:
        """Locate genisoimage or mkisofs."""
        for tool in ("genisoimage", "mkisofs", "xorriso"):
            result = subprocess.run(
                ["which", tool], capture_output=True, text=True, check=False,
            )
            if result.returncode == 0:
                if tool == "xorriso":
                    return [tool, "-as", "mkisofs"]
                return [tool]
        raise CloudInitError(
            "No ISO creation tool found. Install genisoimage or xorriso."
        )

    # ------------------------------------------------------------------
    # Attach / configure
    # ------------------------------------------------------------------

    def attach_iso(self, domain: str, iso_path: str) -> None:
        """Attach a cloud-init ISO as a SATA CDROM to the domain.

        Args:
            domain: Domain name.
            iso_path: Path to the ISO file.
        """
        cdrom_xml = (
            f"<disk type='file' device='cdrom'>"
            f"  <driver name='qemu' type='raw'/>"
            f"  <source file='{iso_path}'/>"
            f"  <target dev='sda' bus='sata'/>"
            f"  <readonly/>"
            f"</disk>"
        )
        client = self._ensure_client(self._client)
        dom = client.get_domain(domain)
        try:
            # Remove existing cloud-init CDROM
            xml_desc = dom.XMLDesc(0)
            root = ET.fromstring(xml_desc)
            devices = root.find("devices")
            if devices is not None:
                for disk in devices.findall("disk"):
                    target = disk.find("target")
                    if target is not None and target.get("dev") == "sda":
                        src = disk.find("source")
                        if src is not None and "cloud-init" in (src.get("file") or ""):
                            devices.remove(disk)
                            break

            # Add new one
            flags = libvirt.VIR_DOMAIN_AFFECT_CONFIG
            dom.attachDeviceFlags(cdrom_xml, flags=flags)
            logger.info("Attached cloud-init ISO '%s' to VM '%s'", iso_path, domain)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc

    def configure(
        self,
        domain: str,
        user_data: str | None = None,
        meta_data: str | None = None,
        network_config: str | None = None,
    ) -> str:
        """Create and attach a cloud-init ISO from raw YAML strings.

        Args:
            domain: Domain name.
            user_data: Raw user-data YAML.
            meta_data: Raw meta-data YAML.
            network_config: Raw network-config YAML.

        Returns:
            Path to the generated ISO.
        """
        with tempfile.TemporaryDirectory(prefix="cloudinit_") as tmpdir:
            if meta_data:
                with open(os.path.join(tmpdir, "meta-data"), "w") as fh:
                    fh.write(meta_data)
            else:
                with open(os.path.join(tmpdir, "meta-data"), "w") as fh:
                    fh.write(f"instance-id: {domain}\nlocal-hostname: {domain}\n")

            if user_data:
                with open(os.path.join(tmpdir, "user-data"), "w") as fh:
                    fh.write(user_data)
            else:
                with open(os.path.join(tmpdir, "user-data"), "w") as fh:
                    fh.write("#cloud-config\npackage_update: true\n")

            iso_path = f"/var/lib/libvirt/images/{domain}-cloud-init.iso"
            iso_cmd = self._find_iso_tool()
            iso_cmd += [
                "-output", iso_path,
                "-volid", "cidata",
                "-joliet", "-rock",
                os.path.join(tmpdir, "meta-data"),
                os.path.join(tmpdir, "user-data"),
            ]

            files = [os.path.join(tmpdir, "meta-data"), os.path.join(tmpdir, "user-data")]
            if network_config:
                nc_path = os.path.join(tmpdir, "network-config")
                with open(nc_path, "w") as fh:
                    fh.write(network_config)
                iso_cmd.append(nc_path)

            self._run(iso_cmd)

        self.attach_iso(domain, iso_path)
        return iso_path

    def dump(self, domain: str) -> dict[str, str]:
        """Read the attached cloud-init ISO contents.

        Attempts to mount the ISO (read-only) and extract the
        ``meta-data`` and ``user-data`` files.

        Returns:
            Dict with ``meta_data``, ``user_data`` strings.
        """
        # Find the cloud-init CDROM path
        client = self._ensure_client(self._client)
        dom = client.get_domain(domain)
        try:
            xml_desc = dom.XMLDesc(0)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc

        root = ET.fromstring(xml_desc)
        iso_path = None
        for disk in root.findall(".//disk"):
            if disk.get("device") == "cdrom":
                src = disk.find("source")
                if src is not None:
                    f = src.get("file")
                    if f and "cloud-init" in f:
                        iso_path = f
                        break

        if not iso_path:
            return {"meta_data": "", "user_data": "", "error": "No cloud-init ISO found"}

        # Try to extract using isoinfo or mount
        result: dict[str, str] = {}
        with tempfile.TemporaryDirectory() as tmpdir:
            try:
                self._run([
                    "isoinfo", "-i", iso_path, "-x", "/meta-data;1",
                ], check=False)
                meta_result = subprocess.run(
                    ["isoinfo", "-i", iso_path, "-x", "/meta-data;1"],
                    capture_output=True, text=True, check=False,
                )
                result["meta_data"] = meta_result.stdout
                user_result = subprocess.run(
                    ["isoinfo", "-i", iso_path, "-x", "/user-data;1"],
                    capture_output=True, text=True, check=False,
                )
                result["user_data"] = user_result.stdout
            except (subprocess.SubprocessError, FileNotFoundError):
                result["error"] = "Cannot read ISO (install isoinfo)"
                result["meta_data"] = ""
                result["user_data"] = ""

        return result

    def inject_files(self, domain: str, files: dict[str, str]) -> None:
        """Inject files into the cloud-init user-data ``write_files`` section.

        Args:
            domain: Domain name.
            files: Mapping of ``{path: content}`` to inject.
        """
        import yaml

        # Dump existing ISO to get current user-data
        existing = self.dump(domain)
        current_user_data: dict[str, Any] = {}
        if existing.get("user_data"):
            try:
                current_user_data = yaml.safe_load(existing["user_data"]) or {}
            except yaml.YAMLError:
                current_user_data = {}

        # Add write_files
        write_files = current_user_data.get("write_files", [])
        for path, content in files.items():
            write_files.append({
                "path": path,
                "content": content,
                "permissions": "0644",
                "owner": "root:root",
            })
        current_user_data["write_files"] = write_files

        new_user_data = "#cloud-config\n" + yaml.dump(
            current_user_data, default_flow_style=False,
        )
        self.configure(domain, user_data=new_user_data)
        logger.info("Injected %d files into cloud-init for '%s'", len(files), domain)
