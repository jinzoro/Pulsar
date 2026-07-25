# SPDX-License-Identifier: MIT
# proxmox-kvm-swissknife - Snapshot Manager

"""VM / container snapshot management."""

from __future__ import annotations

import logging
from typing import Any

from pve_api_client import PVEClient

logger = logging.getLogger(__name__)


class SnapshotManager:
    """High-level snapshot operations for VMs and LXC containers.

    Parameters
    ----------
    client:
        An authenticated :class:`PVEClient` instance.
    """

    def __init__(self, client: PVEClient) -> None:
        self._client = client

    def create(
        self,
        node: str,
        vmid: int,
        name: str,
        description: str | None = None,
        include_ram: bool = False,
    ) -> dict[str, Any]:
        """Create a snapshot.

        Parameters
        ----------
        node:
            Proxmox node name.
        vmid:
            VM / container ID.
        name:
            Snapshot name.
        description:
            Optional description.
        include_ram:
            Include RAM in the snapshot (VM only, requires ``snaptime`` to be absent).
        """
        data: dict[str, Any] = {"snapname": name}
        if description:
            data["description"] = description
        if include_ram:
            data["ram"] = 1

        logger.info("Creating snapshot '%s' for VM %d on node %s", name, vmid, node)
        result = self._client.post(
            f"/api2/json/nodes/{node}/qemu/{vmid}/snapshot", data=data
        )
        logger.info("Snapshot '%s' created for VM %d", name, vmid)
        return result

    def list(self, node: str, vmid: int) -> list[dict[str, Any]]:
        """List all snapshots for a VM or container.

        Returns a list of snapshot dicts, each containing ``name``,
        ``description``, ``snaptime`` and ``vmstate`` keys.
        """
        return self._client.vm_snapshot_list(node, vmid)

    def rollback(self, node: str, vmid: int, snap_name: str) -> dict[str, Any]:
        """Roll back a VM or container to a snapshot.

        The VM / container should be stopped before rolling back.
        """
        logger.info(
            "Rolling back VM %d on node %s to snapshot '%s'", vmid, node, snap_name
        )
        result = self._client.post(
            f"/api2/json/nodes/{node}/qemu/{vmid}/snapshot/{snap_name}/rollback"
        )
        logger.info("Rollback to snapshot '%s' completed for VM %d", snap_name, vmid)
        return result

    def delete(self, node: str, vmid: int, snap_name: str) -> dict[str, Any]:
        """Delete a snapshot."""
        logger.info("Deleting snapshot '%s' for VM %d on node %s", snap_name, vmid, node)
        result = self._client.delete(
            f"/api2/json/nodes/{node}/qemu/{vmid}/snapshot/{snap_name}"
        )
        logger.info("Snapshot '%s' deleted for VM %d", snap_name, vmid)
        return result
