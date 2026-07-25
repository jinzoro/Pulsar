# SPDX-License-Identifier: MIT
# proxmox-kvm-swissknife - Firewall Manager

"""Proxmox VE firewall rules and IPSet management."""

from __future__ import annotations

import logging
from typing import Any

from pve_api_client import PVEClient

logger = logging.getLogger(__name__)


def _scope_path(scope: str, node: str | None = None, vmid: int | None = None) -> str:
    """Build the API path prefix for a firewall scope."""
    if scope == "cluster":
        return "/api2/json/cluster/firewall"
    if scope == "node":
        if not node:
            raise ValueError("node is required for node-level firewall scope")
        return f"/api2/json/nodes/{node}/firewall"
    if scope == "vm":
        if not node or vmid is None:
            raise ValueError("node and vmid are required for VM-level firewall scope")
        return f"/api2/json/nodes/{node}/qemu/{vmid}/firewall"
    raise ValueError(f"Invalid scope: {scope!r}. Use 'cluster', 'node', or 'vm'.")


class FirewallManager:
    """High-level Proxmox firewall operations.

    Parameters
    ----------
    client:
        An authenticated :class:`PVEClient` instance.
    """

    def __init__(self, client: PVEClient) -> None:
        self._client = client

    def enable(self, scope: str, node: str | None = None, vmid: int | None = None) -> dict[str, Any]:
        """Enable the firewall at the given scope."""
        base = _scope_path(scope, node, vmid)
        logger.info("Enabling firewall for %s scope", scope)
        return self._client.put(f"{base}/options", data={"enable": 1})

    def disable(self, scope: str, node: str | None = None, vmid: int | None = None) -> dict[str, Any]:
        """Disable the firewall at the given scope."""
        base = _scope_path(scope, node, vmid)
        logger.info("Disabling firewall for %s scope", scope)
        return self._client.put(f"{base}/options", data={"enable": 0})

    def list_rules(self, scope: str, node: str | None = None, vmid: int | None = None) -> list[dict[str, Any]]:
        """List firewall rules."""
        base = _scope_path(scope, node, vmid)
        return self._client.get(f"{base}/rules")  # type: ignore[return-value]

    def add_rule(
        self,
        scope: str,
        direction: str,
        action: str,
        proto: str | None = None,
        source: str | None = None,
        dest: str | None = None,
        dport: str | None = None,
        sport: str | None = None,
        comment: str | None = None,
        enable: bool = True,
        node: str | None = None,
        vmid: int | None = None,
    ) -> dict[str, Any]:
        """Add a firewall rule.

        Parameters
        ----------
        scope:
            ``cluster``, ``node`` or ``vm``.
        direction:
            ``in`` or ``out``.
        action:
            ``ACCEPT``, ``DROP`` or ``REJECT``.
        proto:
            Protocol – ``tcp``, ``udp``, ``icmp`` or ``all``.
        source:
            Source IP / CIDR.
        dest:
            Destination IP / CIDR.
        dport:
            Destination port or range, e.g. ``80`` or ``8000:8100``.
        sport:
            Source port or range.
        comment:
            Optional comment.
        enable:
            Whether the rule is enabled.
        """
        base = _scope_path(scope, node, vmid)
        data: dict[str, Any] = {
            "type": "in" if direction == "in" else "out",
            "action": action,
        }
        if proto:
            data["proto"] = proto
        if source:
            data["source"] = source
        if dest:
            data["dest"] = dest
        if dport:
            data["dport"] = dport
        if sport:
            data["sport"] = sport
        if comment:
            data["comment"] = comment
        data["enable"] = 1 if enable else 0

        logger.info("Adding %s %s firewall rule in %s scope", direction, action, scope)
        return self._client.post(f"{base}/rules", data=data)

    def delete_rule(
        self, scope: str, rule_id: int, node: str | None = None, vmid: int | None = None
    ) -> dict[str, Any]:
        """Delete a firewall rule by its position."""
        base = _scope_path(scope, node, vmid)
        logger.info("Deleting rule %d in %s scope", rule_id, scope)
        return self._client.delete(f"{base}/rules/{rule_id}")

    def move_rule(
        self,
        scope: str,
        rule_id: int,
        direction: str,
        node: str | None = None,
        vmid: int | None = None,
    ) -> dict[str, Any]:
        """Move a firewall rule up or down.

        Parameters
        ----------
        direction:
            ``up`` or ``down``.
        """
        base = _scope_path(scope, node, vmid)
        logger.info("Moving rule %d %s in %s scope", rule_id, direction, scope)
        return self._client.put(
            f"{base}/rules/{rule_id}",
            data={"move": direction},
        )

    # -- IPSet operations ----------------------------------------------------

    def list_ipsets(self, scope: str, node: str | None = None, vmid: int | None = None) -> list[dict[str, Any]]:
        """List IP sets."""
        base = _scope_path(scope, node, vmid)
        return self._client.get(f"{base}/ipset")  # type: ignore[return-value]

    def create_ipset(
        self, name: str, scope: str, node: str | None = None, vmid: int | None = None
    ) -> dict[str, Any]:
        """Create an IP set."""
        base = _scope_path(scope, node, vmid)
        logger.info("Creating IPSet '%s' in %s scope", name, scope)
        return self._client.post(f"{base}/ipset", data={"name": name})

    def add_to_ipset(
        self,
        ipset_name: str,
        cidr: str,
        scope: str,
        node: str | None = None,
        vmid: int | None = None,
        comment: str | None = None,
    ) -> dict[str, Any]:
        """Add a CIDR entry to an IP set.

        Parameters
        ----------
        ipset_name:
            Name of the IP set.
        cidr:
            CIDR notation, e.g. ``10.0.0.0/8``.
        comment:
            Optional comment.
        """
        base = _scope_path(scope, node, vmid)
        data: dict[str, Any] = {"cidr": cidr}
        if comment:
            data["comment"] = comment
        logger.info("Adding %s to IPSet '%s'", cidr, ipset_name)
        return self._client.post(f"{base}/ipset/{ipset_name}", data=data)

    def delete_ipset(
        self, name: str, scope: str, node: str | None = None, vmid: int | None = None
    ) -> dict[str, Any]:
        """Delete an IP set."""
        base = _scope_path(scope, node, vmid)
        logger.info("Deleting IPSet '%s' from %s scope", name, scope)
        return self._client.delete(f"{base}/ipset/{name}")
