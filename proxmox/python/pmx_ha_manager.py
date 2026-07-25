# SPDX-License-Identifier: MIT
# proxmox-kvm-swissknife - High Availability Manager

"""Proxmox VE High Availability group and resource management."""

from __future__ import annotations

import logging
from typing import Any

from pve_api_client import PVEClient

logger = logging.getLogger(__name__)


class HAManager:
    """High-level HA group and resource operations.

    Parameters
    ----------
    client:
        An authenticated :class:`PVEClient` instance.
    """

    def __init__(self, client: PVEClient) -> None:
        self._client = client

    def list_groups(self) -> list[dict[str, Any]]:
        """List all HA groups."""
        return self._client.get("/api2/json/cluster/ha/groups")  # type: ignore[return-value]

    def create_group(
        self,
        group_id: str,
        nodes: list[str],
        max_restart: int = 3,
        max_relocate: int = 1,
    ) -> dict[str, Any]:
        """Create an HA group.

        Parameters
        ----------
        group_id:
            Unique group identifier.
        nodes:
            List of node names that can host the resources.
        max_restart:
            Maximum restart attempts before failover.
        max_relocate:
            Maximum relocate attempts before giving up.
        """
        nodes_param = ",".join(f"{n}=1" for n in nodes)
        data: dict[str, Any] = {
            "group": group_id,
            "nodes": nodes_param,
            "max_restart": max_restart,
            "max_relocate": max_relocate,
        }
        logger.info("Creating HA group '%s' with nodes %s", group_id, nodes)
        return self._client.post("/api2/json/cluster/ha/groups", data=data)

    def delete_group(self, group_id: str) -> dict[str, Any]:
        """Delete an HA group."""
        logger.info("Deleting HA group '%s'", group_id)
        return self._client.delete(f"/api2/json/cluster/ha/groups/{group_id}")

    def list_resources(self) -> list[dict[str, Any]]:
        """List all HA-managed resources."""
        return self._client.get("/api2/json/cluster/ha/resources")  # type: ignore[return-value]

    def add_resource(
        self,
        vmid: int,
        group: str,
        state: str = "started",
        max_restart: int = 3,
        max_relocate: int = 1,
        priority: int = 0,
    ) -> dict[str, Any]:
        """Register a VM / container as an HA resource.

        Parameters
        ----------
        vmid:
            VM / container ID.
        group:
            HA group to bind the resource to.
        state:
            Desired state – ``started``, ``stopped`` or ``disabled``.
        max_restart:
            Maximum restart attempts.
        max_relocate:
            Maximum relocate attempts.
        priority:
            Resource priority (higher wins).
        """
        sid = f"vm:{vmid}"
        data: dict[str, Any] = {
            "sid": sid,
            "type": "vm",
            "vmid": vmid,
            "group": group,
            "state": state,
            "max_restart": max_restart,
            "max_relocate": max_relocate,
            "priority": priority,
        }
        logger.info("Adding HA resource vm:%d to group '%s'", vmid, group)
        return self._client.post("/api2/json/cluster/ha/resources", data=data)

    def remove_resource(self, vmid: int) -> dict[str, Any]:
        """Remove a resource from HA management."""
        sid = f"vm:{vmid}"
        logger.info("Removing HA resource vm:%d", vmid)
        return self._client.delete(f"/api2/json/cluster/ha/resources/{vmid}")

    def set_state(self, vmid: int, state: str) -> dict[str, Any]:
        """Set the desired state of an HA resource.

        Parameters
        ----------
        state:
            One of ``started``, ``stopped`` or ``disabled``.
        """
        logger.info("Setting HA state for vm:%d to '%s'", vmid, state)
        return self._client.put(
            f"/api2/json/cluster/ha/resources/{vmid}",
            data={"state": state},
        )

    def get_status(self) -> dict[str, Any]:
        """Return overall HA manager status."""
        return self._client.get("/api2/json/cluster/ha/status")
