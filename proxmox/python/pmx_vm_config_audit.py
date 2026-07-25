# SPDX-License-Identifier: MIT
# Pulsar - VM Configuration Audit

"""VM configuration audit and drift detection."""

from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from typing import Any

from pve_api_client import PVEClient

logger = logging.getLogger(__name__)


class VMConfigAudit:
    """Audit VM configurations for drift and compliance.

    Parameters
    ----------
    client:
        An authenticated :class:`PVEClient` instance.
    """

    def __init__(self, client: PVEClient) -> None:
        self._client = client

    def get_running_config(self, node: str, vmid: int) -> dict[str, Any]:
        """Return the live (running) configuration of a VM."""
        config = self._client.get(f"/api2/json/nodes/{node}/qemu/{vmid}/config")
        status = self._client.get(f"/api2/json/nodes/{node}/qemu/{vmid}/status/current")
        return {
            "vmid": vmid,
            "node": node,
            "config": config,
            "status": status.get("status", "unknown"),
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }

    def get_disk_config(self, node: str, vmid: int) -> dict[str, dict[str, Any]]:
        """Extract disk-specific configuration.

        Returns a dict mapping disk name (e.g. ``scsi0``) → config dict.
        """
        config = self._client.get(f"/api2/json/nodes/{node}/qemu/{vmid}/config")
        disks: dict[str, dict[str, Any]] = {}
        disk_prefixes = ("scsi", "sata", "ide", "virtio")

        for key, value in config.items():
            for prefix in disk_prefixes:
                if key.startswith(prefix):
                    disks[key] = self._parse_disk_string(value)
                    break

        return disks

    @staticmethod
    def _parse_disk_string(disk_str: str) -> dict[str, Any]:
        """Parse a Proxmox disk configuration string.

        Example: ``local-lvm:vm-100-disk-0,size=32G``
        """
        parts = disk_str.split(",")
        result: dict[str, Any] = {"raw": disk_str}
        if parts:
            storage_vol = parts[0].split(":", 1)
            result["storage"] = storage_vol[0] if storage_vol else ""
            result["volume"] = storage_vol[1] if len(storage_vol) > 1 else ""
        for part in parts[1:]:
            if "=" in part:
                k, v = part.split("=", 1)
                result[k.strip()] = v.strip()
        return result

    def diff_configs(self, config1: dict[str, Any], config2: dict[str, Any]) -> dict[str, Any]:
        """Compare two configuration dicts and return differences.

        Returns a dict with ``added``, ``removed``, ``changed`` keys.
        """
        keys1 = set(config1.keys())
        keys2 = set(config2.keys())

        added = {k: config2[k] for k in keys2 - keys1}
        removed = {k: config1[k] for k in keys1 - keys2}
        changed: dict[str, dict[str, Any]] = {}
        for k in keys1 & keys2:
            if config1[k] != config2[k]:
                changed[k] = {"old": config1[k], "new": config2[k]}

        return {"added": added, "removed": removed, "changed": changed}

    def audit(self, node: str, vmid: int) -> dict[str, Any]:
        """Perform a full audit of a VM.

        Returns a comprehensive audit report including:
        - Current configuration
        - Disk configuration
        - Template status
        - Snapshot count
        - Any drift indicators
        """
        config = self.get_running_config(node, vmid)
        disks = self.get_disk_config(node, vmid)
        snapshots = self._client.vm_snapshot_list(node, vmid)
        template_info = self._client.get(f"/api2/json/nodes/{node}/qemu/{vmid}")

        issues: list[str] = []

        # Check for common issues
        vm_config = config.get("config", {})

        if not vm_config.get("name"):
            issues.append("VM has no name set")

        if vm_config.get("balloon") and int(vm_config.get("balloon", 0)) > vm_config.get("memory", 0):
            issues.append("Balloon memory exceeds allocated memory")

        for disk_name, disk_info in disks.items():
            if disk_info.get("size") and disk_info["size"].endswith("G"):
                try:
                    size_gb = float(disk_info["size"].rstrip("G"))
                    if size_gb < 1:
                        issues.append(f"Disk {disk_name} is very small ({disk_info['size']})")
                except ValueError:
                    pass

        if not vm_config.get("cpu"):
            issues.append("No CPU type specified")

        return {
            "vmid": vmid,
            "node": node,
            "audit_time": datetime.now(timezone.utc).isoformat(),
            "configuration": config,
            "disks": disks,
            "snapshot_count": len(snapshots),
            "snapshots": snapshots,
            "is_template": template_info.get("template") == 1,
            "issues": issues,
            "health": "healthy" if not issues else "needs_attention",
        }

    def report(self, node: str, vmid: int | None = None) -> str:
        """Generate a formatted audit report.

        Parameters
        ----------
        vmid:
            Specific VM ID – audits all VMs on the node if *None*.
        """
        lines: list[str] = []
        lines.append("=" * 72)
        lines.append("  PROXMOX VM CONFIGURATION AUDIT REPORT")
        lines.append(f"  Generated: {datetime.now(timezone.utc).isoformat()}")
        lines.append("=" * 72)

        if vmid is not None:
            vmids = [vmid]
        else:
            vms = self._client.vm_list(node)
            vmids = [int(vm["vmid"]) for vm in vms]

        for vid in vmids:
            try:
                audit = self.audit(node, vid)
                cfg = audit["configuration"].get("config", {})
                lines.append("")
                lines.append(f"--- VM {vid} ({cfg.get('name', 'unnamed')}) ---")
                lines.append(f"  Status:  {audit['configuration'].get('status', '?')}")
                lines.append(f"  CPUs:    {cfg.get('cores', '?')} cores / {cfg.get('sockets', '?')} sockets")
                lines.append(f"  Memory:  {cfg.get('memory', '?')} MiB")
                lines.append(f"  Disks:   {len(audit['disks'])}")
                lines.append(f"  Snaps:   {audit['snapshot_count']}")
                lines.append(f"  Health:  {audit['health']}")
                if audit["issues"]:
                    for issue in audit["issues"]:
                        lines.append(f"  [!] {issue}")
            except Exception as exc:
                lines.append(f"\n--- VM {vid}: AUDIT FAILED: {exc} ---")

        lines.append("")
        lines.append("=" * 72)
        return "\n".join(lines)
