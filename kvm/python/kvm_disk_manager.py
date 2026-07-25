"""
SPDX-License-Identifier: MIT
Disk image management via qemu-img.

Provides ``DiskManager`` for creating, converting, resizing, snapshotting,
checking, and benchmarking disk images using the ``qemu-img`` CLI.
"""

from __future__ import annotations

import json
import logging
import subprocess
import time
from typing import Any

logger = logging.getLogger(__name__)


class DiskError(Exception):
    """Raised when a disk operation fails."""


class DiskManager:
    """Manage QCOW2 / raw disk images via ``qemu-img``.

    Example::

        dm = DiskManager()
        info = dm.create("/var/lib/libvirt/images/vm.qcow2", size_gb=20)
        print(info)
    """

    @staticmethod
    def _run(args: list[str], check: bool = True) -> subprocess.CompletedProcess[str]:
        """Execute a ``qemu-img`` subcommand.

        Args:
            args: Arguments after ``qemu-img``.
            check: Raise on non-zero exit.

        Raises:
            DiskError: If the command fails and *check* is True.
        """
        cmd = ["qemu-img"] + args
        logger.debug("Running: %s", " ".join(cmd))
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                check=False,
            )
        except FileNotFoundError:
            raise DiskError("qemu-img not found in PATH")

        if check and result.returncode != 0:
            raise DiskError(f"qemu-img failed (rc={result.returncode}): {result.stderr.strip()}")
        return result

    @staticmethod
    def _parse_info(output: str) -> dict[str, Any]:
        """Parse ``qemu-img info --output=json`` output."""
        try:
            return json.loads(output)
        except json.JSONDecodeError:
            return {"raw_output": output}

    # ------------------------------------------------------------------
    # Core operations
    # ------------------------------------------------------------------

    def create(
        self,
        path: str,
        format: str = "qcow2",
        size_gb: int | None = None,
        backing_file: str | None = None,
        preallocation: str = "off",
    ) -> dict[str, Any]:
        """Create a new disk image.

        Args:
            path: Destination file path.
            format: Image format (``qcow2``, ``raw``, ``vmdk``).
            size_gb: Image size in GiB (ignored for backing-file clones).
            backing_file: Path to a backing image for COW.
            preallocation: Preallocation mode (``off``, ``metadata``,
                ``falloc``, ``full``).

        Returns:
            Parsed ``qemu-img info`` for the newly created image.
        """
        args: list[str] = ["create", "-f", format]
        if preallocation != "off":
            args += ["-o", f"preallocation={preallocation}"]
        if backing_file:
            args += ["-b", backing_file, "-F", format]
        if size_gb is not None:
            args.append(f"{size_gb}G")
        args.append(path)
        self._run(args)
        return self.info(path)

    def convert(
        self,
        source: str,
        dest: str,
        output_format: str,
        compress: bool = False,
    ) -> dict[str, Any]:
        """Convert a disk image to another format.

        Args:
            source: Source image path.
            dest: Destination image path.
            output_format: Target format.
            compress: Enable compression (``-c`` flag).

        Returns:
            Parsed info for the destination image.
        """
        args = ["convert", "-f"]
        # Auto-detect source format via info
        src_info = self.info(source)
        src_fmt = src_info.get("format", "qcow2")
        args += [src_fmt, "-O", output_format]
        if compress:
            args.append("-c")
        args += [source, dest]
        self._run(args)
        return self.info(dest)

    def resize(self, path: str, size_gb: int) -> dict[str, Any]:
        """Resize a disk image to the given total size in GiB.

        Returns:
            Parsed info after resize.
        """
        self._run(["resize", path, f"{size_gb}G"])
        return self.info(path)

    def info(self, path: str) -> dict[str, Any]:
        """Return parsed image info.

        Returns:
            Dict with ``file``, ``format``, ``virtual_size``,
            ``actual_size``, ``backing_file``, etc.
        """
        result = self._run(["info", "--output=json", path])
        return self._parse_info(result.stdout)

    def check(self, path: str) -> dict[str, Any]:
        """Run a consistency check on the image.

        Returns:
            Dict with ``check`` status and ``repair`` information.
        """
        result = self._run(["check", "--output=json", path], check=False)
        parsed = self._parse_info(result.stdout)
        parsed["returncode"] = result.returncode
        if result.returncode != 0:
            parsed["error"] = result.stderr.strip()
        return parsed

    # ------------------------------------------------------------------
    # Snapshots
    # ------------------------------------------------------------------

    def snapshot_create(self, path: str, snapshot_name: str) -> dict[str, Any]:
        """Create an internal snapshot.

        Args:
            path: Disk image path.
            snapshot_name: Name for the snapshot.

        Returns:
            Updated image info.
        """
        self._run([
            "snapshot", "create", "-f",
            self.info(path).get("format", "qcow2"),
            "-s", snapshot_name, path,
        ])
        return self.info(path)

    def snapshot_delete(self, path: str, snapshot_name: str) -> dict[str, Any]:
        """Delete an internal snapshot by name."""
        self._run([
            "snapshot", "delete", "-f",
            self.info(path).get("format", "qcow2"),
            "-s", snapshot_name, path,
        ])
        return self.info(path)

    def snapshot_revert(self, path: str, snapshot_name: str) -> dict[str, Any]:
        """Revert the image to a named internal snapshot."""
        self._run([
            "snapshot", "revert", "-f",
            self.info(path).get("format", "qcow2"),
            "-s", snapshot_name, path,
        ])
        return self.info(path)

    # ------------------------------------------------------------------
    # Commit / rebase
    # ------------------------------------------------------------------

    def commit(self, path: str) -> None:
        """Commit changes from an overlay back to its backing file."""
        self._run(["commit", "-f", self.info(path).get("format", "qcow2"), path])

    def rebase(self, path: str, backing_file: str | None = None) -> None:
        """Rebase an image onto a new (or no) backing file.

        Args:
            path: Overlay image path.
            backing_file: New backing image path; ``None`` removes it.
        """
        args = ["rebase", "-u", "-F"]
        fmt = self.info(path).get("format", "qcow2")
        args += [fmt]
        if backing_file:
            args += ["-b", backing_file]
        else:
            args += ["-b", ""]
        args.append(path)
        self._run(args)

    # ------------------------------------------------------------------
    # Advanced
    # ------------------------------------------------------------------

    def sparsify(self, source: str, dest: str) -> dict[str, Any]:
        """Create a sparsified copy of the image.

        Returns:
            Parsed info for the destination.
        """
        fmt = self.info(source).get("format", "qcow2")
        self._run(["convert", "-O", fmt, "-S", "0", source, dest])
        return self.info(dest)

    def benchmark(self, path: str, size_gb: int = 1) -> dict[str, Any]:
        """Run a basic fio benchmark on the image.

        Args:
            path: Path to the disk image.
            size_gb: Test size in GiB.

        Returns:
            Dict with read/write IOPS and bandwidth.
        """
        cmd = [
            "fio",
            "--name=bench",
            f"--filename={path}",
            "--ioengine=libaio",
            "--rw=randrw",
            "--bs=4k",
            f"--size={size_gb}G",
            "--numjobs=1",
            "--runtime=10",
            "--time_based",
            "--group_reporting",
            "--output-format=json",
        ]
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, check=False)
        except FileNotFoundError:
            raise DiskError("fio not found in PATH; install fio for benchmarking")

        if result.returncode != 0:
            raise DiskError(f"fio failed: {result.stderr.strip()}")

        try:
            data = json.loads(result.stdout)
        except json.JSONDecodeError:
            return {"error": result.stderr, "raw": result.stdout}

        read = data.get("jobs", [{}])[0].get("read", {})
        write = data.get("jobs", [{}])[0].get("write", {})
        return {
            "read_iops": read.get("iops", 0),
            "read_bw_kbps": read.get("bw", 0),
            "write_iops": write.get("iops", 0),
            "write_bw_kbps": write.get("bw", 0),
            "read_lat_avg_us": read.get("lat_ns", {}).get("mean", 0) / 1000
            if read.get("lat_ns")
            else 0,
            "write_lat_avg_us": write.get("lat_ns", {}).get("mean", 0) / 1000
            if write.get("lat_ns")
            else 0,
        }
