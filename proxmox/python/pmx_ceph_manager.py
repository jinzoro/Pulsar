# SPDX-License-Identifier: MIT
# proxmox-kvm-swissknife - Ceph Manager

"""Proxmox VE integrated Ceph cluster management."""

from __future__ import annotations

import logging
from typing import Any

from pve_api_client import PVEClient

logger = logging.getLogger(__name__)


class CephManager:
    """High-level Ceph operations through the Proxmox API.

    Parameters
    ----------
    client:
        An authenticated :class:`PVEClient` instance.
    """

    def __init__(self, client: PVEClient) -> None:
        self._client = client

    def status(self, node: str) -> dict[str, Any]:
        """Return overall Ceph cluster status."""
        return self._client.get(f"/api2/json/nodes/{node}/ceph/status")

    def health(self, node: str) -> dict[str, Any]:
        """Return Ceph health details."""
        status = self.status(node)
        return status.get("health", status)

    def deploy(
        self,
        node: str,
        monitors: list[str] | None = None,
        managers: list[str] | None = None,
        osd_devices: list[str] | None = None,
    ) -> dict[str, Any]:
        """Initialise or expand a Ceph cluster.

        Parameters
        ----------
        monitors:
            Nodes to deploy monitors on.
        managers:
            Nodes to deploy managers on.
        osd_devices:
            Block devices to create OSDs on.
        """
        data: dict[str, Any] = {}
        if monitors:
            data["mon-host"] = ",".join(monitors)
        if managers:
            data["mgr-host"] = ",".join(managers)

        logger.info("Deploying Ceph on node %s", node)
        result = self._client.post(f"/api2/json/nodes/{node}/ceph", data=data)

        if osd_devices:
            for dev in osd_devices:
                logger.info("Adding OSD on device %s", dev)
                self._client.post(
                    f"/api2/json/nodes/{node}/ceph/osd",
                    data={"dev": dev},
                )

        return result

    def list_pools(self, node: str) -> list[dict[str, Any]]:
        """List Ceph pools."""
        return self._client.get(f"/api2/json/nodes/{node}/ceph/osd")  # type: ignore[return-value]

    def create_pool(
        self, node: str, name: str, pg_num: int = 128, replica: int = 3
    ) -> dict[str, Any]:
        """Create a Ceph pool.

        Parameters
        ----------
        name:
            Pool name.
        pg_num:
            Number of placement groups.
        replica:
            Replication factor.
        """
        data: dict[str, Any] = {
            "name": name,
            "pg_num": pg_num,
            "replicas": replica,
        }
        logger.info("Creating Ceph pool '%s' on node %s (pg=%d, replica=%d)", name, node, pg_num, replica)
        return self._client.post(f"/api2/json/nodes/{node}/ceph/pool", data=data)

    def delete_pool(self, node: str, name: str) -> dict[str, Any]:
        """Delete a Ceph pool."""
        logger.info("Deleting Ceph pool '%s' on node %s", name, node)
        return self._client.delete(f"/api2/json/nodes/{node}/ceph/pool/{name}")

    def set_pool_size(self, node: str, name: str, size: int) -> dict[str, Any]:
        """Set the replication size of a pool."""
        logger.info("Setting pool '%s' size to %d on node %s", name, size, node)
        return self._client.put(
            f"/api2/json/nodes/{node}/ceph/pool/{name}",
            data={"size": size},
        )

    def list_osds(self, node: str) -> list[dict[str, Any]]:
        """List Ceph OSDs."""
        return self._client.get(f"/api2/json/nodes/{node}/ceph/osd")  # type: ignore[return-value]

    def add_osd(self, node: str, device: str) -> dict[str, Any]:
        """Create an OSD on the given block device."""
        logger.info("Adding OSD on device %s on node %s", device, node)
        return self._client.post(
            f"/api2/json/nodes/{node}/ceph/osd", data={"dev": device}
        )

    def remove_osd(self, node: str, osd_id: int) -> dict[str, Any]:
        """Remove an OSD."""
        logger.info("Removing OSD %d on node %s", osd_id, node)
        return self._client.delete(f"/api2/json/nodes/{node}/ceph/osd/{osd_id}")

    def reweight_osd(self, node: str, osd_id: int, weight: float) -> dict[str, Any]:
        """Reweight an OSD.

        Parameters
        ----------
        weight:
            Weight between 0.0 and 1.0.
        """
        logger.info("Reweighting OSD %d to %.2f on node %s", osd_id, weight, node)
        return self._client.put(
            f"/api2/json/nodes/{node}/ceph/osd/{osd_id}",
            data={"weight": weight},
        )

    def scrub(self, node: str, pool: str | None = None, deep: bool = False) -> dict[str, Any]:
        """Trigger a scrub operation.

        Parameters
        ----------
        pool:
            Pool to scrub – all pools if *None*.
        deep:
            Perform a deep scrub.
        """
        data: dict[str, Any] = {"deep": 1 if deep else 0}
        if pool:
            data["pool"] = pool
        logger.info("Triggering %sscrub on node %s", "deep " if deep else "", node)
        return self._client.post(f"/api2/json/nodes/{node}/ceph/scrub", data=data)
