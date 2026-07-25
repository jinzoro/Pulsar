"""
SPDX-License-Identifier: MIT
Reusable libvirt connection wrapper for KVM/libvirt operations.

Provides a context-managing client that abstracts common libvirt
connection patterns and wraps errors into a custom exception hierarchy.
"""

from __future__ import annotations

import logging
from typing import Any

import libvirt

logger = logging.getLogger(__name__)


class LibvirtError(Exception):
    """Raised when a libvirt API call fails."""

    def __init__(self, message: str, error_code: int | None = None) -> None:
        super().__init__(message)
        self.error_code = error_code


def _wrap_libvirt_error(exc: libvirt.libvirtError) -> LibvirtError:
    """Convert a libvirt error into the custom LibvirtError."""
    msg = exc.get_error_message()
    code = exc.get_error_code()
    logger.error("libvirt error %s: %s", code, msg)
    return LibvirtError(msg, error_code=code)


class LibvirtClient:
    """Reusable wrapper around a libvirt connection.

    The client can be used as a context manager or explicitly via
    ``connect`` / ``disconnect``.

    Args:
        uri: libvirt connection URI.  Defaults to ``qemu:///system``.

    Example::

        with LibvirtClient() as client:
            for dom in client.list_domains():
                print(dom.name())
    """

    def __init__(self, uri: str = "qemu:///system") -> None:
        self._uri = uri
        self._conn: libvirt.virConnect | None = None

    # ------------------------------------------------------------------
    # Context-manager support
    # ------------------------------------------------------------------

    def __enter__(self) -> "LibvirtClient":
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
        """Open the libvirt connection.

        Raises:
            LibvirtError: If the connection cannot be established.
        """
        if self._conn is not None:
            logger.debug("Already connected to %s", self._uri)
            return
        try:
            self._conn = libvirt.open(self._uri)
            if self._conn is None:
                raise LibvirtError(
                    f"Failed to open connection to {self._uri}: "
                    f"{libvirt.virGetLastError()}"
                )
            logger.info("Connected to %s", self._uri)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc

    def disconnect(self) -> None:
        """Close the libvirt connection."""
        if self._conn is None:
            return
        try:
            self._conn.close()
            logger.info("Disconnected from %s", self._uri)
        except libvirt.libvirtError as exc:
            logger.warning("Error closing connection: %s", exc)
        finally:
            self._conn = None

    @property
    def conn(self) -> libvirt.virConnect:
        """Return the underlying ``virConnect``, connecting first if needed.

        Raises:
            LibvirtError: If no connection exists.
        """
        if self._conn is None:
            self.connect()
        assert self._conn is not None  # for type-checkers
        return self._conn

    # ------------------------------------------------------------------
    # Domain helpers
    # ------------------------------------------------------------------

    def list_domains(
        self,
        active: bool = True,
        inactive: bool = False,
    ) -> list[libvirt.virDomain]:
        """Return domains according to the requested filter flags.

        Args:
            active: Include running domains.
            inactive: Include defined-but-shut-off domains.

        Returns:
            A (possibly empty) list of ``virDomain`` objects.
        """
        flags = 0
        if active and not inactive:
            flags = libvirt.VIR_CONNECT_LIST_DOMAINS_ACTIVE
        elif inactive and not active:
            flags = libvirt.VIR_CONNECT_LIST_DOMAINS_INACTIVE
        try:
            return self.conn.listAllDomains(flags)  # type: ignore[return-value]
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc

    def get_domain(self, name_or_id: str | int) -> libvirt.virDomain:
        """Look up a domain by name *or* integer id.

        Args:
            name_or_id: Domain name (``str``) or numeric id (``int``).

        Returns:
            The matching ``virDomain``.

        Raises:
            LibvirtError: If the domain cannot be found.
        """
        try:
            if isinstance(name_or_id, int):
                return self.conn.lookupByID(name_or_id)
            return self.conn.lookupByName(name_or_id)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc

    # ------------------------------------------------------------------
    # Network helpers
    # ------------------------------------------------------------------

    def list_networks(
        self,
        active: bool = True,
        inactive: bool = False,
    ) -> list[libvirt.virNetwork]:
        """Return libvirt networks matching *active* / *inactive* flags."""
        flags = 0
        if active and not inactive:
            flags = libvirt.VIR_CONNECT_LIST_NETWORKS_ACTIVE
        elif inactive and not active:
            flags = libvirt.VIR_CONNECT_LIST_NETWORKS_INACTIVE
        try:
            return self.conn.listAllNetworks(flags)  # type: ignore[return-value]
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc

    def get_network(self, name: str) -> libvirt.virNetwork:
        """Look up a network by name.

        Raises:
            LibvirtError: If the network cannot be found.
        """
        try:
            return self.conn.networkLookupByName(name)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc

    # ------------------------------------------------------------------
    # Storage-pool helpers
    # ------------------------------------------------------------------

    def list_storage_pools(
        self,
        active: bool = True,
        inactive: bool = False,
    ) -> list[libvirt.virStoragePool]:
        """Return storage pools matching the requested filter flags."""
        flags = 0
        if active and not inactive:
            flags = libvirt.VIR_CONNECT_LIST_STORAGE_POOLS_ACTIVE
        elif inactive and not active:
            flags = libvirt.VIR_CONNECT_LIST_STORAGE_POOLS_INACTIVE
        try:
            return self.conn.listAllStoragePools(flags)  # type: ignore[return-value]
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc

    def get_storage_pool(self, name: str) -> libvirt.virStoragePool:
        """Look up a storage pool by name.

        Raises:
            LibvirtError: If the pool cannot be found.
        """
        try:
            return self.conn.storagePoolLookupByName(name)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc

    # ------------------------------------------------------------------
    # Capabilities / node info
    # ------------------------------------------------------------------

    def get_capabilities(self) -> str:
        """Return the host capabilities XML string."""
        try:
            return self.conn.getCapabilities()
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc

    def get_node_info(self) -> dict[str, Any]:
        """Return basic node information as a dict.

        Keys include ``model``, ``memory``, ``cpus``, ``mhz``,
        ``nodes``, ``sockets``, ``cores``, ``threads``, ``hypervisor_version``,
        and ``domain_count``.
        """
        try:
            info = self.conn.getInfo()
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc
        labels = (
            "model",
            "memory",
            "cpus",
            "mhz",
            "nodes",
            "sockets",
            "cores",
            "threads",
            "hypervisor_version",
        )
        result: dict[str, Any] = dict(zip(labels, info))
        result["memory_mb"] = result.pop("memory", 0) // 1024
        result["domain_count"] = self.conn.numOfDomains()
        return result
