#!/usr/bin/env python3
# =============================================================================
# inventory_parser.py — YAML inventory parser for Pulsar
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Pulsar contributors
# =============================================================================
# Parses a YAML-based inventory file describing hosts, groups, and their
# connection parameters.  Provides a typed interface via pydantic models.
# =============================================================================

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any, Dict, List, Optional

import yaml

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Optional pydantic models (fallback to plain dicts if unavailable)
# ---------------------------------------------------------------------------
try:
    from pydantic import BaseModel, Field, field_validator

    class HostEntry(BaseModel):
        """A single host in the inventory."""

        hostname: str
        ip: Optional[str] = None
        user: str = "root"
        port: int = 22
        key_path: Optional[str] = None
        group: str = "default"
        tags: List[str] = Field(default_factory=list)
        variables: Dict[str, Any] = Field(default_factory=dict)
        proxmox_node: Optional[str] = None
        libvirt_uri: Optional[str] = None

        @field_validator("port")
        @classmethod
        def validate_port(cls, v: int) -> int:
            if not 1 <= v <= 65535:
                raise ValueError(f"Port must be between 1 and 65535, got {v}")
            return v

    class Inventory(BaseModel):
        """Top-level inventory structure."""

        hosts: List[HostEntry] = Field(default_factory=list)
        groups: Dict[str, List[str]] = Field(default_factory=dict)
        defaults: Dict[str, Any] = Field(default_factory=dict)

    _HAS_PYDANTIC = True

except ImportError:
    _HAS_PYDANTIC = False
    logger.debug(
        "pydantic not installed; inventory validation will use basic checks."
    )


# ---------------------------------------------------------------------------
# InventoryParser
# ---------------------------------------------------------------------------

class InventoryParser:
    """Parse and query a YAML inventory file.

    Expected YAML format::

        defaults:
          user: root
          port: 22

        groups:
          webservers:
            - web01
            - web02
          databases:
            - db01

        hosts:
          - hostname: web01
            ip: 10.0.0.10
            group: webservers
            tags: [production, nginx]
            variables:
              ansible_port: 2222
          - hostname: web02
            ip: 10.0.0.11
            group: webservers
          - hostname: db01
            ip: 10.0.0.20
            group: databases
            proxmox_node: pve1

    Parameters
    ----------
    inventory_path : str
        Path to the YAML inventory file.
    """

    def __init__(self, inventory_path: str) -> None:
        self._path = Path(inventory_path).expanduser().resolve()
        self._data: Dict[str, Any] = {}
        self._parsed_hosts: List[Dict[str, Any]] = []
        self._groups: Dict[str, List[str]] = {}
        self._defaults: Dict[str, Any] = {}

        if not self._path.is_file():
            raise FileNotFoundError(
                f"Inventory file not found: {self._path}"
            )

        self._load()

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    def _load(self) -> None:
        """Load and parse the YAML file."""
        logger.debug("Loading inventory from %s", self._path)
        with open(self._path, "r", encoding="utf-8") as fh:
            raw = yaml.safe_load(fh)

        if raw is None:
            logger.warning("Inventory file is empty: %s", self._path)
            self._data = {}
            return

        if not isinstance(raw, dict):
            raise ValueError(
                f"Inventory must be a YAML mapping, got {type(raw).__name__}"
            )

        self._data = raw
        self._defaults = raw.get("defaults", {})
        self._groups = raw.get("groups", {})

        raw_hosts = raw.get("hosts", [])
        if not isinstance(raw_hosts, list):
            raise ValueError("'hosts' must be a list of mappings")

        self._parsed_hosts = []
        for entry in raw_hosts:
            if not isinstance(entry, dict):
                logger.warning("Skipping non-dict host entry: %r", entry)
                continue

            # Apply defaults
            merged: Dict[str, Any] = {**self._defaults, **entry}
            self._parsed_hosts.append(merged)

        logger.info(
            "Loaded %d hosts in %d groups from %s",
            len(self._parsed_hosts),
            len(self._groups),
            self._path,
        )

        if _HAS_PYDANTIC:
            self._validate()

    def _validate(self) -> None:
        """Validate the inventory using pydantic models."""
        validated_hosts = []
        for entry in self._parsed_hosts:
            try:
                model = HostEntry(**entry)
                validated_hosts.append(model.model_dump())
            except Exception as exc:
                hostname = entry.get("hostname", "<unknown>")
                logger.error(
                    "Validation failed for host '%s': %s", hostname, exc
                )
                raise
        self._parsed_hosts = validated_hosts

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def parse(self) -> Dict[str, Any]:
        """Return the full parsed inventory as a dictionary.

        Returns
        -------
        dict
            The complete inventory structure with hosts, groups, and
            defaults.
        """
        return {
            "hosts": self._parsed_hosts,
            "groups": self._groups,
            "defaults": self._defaults,
            "source": str(self._path),
        }

    def get_hosts(self, group: Optional[str] = None) -> List[Dict[str, Any]]:
        """Return all hosts, optionally filtered by group name.

        Parameters
        ----------
        group : str or None
            If provided, only return hosts belonging to this group.

        Returns
        -------
        list[dict]
            List of host dictionaries.
        """
        if group is None:
            return list(self._parsed_hosts)

        # If the group is defined in the groups mapping, filter by hostname
        group_hostnames = set(self._groups.get(group, []))

        # Also filter by the 'group' key on each host entry
        result = []
        for host in self._parsed_hosts:
            host_group = host.get("group", "")
            host_name = host.get("hostname", "")
            if host_group == group or host_name in group_hostnames:
                result.append(host)

        return result

    def get_host(self, hostname: str) -> Dict[str, Any]:
        """Return a single host by hostname.

        Parameters
        ----------
        hostname : str
            The hostname to look up.

        Returns
        -------
        dict
            The host dictionary.

        Raises
        ------
        KeyError
            If no host with the given hostname exists.
        """
        for host in self._parsed_hosts:
            if host.get("hostname") == hostname:
                return host

        available = [h.get("hostname", "?") for h in self._parsed_hosts]
        raise KeyError(
            f"Host '{hostname}' not found in inventory. "
            f"Available: {available}"
        )

    def get_groups(self) -> List[str]:
        """Return a sorted list of all group names.

        Returns
        -------
        list[str]
            Group names derived from both the ``groups`` mapping and the
            ``group`` key on individual host entries.
        """
        groups = set(self._groups.keys())
        for host in self._parsed_hosts:
            g = host.get("group")
            if g:
                groups.add(g)
        return sorted(groups)

    def get_group_hosts(self, group: str) -> List[str]:
        """Return hostnames belonging to a group.

        Parameters
        ----------
        group : str
            Group name.

        Returns
        -------
        list[str]
            Hostnames in the group.
        """
        # Start with the explicit group mapping
        hostnames = list(self._groups.get(group, []))

        # Also collect hosts with matching 'group' key
        for host in self._parsed_hosts:
            if host.get("group") == group:
                name = host.get("hostname", "")
                if name and name not in hostnames:
                    hostnames.append(name)

        return hostnames

    def get_variable(self, hostname: str, var_name: str) -> Any:
        """Get a variable for a specific host.

        Checks the host's ``variables`` dict first, then falls back to
        the inventory defaults.

        Parameters
        ----------
        hostname : str
            Hostname to look up.
        var_name : str
            Variable name.

        Returns
        -------
        Any
            The variable value, or ``None`` if not found.

        Raises
        ------
        KeyError
            If the hostname does not exist in the inventory.
        """
        host = self.get_host(hostname)

        # Check host-level variables first
        host_vars = host.get("variables", {})
        if var_name in host_vars:
            return host_vars[var_name]

        # Check top-level host keys
        if var_name in host:
            return host[var_name]

        # Fall back to defaults
        return self._defaults.get(var_name)

    @property
    def host_count(self) -> int:
        """Return the total number of hosts in the inventory."""
        return len(self._parsed_hosts)

    def __repr__(self) -> str:
        return (
            f"InventoryParser(path={self._path!r}, "
            f"hosts={self.host_count}, "
            f"groups={len(self.get_groups())})"
        )
