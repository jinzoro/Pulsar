"""
SPDX-License-Identifier: MIT
QEMU Machine Protocol (QMP) client over Unix socket.

Provides ``QMPClient`` for issuing QMP commands to a running QEMU
instance, including status queries, migration, snapshot, key-sending,
and CD-ROM changes.
"""

from __future__ import annotations

import json
import logging
import socket
from typing import Any

logger = logging.getLogger(__name__)


class QMPError(Exception):
    """Raised when a QMP command fails."""


class QMPClient:
    """QMP client for interacting with QEMU monitor sockets.

    Args:
        socket_path: Path to the QEMU QMP Unix socket.

    Example::

        with QMPClient("/var/run/libvirt/qemu/web01.monitor") as qmp:
            status = qmp.query_status()
            print(status)
    """

    def __init__(self, socket_path: str) -> None:
        self._socket_path = socket_path
        self._sock: socket.socket | None = None
        self._negotiated = False

    # ------------------------------------------------------------------
    # Context-manager support
    # ------------------------------------------------------------------

    def __enter__(self) -> "QMPClient":
        self.connect()
        return self

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc_val: BaseException | None,
        exc_tb: Any,
    ) -> None:
        self.disconnect()

    # ------------------------------------------------------------------
    # Connection lifecycle
    # ------------------------------------------------------------------

    def connect(self) -> None:
        """Open the QMP socket and perform capability negotiation.

        Raises:
            QMPError: If connection or negotiation fails.
        """
        try:
            self._sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            self._sock.settimeout(10)
            self._sock.connect(self._socket_path)
        except (socket.error, OSError) as exc:
            raise QMPError(f"Cannot connect to QMP socket {self._socket_path}: {exc}") from exc

        # Read QMP greeting
        greeting = self._recv()
        if "QMP" not in greeting:
            raise QMPError(f"Invalid QMP greeting: {greeting}")

        # Negotiate capabilities
        self._send({"execute": "qmp_capabilities"})
        resp = self._recv()
        if "return" not in resp:
            raise QMPError(f"QMP negotiation failed: {resp}")

        self._negotiated = True
        logger.info("Connected to QMP at %s", self._socket_path)

    def disconnect(self) -> None:
        """Close the QMP socket."""
        if self._sock:
            try:
                self._sock.close()
            except OSError:
                pass
            self._sock = None
            self._negotiated = False
            logger.info("Disconnected from QMP at %s", self._socket_path)

    # ------------------------------------------------------------------
    # Low-level I/O
    # ------------------------------------------------------------------

    def _send(self, payload: dict[str, Any]) -> None:
        if self._sock is None:
            raise QMPError("Not connected")
        data = json.dumps(payload).encode("utf-8") + b"\n"
        try:
            self._sock.sendall(data)
        except (socket.error, OSError) as exc:
            raise QMPError(f"QMP send failed: {exc}") from exc

    def _recv(self) -> dict[str, Any]:
        if self._sock is None:
            raise QMPError("Not connected")
        chunks: list[bytes] = []
        try:
            while True:
                chunk = self._sock.recv(65536)
                if not chunk:
                    raise QMPError("QMP connection closed")
                chunks.append(chunk)
                raw = b"".join(chunks)
                # Try to parse (QMP may send multiple JSON objects)
                try:
                    lines = raw.decode("utf-8").strip().splitlines()
                    # Return the last complete JSON object
                    for line in reversed(lines):
                        line = line.strip()
                        if line.startswith("{"):
                            return json.loads(line)
                except json.JSONDecodeError:
                    continue
        except (socket.error, OSError) as exc:
            raise QMPError(f"QMP receive failed: {exc}") from exc
        return {}

    # ------------------------------------------------------------------
    # Commands
    # ------------------------------------------------------------------

    def execute(self, command: str, arguments: dict[str, Any] | None = None) -> dict[str, Any]:
        """Execute a QMP command.

        Args:
            command: QMP command name (e.g. ``query-status``).
            arguments: Optional command arguments.

        Returns:
            The QMP response dict.
        """
        payload: dict[str, Any] = {"execute": command}
        if arguments:
            payload["arguments"] = arguments
        self._send(payload)
        resp = self._recv()

        # Check for error
        if "error" in resp:
            raise QMPError(f"QMP error on '{command}': {resp['error']}")
        return resp

    def query_status(self) -> dict[str, Any]:
        """Return the current run status of the VM.

        Returns:
            Dict with ``status`` (e.g. ``running``, ``paused``) and
            ``singlestep``.
        """
        resp = self.execute("query-status")
        return resp.get("return", resp)

    def query_block(self) -> list[dict[str, Any]]:
        """Return block device status for all devices.

        Returns:
            List of dicts with ``device``, ``type``, ``removable``,
            ``locked``, ``inserted`` info.
        """
        resp = self.execute("query-block")
        return resp.get("return", [])

    def query_cpus(self) -> list[dict[str, Any]]:
        """Return information about each vCPU.

        Returns:
            List of dicts with ``CPU``, ``current``, ``halted``,
            ``qom_path``.
        """
        resp = self.execute("query-cpus-fast")
        return resp.get("return", [])

    def stop(self) -> None:
        """Stop (pause) the VM."""
        self.execute("stop")
        logger.info("QMP: VM stopped")

    def cont(self) -> None:
        """Resume a paused VM."""
        self.execute("cont")
        logger.info("QMP: VM resumed")

    def quit(self) -> None:
        """Quit QEMU (immediate shutdown)."""
        self.execute("quit")
        logger.info("QMP: QEMU quit")

    def migrate(
        self,
        dest_uri: str,
        live: bool = True,
    ) -> None:
        """Initiate migration to a destination URI.

        Args:
            dest_uri: Migration destination URI (e.g.
                ``tcp:10.0.0.2:4444``).
            live: Enable live migration.
        """
        args: dict[str, Any] = {"uri": dest_uri}
        if live:
            args["live"] = True
        self.execute("migrate", args)
        logger.info("QMP: Migration started to %s (live=%s)", dest_uri, live)

    def snapshot(self, device: str | None = None) -> None:
        """Take an inline snapshot.

        Args:
            device: Block device to snapshot; ``None`` for all.
        """
        args: dict[str, Any] = {}
        if device:
            args["device"] = device
        self.execute("snapshot-drive", args)
        logger.info("QMP: Snapshot taken (device=%s)", device or "all")

    def send_key(self, keys: list[int]) -> None:
        """Send key events to the VM.

        Args:
            keys: List of QEMU keycodes to send.
        """
        self.execute("send-key", {"keys": [{"type": "number", "data": k} for k in keys]})
        logger.debug("QMP: Sent keys %s", keys)

    def change_cd(self, device: str, filename: str) -> None:
        """Change the CD-ROM media.

        Args:
            device: Block device name (e.g. ``ide0-cd0``).
            filename: Path to the new ISO image.
        """
        self.execute("change", {"device": device, "arg": filename})
        logger.info("QMP: Changed CD in %s -> %s", device, filename)
