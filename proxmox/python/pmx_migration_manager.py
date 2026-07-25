# SPDX-License-Identifier: MIT
# Pulsar - Migration Manager

"""VM / container live migration across Proxmox nodes."""

from __future__ import annotations

import logging
from typing import Any

from pve_api_client import PVEClient

logger = logging.getLogger(__name__)


class MigrationManager:
    """High-level live migration operations.

    Parameters
    ----------
    client:
        An authenticated :class:`PVEClient` instance.
    """

    def __init__(self, client: PVEClient) -> None:
        self._client = client

    def migrate(
        self,
        node: str,
        vmid: int,
        target_node: str,
        online: bool = True,
        with_local_disks: bool = False,
        bandwidth_limit: int | None = None,
    ) -> dict[str, Any]:
        """Migrate a VM or container to another node.

        Parameters
        ----------
        node:
            Source node name.
        vmid:
            VM / container ID.
        target_node:
            Destination node name.
        online:
            Perform a live migration.
        with_local_disks:
            Also migrate locally-used disks.
        bandwidth_limit:
            Speed limit in KiB/s for the migration.
        """
        data: dict[str, Any] = {
            "target": target_node,
            "online": 1 if online else 0,
        }
        if with_local_disks:
            data["localdisk"] = 1
        if bandwidth_limit is not None:
            data["bwlimit"] = bandwidth_limit

        logger.info(
            "Migrating VM %d from %s → %s (online=%s)", vmid, node, target_node, online
        )
        result = self._client.post(
            f"/api2/json/nodes/{node}/qemu/{vmid}/migrate", data=data
        )
        logger.info("Migration of VM %d initiated", vmid)
        return result

    def status(self, node: str, vmid: int) -> dict[str, Any]:
        """Return migration status for a VM."""
        return self._client.get(f"/api2/json/nodes/{node}/qemu/{vmid}/migratestatus")

    def batch_migrate(
        self,
        source_node: str,
        target_node: str,
        vmids: list[int],
        online: bool = True,
    ) -> dict[str, dict[str, Any]]:
        """Migrate multiple VMs sequentially.

        Returns a mapping of VMID → result dict.
        """
        results: dict[str, dict[str, Any]] = {}
        for vmid in vmids:
            try:
                results[str(vmid)] = self.migrate(
                    source_node, vmid, target_node, online=online
                )
            except Exception as exc:
                logger.error("Migration of VM %d failed: %s", vmid, exc)
                results[str(vmid)] = {"error": str(exc)}
        return results

    def evacuate(
        self,
        node: str,
        target_node: str | None = None,
    ) -> dict[str, dict[str, Any]]:
        """Evacuate all VMs from a node.

        Parameters
        ----------
        node:
            Node to evacuate.
        target_node:
            If provided, migrate all VMs to this node. Otherwise Proxmox
            selects the target automatically.
        """
        vms = self._client.vm_list(node)
        vmids = [int(vm["vmid"]) for vm in vms if vm.get("status") != "running" or True]

        if not vmids:
            logger.info("No VMs to evacuate from node %s", node)
            return {}

        if target_node:
            return self.batch_migrate(node, target_node, vmids, online=True)

        results: dict[str, dict[str, Any]] = {}
        for vmid in vmids:
            try:
                data: dict[str, Any] = {"online": 1}
                if target_node:
                    data["target"] = target_node
                results[str(vmid)] = self._client.post(
                    f"/api2/json/nodes/{node}/qemu/{vmid}/migrate", data=data
                )
            except Exception as exc:
                logger.error("Evacuation of VM %d from %s failed: %s", vmid, node, exc)
                results[str(vmid)] = {"error": str(exc)}
        return results
