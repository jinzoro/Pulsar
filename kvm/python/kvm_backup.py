"""
SPDX-License-Identifier: MIT
VM backup operations via virsh, qemu-img, and QMP.

Provides ``BackupManager`` for full, incremental, live, and offline
backup workflows for KVM virtual machines.
"""

from __future__ import annotations

import datetime
import json
import logging
import os
import shutil
import socket
import subprocess
from typing import Any

import libvirt

from kvm_libvirt_client import LibvirtClient, LibvirtError, _wrap_libvirt_error

logger = logging.getLogger(__name__)


class BackupError(Exception):
    """Raised when a backup operation fails."""


class BackupManager:
    """Manage VM backups.

    Args:
        client: Optional existing :class:`LibvirtClient`.

    Example::

        bm = BackupManager()
        path = bm.full_backup("web01", "/backups/web01", format="qcow2")
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
            raise BackupError(
                f"Command failed (rc={result.returncode}): "
                f"{result.stderr.strip() or result.stdout.strip()}"
            )
        return result

    @staticmethod
    def _timestamp() -> str:
        return datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")

    def _ensure_dir(self, path: str) -> None:
        os.makedirs(path, exist_ok=True)

    def _get_domain_xml(self, name: str) -> str:
        """Fetch domain XML via virsh."""
        result = self._run(["virsh", "dumpxml", name])
        return result.stdout

    def _get_disk_paths(self, domain: str) -> list[str]:
        """Extract disk file paths from domain XML."""
        import xml.etree.ElementTree as ET
        xml_desc = self._get_domain_xml(domain)
        root = ET.fromstring(xml_desc)
        paths = []
        for disk in root.findall(".//disk"):
            if disk.get("device") == "disk":
                source = disk.find("source")
                if source is not None:
                    path = source.get("file") or source.get("dev")
                    if path:
                        paths.append(path)
        return paths

    def _qmp_command(self, socket_path: str, command: str, arguments: dict | None = None) -> dict:
        """Execute a QMP command over a Unix socket."""
        try:
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.settimeout(10)
            sock.connect(socket_path)

            # Read greeting
            greeting = sock.recv(4096)
            if not greeting:
                raise BackupError("QMP connection failed: no greeting")

            # Send negotiate
            sock.sendall(b'{"execute": "qmp_capabilities"}\n')
            resp = sock.recv(4096)

            # Send command
            payload: dict[str, Any] = {"execute": command}
            if arguments:
                payload["arguments"] = arguments
            sock.sendall(json.dumps(payload).encode() + b"\n")
            resp = sock.recv(65536)
            return json.loads(resp.decode().strip().splitlines()[-1])
        except socket.error as exc:
            raise BackupError(f"QMP error: {exc}") from exc
        finally:
            sock.close()

    def _get_qmp_socket(self, domain: str) -> str | None:
        """Return the QMP monitor socket path for a domain."""
        result = self._run(
            ["virsh", "qemu-monitor-command", domain,
             "--hmp", "info status"],
            check=False,
        )
        if result.returncode != 0:
            return None
        # Query libvirtd for the socket path
        pid_result = self._run(
            ["virsh", "dompid", domain], check=False,
        )
        if pid_result.returncode != 0:
            return None
        pid = pid_result.stdout.strip()
        if not pid.isdigit():
            return None
        # Typical path
        return f"/var/run/libvirt/qemu/{domain}.monitor"

    # ------------------------------------------------------------------
    # Backup types
    # ------------------------------------------------------------------

    def full_backup(
        self,
        domain: str,
        output_dir: str,
        format: str = "qcow2",
        compress: bool = True,
    ) -> str:
        """Perform a full backup by converting disk images.

        Args:
            domain: Domain name.
            output_dir: Destination directory for backup files.
            format: Output format (``qcow2`` or ``raw``).
            compress: Add ``-c`` flag to ``qemu-img convert``.

        Returns:
            Path to the backup directory.
        """
        ts = self._timestamp()
        backup_path = os.path.join(output_dir, f"{domain}_full_{ts}")
        self._ensure_dir(backup_path)

        disk_paths = self._get_disk_paths(domain)
        if not disk_paths:
            raise BackupError(f"No disks found for domain '{domain}'")

        for i, disk_path in enumerate(disk_paths):
            dest_name = f"disk{i}.{format}"
            dest = os.path.join(backup_path, dest_name)
            cmd = ["qemu-img", "convert", "-f", format, "-O", format]
            if compress:
                cmd.append("-c")
            cmd += [disk_path, dest]
            self._run(cmd)
            logger.info("Backed up %s -> %s", disk_path, dest)

        # Save domain XML
        xml_path = os.path.join(backup_path, "domain.xml")
        with open(xml_path, "w") as fh:
            fh.write(self._get_domain_xml(domain))

        # Save metadata
        meta = {
            "domain": domain,
            "type": "full",
            "timestamp": ts,
            "format": format,
            "disks": [os.path.basename(d) for d in disk_paths],
        }
        with open(os.path.join(backup_path, "meta.json"), "w") as fh:
            json.dump(meta, fh, indent=2)

        logger.info("Full backup completed: %s", backup_path)
        return backup_path

    def incremental_backup(
        self,
        domain: str,
        output_dir: str,
        base_snapshot: str | None = None,
    ) -> str:
        """Perform an incremental backup using qcow2 backing files.

        If *base_snapshot* is provided, the backup uses the existing
        snapshot as the backing file.  Otherwise, a new snapshot is
        created for future incremental runs.

        Args:
            domain: Domain name.
            output_dir: Destination directory.
            base_snapshot: Optional path to a previous backup image.

        Returns:
            Path to the backup directory.
        """
        ts = self._timestamp()
        backup_path = os.path.join(output_dir, f"{domain}_incr_{ts}")
        self._ensure_dir(backup_path)

        disk_paths = self._get_disk_paths(domain)
        if not disk_paths:
            raise BackupError(f"No disks found for domain '{domain}'")

        for i, disk_path in enumerate(disk_paths):
            dest_name = f"disk{i}.qcow2"
            dest = os.path.join(backup_path, dest_name)
            backing = base_snapshot
            if not backing:
                # Create a snapshot of the current image to use as base
                snapshot_path = os.path.join(backup_path, f"disk{i}_base.qcow2")
                self._run([
                    "qemu-img", "snapshot", "create", "-f", "qcow2",
                    "-s", f"backup_{ts}", disk_path,
                ])
                self._run([
                    "qemu-img", "convert", "-f", "qcow2", "-O", "qcow2",
                    disk_path, snapshot_path,
                ])
                backing = snapshot_path

            cmd = [
                "qemu-img", "create", "-f", "qcow2",
                "-b", backing, "-F", "qcow2", dest,
            ]
            self._run(cmd)
            logger.info("Incremental backup: %s -> %s (base=%s)", disk_path, dest, backing)

        # Save metadata
        meta = {
            "domain": domain,
            "type": "incremental",
            "timestamp": ts,
            "base_snapshot": base_snapshot,
        }
        with open(os.path.join(backup_path, "meta.json"), "w") as fh:
            json.dump(meta, fh, indent=2)

        logger.info("Incremental backup completed: %s", backup_path)
        return backup_path

    def live_backup(self, domain: str, output_dir: str) -> str:
        """Perform a live backup: fsfreeze → copy → fsthaw.

        Uses QMP ``guest-fsfreeze-freeze`` / ``guest-fsfreeze-thaw``
        to quiesce the filesystem, then copies disk images.

        Args:
            domain: Domain name.
            output_dir: Destination directory.

        Returns:
            Path to the backup directory.
        """
        ts = self._timestamp()
        backup_path = os.path.join(output_dir, f"{domain}_live_{ts}")
        self._ensure_dir(backup_path)

        qmp_socket = self._get_qmp_socket(domain)

        # Freeze filesystem
        frozen = False
        if qmp_socket:
            try:
                self._qmp_command(qmp_socket, "guest-fsfreeze-freeze")
                frozen = True
                logger.info("Froze guest filesystem for '%s'", domain)
            except BackupError as exc:
                logger.warning("Could not freeze filesystem: %s", exc)

        try:
            disk_paths = self._get_disk_paths(domain)
            for i, disk_path in enumerate(disk_paths):
                dest = os.path.join(backup_path, f"disk{i}.qcow2")
                self._run([
                    "qemu-img", "convert", "-f", "qcow2", "-O", "qcow2",
                    "-c", disk_path, dest,
                ])
                logger.info("Live backup: %s -> %s", disk_path, dest)
        finally:
            if frozen and qmp_socket:
                try:
                    self._qmp_command(qmp_socket, "guest-fsfreeze-thaw")
                    logger.info("Thawed guest filesystem for '%s'", domain)
                except BackupError as exc:
                    logger.warning("Could not thaw filesystem: %s", exc)

        meta = {
            "domain": domain,
            "type": "live",
            "timestamp": ts,
        }
        with open(os.path.join(backup_path, "meta.json"), "w") as fh:
            json.dump(meta, fh, indent=2)

        logger.info("Live backup completed: %s", backup_path)
        return backup_path

    def offline_backup(self, domain: str, output_dir: str) -> str:
        """Perform an offline backup: shut down → backup → start.

        Args:
            domain: Domain name.
            output_dir: Destination directory.

        Returns:
            Path to the backup directory.
        """
        ts = self._timestamp()
        backup_path = os.path.join(output_dir, f"{domain}_offline_{ts}")
        self._ensure_dir(backup_path)

        # Check if running
        result = self._run(["virsh", "domstate", domain], check=False)
        was_running = result.stdout.strip() == "running"

        # Shutdown
        if was_running:
            self._run(["virsh", "shutdown", domain], check=False)
            import time
            for _ in range(30):
                time.sleep(1)
                state = self._run(["virsh", "domstate", domain], check=False).stdout.strip()
                if state in ("shut off", "shut down"):
                    break
            else:
                logger.warning("Domain '%s' did not shut down cleanly; forcing", domain)
                self._run(["virsh", "destroy", domain], check=False)

        # Backup disks
        disk_paths = self._get_disk_paths(domain)
        for i, disk_path in enumerate(disk_paths):
            dest = os.path.join(backup_path, f"disk{i}.qcow2")
            self._run([
                "qemu-img", "convert", "-f", "qcow2", "-O", "qcow2",
                "-c", disk_path, dest,
            ])

        # Save XML
        with open(os.path.join(backup_path, "domain.xml"), "w") as fh:
            fh.write(self._get_domain_xml(domain))

        meta = {
            "domain": domain,
            "type": "offline",
            "timestamp": ts,
            "was_running": was_running,
        }
        with open(os.path.join(backup_path, "meta.json"), "w") as fh:
            json.dump(meta, fh, indent=2)

        # Restart if it was running
        if was_running:
            self._run(["virsh", "start", domain], check=False)
            logger.info("Restarted VM '%s'", domain)

        logger.info("Offline backup completed: %s", backup_path)
        return backup_path

    def list_backups(self, domain: str | None = None) -> list[dict[str, Any]]:
        """Scan a standard backup directory for backup metadata.

        Searches the current directory and common locations.

        Returns:
            List of backup metadata dicts.
        """
        search_dirs = [
            os.path.join(os.getcwd(), "backups"),
            "/var/backups/libvirt",
            "/var/lib/libvirt/backups",
        ]
        backups: list[dict[str, Any]] = []

        for search_dir in search_dirs:
            if not os.path.isdir(search_dir):
                continue
            for entry in os.listdir(search_dir):
                meta_path = os.path.join(search_dir, entry, "meta.json")
                if os.path.isfile(meta_path):
                    try:
                        with open(meta_path) as fh:
                            meta = json.load(fh)
                        if domain and meta.get("domain") != domain:
                            continue
                        meta["path"] = os.path.join(search_dir, entry)
                        backups.append(meta)
                    except (json.JSONDecodeError, OSError):
                        continue

        return backups
