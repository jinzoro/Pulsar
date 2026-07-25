# SPDX-License-Identifier: MIT
# Pulsar - Backup Manager

"""Proxmox VE backup (VZDump) and restore operations."""

from __future__ import annotations

import logging
from typing import Any

from pve_api_client import PVEClient

logger = logging.getLogger(__name__)


class BackupManager:
    """High-level backup and restore operations via VZDump.

    Parameters
    ----------
    client:
        An authenticated :class:`PVEClient` instance.
    """

    def __init__(self, client: PVEClient) -> None:
        self._client = client

    def backup(
        self,
        node: str,
        vmid: int,
        storage: str,
        mode: str = "snapshot",
        compress: str = "zstd",
        retention: str | None = None,
    ) -> dict[str, Any]:
        """Trigger a backup for a VM or container.

        Parameters
        ----------
        node:
            Proxmox node name.
        vmid:
            VM / container ID.
        storage:
            Target backup storage.
        mode:
            Backup mode – ``snapshot``, ``suspend`` or ``stop``.
        compress:
            Compression algorithm – ``zstd``, ``gzip``, ``lzo`` or ``none``.
        retention:
            Retention policy string, e.g. ``keep-daily=7,keep-weekly=4``.
        """
        data: dict[str, Any] = {
            "vmid": str(vmid),
            "storage": storage,
            "mode": mode,
            "compress": compress,
        }
        if retention:
            data["retain"] = retention

        logger.info("Starting backup of VM %d on node %s (mode=%s)", vmid, node, mode)
        result = self._client.post(f"/api2/json/nodes/{node}/storage/{storage}/vzdump", data=data)
        logger.info("Backup initiated for VM %d", vmid)
        return result

    def restore(
        self,
        node: str,
        vmid: int,
        storage: str,
        backup_id: str,
        target_node: str | None = None,
        target_storage: str | None = None,
        target_vmid: int | None = None,
    ) -> dict[str, Any]:
        """Restore a backup to a VM / container.

        Parameters
        ----------
        backup_id:
            Backup archive identifier.
        target_node:
            Node to restore to (defaults to *node*).
        target_storage:
            Storage to restore disks to.
        target_vmid:
            New VMID for the restore.
        """
        data: dict[str, Any] = {
            "vmid": str(vmid),
            "archive": backup_id,
        }
        if target_node:
            data["target"] = target_node
        if target_storage:
            data["storage"] = target_storage
        if target_vmid:
            data["vmid"] = str(target_vmid)

        restore_node = target_node or node
        logger.info("Restoring backup %s to VM %d on node %s", backup_id, vmid, restore_node)
        result = self._client.post(
            f"/api2/json/nodes/{restore_node}/storage/{storage}/vzdump/restore",
            data=data,
        )
        logger.info("Restore completed for VM %d", vmid)
        return result

    def list_backups(
        self,
        node: str | None = None,
        vmid: int | None = None,
        storage: str | None = None,
    ) -> list[dict[str, Any]]:
        """List available backups.

        Parameters
        ----------
        node:
            Filter by node.
        vmid:
            Filter by VM / container ID.
        storage:
            Filter by storage.
        """
        results: list[dict[str, Any]] = []
        if node and storage:
            content = self._client.get(
                f"/api2/json/nodes/{node}/storage/{storage}/content",
                params={"content": "vzdump"},
            )
            if isinstance(content, list):
                results.extend(content)
        else:
            nodes = self._client.nodes()
            for n in nodes:
                storages = self._client.storage_list(n["node"])
                for s in storages:
                    content = self._client.get(
                        f"/api2/json/nodes/{n['node']}/storage/{s['storage']}/content",
                        params={"content": "vzdump"},
                    )
                    if isinstance(content, list):
                        results.extend(content)

        if vmid is not None:
            results = [b for b in results if str(vmid) in b.get("volid", "")]

        return results

    def verify(self, node: str, vmid: int, backup_id: str) -> dict[str, Any]:
        """Verify the integrity of a backup."""
        logger.info("Verifying backup %s for VM %d on node %s", backup_id, vmid, node)
        return self._client.post(
            f"/api2/json/nodes/{node}/vzdump/verify",
            data={"vmid": str(vmid), "archive": backup_id},
        )

    def prune(
        self,
        node: str,
        vmid: int,
        storage: str,
        keep_daily: int = 7,
        keep_weekly: int = 4,
        keep_monthly: int = 6,
    ) -> dict[str, Any]:
        """Prune old backups according to retention policy.

        Parameters
        ----------
        keep_daily:
            Number of daily backups to keep.
        keep_weekly:
            Number of weekly backups to keep.
        keep_monthly:
            Number of monthly backups to keep.
        """
        retention = (
            f"keep-daily={keep_daily},keep-weekly={keep_weekly},keep-monthly={keep_monthly}"
        )
        logger.info(
            "Pruning backups for VM %d on node %s (retention=%s)", vmid, node, retention
        )
        return self._client.post(
            f"/api2/json/nodes/{node}/vzdump/prune",
            data={"vmid": str(vmid), "storage": storage, "retain": retention},
        )

    def schedule_backup(
        self,
        node: str,
        vmid: int,
        cron: str,
        storage: str,
        mode: str = "snapshot",
    ) -> dict[str, Any]:
        """Create or update a scheduled backup job.

        Parameters
        ----------
        cron:
            Cron expression, e.g. ``daily`` or ``0 2 * * *``.
        """
        data: dict[str, Any] = {
            "vmid": str(vmid),
            "storage": storage,
            "mode": mode,
            "schedule": cron,
        }
        logger.info("Scheduling backup for VM %d on node %s: %s", vmid, node, cron)
        return self._client.post(f"/api2/json/nodes/{node}/vzdump", data=data)
