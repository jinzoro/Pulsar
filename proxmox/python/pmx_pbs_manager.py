# SPDX-License-Identifier: MIT
# proxmox-kvm-swissknife - Proxmox Backup Server Manager

"""Integration with Proxmox Backup Server (PBS) via the Proxmox API."""

from __future__ import annotations

import logging
from typing import Any

from pve_api_client import PVEClient

logger = logging.getLogger(__name__)


class PBSManager:
    """High-level Proxmox Backup Server operations.

    Parameters
    ----------
    client:
        An authenticated :class:`PVEClient` instance.
    """

    def __init__(self, client: PVEClient) -> None:
        self._client = client

    def add_datastore(
        self,
        name: str,
        server: str,
        token: str,
        fingerprint: str | None = None,
    ) -> dict[str, Any]:
        """Register a PBS datastore as a Proxmox backup target.

        Parameters
        ----------
        name:
            Local name for the datastore.
        server:
            PBS server address, e.g. ``pbs.example.com``.
        token:
            API token in the format ``USER@REALM!TOKENID=UUID``.
        fingerprint:
            TLS fingerprint of the PBS server.
        """
        data: dict[str, Any] = {
            "type": "pbs",
            "server": server,
            "content": "backup,restore",
            "token": token,
        }
        if fingerprint:
            data["fingerprint"] = fingerprint

        logger.info("Adding PBS datastore '%s' → %s", name, server)
        # PBS datastores are added per-node via the storage API
        nodes = self._client.nodes()
        results: dict[str, Any] = {}
        for node_info in nodes:
            node = node_info["node"]
            try:
                results[node] = self._client.post(
                    f"/api2/json/nodes/{node}/storage",
                    data={"storage": name, **data},
                )
            except Exception as exc:
                logger.error("Failed to add PBS datastore on node %s: %s", node, exc)
                results[node] = {"error": str(exc)}
        return results

    def list_datastores(self) -> list[dict[str, Any]]:
        """List PBS-type storage backends across the cluster."""
        all_storage: list[dict[str, Any]] = []
        nodes = self._client.nodes()
        for node_info in nodes:
            storage_list = self._client.storage_list(node_info["node"])
            for s in storage_list:
                if s.get("type") == "pbs":
                    all_storage.append(s)
        return all_storage

    def backup(
        self,
        vmid: int,
        datastore: str,
        node: str | None = None,
    ) -> dict[str, Any]:
        """Trigger a PBS backup for a VM / container.

        Parameters
        ----------
        vmid:
            VM / container ID.
        datastore:
            PBS datastore name.
        node:
            If provided, trigger backup on this node only.
        """
        nodes = self._client.nodes() if node is None else [{"node": node}]
        results: dict[str, Any] = {}
        for node_info in nodes:
            n = node_info["node"]
            logger.info("Starting PBS backup of VM %d on node %s (datastore=%s)", vmid, n, datastore)
            try:
                results[n] = self._client.post(
                    f"/api2/json/nodes/{n}/storage/{datastore}/vzdump",
                    data={"vmid": str(vmid), "mode": "snapshot"},
                )
            except Exception as exc:
                logger.error("PBS backup of VM %d on node %s failed: %s", vmid, n, exc)
                results[n] = {"error": str(exc)}
        return results

    def restore(
        self,
        vmid: int,
        datastore: str,
        snapshot: str,
        target_node: str | None = None,
        target_storage: str | None = None,
    ) -> dict[str, Any]:
        """Restore a VM / container from a PBS backup.

        Parameters
        ----------
        vmid:
            Target VM / container ID.
        datastore:
            PBS datastore name.
        snapshot:
            Backup snapshot identifier.
        target_node:
            Node to restore to.
        target_storage:
            Storage for the restored disks.
        """
        node = target_node or self._client.nodes()[0]["node"]
        data: dict[str, Any] = {
            "vmid": str(vmid),
            "archive": f"{datastore}:{snapshot}",
        }
        if target_storage:
            data["storage"] = target_storage

        logger.info("Restoring PBS backup %s:%s to VM %d on node %s", datastore, snapshot, vmid, node)
        return self._client.post(
            f"/api2/json/nodes/{node}/storage/{datastore}/vzdump/restore", data=data
        )

    def verify(
        self,
        datastore: str,
        snapshot: str | None = None,
    ) -> dict[str, Any]:
        """Verify the integrity of PBS backup data.

        Parameters
        ----------
        datastore:
            PBS datastore name.
        snapshot:
            Specific snapshot to verify – all if *None*.
        """
        data: dict[str, Any] = {"storage": datastore}
        if snapshot:
            data["archive"] = snapshot
        logger.info("Verifying PBS datastore '%s'", datastore)
        nodes = self._client.nodes()
        results: dict[str, Any] = {}
        for node_info in nodes:
            n = node_info["node"]
            try:
                results[n] = self._client.post(
                    f"/api2/json/nodes/{n}/vzdump/verify", data=data
                )
            except Exception as exc:
                logger.error("PBS verify on node %s failed: %s", n, exc)
                results[n] = {"error": str(exc)}
        return results

    def prune(
        self,
        datastore: str,
        keep_daily: int = 7,
        keep_weekly: int = 4,
        keep_monthly: int = 6,
    ) -> dict[str, Any]:
        """Prune old backups on a PBS datastore.

        Parameters
        ----------
        keep_daily:
            Daily backups to keep.
        keep_weekly:
            Weekly backups to keep.
        keep_monthly:
            Monthly backups to keep.
        """
        retention = (
            f"keep-daily={keep_daily},keep-weekly={keep_weekly},keep-monthly={keep_monthly}"
        )
        logger.info("Pruning PBS datastore '%s' (retention=%s)", datastore, retention)
        nodes = self._client.nodes()
        results: dict[str, Any] = {}
        for node_info in nodes:
            n = node_info["node"]
            try:
                results[n] = self._client.post(
                    f"/api2/json/nodes/{n}/vzdump/prune",
                    data={"storage": datastore, "retain": retention},
                )
            except Exception as exc:
                logger.error("PBS prune on node %s failed: %s", n, exc)
                results[n] = {"error": str(exc)}
        return results

    def status(self, datastore: str) -> dict[str, Any]:
        """Return status of a PBS datastore."""
        nodes = self._client.nodes()
        if not nodes:
            return {"error": "No nodes available"}
        node = nodes[0]["node"]
        return self._client.storage_status(node, datastore)
