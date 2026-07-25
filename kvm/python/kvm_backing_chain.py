"""
SPDX-License-Identifier: MIT
Qcow2 backing-chain management via qemu-img.

Provides ``BackingChain`` for creating, listing, committing, rebasing,
and flattening overlay chains.
"""

from __future__ import annotations

import json
import logging
import subprocess
from typing import Any

logger = logging.getLogger(__name__)


class ChainError(Exception):
    """Raised when a backing-chain operation fails."""


class BackingChain:
    """Manage qcow2 backing chains.

    Example::

        chain = BackingChain()
        chain.create_chain("base.qcow2", "overlay.qcow2")
        print(chain.list_chain("overlay.qcow2"))
    """

    @staticmethod
    def _run(args: list[str], check: bool = True) -> subprocess.CompletedProcess[str]:
        """Run ``qemu-img`` with the given arguments."""
        cmd = ["qemu-img"] + args
        logger.debug("Running: %s", " ".join(cmd))
        result = subprocess.run(cmd, capture_output=True, text=True, check=False)
        if check and result.returncode != 0:
            raise ChainError(
                f"qemu-img failed (rc={result.returncode}): "
                f"{result.stderr.strip()}"
            )
        return result

    @staticmethod
    def _info(path: str) -> dict[str, Any]:
        """Return parsed ``qemu-img info``."""
        result = subprocess.run(
            ["qemu-img", "info", "--output=json", path],
            capture_output=True,
            text=True,
            check=False,
        )
        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError:
            return {"format": "unknown", "file": path}

    # ------------------------------------------------------------------
    # Operations
    # ------------------------------------------------------------------

    def create_chain(self, base: str, delta: str) -> None:
        """Create an overlay (*delta*) on top of *base*.

        Args:
            base: Path to the base (backing) image.
            delta: Path for the new overlay image.
        """
        fmt = self._info(base).get("format", "qcow2")
        self._run([
            "create", "-f", fmt,
            "-b", base,
            "-F", fmt,
            delta,
        ])
        logger.info("Created overlay chain: %s -> %s", base, delta)

    def list_chain(self, path: str) -> list[dict[str, Any]]:
        """Walk the backing chain and return each layer.

        Returns:
            List of dicts (bottom-up) with ``file``, ``format``,
            ``virtual_size``, ``backing_file``.
        """
        chain: list[dict[str, Any]] = []
        current = path
        visited: set[str] = set()
        while current and current not in visited:
            visited.add(current)
            info = self._info(current)
            chain.append({
                "file": current,
                "format": info.get("format"),
                "virtual_size": info.get("virtual_size"),
                "actual_size": info.get("actual_size"),
                "backing_file": info.get("backing_file"),
                "backing_file_format": info.get("backing_file_format"),
            })
            current = info.get("backing_file")
        return chain

    def commit(self, path: str) -> None:
        """Commit *path*'s changes into its backing file.

        After committing, the backing file absorbs all modifications and
        the overlay is no longer needed.
        """
        fmt = self._info(path).get("format", "qcow2")
        self._run(["commit", "-f", fmt, path])
        logger.info("Committed %s to its backing file", path)

    def rebase(self, path: str, new_backing: str | None = None) -> None:
        """Rebase *path* onto a new (or no) backing file.

        Args:
            path: Overlay image to rebase.
            new_backing: New backing file path; ``None`` removes the
                backing file.
        """
        fmt = self._info(path).get("format", "qcow2")
        if new_backing is None:
            self._run(["rebase", "-u", "-F", fmt, "-b", "", path])
        else:
            new_fmt = self._info(new_backing).get("format", "qcow2")
            self._run(["rebase", "-u", "-F", fmt, "-b", new_backing, "-F", new_fmt, path])
        logger.info("Rebased %s (new backing=%s)", path, new_backing)

    def flatten(self, path: str) -> None:
        """Flatten an entire overlay chain into a single file.

        Creates a temporary merged image using ``qemu-img convert``
        then replaces the original.
        """
        info = self._info(path)
        fmt = info.get("format", "qcow2")
        # Convert with no backing file to flatten
        tmp_path = path + ".flatten_tmp.qcow2"
        self._run([
            "convert", "-f", fmt, "-O", fmt, path, tmp_path,
        ])
        # Replace original
        import os
        import shutil
        orig_backup = path + ".flatten_backup"
        shutil.move(path, orig_backup)
        shutil.move(tmp_path, path)
        os.remove(orig_backup)
        logger.info("Flattened chain at %s", path)

    def flatten_chain(self, paths: list[str]) -> None:
        """Flatten multiple images that share a chain.

        Each image in *paths* is individually flattened (as if calling
        :meth:`flatten` on each).
        """
        for p in paths:
            self.flatten(p)
        logger.info("Flattened %d images", len(paths))
