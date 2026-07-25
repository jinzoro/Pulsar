# SPDX-License-Identifier: MIT
# Pulsar - Bulk Operations

"""Batch and pool-level VM operations."""

from __future__ import annotations

import logging
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Any

from pve_api_client import PVEClient

logger = logging.getLogger(__name__)


class BulkOperations:
    """Batch operations for managing multiple VMs efficiently.

    Parameters
    ----------
    client:
        An authenticated :class:`PVEClient` instance.
    max_workers:
        Maximum parallel API calls per batch.
    """

    def __init__(self, client: PVEClient, max_workers: int = 10) -> None:
        self._client = client
        self._max_workers = max_workers

    def _parallel_execute(
        self,
        node: str,
        vmids: list[int],
        operation: str,
        **kwargs: Any,
    ) -> dict[str, dict[str, Any]]:
        """Execute an operation on multiple VMs in parallel."""
        ops: dict[str, Any] = {
            "start": lambda n, v: self._client.vm_start(n, v),
            "stop": lambda n, v: self._client.vm_stop(n, v),
            "shutdown": lambda n, v: self._client.vm_shutdown(n, v, timeout=kwargs.get("timeout", 30)),
            "delete": lambda n, v: self._client.vm_delete(n, v),
        }
        func = ops.get(operation)
        if func is None:
            raise ValueError(f"Unsupported operation: {operation!r}")

        results: dict[str, dict[str, Any]] = {}

        with ThreadPoolExecutor(max_workers=self._max_workers) as pool:
            futures = {
                pool.submit(func, node, vmid): vmid for vmid in vmids
            }
            for future in as_completed(futures):
                vmid = futures[future]
                try:
                    results[str(vmid)] = future.result()
                except Exception as exc:
                    logger.error("Batch %s failed for VM %d: %s", operation, vmid, exc)
                    results[str(vmid)] = {"error": str(exc)}

        return results

    def batch_start(self, node: str, vmids: list[int]) -> dict[str, dict[str, Any]]:
        """Start multiple VMs in parallel."""
        logger.info("Batch starting %d VMs on node %s", len(vmids), node)
        return self._parallel_execute(node, vmids, "start")

    def batch_stop(
        self, node: str, vmids: list[int], force: bool = False
    ) -> dict[str, dict[str, Any]]:
        """Stop multiple VMs in parallel."""
        if force:
            # force stop goes directly
            logger.info("Force-stopping %d VMs on node %s", len(vmids), node)
            return self._parallel_execute(node, vmids, "stop")
        return self._parallel_execute(node, vmids, "stop")

    def batch_shutdown(
        self, node: str, vmids: list[int], timeout: int = 30
    ) -> dict[str, dict[str, Any]]:
        """Gracefully shut down multiple VMs in parallel."""
        logger.info("Batch shutting down %d VMs on node %s (timeout=%ds)", len(vmids), node, timeout)
        return self._parallel_execute(node, vmids, "shutdown", timeout=timeout)

    def batch_delete(
        self, node: str, vmids: list[int], purge: bool = False
    ) -> dict[str, dict[str, Any]]:
        """Delete multiple VMs in parallel."""
        logger.warning("Batch deleting %d VMs on node %s (purge=%s)", len(vmids), node, purge)
        return self._parallel_execute(node, vmids, "delete")

    def batch_snapshot(
        self,
        node: str,
        vmids: list[int],
        name: str,
        description: str | None = None,
    ) -> dict[str, dict[str, Any]]:
        """Create snapshots for multiple VMs in parallel."""
        logger.info("Batch snapshotting %d VMs on node %s (name=%s)", len(vmids), node, name)
        results: dict[str, dict[str, Any]] = {}

        def _snapshot(vmid: int) -> dict[str, Any]:
            data: dict[str, Any] = {"snapname": name}
            if description:
                data["description"] = description
            return self._client.post(
                f"/api2/json/nodes/{node}/qemu/{vmid}/snapshot", data=data
            )

        with ThreadPoolExecutor(max_workers=self._max_workers) as pool:
            futures = {pool.submit(_snapshot, vmid): vmid for vmid in vmids}
            for future in as_completed(futures):
                vmid = futures[future]
                try:
                    results[str(vmid)] = future.result()
                except Exception as exc:
                    logger.error("Snapshot failed for VM %d: %s", vmid, exc)
                    results[str(vmid)] = {"error": str(exc)}

        return results

    def batch_tag(
        self, node: str, vmids: list[int], tag: str
    ) -> dict[str, dict[str, Any]]:
        """Add a tag to multiple VMs in parallel."""
        logger.info("Tagging %d VMs on node %s with '%s'", len(vmids), node, tag)
        results: dict[str, dict[str, Any]] = {}

        def _add_tag(vmid: int) -> dict[str, Any]:
            # Read current tags first
            config = self._client.get(f"/api2/json/nodes/{node}/qemu/{vmid}/config")
            existing_tags = set()
            for key, value in config.items():
                if key.startswith("tags"):
                    if isinstance(value, str):
                        existing_tags.update(value.split(","))
            existing_tags.add(tag)
            new_tags = ",".join(sorted(existing_tags))
            return self._client.put(
                f"/api2/json/nodes/{node}/qemu/{vmid}",
                data={"tags": new_tags},
            )

        with ThreadPoolExecutor(max_workers=self._max_workers) as pool:
            futures = {pool.submit(_add_tag, vmid): vmid for vmid in vmids}
            for future in as_completed(futures):
                vmid = futures[future]
                try:
                    results[str(vmid)] = future.result()
                except Exception as exc:
                    logger.error("Tag failed for VM %d: %s", vmid, exc)
                    results[str(vmid)] = {"error": str(exc)}

        return results

    def pool_operation(self, pool: str, operation: str, **kwargs: Any) -> dict[str, Any]:
        """Execute an operation on all members of a Proxmox resource pool.

        Parameters
        ----------
        pool:
            Pool name.
        operation:
            One of ``start``, ``stop``, ``shutdown``, ``delete``.
        **kwargs:
            Extra parameters forwarded to the underlying operation.
        """
        pool_resources = self._client.get(f"/api2/json/pools/{pool}")
        if not isinstance(pool_resources, dict):
            raise RuntimeError(f"Pool '{pool}' not found or empty")

        members = pool_resources.get("members", [])
        if not members:
            logger.warning("Pool '%s' has no members", pool)
            return {}

        # Group members by node
        by_node: dict[str, list[int]] = {}
        for member in members:
            node = member.get("node")
            vmid = member.get("vmid")
            if node and vmid:
                by_node.setdefault(node, []).append(int(vmid))

        all_results: dict[str, Any] = {}
        for node, vmids in by_node.items():
            node_results = self._parallel_execute(node, vmids, operation, **kwargs)
            all_results[node] = node_results

        return {"pool": pool, "operation": operation, "results": all_results}
