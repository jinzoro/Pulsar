#!/usr/bin/env python3
# =============================================================================
# health_check.py — Host and service health checker
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Pulsar contributors
# =============================================================================
# Provides HealthChecker class for pinging hosts, testing SSH and TCP
# connectivity, and querying disk / memory / load statistics (local or
# remote via SSH).
# =============================================================================

from __future__ import annotations

import json
import logging
import re
import shutil
import socket
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Try to import ssh_executor for remote checks
# ---------------------------------------------------------------------------
try:
    from .ssh_executor import SSHExecutor
    _HAS_SSH_EXECUTOR = True
except ImportError:
    _HAS_SSH_EXECUTOR = False


# ---------------------------------------------------------------------------
# HealthChecker
# ---------------------------------------------------------------------------

class HealthChecker:
    """Comprehensive health-check utility for local and remote hosts.

    Parameters
    ----------
    config : dict or None
        Configuration dictionary.  Recognised keys:

        - ``ssh.user`` — default SSH user (default ``"root"``).
        - ``ssh.key_path`` — default key path.
        - ``ssh.timeout`` — SSH timeout (default 30).
        - ``ssh.retries`` — SSH retries (default 3).
    """

    def __init__(self, config: Optional[Dict[str, Any]] = None) -> None:
        self._cfg = config or {}
        ssh_cfg = self._cfg.get("ssh", {})
        self._default_user: str = ssh_cfg.get("default_user", "root")
        self._default_key: Optional[str] = ssh_cfg.get("key_path")
        self._ssh_timeout: int = int(ssh_cfg.get("timeout", 30))
        self._ssh_retries: int = int(ssh_cfg.get("retry", 3))

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _get_ssh_executor(self, host: str) -> Any:
        """Return an SSHExecutor for the given host."""
        if not _HAS_SSH_EXECUTOR:
            raise RuntimeError(
                "ssh_executor module is required for remote checks."
            )
        return SSHExecutor(
            host=host,
            user=self._default_user,
            key_path=self._default_key,
            timeout=self._ssh_timeout,
            retries=self._ssh_retries,
        )

    def _run_ssh(self, host: str, command: str) -> Tuple[int, str, str]:
        """Run a command over SSH and return (exit_code, stdout, stderr)."""
        executor = self._get_ssh_executor(host)
        return executor.execute(command)

    def _run_local(self, command: str) -> Tuple[int, str, str]:
        """Run a local command via subprocess."""
        try:
            result = subprocess.run(
                command,
                shell=True,
                capture_output=True,
                text=True,
                timeout=15,
            )
            return result.returncode, result.stdout, result.stderr
        except subprocess.TimeoutExpired:
            return 1, "", "Command timed out"
        except Exception as exc:
            return 1, "", str(exc)

    # ------------------------------------------------------------------
    # Ping check
    # ------------------------------------------------------------------

    def check_ping(
        self,
        host: str,
        count: int = 3,
        timeout: int = 5,
    ) -> Dict[str, Any]:
        """Ping a host and report reachability and latency.

        Parameters
        ----------
        host : str
            Hostname or IP address.
        count : int
            Number of ICMP packets to send.
        timeout : int
            Per-packet timeout in seconds.

        Returns
        -------
        dict
            ``{host, reachable, avg_ms, packet_loss, min_ms, max_ms}``.
        """
        result: Dict[str, Any] = {
            "host": host,
            "reachable": False,
            "avg_ms": None,
            "min_ms": None,
            "max_ms": None,
            "packet_loss": 100.0,
        }

        # Build platform-appropriate ping command
        import platform
        if platform.system().lower() == "windows":
            cmd = f"ping -n {count} -w {timeout * 1000} {host}"
        else:
            cmd = f"ping -c {count} -W {timeout} {host}"

        exit_code, stdout, stderr = self._run_local(cmd)
        output = stdout + stderr

        if exit_code != 0 and "100% packet loss" in output:
            result["reachable"] = False
            result["packet_loss"] = 100.0
            return result

        # Parse packet loss
        loss_match = re.search(r"(\d+(?:\.\d+)?)% packet loss", output)
        if loss_match:
            result["packet_loss"] = float(loss_match.group(1))

        result["reachable"] = result["packet_loss"] < 100.0

        # Parse RTT stats (Linux: rtt min/avg/max/mdev, macOS: min/avg/max/stddev)
        rtt_match = re.search(
            r"rtt(?:/ping)? min/avg/max(?:/mdev)?/?(?:stddev)?\s*=\s*"
            r"([\d.]+)/([\d.]+)/([\d.]+)",
            output,
        )
        if rtt_match:
            result["min_ms"] = float(rtt_match.group(1))
            result["avg_ms"] = float(rtt_match.group(2))
            result["max_ms"] = float(rtt_match.group(3))

        logger.debug("Ping %s: reachable=%s avg=%.1fms", host, result["reachable"], result["avg_ms"] or 0)
        return result

    # ------------------------------------------------------------------
    # SSH check
    # ------------------------------------------------------------------

    def check_ssh(
        self,
        host: str,
        port: int = 22,
        timeout: int = 5,
    ) -> Dict[str, Any]:
        """Test SSH connectivity and capture the server banner.

        Parameters
        ----------
        host : str
            Hostname or IP address.
        port : int
            SSH port.
        timeout : int
            Connection timeout in seconds.

        Returns
        -------
        dict
            ``{host, port, ssh_reachable, banner}``.
        """
        result: Dict[str, Any] = {
            "host": host,
            "port": port,
            "ssh_reachable": False,
            "banner": "",
        }

        try:
            sock = socket.create_connection((host, port), timeout=timeout)
            banner = sock.recv(1024).decode("utf-8", errors="replace").strip()
            result["banner"] = banner
            result["ssh_reachable"] = True
            sock.close()
        except socket.timeout:
            logger.debug("SSH check timed out for %s:%d", host, port)
        except ConnectionRefusedError:
            logger.debug("SSH connection refused for %s:%d", host, port)
        except Exception as exc:
            logger.debug("SSH check failed for %s:%d: %s", host, port, exc)

        logger.debug(
            "SSH %s:%d: reachable=%s", host, port, result["ssh_reachable"]
        )
        return result

    # ------------------------------------------------------------------
    # Port check
    # ------------------------------------------------------------------

    def check_port(
        self,
        host: str,
        port: int,
        timeout: int = 5,
    ) -> Dict[str, Any]:
        """Check whether a TCP port is open.

        Parameters
        ----------
        host : str
            Hostname or IP address.
        port : int
            TCP port number.
        timeout : int
            Connection timeout in seconds.

        Returns
        -------
        dict
            ``{host, port, open}``.
        """
        result: Dict[str, Any] = {
            "host": host,
            "port": port,
            "open": False,
        }

        try:
            sock = socket.create_connection((host, port), timeout=timeout)
            result["open"] = True
            sock.close()
        except (socket.timeout, ConnectionRefusedError, OSError):
            pass

        return result

    # ------------------------------------------------------------------
    # Disk check
    # ------------------------------------------------------------------

    def check_disk(self, host: Optional[str] = None) -> Dict[str, Any]:
        """Check disk usage for the local or a remote host.

        Parameters
        ----------
        host : str or None
            Remote host.  If ``None``, checks the local machine.

        Returns
        -------
        dict
            ``{host, filesystems: [{filesystem, size, used, avail, use_percent, mountpoint}]}``.
        """
        df_cmd = "df -h --output=source,size,used,avail,pcent,target 2>/dev/null || df -h"

        if host:
            exit_code, stdout, stderr = self._run_ssh(host, df_cmd)
        else:
            exit_code, stdout, stderr = self._run_local(df_cmd)

        filesystems: List[Dict[str, Any]] = []

        for line in stdout.strip().splitlines()[1:]:  # skip header
            parts = line.split()
            if len(parts) >= 6:
                filesystems.append({
                    "filesystem": parts[0],
                    "size": parts[1],
                    "used": parts[2],
                    "avail": parts[3],
                    "use_percent": parts[4].rstrip("%"),
                    "mountpoint": parts[5],
                })
            elif len(parts) >= 5:
                # Some df outputs lack the source column
                filesystems.append({
                    "filesystem": "unknown",
                    "size": parts[0],
                    "used": parts[1],
                    "avail": parts[2],
                    "use_percent": parts[3].rstrip("%"),
                    "mountpoint": parts[4],
                })

        return {
            "host": host or "localhost",
            "filesystems": filesystems,
        }

    # ------------------------------------------------------------------
    # Memory check
    # ------------------------------------------------------------------

    def check_memory(self, host: Optional[str] = None) -> Dict[str, Any]:
        """Check memory usage for the local or a remote host.

        Parameters
        ----------
        host : str or None
            Remote host.  If ``None``, checks the local machine.

        Returns
        -------
        dict
            ``{host, total_mb, used_mb, free_mb, available_mb, use_percent, swap_total_mb, swap_used_mb}``.
        """
        mem_cmd = "free -m"

        if host:
            exit_code, stdout, stderr = self._run_ssh(host, mem_cmd)
        else:
            exit_code, stdout, stderr = self._run_local(mem_cmd)

        result: Dict[str, Any] = {
            "host": host or "localhost",
            "total_mb": 0,
            "used_mb": 0,
            "free_mb": 0,
            "available_mb": 0,
            "use_percent": 0.0,
            "swap_total_mb": 0,
            "swap_used_mb": 0,
        }

        for line in stdout.strip().splitlines():
            parts = line.split()
            if len(parts) < 3:
                continue

            label = parts[0].rstrip(":")
            values = [int(p) for p in parts[1:] if p.isdigit()]

            if label == "Mem" and len(values) >= 3:
                result["total_mb"] = values[0]
                result["used_mb"] = values[1] if len(values) > 1 else 0
                result["free_mb"] = values[2] if len(values) > 2 else 0
                result["available_mb"] = values[6] if len(values) > 6 else values[2]
                if result["total_mb"] > 0:
                    result["use_percent"] = round(
                        (result["used_mb"] / result["total_mb"]) * 100, 1
                    )
            elif label == "Swap" and len(values) >= 2:
                result["swap_total_mb"] = values[0]
                result["swap_used_mb"] = values[1]

        return result

    # ------------------------------------------------------------------
    # Load check
    # ------------------------------------------------------------------

    def check_load(self, host: Optional[str] = None) -> Dict[str, Any]:
        """Check CPU load average for the local or a remote host.

        Parameters
        ----------
        host : str or None
            Remote host.  If ``None``, checks the local machine.

        Returns
        -------
        dict
            ``{host, load_1m, load_5m, load_15m, cpu_count}``.
        """
        load_cmd = "cat /proc/loadavg 2>/dev/null || sysctl -n vm.loadavg 2>/dev/null || uptime"

        if host:
            exit_code, stdout, stderr = self._run_ssh(host, load_cmd)
        else:
            exit_code, stdout, stderr = self._run_local(load_cmd)

        result: Dict[str, Any] = {
            "host": host or "localhost",
            "load_1m": 0.0,
            "load_5m": 0.0,
            "load_15m": 0.0,
            "cpu_count": 0,
        }

        loadavg_match = re.search(
            r"([\d.]+)\s+([\d.]+)\s+([\d.]+)", stdout
        )
        if loadavg_match:
            result["load_1m"] = float(loadavg_match.group(1))
            result["load_5m"] = float(loadavg_match.group(2))
            result["load_15m"] = float(loadavg_match.group(3))

        # Try to get CPU count
        cpu_cmd = "nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 0"
        if host:
            _, cpu_out, _ = self._run_ssh(host, cpu_cmd)
        else:
            _, cpu_out, _ = self._run_local(cpu_cmd)

        try:
            result["cpu_count"] = int(cpu_out.strip())
        except (ValueError, TypeError):
            result["cpu_count"] = 0

        return result

    # ------------------------------------------------------------------
    # Comprehensive check
    # ------------------------------------------------------------------

    def check_all(self, hosts: List[str]) -> Dict[str, Any]:
        """Run a comprehensive health check across multiple hosts.

        For each host, runs ping, SSH, disk, memory, and load checks in
        parallel where possible.

        Parameters
        ----------
        hosts : list[str]
            Hostnames or IPs to check.

        Returns
        -------
        dict
            ``{timestamp, hosts: {hostname: {ping, ssh, disk, memory, load}}}``
        """
        results: Dict[str, Any] = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "hosts": {},
        }

        def _check_single(host: str) -> Dict[str, Any]:
            host_result: Dict[str, Any] = {}

            # Always run ping first
            host_result["ping"] = self.check_ping(host)

            # If reachable, run deeper checks
            if host_result["ping"]["reachable"]:
                host_result["ssh"] = self.check_ssh(host)
                host_result["disk"] = self.check_disk(host)
                host_result["memory"] = self.check_memory(host)
                host_result["load"] = self.check_load(host)
            else:
                host_result["ssh"] = {
                    "host": host, "port": 22, "ssh_reachable": False, "banner": ""
                }
                host_result["disk"] = {"host": host, "filesystems": []}
                host_result["memory"] = {
                    "host": host, "total_mb": 0, "used_mb": 0,
                    "free_mb": 0, "available_mb": 0, "use_percent": 0.0,
                    "swap_total_mb": 0, "swap_used_mb": 0,
                }
                host_result["load"] = {
                    "host": host, "load_1m": 0.0, "load_5m": 0.0,
                    "load_15m": 0.0, "cpu_count": 0,
                }

            return host_result

        # Run checks for each host in parallel
        max_workers = min(len(hosts), 8)
        with ThreadPoolExecutor(max_workers=max_workers) as pool:
            future_to_host = {
                pool.submit(_check_single, host): host for host in hosts
            }
            for future in as_completed(future_to_host):
                host = future_to_host[future]
                try:
                    results["hosts"][host] = future.result()
                except Exception as exc:
                    logger.error("Health check failed for %s: %s", host, exc)
                    results["hosts"][host] = {"error": str(exc)}

        logger.info(
            "Health check complete for %d host(s).", len(hosts)
        )
        return results

    # ------------------------------------------------------------------
    # Output formatting
    # ------------------------------------------------------------------

    def to_json(self, results: Dict[str, Any], indent: int = 2) -> str:
        """Format health-check results as a JSON string.

        Parameters
        ----------
        results : dict
            Results from :meth:`check_all` or any individual check.
        indent : int
            JSON indentation level.

        Returns
        -------
        str
            Pretty-printed JSON string.
        """
        return json.dumps(results, indent=indent, default=str, ensure_ascii=False)

    def to_markdown(self, results: Dict[str, Any]) -> str:
        """Format health-check results as a Markdown report.

        Parameters
        ----------
        results : dict
            Results from :meth:`check_all`.

        Returns
        -------
        str
            Markdown string.
        """
        lines: List[str] = []
        ts = results.get("timestamp", "unknown")
        lines.append("# Health Check Report")
        lines.append(f"*Timestamp: {ts}*")
        lines.append("")

        hosts = results.get("hosts", {})
        for host, data in sorted(hosts.items()):
            lines.append(f"## {host}")
            lines.append("")

            # Ping
            ping = data.get("ping", {})
            reachable = "Yes" if ping.get("reachable") else "No"
            lines.append(f"**Ping:** {reachable}")
            if ping.get("avg_ms") is not None:
                lines.append(f"  - Avg latency: {ping['avg_ms']:.1f} ms")
                lines.append(f"  - Packet loss: {ping.get('packet_loss', 0):.1f}%")
            lines.append("")

            # SSH
            ssh = data.get("ssh", {})
            ssh_ok = "Yes" if ssh.get("ssh_reachable") else "No"
            lines.append(f"**SSH:** {ssh_ok}")
            if ssh.get("banner"):
                lines.append(f"  - Banner: `{ssh['banner']}`")
            lines.append("")

            # Disk
            disk = data.get("disk", {})
            filesystems = disk.get("filesystems", [])
            if filesystems:
                lines.append("**Disk:**")
                lines.append("| Filesystem | Size | Used | Avail | Use% | Mount |")
                lines.append("| --- | --- | --- | --- | --- | --- |")
                for fs in filesystems:
                    lines.append(
                        f"| {fs.get('filesystem', '')} "
                        f"| {fs.get('size', '')} "
                        f"| {fs.get('used', '')} "
                        f"| {fs.get('avail', '')} "
                        f"| {fs.get('use_percent', '')}% "
                        f"| {fs.get('mountpoint', '')} |"
                    )
                lines.append("")

            # Memory
            mem = data.get("memory", {})
            if mem.get("total_mb"):
                lines.append("**Memory:**")
                lines.append(
                    f"  - Used: {mem['used_mb']}MB / {mem['total_mb']}MB "
                    f"({mem['use_percent']}%)"
                )
                lines.append(
                    f"  - Available: {mem.get('available_mb', mem.get('free_mb', 0))}MB"
                )
                if mem.get("swap_total_mb"):
                    lines.append(
                        f"  - Swap: {mem['swap_used_mb']}MB / {mem['swap_total_mb']}MB"
                    )
                lines.append("")

            # Load
            load = data.get("load", {})
            if load.get("cpu_count"):
                lines.append("**Load Average:**")
                lines.append(
                    f"  - 1m: {load['load_1m']:.2f}  "
                    f"5m: {load['load_5m']:.2f}  "
                    f"15m: {load['load_15m']:.2f}  "
                    f"({load['cpu_count']} CPUs)"
                )
                lines.append("")

            lines.append("---")
            lines.append("")

        return "\n".join(lines)
