# SPDX-License-Identifier: MIT
# Pulsar - Monitoring

"""Proxmox VE metrics collection and Prometheus export."""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any

from pve_api_client import PVEClient

logger = logging.getLogger(__name__)


class PXEMonitoring:
    """Metrics collection and monitoring for Proxmox VE.

    Parameters
    ----------
    client:
        An authenticated :class:`PVEClient` instance.
    """

    def __init__(self, client: PVEClient) -> None:
        self._client = client

    def get_rrd_data(
        self,
        node: str,
        timeframe: str = "hour",
        cf: str = "AVERAGE",
    ) -> dict[str, Any]:
        """Fetch RRD (round-robin database) metrics for a node.

        Parameters
        ----------
        timeframe:
            ``hour``, ``day``, ``week``, ``month`` or ``year``.
        cf:
            Consolidation function – ``AVERAGE``, ``MAX``, ``MIN``.
        """
        return self._client.get(
            f"/api2/json/nodes/{node}/rrddata",
            params={"timeframe": timeframe, "cf": cf},
        )

    def get_cluster_resources(self) -> list[dict[str, Any]]:
        """Return cluster-wide resource summary (VMs, nodes, storage)."""
        return self._client.get("/api2/json/cluster/resources")  # type: ignore[return-value]

    def get_node_metrics(self, node: str) -> dict[str, Any]:
        """Collect CPU, memory, disk and network metrics for a node."""
        status = self._client.node_status(node)
        rrd = self.get_rrd_data(node, timeframe="hour", cf="AVERAGE")

        latest_rrd: dict[str, Any] = {}
        if isinstance(rrd, list) and rrd:
            latest_rrd = rrd[-1]

        return {
            "node": node,
            "status": status.get("status"),
            "uptime": status.get("uptime"),
            "cpu": status.get("cpu"),
            "cpu_cores": status.get("cpuinfo", {}).get("cores"),
            "maxcpu": status.get("maxcpu"),
            "memory_used": status.get("mem"),
            "memory_total": status.get("maxmem"),
            "memory_pct": round(status.get("mem", 0) / max(status.get("maxmem", 1), 1) * 100, 2),
            "disk_used": status.get("disk"),
            "disk_total": status.get("maxdisk"),
            "disk_pct": round(status.get("disk", 0) / max(status.get("maxdisk", 1), 1) * 100, 2),
            "loadavg": latest_rrd.get("loadavg"),
            "netin": latest_rrd.get("netin"),
            "netout": latest_rrd.get("netout"),
        }

    def get_vm_metrics(self, node: str, vmid: int) -> dict[str, Any]:
        """Collect metrics for a specific VM."""
        status = self._client.vm_status(node, vmid)
        config = self._client.get(f"/api2/json/nodes/{node}/qemu/{vmid}/config")
        return {
            "vmid": vmid,
            "node": node,
            "name": config.get("name"),
            "status": status.get("status"),
            "cpu": status.get("cpu"),
            "cpus": config.get("cores"),
            "mem": status.get("mem"),
            "mem_total": config.get("memory"),
            "mem_pct": round(status.get("mem", 0) / max(config.get("memory", 1), 1) * 100, 2),
            "disk_read": status.get("diskread"),
            "disk_write": status.get("diskwrite"),
            "net_in": status.get("netin"),
            "net_out": status.get("netout"),
            "uptime": status.get("uptime"),
            "maxmem": config.get("balloon") if config.get("balloon") else config.get("memory"),
        }

    def export_prometheus(self) -> str:
        """Generate Prometheus text-format metrics for the entire cluster."""
        lines: list[str] = []
        ts = int(datetime.now(timezone.utc).timestamp())

        # Node metrics
        nodes = self._client.nodes()
        for node_info in nodes:
            node = node_info["node"]
            metrics = self.get_node_metrics(node)
            prefix = "pve_node"

            lines.append(f"# HELP {prefix}_cpu_usage CPU usage ratio")
            lines.append(f"# TYPE {prefix}_cpu_usage gauge")
            lines.append(f"{prefix}_cpu_usage{{node=\"{node}\"}} {metrics.get('cpu', 0)} {ts}")

            lines.append(f"# HELP {prefix}_memory_bytes Memory usage in bytes")
            lines.append(f"# TYPE {prefix}_memory_bytes gauge")
            lines.append(f"{prefix}_memory_bytes{{node=\"{node}\",type=\"used\"}} {metrics.get('memory_used', 0)} {ts}")
            lines.append(f"{prefix}_memory_bytes{{node=\"{node}\",type=\"total\"}} {metrics.get('memory_total', 0)} {ts}")

            lines.append(f"# HELP {prefix}_disk_bytes Disk usage in bytes")
            lines.append(f"# TYPE {prefix}_disk_bytes gauge")
            lines.append(f"{prefix}_disk_bytes{{node=\"{node}\",type=\"used\"}} {metrics.get('disk_used', 0)} {ts}")
            lines.append(f"{prefix}_disk_bytes{{node=\"{node}\",type=\"total\"}} {metrics.get('disk_total', 0)} {ts}")

            lines.append(f"# HELP {prefix}_uptime_seconds Node uptime")
            lines.append(f"# TYPE {prefix}_uptime_seconds gauge")
            lines.append(f"{prefix}_uptime_seconds{{node=\"{node}\"}} {metrics.get('uptime', 0)} {ts}")

        # VM metrics
        for node_info in nodes:
            node = node_info["node"]
            vms = self._client.vm_list(node)
            for vm in vms:
                vmid = vm.get("vmid")
                if not vmid:
                    continue
                try:
                    vm_metrics = self.get_vm_metrics(node, int(vmid))
                    prefix = "pve_vm"

                    lines.append(f"# HELP {prefix}_cpu_usage VM CPU usage ratio")
                    lines.append(f"# TYPE {prefix}_cpu_usage gauge")
                    lines.append(f'{prefix}_cpu_usage{{node="{node}",vmid="{vmid}",name="{vm_metrics.get("name", "")}"}} {vm_metrics.get("cpu", 0)} {ts}')

                    lines.append(f"# HELP {prefix}_memory_bytes VM memory usage in bytes")
                    lines.append(f"# TYPE {prefix}_memory_bytes gauge")
                    lines.append(f'{prefix}_memory_bytes{{node="{node}",vmid="{vmid}",type="used"}} {vm_metrics.get("mem", 0)} {ts}')
                    lines.append(f'{prefix}_memory_bytes{{node="{node}",vmid="{vmid}",type="total"}} {vm_metrics.get("maxmem", 0)} {ts}')

                    lines.append(f"# HELP {prefix}_disk_read_bytes Disk read in bytes")
                    lines.append(f"# TYPE {prefix}_disk_read_bytes counter")
                    lines.append(f'{prefix}_disk_read_bytes{{node="{node}",vmid="{vmid}"}} {vm_metrics.get("disk_read", 0)} {ts}')

                    lines.append(f"# HELP {prefix}_disk_write_bytes Disk write in bytes")
                    lines.append(f"# TYPE {prefix}_disk_write_bytes counter")
                    lines.append(f'{prefix}_disk_write_bytes{{node="{node}",vmid="{vmid}"}} {vm_metrics.get("disk_write", 0)} {ts}')
                except Exception as exc:
                    logger.debug("Skipping metrics for VM %s on %s: %s", vmid, node, exc)

        return "\n".join(lines)

    def check_thresholds(self, config: dict[str, Any]) -> list[dict[str, Any]]:
        """Check metrics against configurable thresholds and return alerts.

        Parameters
        ----------
        config:
            Threshold configuration dict, e.g.::

                {
                    "cpu_threshold": 90,
                    "memory_threshold": 90,
                    "disk_threshold": 85,
                }

        Returns
        -------
        list
            List of alert dicts.
        """
        alerts: list[dict[str, Any]] = []
        cpu_thresh = config.get("cpu_threshold", 90) / 100.0
        mem_thresh = config.get("memory_threshold", 90) / 100.0
        disk_thresh = config.get("disk_threshold", 85) / 100.0

        nodes = self._client.nodes()
        for node_info in nodes:
            node = node_info["node"]
            metrics = self.get_node_metrics(node)

            cpu_pct = metrics.get("cpu", 0) or 0
            if cpu_pct > cpu_thresh:
                alerts.append({
                    "type": "cpu_high",
                    "severity": "warning",
                    "node": node,
                    "message": f"CPU usage is {cpu_pct * 100:.1f}% (threshold: {cpu_thresh * 100}%)",
                    "value": cpu_pct,
                    "threshold": cpu_thresh,
                })

            mem_pct = metrics.get("memory_pct", 0) / 100.0
            if mem_pct > mem_thresh:
                alerts.append({
                    "type": "memory_high",
                    "severity": "warning",
                    "node": node,
                    "message": f"Memory usage is {mem_pct * 100:.1f}% (threshold: {mem_thresh * 100}%)",
                    "value": mem_pct,
                    "threshold": mem_thresh,
                })

            disk_pct = metrics.get("disk_pct", 0) / 100.0
            if disk_pct > disk_thresh:
                alerts.append({
                    "type": "disk_high",
                    "severity": "warning",
                    "node": node,
                    "message": f"Disk usage is {disk_pct * 100:.1f}% (threshold: {disk_thresh * 100}%)",
                    "value": disk_pct,
                    "threshold": disk_thresh,
                })

        return alerts
