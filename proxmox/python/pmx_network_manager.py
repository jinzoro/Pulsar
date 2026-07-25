# SPDX-License-Identifier: MIT
# Pulsar - Network Manager

"""Proxmox VE host network interface management."""

from __future__ import annotations

import logging
from typing import Any

from pve_api_client import PVEClient

logger = logging.getLogger(__name__)


class NetworkManager:
    """High-level network configuration operations on Proxmox nodes.

    Parameters
    ----------
    client:
        An authenticated :class:`PVEClient` instance.
    """

    def __init__(self, client: PVEClient) -> None:
        self._client = client

    def list_interfaces(self, node: str) -> list[dict[str, Any]]:
        """List network interfaces on a node."""
        return self._client.network_list(node)

    def create_bridge(
        self,
        node: str,
        name: str,
        ports: list[str] | None = None,
        vlan_aware: bool = False,
        mtu: int | None = None,
    ) -> dict[str, Any]:
        """Create a Linux bridge.

        Parameters
        ----------
        name:
            Bridge name, e.g. ``vmbr0``.
        ports:
            Slave interfaces to add.
        vlan_aware:
            Enable VLAN filtering.
        mtu:
            MTU size.
        """
        iface: dict[str, Any] = {
            "name": name,
            "type": "bridge",
        }
        if ports:
            iface["bridge_ports"] = " ".join(ports)
        if vlan_aware:
            iface["vlan_aware"] = 1
        if mtu is not None:
            iface["mtu"] = mtu

        logger.info("Creating bridge '%s' on node %s", name, node)
        result = self._client.post(
            f"/api2/json/nodes/{node}/network", data=iface
        )
        logger.info("Bridge '%s' created – applying changes", name)
        self._client.post(f"/api2/json/nodes/{node}/network/apply")
        return result

    def delete_bridge(self, node: str, name: str) -> dict[str, Any]:
        """Delete a Linux bridge."""
        logger.info("Deleting bridge '%s' on node %s", name, node)
        result = self._client.delete(f"/api2/json/nodes/{node}/network/{name}")
        self._client.post(f"/api2/json/nodes/{node}/network/apply")
        return result

    def create_bond(
        self,
        node: str,
        name: str,
        slaves: list[str],
        mode: str = "active-backup",
        mtu: int | None = None,
    ) -> dict[str, Any]:
        """Create a network bond.

        Parameters
        ----------
        name:
            Bond name, e.g. ``bond0``.
        slaves:
            Slave interfaces.
        mode:
            Bonding mode – ``active-backup``, ``balance-rr``, ``802.3ad``, etc.
        mtu:
            MTU size.
        """
        iface: dict[str, Any] = {
            "name": name,
            "type": "bond",
            "bond_mode": mode,
            "bond_slaves": " ".join(slaves),
        }
        if mtu is not None:
            iface["mtu"] = mtu

        logger.info("Creating bond '%s' (mode=%s) on node %s", name, mode, node)
        result = self._client.post(f"/api2/json/nodes/{node}/network", data=iface)
        self._client.post(f"/api2/json/nodes/{node}/network/apply")
        return result

    def delete_bond(self, node: str, name: str) -> dict[str, Any]:
        """Delete a network bond."""
        logger.info("Deleting bond '%s' on node %s", name, node)
        result = self._client.delete(f"/api2/json/nodes/{node}/network/{name}")
        self._client.post(f"/api2/json/nodes/{node}/network/apply")
        return result

    def create_vlan(
        self, node: str, name: str, parent: str, vlan_id: int
    ) -> dict[str, Any]:
        """Create a VLAN interface.

        Parameters
        ----------
        name:
            VLAN interface name, e.g. ``vmbr0.100``.
        parent:
            Parent interface.
        vlan_id:
            VLAN tag ID.
        """
        iface: dict[str, Any] = {
            "name": name,
            "type": "vlan",
            "vlan_id": vlan_id,
            "vlan_raw_device": parent,
        }
        logger.info("Creating VLAN %d (%s) on node %s", vlan_id, name, node)
        result = self._client.post(f"/api2/json/nodes/{node}/network", data=iface)
        self._client.post(f"/api2/json/nodes/{node}/network/apply")
        return result

    def delete_vlan(self, node: str, name: str) -> dict[str, Any]:
        """Delete a VLAN interface."""
        logger.info("Deleting VLAN '%s' on node %s", name, node)
        result = self._client.delete(f"/api2/json/nodes/{node}/network/{name}")
        self._client.post(f"/api2/json/nodes/{node}/network/apply")
        return result

    def apply_config(self, node: str) -> dict[str, Any]:
        """Apply pending network configuration changes."""
        logger.info("Applying network config on node %s", node)
        return self._client.post(f"/api2/json/nodes/{node}/network/apply")
