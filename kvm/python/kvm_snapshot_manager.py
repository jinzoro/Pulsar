"""
SPDX-License-Identifier: MIT
VM snapshot management via virsh and qemu-img.

Provides ``SnapshotManager`` for creating, listing, reverting, and
deleting libvirt snapshots, as well as managing external (file-backed)
snapshots.
"""

from __future__ import annotations

import json
import logging
import subprocess
from typing import Any

import libvirt

from kvm_libvirt_client import LibvirtClient, LibvirtError, _wrap_libvirt_error

logger = logging.getLogger(__name__)


class SnapshotError(Exception):
    """Raised when a snapshot operation fails."""


class SnapshotManager:
    """Manage VM snapshots via virsh / libvirt.

    Args:
        client: Optional existing :class:`LibvirtClient`.

    Example::

        sm = SnapshotManager()
        sm.create("web01", "pre-upgrade", description="Before apt upgrade")
        sm.list_all("web01")
        sm.revert("web01", "pre-upgrade")
    """

    def __init__(self, client: LibvirtClient | None = None) -> None:
        self._client = client

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _run(cmd: list[str], check: bool = True) -> subprocess.CompletedProcess[str]:
        """Run a CLI command (typically virsh)."""
        logger.debug("Running: %s", " ".join(cmd))
        result = subprocess.run(cmd, capture_output=True, text=True, check=False)
        if check and result.returncode != 0:
            raise SnapshotError(
                f"Command failed (rc={result.returncode}): "
                f"{result.stderr.strip() or result.stdout.strip()}"
            )
        return result

    def _get_virsh_domain(self, domain: str) -> str:
        """Resolve a domain name to the virsh ``--domain`` value."""
        return domain

    # ------------------------------------------------------------------
    # Operations
    # ------------------------------------------------------------------

    def create(
        self,
        domain: str,
        name: str,
        description: str | None = None,
        live: bool = True,
        quiesce: bool = False,
    ) -> None:
        """Create an internal libvirt snapshot.

        Args:
            domain: Domain name.
            name: Snapshot name.
            description: Optional description.
            live: Include the live (running) state.
            quiesce: Freeze the guest filesystem before snapshot.
        """
        cmd = [
            "virsh", "snapshot-create", self._get_virsh_domain(domain),
            "--name", name,
        ]
        if description:
            cmd += ["--description", description]
        if live:
            cmd.append("--live")
        if quiesce:
            cmd.append("--quiesce")
        self._run(cmd)
        logger.info("Created snapshot '%s' for VM '%s'", name, domain)

    def list_all(self, domain: str) -> list[dict[str, Any]]:
        """List all snapshots for a domain.

        Returns:
            List of dicts with ``name``, ``state``, ``parent``,
            ``creation_time``, ``description``.
        """
        cmd = [
            "virsh", "snapshot-list", self._get_virsh_domain(domain),
            "--details", "--trees",
        ]
        result = self._run(cmd)
        snapshots: list[dict[str, Any]] = []

        # Parse the tree output
        current_name: str | None = None
        current_state: str | None = None

        # Try JSON-like parsing via domstats
        dom_cmd = [
            "virsh", "snapshot-list", self._get_virsh_domain(domain),
            "--name",
        ]
        name_result = self._run(dom_cmd, check=False)
        if name_result.returncode != 0:
            return snapshots

        for snap_name in name_result.stdout.strip().splitlines():
            if not snap_name.strip():
                continue
            # Get info for each snapshot
            info_cmd = [
                "virsh", "snapshot-info",
                self._get_virsh_domain(domain),
                snap_name.strip(),
            ]
            info_result = self._run(info_cmd, check=False)
            snap_info: dict[str, Any] = {"name": snap_name.strip()}
            if info_result.returncode == 0:
                for line in info_result.stdout.splitlines():
                    if ":" in line:
                        key, _, val = line.partition(":")
                        snap_info[key.strip()] = val.strip()
            snapshots.append(snap_info)

        return snapshots

    def revert(self, domain: str, snapshot_name: str) -> None:
        """Revert a domain to a named snapshot.

        Args:
            domain: Domain name.
            snapshot_name: Snapshot to revert to.
        """
        cmd = [
            "virsh", "snapshot-revert",
            self._get_virsh_domain(domain),
            snapshot_name,
        ]
        self._run(cmd)
        logger.info("Reverted VM '%s' to snapshot '%s'", domain, snapshot_name)

    def delete(self, domain: str, snapshot_name: str) -> None:
        """Delete a named snapshot.

        Args:
            domain: Domain name.
            snapshot_name: Snapshot to remove.
        """
        cmd = [
            "virsh", "snapshot-delete",
            self._get_virsh_domain(domain),
            snapshot_name,
        ]
        self._run(cmd)
        logger.info("Deleted snapshot '%s' from VM '%s'", snapshot_name, domain)

    def create_external(
        self,
        domain: str,
        name: str,
        disk_file: str,
        state_file: str | None = None,
    ) -> dict[str, Any]:
        """Create an external (file-backed) snapshot.

        This uses ``virsh snapshot-create-as`` with ``--diskspec`` for
        an external disk snapshot and optionally a memory dump.

        Args:
            domain: Domain name.
            name: Snapshot name.
            disk_file: Path for the external delta disk.
            state_file: Optional memory state dump file.

        Returns:
            Dict with ``snapshot_name``, ``disk_file``, ``state_file``.
        """
        cmd = [
            "virsh", "snapshot-create-as",
            self._get_virsh_domain(domain),
            name,
            "--diskspec", f"vda,file={disk_file},format=qcow2",
        ]
        if state_file:
            cmd += ["--memspec", f"file={state_file},format=memory-backend-file"]
        else:
            cmd.append("--no-metadata")

        self._run(cmd)
        logger.info(
            "Created external snapshot '%s' for VM '%s' -> %s",
            name, domain, disk_file,
        )
        return {
            "snapshot_name": name,
            "disk_file": disk_file,
            "state_file": state_file,
        }

    def commit(self, domain: str, disk_file: str) -> None:
        """Commit changes from an external snapshot's delta disk back to
        the base.

        Uses ``qemu-img commit`` on the delta file.

        Args:
            domain: Domain name (used for logging).
            disk_file: Path to the delta disk to commit.
        """
        cmd = ["qemu-img", "commit", "-f", "qcow2", disk_file]
        self._run(cmd)
        logger.info("Committed snapshot delta %s for VM '%s'", disk_file, domain)
