# SPDX-License-Identifier: MIT
# Pulsar - ZFS Manager

"""Proxmox VE ZFS pool and dataset management."""

from __future__ import annotations

import logging
from typing import Any

from pve_api_client import PVEClient

logger = logging.getLogger(__name__)


class ZFSManager:
    """High-level ZFS operations on Proxmox nodes.

    Parameters
    ----------
    client:
        An authenticated :class:`PVEClient` instance.
    """

    def __init__(self, client: PVEClient) -> None:
        self._client = client

    def list_pools(self, node: str) -> list[dict[str, Any]]:
        """List ZFS pools on a node."""
        return self._client.get(f"/api2/json/nodes/{node}/disks/zfs")  # type: ignore[return-value]

    def create_pool(
        self,
        node: str,
        name: str,
        devices: list[str],
        raidz: int | None = None,
    ) -> dict[str, Any]:
        """Create a ZFS pool.

        Parameters
        ----------
        name:
            Pool name.
        devices:
            List of block devices, e.g. ``['/dev/sdb', '/dev/sdc']``.
        raidz:
            RAID-Z level (1, 2, or 3) – *None* for stripe / mirror
            when two devices.
        """
        data: dict[str, Any] = {
            "name": name,
            "devices": ",".join(devices),
        }
        if raidz is not None:
            data["raidlevel"] = f"raidz{raidz}"

        logger.info(
            "Creating ZFS pool '%s' on node %s with %d devices", name, node, len(devices)
        )
        return self._client.post(f"/api2/json/nodes/{node}/disks/zfs", data=data)

    def destroy_pool(self, node: str, name: str) -> dict[str, Any]:
        """Destroy a ZFS pool (dangerous!)."""
        logger.warning("Destroying ZFS pool '%s' on node %s", name, node)
        return self._client.delete(f"/api2/json/nodes/{node}/disks/zfs/{name}")

    def pool_status(self, node: str, name: str) -> dict[str, Any]:
        """Return ZFS pool status."""
        pools = self.list_pools(node)
        for pool in pools:
            if pool.get("name") == name:
                return pool
        raise KeyError(f"ZFS pool '{name}' not found on node {node}")

    def list_datasets(self, node: str, pool: str | None = None) -> list[dict[str, Any]]:
        """List ZFS datasets, optionally filtered by pool."""
        path = f"/api2/json/nodes/{node}/disks/zfs/datas"
        if pool:
            path = f"{path}?pool={pool}"
        return self._client.get(path)  # type: ignore[return-value]

    def create_dataset(
        self, node: str, name: str, properties: dict[str, str] | None = None
    ) -> dict[str, Any]:
        """Create a ZFS dataset.

        Parameters
        ----------
        name:
            Full dataset path, e.g. ``tank/data``.
        properties:
            ZFS properties to set, e.g. ``{"quota": "10G"}``.
        """
        data: dict[str, Any] = {"name": name}
        if properties:
            for k, v in properties.items():
                data[f"property[{k}]"] = v
        logger.info("Creating ZFS dataset '%s' on node %s", name, node)
        return self._client.post(f"/api2/json/nodes/{node}/disks/zfs/dataset", data=data)

    def destroy_dataset(self, node: str, name: str) -> dict[str, Any]:
        """Destroy a ZFS dataset."""
        logger.warning("Destroying ZFS dataset '%s' on node %s", name, node)
        return self._client.delete(f"/api2/json/nodes/{node}/disks/zfs/dataset/{name}")

    def set_property(self, node: str, name: str, prop: str, value: str) -> dict[str, Any]:
        """Set a ZFS property."""
        logger.info("Setting ZFS property '%s'='%s' on '%s' (node %s)", prop, value, name, node)
        return self._client.put(
            f"/api2/json/nodes/{node}/disks/zfs/{name}",
            data={"property": f"{prop}={value}"},
        )

    def get_property(self, node: str, name: str, prop: str) -> str:
        """Get a single ZFS property value."""
        pools = self.list_pools(node)
        for pool in pools:
            if pool.get("name") == name:
                return str(pool.get(prop, ""))
        raise KeyError(f"ZFS pool '{name}' not found on node {node}")

    def scrub(self, node: str, pool: str) -> dict[str, Any]:
        """Start a ZFS scrub."""
        logger.info("Starting ZFS scrub on pool '%s' (node %s)", pool, node)
        return self._client.post(f"/api2/json/nodes/{node}/disks/zfs/{pool}/scrub")

    def scrub_status(self, node: str, pool: str) -> dict[str, Any]:
        """Return ZFS scrub status for a pool."""
        status = self.pool_status(node, pool)
        return {
            "pool": pool,
            "scan": status.get("scan", "none"),
            "status": status.get("health", "UNKNOWN"),
        }
