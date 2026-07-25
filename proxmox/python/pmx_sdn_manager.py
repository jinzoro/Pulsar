# SPDX-License-Identifier: MIT
# Pulsar - SDN Manager

"""Proxmox VE Software-Defined Networking management."""

from __future__ import annotations

import logging
from typing import Any

from pve_api_client import PVEClient

logger = logging.getLogger(__name__)


class SDNManager:
    """High-level SDN zone, VNet and subnet operations.

    Parameters
    ----------
    client:
        An authenticated :class:`PVEClient` instance.
    """

    def __init__(self, client: PVEClient) -> None:
        self._client = client

    def list_zones(self, node: str) -> list[dict[str, Any]]:
        """List SDN zones on a node."""
        return self._client.get(f"/api2/json/nodes/{node}/sdn/zones")  # type: ignore[return-value]

    def create_zone(
        self,
        node: str,
        zone_id: str,
        zone_type: str,
        ipam: str | None = None,
        dns: str | None = None,
    ) -> dict[str, Any]:
        """Create an SDN zone.

        Parameters
        ----------
        zone_id:
            Zone identifier.
        zone_type:
            Zone type – ``simple``, ``vlan``, ``qinq``, ``vxlan``, ``evpn``.
        ipam:
            IPAM plugin.
        dns:
            DNS plugin.
        """
        data: dict[str, Any] = {
            "zone": zone_id,
            "type": zone_type,
        }
        if ipam:
            data["ipam"] = ipam
        if dns:
            data["dns"] = dns

        logger.info("Creating SDN zone '%s' (type=%s) on node %s", zone_id, zone_type, node)
        result = self._client.post(f"/api2/json/nodes/{node}/sdn/zones", data=data)
        logger.info("Zone '%s' created – applying SDN", zone_id)
        self._client.post(f"/api2/json/nodes/{node}/sdn")
        return result

    def delete_zone(self, node: str, zone_id: str) -> dict[str, Any]:
        """Delete an SDN zone."""
        logger.info("Deleting SDN zone '%s' on node %s", zone_id, node)
        result = self._client.delete(f"/api2/json/nodes/{node}/sdn/zones/{zone_id}")
        self._client.post(f"/api2/json/nodes/{node}/sdn")
        return result

    def list_vnets(self, node: str) -> list[dict[str, Any]]:
        """List VNets."""
        return self._client.get(f"/api2/json/nodes/{node}/sdn/vnets")  # type: ignore[return-value]

    def create_vnet(
        self,
        node: str,
        vnet_id: str,
        zone: str,
        alias: str | None = None,
    ) -> dict[str, Any]:
        """Create a VNet.

        Parameters
        ----------
        vnet_id:
            VNet identifier.
        zone:
            Zone this VNet belongs to.
        alias:
            Display alias.
        """
        data: dict[str, Any] = {
            "vnet": vnet_id,
            "zone": zone,
        }
        if alias:
            data["alias"] = alias

        logger.info("Creating VNet '%s' in zone '%s' on node %s", vnet_id, zone, node)
        result = self._client.post(f"/api2/json/nodes/{node}/sdn/vnets", data=data)
        self._client.post(f"/api2/json/nodes/{node}/sdn")
        return result

    def delete_vnet(self, node: str, vnet_id: str) -> dict[str, Any]:
        """Delete a VNet."""
        logger.info("Deleting VNet '%s' on node %s", vnet_id, node)
        result = self._client.delete(f"/api2/json/nodes/{node}/sdn/vnets/{vnet_id}")
        self._client.post(f"/api2/json/nodes/{node}/sdn")
        return result

    def list_subnets(self, node: str) -> list[dict[str, Any]]:
        """List subnets across all VNets."""
        vnets = self.list_vnets(node)
        all_subnets: list[dict[str, Any]] = []
        for vnet in vnets:
            vnet_id = vnet.get("vnet", "")
            subnets = self._client.get(
                f"/api2/json/nodes/{node}/sdn/vnets/{vnet_id}/subnets"
            )
            if isinstance(subnets, list):
                all_subnets.extend(subnets)
        return all_subnets

    def create_subnet(
        self,
        node: str,
        vnet_id: str,
        cidr: str,
        gateway: str | None = None,
        dhcp_range: str | None = None,
    ) -> dict[str, Any]:
        """Create a subnet within a VNet.

        Parameters
        ----------
        vnet_id:
            VNet to attach to.
        cidr:
            Subnet CIDR, e.g. ``10.0.0.0/24``.
        gateway:
            Gateway address.
        dhcp_range:
            DHCP range, e.g. ``10.0.0.100-10.0.0.200``.
        """
        data: dict[str, Any] = {"cidr": cidr}
        if gateway:
            data["gateway"] = gateway
        if dhcp_range:
            parts = dhcp_range.split("-", 1)
            if len(parts) == 2:
                data["dhcpstart"] = parts[0]
                data["dhcpend"] = parts[1]

        logger.info("Creating subnet '%s' on VNet '%s' (node %s)", cidr, vnet_id, node)
        result = self._client.post(
            f"/api2/json/nodes/{node}/sdn/vnets/{vnet_id}/subnets", data=data
        )
        self._client.post(f"/api2/json/nodes/{node}/sdn")
        return result

    def delete_subnet(self, node: str, vnet_id: str, cidr: str) -> dict[str, Any]:
        """Delete a subnet."""
        encoded_cidr = cidr.replace("/", "%2F")
        logger.info("Deleting subnet '%s' from VNet '%s'", cidr, vnet_id)
        result = self._client.delete(
            f"/api2/json/nodes/{node}/sdn/vnets/{vnet_id}/subnets/{encoded_cidr}"
        )
        self._client.post(f"/api2/json/nodes/{node}/sdn")
        return result

    def apply(self, node: str) -> dict[str, Any]:
        """Apply pending SDN configuration."""
        logger.info("Applying SDN config on node %s", node)
        return self._client.post(f"/api2/json/nodes/{node}/sdn")
