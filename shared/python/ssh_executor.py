#!/usr/bin/env python3
# =============================================================================
# ssh_executor.py — SSH command execution for Pulsar
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Pulsar contributors
# =============================================================================
# Provides SSHExecutor class for running commands on local and remote hosts
# via subprocess (native OpenSSH) with optional paramiko fallback.
# =============================================================================

from __future__ import annotations

import logging
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Result dataclass
# ---------------------------------------------------------------------------

@dataclass
class SSHResult:
    """Result of an SSH command execution."""

    host: str
    command: str
    exit_code: int
    stdout: str
    stderr: str
    duration_ms: float = 0.0

    @property
    def success(self) -> bool:
        """Return True if the command exited with code 0."""
        return self.exit_code == 0

    def __str__(self) -> str:
        status = "OK" if self.success else f"FAIL(rc={self.exit_code})"
        return (
            f"[{status}] {self.host}: {self.command} "
            f"({self.duration_ms:.0f}ms)"
        )


@dataclass
class SSHExecutor:
    """Execute commands over SSH on local and remote hosts.

    Uses the native OpenSSH ``ssh`` binary via :mod:`subprocess`.  If
    ``paramiko`` is importable, a transparent fallback is used when the
    OpenSSH client is unavailable.

    Parameters
    ----------
    host : str
        Target hostname or IP address.
    user : str
        SSH user name.
    key_path : str or None
        Path to the SSH private key file.  ``None`` uses the default key.
    timeout : int
        Connection and command timeout in seconds.
    retries : int
        Number of retry attempts on connection failure.
    """

    host: str
    user: str
    key_path: Optional[str] = None
    timeout: int = 30
    retries: int = 3
    _use_paramiko: bool = field(default=False, init=False, repr=False)

    def __post_init__(self) -> None:
        # Detect whether native ssh is available
        try:
            subprocess.run(
                ["ssh", "-V"],
                capture_output=True,
                timeout=5,
            )
            self._use_paramiko = False
        except (FileNotFoundError, subprocess.TimeoutExpired):
            self._use_paramiko = True
            logger.debug(
                "Native ssh not found; falling back to paramiko for %s",
                self.host,
            )

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    def _build_ssh_command(self, command: str) -> List[str]:
        """Build the SSH command vector."""
        cmd = [
            "ssh",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", f"ServerAliveInterval={max(self.timeout // 5, 5)}",
            "-o", "ServerAliveCountMax=3",
        ]
        if self.key_path:
            cmd += ["-i", str(Path(self.key_path).expanduser())]
        cmd += [f"{self.user}@{self.host}", command]
        return cmd

    def _execute_subprocess(self, command: str) -> Tuple[int, str, str]:
        """Run command via native OpenSSH subprocess."""
        ssh_cmd = self._build_ssh_command(command)
        logger.debug("ssh cmd: %s", " ".join(ssh_cmd))
        result = subprocess.run(
            ssh_cmd,
            capture_output=True,
            text=True,
            timeout=self.timeout,
        )
        return result.returncode, result.stdout, result.stderr

    def _execute_paramiko(self, command: str) -> Tuple[int, str, str]:
        """Run command via paramiko as a fallback transport."""
        try:
            import paramiko  # type: ignore[import-untyped]
        except ImportError:
            raise RuntimeError(
                "paramiko is required when the ssh binary is unavailable. "
                "Install it with: pip install paramiko"
            )

        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

        connect_kwargs: Dict[str, Any] = {
            "hostname": self.host,
            "username": self.user,
            "timeout": self.timeout,
        }
        if self.key_path:
            connect_kwargs["key_filename"] = str(
                Path(self.key_path).expanduser()
            )

        client.connect(**connect_kwargs)
        try:
            _, stdout, stderr = client.exec_command(
                command, timeout=self.timeout
            )
            exit_code = stdout.channel.recv_exit_status()
            stdout_str = stdout.read().decode("utf-8", errors="replace")
            stderr_str = stderr.read().decode("utf-8", errors="replace")
            return exit_code, stdout_str, stderr_str
        finally:
            client.close()

    def _run_with_retries(self, command: str) -> Tuple[int, str, str]:
        """Execute a command with retry logic."""
        last_error: Optional[Exception] = None

        for attempt in range(1, self.retries + 1):
            try:
                if self._use_paramiko:
                    return self._execute_paramiko(command)
                return self._execute_subprocess(command)
            except subprocess.TimeoutExpired:
                last_error = TimeoutError(
                    f"Command timed out after {self.timeout}s"
                )
                logger.warning(
                    "Attempt %d/%d timed out for %s: %s",
                    attempt,
                    self.retries,
                    self.host,
                    command,
                )
            except Exception as exc:
                last_error = exc
                logger.warning(
                    "Attempt %d/%d failed for %s: %s",
                    attempt,
                    self.retries,
                    self.host,
                    exc,
                )

            if attempt < self.retries:
                backoff = min(2 ** attempt, 10)
                logger.debug(
                    "Retrying in %ds (attempt %d/%d)...",
                    backoff,
                    attempt + 1,
                    self.retries,
                )
                time.sleep(backoff)

        raise last_error  # type: ignore[misc]

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def execute(self, command: str) -> Tuple[int, str, str]:
        """Execute a single command on the remote host.

        Parameters
        ----------
        command : str
            The shell command to execute.

        Returns
        -------
        tuple[int, str, str]
            ``(exit_code, stdout, stderr)``

        Raises
        ------
        RuntimeError
            If all retry attempts fail.
        """
        start = time.monotonic()
        try:
            exit_code, stdout, stderr = self._run_with_retries(command)
        except Exception as exc:
            duration = (time.monotonic() - start) * 1000
            logger.error(
                "SSH execution failed on %s after %.0fms: %s",
                self.host,
                duration,
                exc,
            )
            raise RuntimeError(
                f"SSH command failed on {self.host}: {exc}"
            ) from exc

        duration = (time.monotonic() - start) * 1000
        logger.debug(
            "SSH %s [%d] (%.0fms): %s",
            self.host,
            exit_code,
            duration,
            command,
        )
        return exit_code, stdout, stderr

    def execute_parallel(
        self,
        commands: List[str],
        hosts: Optional[List[str]] = None,
    ) -> Dict[str, Tuple[int, str, str]]:
        """Execute commands on multiple hosts in parallel.

        Parameters
        ----------
        commands : list[str]
            Commands to run on each host.
        hosts : list[str] or None
            Target hostnames.  If ``None``, uses ``self.host`` for each
            command (same host, different commands).

        Returns
        -------
        dict[str, tuple[int, str, str]]
            Mapping of ``host:command`` to ``(exit_code, stdout, stderr)``.

        Raises
        ------
        RuntimeError
            If any execution fails after retries.
        """
        if hosts is None:
            hosts = [self.host]

        # Build work items: each is (host, command)
        work_items: List[Tuple[str, str]] = []
        for host in hosts:
            for cmd in commands:
                work_items.append((host, cmd))

        results: Dict[str, Tuple[int, str, str]] = {}
        max_workers = min(len(work_items), 8)

        with ThreadPoolExecutor(max_workers=max_workers) as pool:
            futures = {}
            for host, cmd in work_items:
                executor = SSHExecutor(
                    host=host,
                    user=self.user,
                    key_path=self.key_path,
                    timeout=self.timeout,
                    retries=self.retries,
                )
                future = pool.submit(executor.execute, cmd)
                futures[future] = (host, cmd)

            for future in as_completed(futures):
                host, cmd = futures[future]
                key = f"{host}:{cmd}"
                try:
                    results[key] = future.result()
                except Exception as exc:
                    logger.error("Parallel SSH failed for %s: %s", key, exc)
                    results[key] = (-1, "", str(exc))

        return results

    def execute_script(
        self,
        script_path: str,
        script_args: Optional[List[str]] = None,
    ) -> Tuple[int, str, str]:
        """Execute a local script file on the remote host.

        The script is read locally, then executed via ``bash -s`` on the
        remote host.

        Parameters
        ----------
        script_path : str
            Path to the local script file.
        script_args : list[str] or None
            Arguments to pass to the script.

        Returns
        -------
        tuple[int, str, str]
            ``(exit_code, stdout, stderr)``
        """
        local_path = Path(script_path).expanduser().resolve()
        if not local_path.is_file():
            raise FileNotFoundError(f"Script not found: {local_path}")

        script_content = local_path.read_text(encoding="utf-8")

        # Build remote invocation command
        remote_cmd = "bash -s"
        if script_args:
            # Shell-escape each argument
            import shlex
            remote_cmd += " " + " ".join(shlex.quote(a) for a in script_args)

        # Use SSH to pipe the script into bash on the remote
        ssh_cmd = self._build_ssh_command(remote_cmd)
        logger.debug(
            "Executing script %s on %s", local_path.name, self.host
        )

        start = time.monotonic()
        try:
            result = subprocess.run(
                ssh_cmd,
                input=script_content,
                capture_output=True,
                text=True,
                timeout=self.timeout,
            )
            duration = (time.monotonic() - start) * 1000
            logger.debug(
                "Script %s completed on %s [%d] (%.0fms)",
                local_path.name,
                self.host,
                result.returncode,
                duration,
            )
            return result.returncode, result.stdout, result.stderr
        except subprocess.TimeoutExpired as exc:
            duration = (time.monotonic() - start) * 1000
            logger.error(
                "Script %s timed out on %s after %.0fms",
                local_path.name,
                self.host,
                duration,
            )
            raise RuntimeError(
                f"Script execution timed out on {self.host}"
            ) from exc


# ---------------------------------------------------------------------------
# Convenience: quick local command execution
# ---------------------------------------------------------------------------

def run_local(
    command: str,
    timeout: int = 30,
    cwd: Optional[str] = None,
) -> Tuple[int, str, str]:
    """Run a local command via subprocess.

    Parameters
    ----------
    command : str
        Shell command to execute.
    timeout : int
        Timeout in seconds.
    cwd : str or None
        Working directory for the command.

    Returns
    -------
    tuple[int, str, str]
        ``(exit_code, stdout, stderr)``
    """
    result = subprocess.run(
        command,
        shell=True,
        capture_output=True,
        text=True,
        timeout=timeout,
        cwd=cwd,
    )
    return result.returncode, result.stdout, result.stderr
