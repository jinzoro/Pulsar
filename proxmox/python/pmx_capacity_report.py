# SPDX-License-Identifier: MIT
# Pulsar - Capacity Report

"""Proxmox VE cluster capacity reporting with storage forecasting."""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any

from pve_api_client import PVEClient

logger = logging.getLogger(__name__)


class CapacityReport:
    """Cluster capacity and inventory reporting.

    Parameters
    ----------
    client:
        An authenticated :class:`PVEClient` instance.
    """

    def __init__(self, client: PVEClient) -> None:
        self._client = client

    def generate(self) -> dict[str, Any]:
        """Generate a full cluster capacity report.

        Returns a comprehensive dict with node summaries, storage summaries
        and a VM inventory.
        """
        nodes = self._client.nodes()
        report: dict[str, Any] = {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "cluster_name": self._get_cluster_name(),
            "node_count": len(nodes),
            "nodes": [],
            "storage": {},
            "vm_inventory": [],
            "totals": {
                "cpu_total": 0,
                "cpu_used": 0,
                "memory_total": 0,
                "memory_used": 0,
                "disk_total": 0,
                "disk_used": 0,
                "vm_count": 0,
                "ct_count": 0,
            },
        }

        for node_info in nodes:
            node = node_info["node"]
            ns = self.node_summary(node)
            report["nodes"].append(ns)

            report["totals"]["cpu_total"] += ns.get("cpu_total", 0)
            report["totals"]["cpu_used"] += ns.get("cpu_used", 0)
            report["totals"]["memory_total"] += ns.get("memory_total", 0)
            report["totals"]["memory_used"] += ns.get("memory_used", 0)
            report["totals"]["disk_total"] += ns.get("disk_total", 0)
            report["totals"]["disk_used"] += ns.get("disk_used", 0)

            storage = self.storage_summary(node)
            report["storage"][node] = storage

        report["vm_inventory"] = self.vm_inventory()
        report["totals"]["vm_count"] = sum(
            1 for vm in report["vm_inventory"] if vm.get("type") == "qemu"
        )
        report["totals"]["ct_count"] = sum(
            1 for vm in report["vm_inventory"] if vm.get("type") == "lxc"
        )

        return report

    def node_summary(self, node: str) -> dict[str, Any]:
        """Return capacity summary for a single node."""
        status = self._client.node_status(node)
        cpu_total = status.get("maxcpu", 0)
        cpu_used = status.get("cpu", 0) * cpu_total
        mem_total = status.get("maxmem", 0)
        mem_used = status.get("mem", 0)
        disk_total = status.get("maxdisk", 0)
        disk_used = status.get("disk", 0)

        return {
            "node": node,
            "status": status.get("status"),
            "uptime": status.get("uptime"),
            "cpu_total": cpu_total,
            "cpu_used": round(cpu_used),
            "cpu_pct": round(cpu_used / max(cpu_total, 1) * 100, 2),
            "memory_total": mem_total,
            "memory_used": mem_used,
            "memory_pct": round(mem_used / max(mem_total, 1) * 100, 2),
            "disk_total": disk_total,
            "disk_used": disk_used,
            "disk_pct": round(disk_used / max(disk_total, 1) * 100, 2),
        }

    def storage_summary(self, node: str | None = None) -> dict[str, Any]:
        """Return storage capacity summary, optionally per-node."""
        storages: dict[str, Any] = {}
        if node:
            storage_list = self._client.storage_list(node)
            for s in storage_list:
                name = s.get("storage", "unknown")
                total = s.get("total", 0)
                used = s.get("used", 0)
                storages[name] = {
                    "type": s.get("type"),
                    "total": total,
                    "used": used,
                    "free": s.get("free", total - used),
                    "usage_pct": round(used / max(total, 1) * 100, 2),
                    "active": s.get("active") == 1,
                }
        else:
            nodes = self._client.nodes()
            for node_info in nodes:
                storages[node_info["node"]] = self.storage_summary(node_info["node"])
        return storages

    def vm_inventory(self) -> list[dict[str, Any]]:
        """Return a list of all VMs and containers across the cluster."""
        inventory: list[dict[str, Any]] = []
        nodes = self._client.nodes()

        for node_info in nodes:
            node = node_info["node"]
            for vm_type in ("qemu", "lxc"):
                vms = self._client.vm_list(node, type_=vm_type)
                for vm in vms:
                    inventory.append({
                        "vmid": vm.get("vmid"),
                        "name": vm.get("name"),
                        "type": vm_type,
                        "node": node,
                        "status": vm.get("status"),
                        "cpu": vm.get("cpus"),
                        "memory": vm.get("mem"),
                        "disk": vm.get("maxdisk"),
                        "uptime": vm.get("uptime"),
                    })

        return sorted(inventory, key=lambda x: (x.get("node", ""), x.get("vmid", 0)))

    def forecast_storage(
        self, node: str, storage: str, days: int = 30
    ) -> dict[str, Any]:
        """Forecast storage usage using simple linear regression.

        Parameters
        ----------
        node:
            Node name.
        storage:
            Storage name.
        days:
            Number of days to forecast ahead.

        Returns a dict with ``daily_usage``, ``forecast_days``,
        ``projected_usage`` and ``estimated_full_date``.
        """
        # Gather historical data from RRD
        rrd = self._client.get(
            f"/api2/json/nodes/{node}/rrddata",
            params={"timeframe": "month", "cf": "AVERAGE"},
        )

        if not isinstance(rrd, list) or len(rrd) < 2:
            return {
                "error": "Insufficient historical data for forecasting",
                "data_points": len(rrd) if isinstance(rrd, list) else 0,
            }

        # Extract time-series of disk usage
        timestamps: list[float] = []
        usage: list[float] = []
        for point in rrd:
            ts = point.get("timestamp", 0)
            disk = point.get("disk", 0)
            if ts and disk:
                timestamps.append(float(ts))
                usage.append(float(disk))

        if len(timestamps) < 2:
            return {"error": "Not enough data points for regression"}

        # Simple linear regression: y = mx + b
        n = len(timestamps)
        sum_x = sum(timestamps)
        sum_y = sum(usage)
        sum_xy = sum(t * u for t, u in zip(timestamps, usage))
        sum_x2 = sum(t**2 for t in timestamps)

        denominator = n * sum_x2 - sum_x**2
        if denominator == 0:
            return {"error": "Degenerate data – cannot compute regression"}

        slope = (n * sum_xy - sum_x * sum_y) / denominator
        intercept = (sum_y - slope * sum_x) / n

        # Daily usage rate in bytes/second → bytes/day
        daily_rate = slope * 86400

        # Current and projected usage
        now_ts = timestamps[-1]
        current_usage = usage[-1]
        projected_ts = now_ts + days * 86400
        projected_usage = slope * projected_ts + intercept

        # Estimate when storage fills up (if slope > 0)
        full_date: str | None = None
        current_total = self._client.storage_status(node, storage).get("total", 0)
        if slope > 0 and current_total > current_usage:
            seconds_remaining = (current_total - current_usage) / slope
            full_date_ts = now_ts + seconds_remaining
            full_date = datetime.fromtimestamp(full_date_ts, tz=timezone.utc).isoformat()

        return {
            "node": node,
            "storage": storage,
            "data_points": n,
            "current_usage": round(current_usage),
            "daily_rate_bytes": round(daily_rate),
            "forecast_days": days,
            "projected_usage": round(projected_usage),
            "estimated_full_date": full_date,
        }

    def to_markdown(self, report: dict[str, Any]) -> str:
        """Convert a capacity report to Markdown format."""
        lines: list[str] = []
        lines.append(f"# Proxmox Cluster Capacity Report")
        lines.append(f"*Generated: {report.get('generated_at', 'N/A')}*\n")

        totals = report.get("totals", {})
        lines.append("## Cluster Totals")
        lines.append(f"| Metric | Value |")
        lines.append(f"|--------|-------|")
        lines.append(f"| Nodes | {report.get('node_count', 0)} |")
        lines.append(f"| Total CPUs | {totals.get('cpu_total', 0)} |")
        lines.append(f"| Used CPUs | {totals.get('cpu_used', 0)} |")
        lines.append(f"| Total Memory | {self._bytes_to_human(totals.get('memory_total', 0))} |")
        lines.append(f"| Used Memory | {self._bytes_to_human(totals.get('memory_used', 0))} |")
        lines.append(f"| Total Disk | {self._bytes_to_human(totals.get('disk_total', 0))} |")
        lines.append(f"| Used Disk | {self._bytes_to_human(totals.get('disk_used', 0))} |")
        lines.append(f"| VMs | {totals.get('vm_count', 0)} |")
        lines.append(f"| Containers | {totals.get('ct_count', 0)} |")
        lines.append("")

        lines.append("## Node Details")
        for node in report.get("nodes", []):
            lines.append(f"### {node.get('node')}")
            lines.append(f"- **Status:** {node.get('status')}")
            lines.append(f"- **CPU:** {node.get('cpu_used', 0)}/{node.get('cpu_total', 0)} ({node.get('cpu_pct', 0)}%)")
            lines.append(f"- **Memory:** {self._bytes_to_human(node.get('memory_used', 0))}/{self._bytes_to_human(node.get('memory_total', 0))} ({node.get('memory_pct', 0)}%)")
            lines.append(f"- **Disk:** {self._bytes_to_human(node.get('disk_used', 0))}/{self._bytes_to_human(node.get('disk_total', 0))} ({node.get('disk_pct', 0)}%)")
            lines.append("")

        return "\n".join(lines)

    def to_html(self, report: dict[str, Any]) -> str:
        """Convert a capacity report to an HTML page."""
        totals = report.get("totals", {})
        html_parts: list[str] = [
            "<!DOCTYPE html>",
            "<html><head><title>Proxmox Capacity Report</title>",
            "<style>body{font-family:sans-serif;margin:2em}table{border-collapse:collapse}th,td{border:1px solid #ddd;padding:8px;text-align:left}th{background:#f5f5f5}h1,h2{color:#333}</style>",
            "</head><body>",
            f"<h1>Proxmox Cluster Capacity Report</h1>",
            f"<p>Generated: {report.get('generated_at', 'N/A')}</p>",
            "<h2>Cluster Totals</h2>",
            "<table>",
            "<tr><th>Metric</th><th>Value</th></tr>",
            f"<tr><td>Nodes</td><td>{report.get('node_count', 0)}</td></tr>",
            f"<tr><td>Total CPUs</td><td>{totals.get('cpu_total', 0)}</td></tr>",
            f"<tr><td>Used CPUs</td><td>{totals.get('cpu_used', 0)}</td></tr>",
            f"<tr><td>Total Memory</td><td>{self._bytes_to_human(totals.get('memory_total', 0))}</td></tr>",
            f"<tr><td>Used Memory</td><td>{self._bytes_to_human(totals.get('memory_used', 0))}</td></tr>",
            f"<tr><td>Total Disk</td><td>{self._bytes_to_human(totals.get('disk_total', 0))}</td></tr>",
            f"<tr><td>Used Disk</td><td>{self._bytes_to_human(totals.get('disk_used', 0))}</td></tr>",
            f"<tr><td>VMs</td><td>{totals.get('vm_count', 0)}</td></tr>",
            f"<tr><td>Containers</td><td>{totals.get('ct_count', 0)}</td></tr>",
            "</table>",
            "<h2>Node Details</h2>",
        ]

        for node in report.get("nodes", []):
            html_parts.append(f"<h3>{node.get('node')}</h3>")
            html_parts.append("<table>")
            html_parts.append("<tr><th>Metric</th><th>Value</th></tr>")
            html_parts.append(f"<tr><td>Status</td><td>{node.get('status')}</td></tr>")
            html_parts.append(f"<tr><td>CPU</td><td>{node.get('cpu_used', 0)}/{node.get('cpu_total', 0)} ({node.get('cpu_pct', 0)}%)</td></tr>")
            html_parts.append(f"<tr><td>Memory</td><td>{self._bytes_to_human(node.get('memory_used', 0))}/{self._bytes_to_human(node.get('memory_total', 0))} ({node.get('memory_pct', 0)}%)</td></tr>")
            html_parts.append(f"<tr><td>Disk</td><td>{self._bytes_to_human(node.get('disk_used', 0))}/{self._bytes_to_human(node.get('disk_total', 0))} ({node.get('disk_pct', 0)}%)</td></tr>")
            html_parts.append("</table>")

        html_parts.extend(["</body></html>"])
        return "\n".join(html_parts)

    def _get_cluster_name(self) -> str:
        """Best-effort cluster name extraction."""
        try:
            status = self._client.get("/api2/json/cluster/status")
            if isinstance(status, list):
                for item in status:
                    if item.get("type") == "cluster":
                        return item.get("name", "unknown")
        except Exception:
            pass
        return "unknown"

    @staticmethod
    def _bytes_to_human(value: int | float) -> str:
        """Convert bytes to a human-readable string."""
        value = float(value)
        for unit in ("B", "KiB", "MiB", "GiB", "TiB", "PiB"):
            if abs(value) < 1024:
                return f"{value:.2f} {unit}"
            value /= 1024
        return f"{value:.2f} EiB"
