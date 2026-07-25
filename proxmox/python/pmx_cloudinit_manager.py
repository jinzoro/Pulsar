# SPDX-License-Identifier: MIT
# proxmox-kvm-swissknife - CloudInit Manager

"""Proxmox VE CloudInit image and configuration management."""

from __future__ import annotations

import logging
from typing import Any

from pve_api_client import PVEClient

logger = logging.getLogger(__name__)


class CloudInitManager:
    """High-level CloudInit configuration and image operations.

    Parameters
    ----------
    client:
        An authenticated :class:`PVEClient` instance.
    """

    def __init__(self, client: PVEClient) -> None:
        self._client = client

    def configure(
        self,
        node: str,
        vmid: int,
        user: str | None = None,
        password: str | None = None,
        ssh_keys: str | None = None,
        ip: str | None = None,
        gateway: str | None = None,
        dns: str | None = None,
        nameserver: str | None = None,
        searchdomain: str | None = None,
    ) -> dict[str, Any]:
        """Configure CloudInit parameters for a VM.

        Parameters
        ----------
        node:
            Proxmox node name.
        vmid:
            VM ID (must have a CloudInit drive attached).
        user:
            Default user name, e.g. ``ubuntu``.
        password:
            Default user password.
        ssh_keys:
            SSH public key(s), newline-separated.
        ip:
            Static IP in CIDR notation, e.g. ``10.0.0.100/24``.
            Use ``ip=dhcp`` for DHCP.
        gateway:
            Default gateway.
        dns:
            DNS server.
        nameserver:
            Nameserver (space-separated IPs).
        searchdomain:
            DNS search domain.
        """
        data: dict[str, Any] = {}
        if user is not None:
            data["ciuser"] = user
        if password is not None:
            data["cipassword"] = password
        if ssh_keys is not None:
            data["sshkeys"] = ssh_keys
        if ip is not None:
            if ip.lower() == "dhcp":
                data["ipconfig0"] = "ip=dhcp"
            else:
                ipconfig = f"ip={ip}"
                if gateway:
                    ipconfig += f",gw={gateway}"
                data["ipconfig0"] = ipconfig
        if dns is not None:
            data["nameserver"] = dns
        if nameserver is not None:
            data["nameserver"] = nameserver
        if searchdomain is not None:
            data["searchdomain"] = searchdomain

        if not data:
            raise ValueError("At least one CloudInit parameter must be provided")

        logger.info("Configuring CloudInit for VM %d on node %s", vmid, node)
        result = self._client.put(
            f"/api2/json/nodes/{node}/qemu/{vmid}", data=data
        )
        logger.info("CloudInit configured for VM %d", vmid)
        return result

    def regenerate(self, node: str, vmid: int) -> dict[str, Any]:
        """Regenerate the CloudInit drive.

        This rebuilds the CloudInit ISO from the current configuration.
        """
        logger.info("Regenerating CloudInit drive for VM %d on node %s", vmid, node)
        result = self._client.post(
            f"/api2/json/nodes/{node}/qemu/{vmid}/cloudinit/modify",
            data={"drive": "ide2"},
        )
        logger.info("CloudInit drive regenerated for VM %d", vmid)
        return result

    def dump(self, node: str, vmid: int) -> dict[str, Any]:
        """Return the rendered CloudInit configuration (user-data, network-data, meta-data)."""
        logger.info("Dumping CloudInit config for VM %d on node %s", vmid, node)
        return self._client.get(f"/api2/json/nodes/{node}/qemu/{vmid}/cloudinit/dump")

    def download_image(
        self,
        node: str,
        os_name: str,
        version: str | None = None,
        storage: str = "local",
    ) -> dict[str, Any]:
        """Download a CloudInit-ready OS image template.

        Parameters
        ----------
        os_name:
            OS name, e.g. ``ubuntu``, ``debian``, ``centos``.
        version:
            OS version, e.g. ``22.04``, ``12``.
        storage:
            Target storage for the template.
        """
        # Build template name
        template_name = os_name
        if version:
            template_name = f"{os_name}-{version}"

        logger.info(
            "Downloading CloudInit image '%s' to storage '%s' on node %s",
            template_name, storage, node,
        )
        result = self._client.post(
            f"/api2/json/nodes/{node}/storage/{storage}/download-url",
            data={
                "content": "vztmpl",
                "filename": template_name,
            },
        )
        return result

    def create_template(
        self,
        node: str,
        vmid: int,
        template_name: str | None = None,
    ) -> dict[str, Any]:
        """Convert a configured VM into a CloudInit template.

        Parameters
        ----------
        vmid:
            VM ID to convert.
        template_name:
            Optional name for the template.
        """
        logger.info("Creating CloudInit template from VM %d on node %s", vmid, node)

        # First convert to template
        result = self._client.post(
            f"/api2/json/nodes/{node}/qemu/{vmid}/template"
        )

        if template_name:
            self._client.put(
                f"/api2/json/nodes/{node}/qemu/{vmid}",
                data={"description": template_name},
            )

        logger.info("Template created from VM %d", vmid)
        return result
