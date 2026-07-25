# SPDX-License-Identifier: MIT
# Pulsar - LXC Container Manager

"""LXC container lifecycle management."""

from __future__ import annotations

import logging
from typing import Any

from pve_api_client import PVEClient

logger = logging.getLogger(__name__)


class CTManager:
    """High-level LXC container lifecycle operations.

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
        vmid: int | None = None,
        hostname: str = "container",
        template: str = "",
        storage: str = "local",
        unprivileged: bool = True,
        cpu: int = 1,
        memory: int = 512,
        swap: int = 512,
        rootfs_size: str = "8G",
        nesting: bool = False,
        features: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Create a new LXC container.

        Parameters
        ----------
        node:
            Target Proxmox node name.
        vmid:
            Container ID – auto-assigned if *None*.
        hostname:
            Hostname of the container.
        template:
            Template volume to use, e.g. ``local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst``.
        storage:
            Storage for the rootfs.
        unprivileged:
            Create an unprivileged container.
        cpu:
            Number of CPU cores.
        memory:
            Memory in MiB.
        swap:
            Swap in MiB.
        rootfs_size:
            Root filesystem size, e.g. ``8G``.
        nesting:
            Enable nesting (required for Docker inside LXC).
        features:
            Additional LXC features dict.
        """
        data: dict[str, Any] = {
            "hostname": hostname,
            "template": template,
            "rootfs": f"{storage}:size={rootfs_size}",
            "cpus": cpu,
            "memory": memory,
            "swap": swap,
            "unprivileged": 1 if unprivileged else 0,
        }
        if vmid is not None:
            data["vmid"] = vmid

        if nesting or (features and features.get("nesting")):
            data["features"] = "nesting=1"

        logger.info("Creating LXC container '%s' on node %s", hostname, node)
        result = self._client.post(f"/api2/json/nodes/{node}/lxc", data=data)
        logger.info("Container created: %s", result)
        return result

    def start(self, node: str, vmid: int) -> dict[str, Any]:
        """Start a container."""
        logger.info("Starting container %d on node %s", vmid, node)
        return self._client.post(f"/api2/json/nodes/{node}/lxc/{vmid}/status/start")

    def stop(self, node: str, vmid: int) -> dict[str, Any]:
        """Force-stop a container."""
        logger.info("Stopping container %d on node %s", vmid, node)
        return self._client.post(f"/api2/json/nodes/{node}/lxc/{vmid}/status/stop")

    def shutdown(self, node: str, vmid: int, timeout: int = 30, force: bool = False) -> dict[str, Any]:
        """Gracefully shut down a container."""
        if force:
            return self.stop(node, vmid)
        logger.info("Shutting down container %d on node %s", vmid, node)
        return self._client.post(
            f"/api2/json/nodes/{node}/lxc/{vmid}/status/shutdown",
            data={"timeout": timeout},
        )

    def delete(self, node: str, vmid: int, purge: bool = False) -> dict[str, Any]:
        """Delete a container."""
        logger.info("Deleting container %d on node %s (purge=%s)", vmid, node, purge)
        params: dict[str, Any] = {}
        if purge:
            params["purge"] = 1
        return self._client.post(f"/api2/json/nodes/{node}/lxc/{vmid}", data=params)

    def clone(
        self,
        node: str,
        vmid: int,
        new_vmid: int | None = None,
        name: str | None = None,
        full: bool = True,
        target_node: str | None = None,
        target_storage: str | None = None,
    ) -> dict[str, Any]:
        """Clone a container."""
        data: dict[str, Any] = {"newid": new_vmid} if new_vmid else {}
        if name:
            data["name"] = name
        data["full"] = 1 if full else 0
        if target_node:
            data["target"] = target_node
        if target_storage:
            data["storage"] = target_storage

        logger.info("Cloning container %d on node %s", vmid, node)
        return self._client.post(f"/api2/json/nodes/{node}/lxc/{vmid}/clone", data=data)

    def resize_rootfs(self, node: str, vmid: int, size: str) -> dict[str, Any]:
        """Resize the root filesystem of a container.

        Parameters
        ----------
        size:
            New absolute size, e.g. ``16G``.
        """
        logger.info("Resizing rootfs of container %d on node %s to %s", vmid, node, size)
        return self._client.put(
            f"/api2/json/nodes/{node}/lxc/{vmid}/resize",
            data={"disk": "rootfs", "size": size},
        )

    def set_features(
        self,
        node: str,
        vmid: int,
        nesting: bool | None = None,
        keyctl: bool | None = None,
        fuse: bool | None = None,
        mount: str | None = None,
    ) -> dict[str, Any]:
        """Update container features.

        Parameters
        ----------
        nesting:
            Enable nesting.
        keyctl:
            Enable keyctl.
        fuse:
            Enable FUSE.
        mount:
            Mount type (e.g. ``cifs``, ``nfs``).
        """
        features_parts: list[str] = []
        if nesting is not None:
            features_parts.append(f"nesting={'1' if nesting else '0'}")
        if keyctl is not None:
            features_parts.append(f"keyctl={'1' if keyctl else '0'}")
        if fuse is not None:
            features_parts.append(f"fuse={'1' if fuse else '0'}")
        if mount is not None:
            features_parts.append(f"mount={mount}")

        if not features_parts:
            raise ValueError("At least one feature must be specified")

        features_str = ",".join(features_parts)
        logger.info("Setting features for container %d on node %s: %s", vmid, node, features_str)
        return self._client.put(
            f"/api2/json/nodes/{node}/lxc/{vmid}", data={"features": features_str}
        )

    def set_dns(
        self,
        node: str,
        vmid: int,
        nameserver: str | None = None,
        searchdomain: str | None = None,
    ) -> dict[str, Any]:
        """Configure container DNS settings.

        Parameters
        ----------
        nameserver:
            DNS server IP(s), space-separated.
        searchdomain:
            DNS search domain.
        """
        data: dict[str, Any] = {}
        if nameserver is not None:
            data["nameserver"] = nameserver
        if searchdomain is not None:
            data["searchdomain"] = searchdomain
        if not data:
            raise ValueError("At least one DNS parameter must be provided")
        logger.info("Setting DNS for container %d on node %s: %s", vmid, node, data)
        return self._client.put(f"/api2/json/nodes/{node}/lxc/{vmid}", data=data)

    def get_config(self, node: str, vmid: int) -> dict[str, Any]:
        """Return the full configuration of a container."""
        return self._client.get(f"/api2/json/nodes/{node}/lxc/{vmid}/config")
