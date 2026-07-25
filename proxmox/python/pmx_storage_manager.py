# SPDX-License-Identifier: MIT
# proxmox-kvm-swissknife - Storage Manager

"""Proxmox storage backend management."""

from __future__ import annotations

import logging
from typing import Any

from pve_api_client import PVEClient

logger = logging.getLogger(__name__)


class StorageManager:
    """High-level storage operations on Proxmox nodes.

    Parameters
    ----------
    client:
        An authenticated :class:`PVEClient` instance.
    """

    def __init__(self, client: PVEClient) -> None:
        self._client = client

    # -- type-specific parameter templates -----------------------------------

    _STORAGE_BUILDERS: dict[str, list[str]] = {
        "dir": ["path", "content"],
        "nfs": ["server", "export", "content"],
        "cifs": ["server", "share", "content"],
        "iscsi": ["portal", "target", "content"],
        "lvm": ["vgname", "content"],
        "lvmthin": ["vgname", "thinpool", "content"],
        "zfs": ["pool", "content"],
        "zfspool": ["pool", "content"],
        "rbd": ["monhost", "pool", "content"],
        "cephfs": ["monhost", "content"],
        "glusterfs": ["server", "volume", "content"],
        "pbs": ["server", " datastore", "fingerprint", "content"],
    }

    def add(self, node: str, name: str, storage_type: str, **kwargs: Any) -> dict[str, Any]:
        """Add a storage backend.

        Parameters
        ----------
        node:
            Proxmox node name.
        name:
            Storage identifier.
        storage_type:
            One of: dir, nfs, cifs, iscsi, lvm, lvmthin, zfs, rbd, cephfs, glusterfs, pbs.
        **kwargs:
            Type-specific parameters.  Required keys depend on the backend:

            * **dir** – ``path``, ``content``
            * **nfs** – ``server``, ``export``, ``content``
            * **cifs** – ``server``, ``share``, ``content``
            * **iscsi** – ``portal``, ``target``, ``content``
            * **lvm** – ``vgname``, ``content``
            * **lvmthin** – ``vgname``, ``thinpool``, ``content``
            * **zfs** – ``pool``, ``content``
            * **rbd** – ``monhost``, ``pool``, ``content``
            * **cephfs** – ``monhost``, ``content``
            * **glusterfs** – ``server``, ``volume``, ``content``
            * **pbs** – ``server``, ``datastore``, ``fingerprint``, ``content``
        """
        data: dict[str, Any] = {"type": storage_type, **kwargs}
        logger.info("Adding storage '%s' (type=%s) on node %s", name, storage_type, node)
        result = self._client.post(f"/api2/json/nodes/{node}/storage", data={"storage": name, **data})
        logger.info("Storage '%s' added", name)
        return result

    def remove(self, node: str, name: str) -> dict[str, Any]:
        """Remove a storage backend from a node."""
        logger.info("Removing storage '%s' from node %s", name, node)
        return self._client.delete(f"/api2/json/nodes/{node}/storage/{name}")

    def list_all(self, node: str | None = None) -> list[dict[str, Any]]:
        """List storage backends.

        Parameters
        ----------
        node:
            If provided, list storage on that node only. Otherwise return cluster-wide storage.
        """
        if node:
            return self._client.get(f"/api2/json/nodes/{node}/storage")  # type: ignore[return-value]
        return self._client.get("/api2/json/cluster/storage")  # type: ignore[return-value]

    def status(self, node: str, storage: str) -> dict[str, Any]:
        """Return status of a specific storage on a node."""
        return self._client.get(f"/api2/json/nodes/{node}/storage/{storage}/status")

    def resize_disk(self, node: str, vmid: int, disk: str, size: str) -> dict[str, Any]:
        """Resize a VM or container disk.

        Parameters
        ----------
        vmid:
            VM / container ID.
        disk:
            Disk identifier, e.g. ``scsi0``.
        size:
            New absolute size, e.g. ``64G``.
        """
        logger.info("Resizing disk %s of VM %d on node %s to %s", disk, vmid, node, size)
        return self._client.put(
            f"/api2/json/nodes/{node}/qemu/{vmid}/resize",
            data={"disk": disk, "size": size},
        )

    def move_disk(
        self,
        node: str,
        vmid: int,
        disk: str,
        target_storage: str,
        online: bool = True,
    ) -> dict[str, Any]:
        """Move a VM disk to a different storage.

        Parameters
        ----------
        disk:
            Disk to move, e.g. ``scsi0``.
        target_storage:
            Destination storage.
        online:
            Move while the VM is running.
        """
        data: dict[str, Any] = {
            "disk": disk,
            "storage": target_storage,
            "online": 1 if online else 0,
        }
        logger.info(
            "Moving disk %s of VM %d on node %s to %s (online=%s)",
            disk, vmid, node, target_storage, online,
        )
        return self._client.post(
            f"/api2/json/nodes/{node}/qemu/{vmid}/move_disk", data=data
        )

    def import_disk(
        self,
        node: str,
        vmid: int,
        file_path: str,
        format: str,
        storage: str,
    ) -> dict[str, Any]:
        """Import a disk image into a VM.

        Parameters
        ----------
        file_path:
            Path to the image file on the Proxmox node.
        format:
            Image format (raw, qcow2, vmdk).
        storage:
            Target storage for the imported disk.
        """
        data: dict[str, Any] = {
            "filename": file_path,
            "format": format,
            "storage": storage,
        }
        logger.info(
            "Importing disk '%s' into VM %d on node %s", file_path, vmid, node
        )
        return self._client.post(
            f"/api2/json/nodes/{node}/qemu/{vmid}/import", data=data
        )
