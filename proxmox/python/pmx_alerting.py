# SPDX-License-Identifier: MIT
# Pulsar - Alerting

"""Proxmox VE health-check alerting system."""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any, Protocol

from pve_api_client import PVEClient

logger = logging.getLogger(__name__)


class NotificationTransport(Protocol):
    """Protocol for pluggable notification transports."""

    def send(self, alert: dict[str, Any]) -> None: ...


class _NullTransport:
    """Silent fallback transport that logs alerts instead of sending."""

    def send(self, alert: dict[str, Any]) -> None:
        logger.warning("ALERT: %s", alert.get("message", ""))


class AlertManager:
    """Proxmox VE health monitoring and alerting.

    Parameters
    ----------
    client:
        An authenticated :class:`PVEClient` instance.
    notification_manager:
        Any object implementing ``send(alert: dict)`` – e.g. an email,
        Slack or PagerDuty notifier.
    thresholds:
        Default threshold configuration::

            {
                "cpu_threshold": 90,
                "memory_threshold": 90,
                "disk_threshold": 85,
            }
    """

    def __init__(
        self,
        client: PVEClient,
        notification_manager: NotificationTransport | None = None,
        thresholds: dict[str, Any] | None = None,
    ) -> None:
        self._client = client
        self._transport: NotificationTransport = notification_manager or _NullTransport()
        self._thresholds = thresholds or {
            "cpu_threshold": 90,
            "memory_threshold": 90,
            "disk_threshold": 85,
        }

    # -- individual checks ----------------------------------------------------

    def check_cpu(self, threshold: float | None = None) -> list[dict[str, Any]]:
        """Check CPU usage across all nodes."""
        thresh = (threshold or self._thresholds.get("cpu_threshold", 90)) / 100.0
        alerts: list[dict[str, Any]] = []
        nodes = self._client.nodes()

        for node_info in nodes:
            node = node_info["node"]
            status = self._client.node_status(node)
            cpu = status.get("cpu", 0) or 0
            if cpu > thresh:
                alert = {
                    "type": "cpu_high",
                    "severity": "critical" if cpu > 0.95 else "warning",
                    "node": node,
                    "message": f"CPU usage on {node} is {cpu * 100:.1f}% (threshold: {thresh * 100}%)",
                    "value": round(cpu * 100, 2),
                    "threshold": round(thresh * 100, 2),
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                }
                alerts.append(alert)
                logger.warning(alert["message"])
        return alerts

    def check_memory(self, threshold: float | None = None) -> list[dict[str, Any]]:
        """Check memory usage across all nodes."""
        thresh = (threshold or self._thresholds.get("memory_threshold", 90)) / 100.0
        alerts: list[dict[str, Any]] = []
        nodes = self._client.nodes()

        for node_info in nodes:
            node = node_info["node"]
            status = self._client.node_status(node)
            mem = status.get("mem", 0) or 0
            maxmem = status.get("maxmem", 1) or 1
            pct = mem / maxmem
            if pct > thresh:
                alert = {
                    "type": "memory_high",
                    "severity": "critical" if pct > 0.95 else "warning",
                    "node": node,
                    "message": f"Memory usage on {node} is {pct * 100:.1f}% (threshold: {thresh * 100}%)",
                    "value": round(pct * 100, 2),
                    "threshold": round(thresh * 100, 2),
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                }
                alerts.append(alert)
                logger.warning(alert["message"])
        return alerts

    def check_disk(self, threshold: float | None = None) -> list[dict[str, Any]]:
        """Check disk usage across all nodes."""
        thresh = (threshold or self._thresholds.get("disk_threshold", 85)) / 100.0
        alerts: list[dict[str, Any]] = []
        nodes = self._client.nodes()

        for node_info in nodes:
            node = node_info["node"]
            status = self._client.node_status(node)
            disk = status.get("disk", 0) or 0
            maxdisk = status.get("maxdisk", 1) or 1
            pct = disk / maxdisk
            if pct > thresh:
                alert = {
                    "type": "disk_high",
                    "severity": "critical" if pct > 0.95 else "warning",
                    "node": node,
                    "message": f"Disk usage on {node} is {pct * 100:.1f}% (threshold: {thresh * 100}%)",
                    "value": round(pct * 100, 2),
                    "threshold": round(thresh * 100, 2),
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                }
                alerts.append(alert)
                logger.warning(alert["message"])
        return alerts

    def check_vms_down(self) -> list[dict[str, Any]]:
        """Check for HA-managed VMs that are unexpectedly stopped."""
        alerts: list[dict[str, Any]] = []
        try:
            resources = self._client.get("/api2/json/cluster/ha/resources")
            if not isinstance(resources, list):
                return alerts
            for res in resources:
                state = res.get("state", "")
                if state == "stopped" and res.get("type") == "vm":
                    vmid = res.get("sid", "").replace("vm:", "")
                    alert = {
                        "type": "vm_ha_down",
                        "severity": "warning",
                        "vmid": vmid,
                        "message": f"HA-managed VM {vmid} is stopped (desired state: started)",
                        "timestamp": datetime.now(timezone.utc).isoformat(),
                    }
                    alerts.append(alert)
                    logger.warning(alert["message"])
        except Exception as exc:
            logger.error("HA check failed: %s", exc)
        return alerts

    def check_backup_failed(self) -> list[dict[str, Any]]:
        """Check for failed backup tasks."""
        alerts: list[dict[str, Any]] = []
        nodes = self._client.nodes()

        for node_info in nodes:
            node = node_info["node"]
            try:
                tasks = self._client.get(
                    f"/api2/json/nodes/{node}/tasks",
                    params={"typefilter": "vzdump", "limit": 20},
                )
                if not isinstance(tasks, list):
                    continue
                for task in tasks:
                    if task.get("status") == "failed":
                        alert = {
                            "type": "backup_failed",
                            "severity": "critical",
                            "node": node,
                            "task_id": task.get("upid"),
                            "message": f"Backup task failed on {node}: {task.get('upid', 'unknown')}",
                            "timestamp": datetime.now(timezone.utc).isoformat(),
                        }
                        alerts.append(alert)
                        logger.warning(alert["message"])
            except Exception as exc:
                logger.error("Backup check on node %s failed: %s", node, exc)
        return alerts

    def check_ceph_health(self) -> list[dict[str, Any]]:
        """Check Ceph cluster health status."""
        alerts: list[dict[str, Any]] = []
        nodes = self._client.nodes()

        for node_info in nodes:
            node = node_info["node"]
            try:
                ceph = self._client.ceph_status(node)
                health = ceph.get("health", {})
                status = health.get("status", "HEALTH_OK")
                if status != "HEALTH_OK":
                    severity = "critical" if status == "HEALTH_ERR" else "warning"
                    alerts_dict = health.get("checks", {})
                    detail_str = "; ".join(
                        f"{k}: {v.get('summary', {}).get('message', '')}"
                        for k, v in alerts_dict.items()
                    )
                    alert = {
                        "type": "ceph_health",
                        "severity": severity,
                        "node": node,
                        "message": f"Ceph health is {status}: {detail_str}",
                        "ceph_status": status,
                        "timestamp": datetime.now(timezone.utc).isoformat(),
                    }
                    alerts.append(alert)
                    logger.warning(alert["message"])
            except Exception as exc:
                logger.debug("Ceph check on node %s skipped: %s", node, exc)
        return alerts

    def run_all_checks(self) -> list[dict[str, Any]]:
        """Run all health checks and return aggregated alerts."""
        all_alerts: list[dict[str, Any]] = []
        all_alerts.extend(self.check_cpu())
        all_alerts.extend(self.check_memory())
        all_alerts.extend(self.check_disk())
        all_alerts.extend(self.check_vms_down())
        all_alerts.extend(self.check_backup_failed())
        all_alerts.extend(self.check_ceph_health())
        logger.info("Health checks complete – %d alert(s) found", len(all_alerts))
        return all_alerts

    def send_alerts(self, alerts: list[dict[str, Any]]) -> dict[str, Any]:
        """Dispatch alerts via the configured notification transport.

        Returns a summary dict with ``sent`` and ``failed`` counts.
        """
        sent = 0
        failed = 0
        for alert in alerts:
            try:
                self._transport.send(alert)
                sent += 1
            except Exception as exc:
                logger.error("Failed to send alert: %s – %s", alert.get("message"), exc)
                failed += 1
        return {"sent": sent, "failed": failed, "total": len(alerts)}
