"""
SPDX-License-Identifier: MIT
VM and host monitoring via virsh, libvirt, and Prometheus metrics.

Provides ``MonitoringManager`` for collecting domain stats, block stats,
interface stats, and generating Prometheus-compatible text output.
"""

from __future__ import annotations

import json
import logging
import subprocess
from typing import Any

import libvirt

from kvm_libvirt_client import LibvirtClient, LibvirtError, _wrap_libvirt_error

logger = logging.getLogger(__name__)


class MonitoringError(Exception):
    """Raised when a monitoring operation fails."""


class MonitoringManager:
    """VM and host monitoring.

    Example::

        mon = MonitoringManager()
        stats = mon.get_domain_stats("web01")
        prom = mon.export_prometheus()
    """

    def __init__(self, client: LibvirtClient | None = None) -> None:
        self._client = client

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _run(cmd: list[str], check: bool = True) -> subprocess.CompletedProcess[str]:
        logger.debug("Running: %s", " ".join(cmd))
        result = subprocess.run(cmd, capture_output=True, text=True, check=False)
        if check and result.returncode != 0:
            raise MonitoringError(
                f"Command failed (rc={result.returncode}): "
                f"{result.stderr.strip() or result.stdout.strip()}"
            )
        return result

    def _ensure_client(self) -> LibvirtClient:
        if self._client and self._client._conn:
            return self._client
        c = LibvirtClient()
        c.connect()
        return c

    # ------------------------------------------------------------------
    # Domain statistics
    # ------------------------------------------------------------------

    def get_domain_stats(self, domain: str) -> dict[str, Any]:
        """Return comprehensive stats for a single domain.

        Combines ``virsh domstats`` output with memory, block, and
        network metrics.

        Returns:
            Dict with ``vcpu``, ``balloon``, ``block`` stats.
        """
        result = self._run(["virsh", "domstats", domain], check=False)
        if result.returncode != 0:
            return {"error": result.stderr.strip()}

        return self._parse_domstats(result.stdout)

    def _parse_domstats(self, output: str) -> dict[str, Any]:
        """Parse ``virsh domstats`` output."""
        stats: dict[str, Any] = {}
        current_section = "general"
        for line in output.splitlines():
            line = line.strip()
            if not line:
                continue
            if ":" in line and "=" in line:
                key, _, val = line.partition("=")
                key = key.strip()
                val = val.strip()
                try:
                    stats.setdefault(current_section, {})[key] = int(val)
                except ValueError:
                    stats.setdefault(current_section, {})[key] = val
            elif line.endswith(":") and "." in line:
                current_section = line.rstrip(":").split(".")[-1]
        return stats

    def get_memory_stats(self, domain: str) -> dict[str, Any]:
        """Return memory statistics for a domain.

        Uses ``virsh dommemstat``.

        Returns:
            Dict with ``actual``, ``swap_in``, ``swap_out``,
            ``major_fault``, ``minor_fault``, etc.
        """
        result = self._run(["virsh", "dommemstat", domain], check=False)
        if result.returncode != 0:
            return {"error": result.stderr.strip()}

        stats: dict[str, Any] = {}
        for line in result.stdout.splitlines():
            parts = line.split()
            if len(parts) == 2:
                try:
                    stats[parts[0]] = int(parts[1])
                except ValueError:
                    stats[parts[0]] = parts[1]
        return stats

    def get_block_stats(self, domain: str) -> list[dict[str, Any]]:
        """Return block (disk) I/O statistics for a domain.

        Uses ``virsh domblkstat``.

        Returns:
            List of dicts with ``device``, ``rd_bytes``, ``wr_bytes``,
            ``rd_reqs``, ``wr_reqs``, ``flush_reqs``.
        """
        result = self._run(
            ["virsh", "domblkstat", domain, "--domain", domain],
            check=False,
        )
        # Simpler invocation
        result = self._run(["virsh", "domblkstat", domain], check=False)
        if result.returncode != 0:
            return [{"error": result.stderr.strip()}]

        block_stats: list[dict[str, Any]] = []
        for line in result.stdout.splitlines():
            parts = line.split()
            if not parts:
                continue
            device = parts[0]
            stat: dict[str, Any] = {"device": device}
            i = 1
            while i < len(parts) - 1:
                key = parts[i]
                try:
                    stat[key] = int(parts[i + 1])
                except (ValueError, IndexError):
                    pass
                i += 2
            block_stats.append(stat)
        return block_stats

    def get_interface_stats(self, domain: str) -> list[dict[str, Any]]:
        """Return network interface statistics for a domain.

        Uses ``virsh domifstat``.

        Returns:
            List of dicts with ``interface``, ``rx_bytes``, ``tx_bytes``,
            ``rx_packets``, ``tx_packets``.
        """
        # First get the interface names
        client = self._ensure_client()
        dom = client.get_domain(domain)
        try:
            xml_desc = dom.XMLDesc(0)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc

        import xml.etree.ElementTree as ET
        root = ET.fromstring(xml_desc)
        interfaces = []
        for iface in root.findall(".//interface"):
            source = iface.find("source")
            if source is not None:
                net = source.get("network", "")
                interfaces.append(f"vnet{len(interfaces)}")

        # Get stats for each interface
        iface_stats: list[dict[str, Any]] = []
        for iface_name in interfaces:
            result = self._run(
                ["virsh", "domifstat", domain, iface_name],
                check=False,
            )
            stat: dict[str, Any] = {"interface": iface_name}
            if result.returncode == 0:
                for line in result.stdout.splitlines():
                    parts = line.split()
                    if len(parts) == 2:
                        try:
                            stat[parts[0]] = int(parts[1])
                        except ValueError:
                            stat[parts[0]] = parts[1]
            iface_stats.append(stat)

        return iface_stats

    def get_all_stats(self) -> list[dict[str, Any]]:
        """Return stats for all running domains.

        Returns:
            List of per-domain stat dicts.
        """
        client = self._ensure_client()
        domains = client.list_domains(active=True, inactive=False)
        all_stats: list[dict[str, Any]] = []
        for dom in domains:
            name = dom.name()
            try:
                stats = self.get_domain_stats(name)
                stats["name"] = name
                all_stats.append(stats)
            except Exception as exc:
                all_stats.append({"name": name, "error": str(exc)})
        return all_stats

    # ------------------------------------------------------------------
    # Prometheus export
    # ------------------------------------------------------------------

    def export_prometheus(self) -> str:
        """Export all domain stats in Prometheus exposition format.

        Returns:
            Prometheus text format string.
        """
        lines: list[str] = []

        client = self._ensure_client()
        domains = client.list_domains(active=True, inactive=False)

        for dom in domains:
            name = dom.name()
            labels = f'domain="{name}"'

            # Basic info
            try:
                info = dom.info()
                lines.append(f'kvm_vcpu_total{{{labels}}} {info[3]}')
                lines.append(f'kvm_memory_bytes{{{labels}}} {info[2] * 1024}')
                lines.append(f'kvm_memory_max_bytes{{{labels}}} {info[1] * 1024}')
                state_map = {1: 1, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0, 7: 0}
                lines.append(f'kvm_domain_running{{{labels}}} {state_map.get(info[0], 0)}')
            except libvirt.libvirtError:
                pass

            # Block stats
            try:
                blk_result = self._run(["virsh", "domblkstat", name], check=False)
                if blk_result.returncode == 0:
                    for bline in blk_result.stdout.splitlines():
                        parts = bline.split()
                        if parts:
                            dev = parts[0]
                            dev_labels = f'{labels},device="{dev}"'
                            i = 1
                            while i < len(parts) - 1:
                                metric_name = parts[i].replace("-", "_")
                                try:
                                    val = int(parts[i + 1])
                                    lines.append(
                                        f'kvm_block_{metric_name}{{{dev_labels}}} {val}'
                                    )
                                except (ValueError, IndexError):
                                    pass
                                i += 2
            except Exception:
                pass

            # Memory stats
            try:
                mem_result = self._run(["virsh", "dommemstat", name], check=False)
                if mem_result.returncode == 0:
                    for mline in mem_result.stdout.splitlines():
                        parts = mline.split()
                        if len(parts) == 2:
                            metric = parts[0].replace("-", "_")
                            try:
                                val = int(parts[1])
                                lines.append(
                                    f'kvm_memory_{metric}{{{labels}}} {val}'
                                )
                            except ValueError:
                                pass
            except Exception:
                pass

        # libvirtd health
        lines.append("# HELP kvm_libvirtd_up Whether libvirtd is running")
        lines.append("# TYPE kvm_libvirtd_up gauge")
        health = self.check_libvirtd_health()
        lines.append(f'kvm_libvirtd_up 1' if health.get("running") else 'kvm_libvirtd_up 0')

        return "\n".join(lines) + "\n"

    # ------------------------------------------------------------------
    # Health checks
    # ------------------------------------------------------------------

    def check_libvirtd_health(self) -> dict[str, Any]:
        """Check if libvirtd is running and responsive.

        Returns:
            Dict with ``running``, ``version``, ``response_time_ms``.
        """
        import time

        start = time.monotonic()
        result = self._run(
            ["virsh", "version", "--daemon"],
            check=False,
        )
        elapsed = (time.monotonic() - start) * 1000

        running = result.returncode == 0
        version = None
        if running:
            for line in result.stdout.splitlines():
                if "libvirt" in line.lower():
                    version = line.strip()
                    break

        return {
            "running": running,
            "version": version,
            "response_time_ms": round(elapsed, 2),
            "error": result.stderr.strip() if result.returncode != 0 else None,
        }

    def check_storage_pool_health(
        self,
        pool_name: str | None = None,
    ) -> list[dict[str, Any]]:
        """Check health of storage pools.

        Args:
            pool_name: Specific pool to check; ``None`` for all.

        Returns:
            List of dicts with ``name``, ``active``, ``allocation``,
            ``capacity``, ``free``, ``state``.
        """
        client = self._ensure_client()
        pools = client.list_storage_pools(active=True, inactive=True)
        result: list[dict[str, Any]] = []

        for pool in pools:
            name = pool.name()
            if pool_name and name != pool_name:
                continue
            try:
                info = pool.info()
                result.append({
                    "name": name,
                    "active": bool(pool.isActive()),
                    "state": ["not running", "building", "running", "degraded", "inaccessible"][
                        info[0]
                    ] if info[0] < 5 else "unknown",
                    "allocation_mb": info[1] // (1024 * 1024) if info[1] else 0,
                    "capacity_mb": info[2] // (1024 * 1024) if info[2] else 0,
                    "free_mb": info[3] // (1024 * 1024) if info[3] else 0,
                })
            except libvirt.libvirtError as exc:
                result.append({"name": name, "error": str(exc)})

        return result

    def check_network_health(
        self,
        network_name: str | None = None,
    ) -> list[dict[str, Any]]:
        """Check health of virtual networks.

        Args:
            network_name: Specific network to check; ``None`` for all.

        Returns:
            List of dicts with ``name``, ``active``, ``bridge``,
            ``autostart``, ``persistent``.
        """
        client = self._ensure_client()
        networks = client.list_networks(active=True, inactive=True)
        result: list[dict[str, Any]] = []

        for net in networks:
            name = net.name()
            if network_name and name != network_name:
                continue
            try:
                result.append({
                    "name": name,
                    "active": bool(net.isActive()),
                    "bridge": net.bridgeName() if net.isActive() else None,
                    "autostart": bool(net.autostart()),
                    "persistent": bool(net.isPersistent()),
                })
            except libvirt.libvirtError as exc:
                result.append({"name": name, "error": str(exc)})

        return result
