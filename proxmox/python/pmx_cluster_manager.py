# SPDX-License-Identifier: MIT
# proxmox-kvm-swissknife - Cluster Manager

"""Proxmox VE cluster formation and management."""

from __future__ import annotations

import logging
from typing import Any

from pve_api_client import PVEClient

logger = logging.getLogger(__name__)


class ClusterManager:
    """High-level Proxmox cluster operations.

    Parameters
    ----------
    client:
        An authenticated :class:`PVEClient` instance.
    """

    def __init__(self, client: PVEClient) -> None:
        self._client = client

    def status(self) -> dict[str, Any]:
        """Return the overall cluster status."""
        return self._client.get("/api2/json/cluster/status")

    def create(self, cluster_name: str, node: str) -> dict[str, Any]:
        """Create a new cluster on *node*.

        Parameters
        ----------
        cluster_name:
            Name for the new cluster.
        node:
            The node that will initialise the cluster.
        """
        logger.info("Creating cluster '%s' on node %s", cluster_name, node)
        result = self._client.post(
            f"/api2/json/nodes/{node}/cluster",
            data={"clustername": cluster_name},
        )
        logger.info("Cluster '%s' created", cluster_name)
        return result

    def join(
        self,
        node: str,
        existing_host: str,
        existing_token: str,
        ring0: str | None = None,
        ring1: str | None = None,
    ) -> dict[str, Any]:
        """Join an existing cluster.

        Parameters
        ----------
        node:
            Local node to join.
        existing_host:
            Hostname or IP of a cluster member.
        existing_token:
            Cluster join token.
        ring0:
            Ring 0 network address.
        ring1:
            Ring 1 network address.
        """
        data: dict[str, Any] = {
            "hostname": existing_host,
            "token": existing_token,
        }
        if ring0:
            data["ring0_addr"] = ring0
        if ring1:
            data["ring1_addr"] = ring1

        logger.info("Joining cluster from node %s via %s", node, existing_host)
        result = self._client.post(f"/api2/json/nodes/{node}/cluster/join", data=data)
        logger.info("Node %s joined cluster", node)
        return result

    def remove_node(self, node: str) -> dict[str, Any]:
        """Remove a node from the cluster.

        This sends a ``delnode`` request. The node should be offline
        before removal.
        """
        logger.info("Removing node %s from cluster", node)
        result = self._client.delete(f"/api2/json/cluster/config/{node}")
        logger.info("Node %s removed", node)
        return result

    def list_nodes(self) -> list[dict[str, Any]]:
        """List all nodes in the cluster."""
        return self._client.get("/api2/json/cluster/config/nodes")  # type: ignore[return-value]

    def quorum(self) -> dict[str, Any]:
        """Return cluster quorum status."""
        return self._client.get("/api2/json/cluster/config/quorum")
