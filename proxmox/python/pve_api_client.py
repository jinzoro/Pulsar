# SPDX-License-Identifier: MIT
# proxmox-kvm-swissknife - Proxmox VE REST API Client

"""Full Proxmox VE REST API client wrapper with retry, rate-limiting, and connection pooling."""

from __future__ import annotations

import logging
import time
from typing import Any

import httpx
from pydantic import BaseModel, Field
from proxmoxer import ProxmoxResource  # type: ignore[import-untyped]

logger = logging.getLogger(__name__)

_RETRYABLE_STATUS_CODES = {429, 500, 502, 503}


class RateLimiter:
    """Token-bucket rate limiter for API requests."""

    def __init__(self, requests_per_second: float = 25.0) -> None:
        self._min_interval = 1.0 / requests_per_second if requests_per_second > 0 else 0.0
        self._last_call = 0.0
        self._lock = False

    def wait_if_needed(self) -> None:
        """Block until enough time has elapsed since the last request."""
        if self._min_interval <= 0:
            return
        now = time.monotonic()
        elapsed = now - self._last_call
        if elapsed < self._min_interval:
            time.sleep(self._min_interval - elapsed)
        self._last_call = time.monotonic()


class PVEClient:
    """Full-featured Proxmox VE REST API client.

    Supports API-token and password authentication, automatic retry with
    exponential back-off, configurable rate-limiting and connection pooling
    via ``httpx.Client``.

    Parameters
    ----------
    api_url:
        Base URL of the Proxmox API, e.g. ``https://pve.example.com:8006``.
    user:
        Authentication user, e.g. ``root@pam``.
    token_id:
        API-token id (used together with *token_secret*).
    token_secret:
        API-token secret.
    password:
        Password for password-based authentication.
    verify_ssl:
        Whether to verify TLS certificates.
    timeout:
        Default request timeout in seconds.
    max_retries:
        Maximum number of retries on transient errors.
    """

    def __init__(
        self,
        api_url: str,
        user: str,
        token_id: str | None = None,
        token_secret: str | None = None,
        password: str | None = None,
        verify_ssl: bool = True,
        timeout: int = 30,
        max_retries: int = 3,
        requests_per_second: float = 25.0,
    ) -> None:
        self._api_url = api_url.rstrip("/")
        self._user = user
        self._token_id = token_id
        self._token_secret = token_secret
        self._password = password
        self._verify_ssl = verify_ssl
        self._timeout = timeout
        self._max_retries = max_retries
        self._rate_limiter = RateLimiter(requests_per_second)

        self._http: httpx.Client | None = None
        self._auth_ticket: str | None = None
        self._csrf_token: str | None = None

        self._connect()

    # -- connection helpers ---------------------------------------------------

    def _connect(self) -> None:
        """Establish the underlying HTTP client and authenticate."""
        self._http = httpx.Client(
            base_url=self._api_url,
            verify=self._verify_ssl,
            timeout=httpx.Timeout(self._timeout),
            limits=httpx.Limits(max_connections=20, max_keepalive_connections=10),
        )
        self._authenticate()

    def _authenticate(self) -> None:
        """Authenticate against the Proxmox API."""
        assert self._http is not None
        if self._token_id and self._token_secret:
            self._http.headers["Authorization"] = (
                f"PVEAPIToken={self._user}!{self._token_id}={self._token_secret}"
            )
            logger.debug("Authenticated using API token for %s", self._user)
        elif self._password:
            resp = self._http.post(
                "/api2/json/access/ticket",
                data={"username": self._user, "password": self._password},
            )
            resp.raise_for_status()
            data = resp.json()["data"]
            self._auth_ticket = data["ticket"]
            self._csrf_token = data.get("CSRFPreventionToken", "")
            self._http.cookies.set("PVEAuthCookie", self._auth_ticket)
            self._http.headers["CSRFPreventionToken"] = self._csrf_token
            logger.debug("Authenticated via password for %s", self._user)
        else:
            raise ValueError("Provide either (token_id + token_secret) or password for authentication.")

    # -- context manager ------------------------------------------------------

    def __enter__(self) -> PVEClient:
        return self

    def __exit__(self, exc_type: type[BaseException] | None, exc_val: BaseException | None, exc_tb: Any) -> None:
        self.close()

    def close(self) -> None:
        """Close the underlying HTTP connection."""
        if self._http:
            self._http.close()
            self._http = None
            logger.debug("HTTP client closed")

    # -- low-level request helpers -------------------------------------------

    def _request(self, method: str, path: str, **kwargs: Any) -> dict[str, Any]:
        """Execute an HTTP request with retry and rate-limiting."""
        assert self._http is not None
        last_exc: Exception | None = None

        for attempt in range(1, self._max_retries + 1):
            self._rate_limiter.wait_if_needed()
            try:
                resp = self._http.request(method, path, **kwargs)
                if resp.status_code in _RETRYABLE_STATUS_CODES:
                    raise httpx.HTTPStatusError(
                        f"Retryable status {resp.status_code}",
                        request=resp.request,
                        response=resp,
                    )
                resp.raise_for_status()
                body = resp.json()
                return body.get("data", body)
            except (httpx.HTTPStatusError, httpx.TransportError) as exc:
                last_exc = exc
                wait = min(2 ** attempt, 30)
                logger.warning(
                    "Request %s %s failed (attempt %d/%d): %s – retrying in %ds",
                    method,
                    path,
                    attempt,
                    self._max_retries,
                    exc,
                    wait,
                )
                time.sleep(wait)

        raise RuntimeError(f"All {self._max_retries} attempts failed for {method} {path}") from last_exc

    def get(self, path: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        """Send a GET request."""
        return self._request("GET", path, params=params)

    def post(self, path: str, data: dict[str, Any] | None = None) -> dict[str, Any]:
        """Send a POST request."""
        return self._request("POST", path, data=data)

    def put(self, path: str, data: dict[str, Any] | None = None) -> dict[str, Any]:
        """Send a PUT request."""
        return self._request("PUT", path, data=data)

    def delete(self, path: str) -> dict[str, Any]:
        """Send a DELETE request."""
        return self._request("DELETE", path)

    # -- convenience endpoint methods -----------------------------------------

    def nodes(self) -> list[dict[str, Any]]:
        """Return all cluster nodes."""
        return self.get("/api2/json/nodes")  # type: ignore[return-value]

    def node_status(self, node: str) -> dict[str, Any]:
        """Return status of a single node."""
        return self.get(f"/api2/json/nodes/{node}/status")

    def vm_status(self, node: str, vmid: int) -> dict[str, Any]:
        """Return current status of a VM / container."""
        return self.get(f"/api2/json/nodes/{node}/qemu/{vmid}/status/current")

    def vm_list(self, node: str, type_: str = "qemu") -> list[dict[str, Any]]:
        """List VMs of the given type (``qemu`` or ``lxc``)."""
        return self.get(f"/api2/json/nodes/{node}/{type_}")  # type: ignore[return-value]

    def vm_create(self, node: str, data: dict[str, Any]) -> dict[str, Any]:
        """Create a new VM on *node*."""
        return self.post(f"/api2/json/nodes/{node}/qemu", data=data)

    def vm_delete(self, node: str, vmid: int) -> dict[str, Any]:
        """Delete a VM."""
        return self.delete(f"/api2/json/nodes/{node}/qemu/{vmid}")

    def vm_start(self, node: str, vmid: int) -> dict[str, Any]:
        """Start a VM."""
        return self.post(f"/api2/json/nodes/{node}/qemu/{vmid}/status/start")

    def vm_stop(self, node: str, vmid: int) -> dict[str, Any]:
        """Stop a VM."""
        return self.post(f"/api2/json/nodes/{node}/qemu/{vmid}/status/stop")

    def vm_shutdown(self, node: str, vmid: int, timeout: int = 30) -> dict[str, Any]:
        """Gracefully shut down a VM."""
        return self.post(
            f"/api2/json/nodes/{node}/qemu/{vmid}/status/shutdown",
            data={"timeout": timeout},
        )

    def vm_clone(self, node: str, vmid: int, data: dict[str, Any]) -> dict[str, Any]:
        """Clone a VM."""
        return self.post(f"/api2/json/nodes/{node}/qemu/{vmid}/clone", data=data)

    def vm_snapshot_create(self, node: str, vmid: int, data: dict[str, Any]) -> dict[str, Any]:
        """Create a snapshot."""
        return self.post(f"/api2/json/nodes/{node}/qemu/{vmid}/snapshot", data=data)

    def vm_snapshot_list(self, node: str, vmid: int) -> list[dict[str, Any]]:
        """List snapshots for a VM."""
        return self.get(f"/api2/json/nodes/{node}/qemu/{vmid}/snapshot")  # type: ignore[return-value]

    def storage_list(self, node: str) -> list[dict[str, Any]]:
        """List storage on a node."""
        return self.get(f"/api2/json/nodes/{node}/storage")  # type: ignore[return-value]

    def storage_status(self, node: str, storage: str) -> dict[str, Any]:
        """Return status of a specific storage."""
        return self.get(f"/api2/json/nodes/{node}/storage/{storage}/status")

    def backup_list(self, node: str, storage: str | None = None) -> list[dict[str, Any]]:
        """List VZDump backup tasks / entries."""
        params: dict[str, Any] = {}
        if storage:
            params["storage"] = storage
        return self.get(f"/api2/json/nodes/{node}/storage", params=params)  # type: ignore[return-value]

    def cluster_status(self) -> dict[str, Any]:
        """Return cluster status."""
        return self.get("/api2/json/cluster/status")

    def ha_resources(self) -> list[dict[str, Any]]:
        """List HA resources."""
        return self.get("/api2/json/cluster/ha/resources")  # type: ignore[return-value]

    def firewall_rules(
        self, node: str | None = None, vmid: int | None = None
    ) -> list[dict[str, Any]]:
        """List firewall rules at cluster, host or VM level."""
        if vmid is not None:
            path = f"/api2/json/nodes/{node}/qemu/{vmid}/firewall/rules"
        elif node is not None:
            path = f"/api2/json/nodes/{node}/firewall/rules"
        else:
            path = "/api2/json/cluster/firewall/rules"
        return self.get(path)  # type: ignore[return-value]

    def user_list(self) -> list[dict[str, Any]]:
        """List all users."""
        return self.get("/api2/json/access/users")  # type: ignore[return-value]

    def acl_list(self) -> list[dict[str, Any]]:
        """List ACL entries."""
        return self.get("/api2/json/access/acl")  # type: ignore[return-value]

    def network_list(self, node: str) -> list[dict[str, Any]]:
        """List network interfaces on a node."""
        return self.get(f"/api2/json/nodes/{node}/network")  # type: ignore[return-value]

    def ceph_status(self, node: str) -> dict[str, Any]:
        """Return Ceph cluster status from a node."""
        return self.get(f"/api2/json/nodes/{node}/ceph/status")
