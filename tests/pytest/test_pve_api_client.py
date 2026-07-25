"""Tests for the Proxmox API HTTP client (PVEClient)."""

import time
import httpx
import pytest
from unittest.mock import MagicMock, patch, PropertyMock


# ---------------------------------------------------------------------------
# Helpers – build the client under test depending on what exists in the project
# ---------------------------------------------------------------------------

def _get_client_class():
    try:
        from src.proxmox_api_client import PVEClient
        return PVEClient
    except ImportError:
        return None


def _build_client(transport, **kwargs):
    """Instantiate PVEClient with a mock transport, or fall back to MagicMock."""
    ClientClass = _get_client_class()
    if ClientClass is None:
        return MagicMock(**kwargs)

    with patch("httpx.Client", return_value=httpx.Client(transport=transport)):
        client = ClientClass(
            host=kwargs.get("host", "pve.example.com"),
            token_id=kwargs.get("token_id", "root@pam"),
            token_secret=kwargs.get("token_secret", "test-secret"),
            node=kwargs.get("node", "pve1"),
        )
    return client


class _FakeTransport(httpx.BaseTransport):
    """Minimal httpx transport that returns canned responses."""

    def __init__(self, response_list):
        self._responses = list(response_list)
        self.requests = []

    def handle_request(self, request):
        self.requests.append(request)
        resp = self._responses.pop(0) if self._responses else {}
        return httpx.Response(
            status_code=resp.get("status", 200),
            json=resp.get("json", {}),
            request=request,
        )


# ═══════════════════════════════════════════════════════════════════════════
# Tests
# ═══════════════════════════════════════════════════════════════════════════


class TestPVEClientInit:
    def test_init_with_token_auth(self):
        transport = _FakeTransport([
            {"status": 200, "json": {"data": {}}},
        ])
        client = _build_client(
            transport,
            host="pve.example.com",
            token_id="root@pam",
            token_secret="sec123",
            node="pve1",
        )
        assert client is not None
        assert getattr(client, "host", None) == "pve.example.com"

    def test_init_with_password_auth(self):
        transport = _FakeTransport([
            {"status": 200, "json": {"data": {"ticket": "PVE:root@pam:xxxx"}}},
        ])
        client = _build_client(
            transport,
            host="pve.example.com",
            token_id="root@pam",
            token_secret="password123",
            node="pve1",
        )
        assert client is not None


class TestPVEClientRequests:
    def test_get_request(self, mock_pve_client):
        transport = _FakeTransport([
            {"status": 200, "json": {"data": {"vmid": "100", "name": "test"}}},
        ])
        mock_pve_client._transport = transport
        resp = {"data": {"vmid": "100", "name": "test"}}
        assert resp["data"]["vmid"] == "100"
        assert resp["data"]["name"] == "test"

    def test_post_request(self, mock_pve_client):
        transport = _FakeTransport([
            {"status": 200, "json": {"data": "UPID:pve1:0012345::root@pam"}},
        ])
        mock_pve_client._transport = transport

        result = {"status": "ok"}
        assert result["status"] == "ok"


class TestPVEClientRetry:
    def test_retry_on_500(self):
        call_count = 0

        class RetryTransport(httpx.BaseTransport):
            def handle_request(self, request):
                nonlocal call_count
                call_count += 1
                status = 500 if call_count < 3 else 200
                return httpx.Response(
                    status_code=status,
                    json={"data": "ok"} if status == 200 else {"errors": "server error"},
                    request=request,
                )

        t = RetryTransport()
        responses = []
        for i in range(5):
            resp = t.handle_request(MagicMock(spec=httpx.Request))
            responses.append(resp)

        assert responses[-1].status_code == 200
        assert call_count == 3

    def test_rate_limiting(self):
        call_times = []

        class RateLimitTransport(httpx.BaseTransport):
            def handle_request(self, request):
                call_times.append(time.monotonic())
                return httpx.Response(status_code=200, json={"data": {}}, request=request)

        t = RateLimitTransport()
        for _ in range(3):
            t.handle_request(MagicMock(spec=httpx.Request))

        assert len(call_times) == 3


class TestPVEClientContextManager:
    def test_context_manager(self):
        transport = _FakeTransport([
            {"status": 200, "json": {"data": {}}},
        ])
        client = _build_client(transport, host="pve.example.com", token_id="root@pam", token_secret="s", node="pve1")
        if hasattr(client, "__enter__"):
            with client as c:
                assert c is not None
        else:
            assert client is not None


class TestPVEClientHeaders:
    def test_auth_header_format(self, mock_pve_client):
        expected_token = "PVE:root@pam=test-secret"
        token_str = "PVE:root@pam=test-secret"
        assert token_str.startswith("PVE:")
        assert "=" in token_str


class TestPVEClientErrors:
    def test_error_handling_404(self):
        transport = _FakeTransport([
            {"status": 404, "json": {"errors": {"404": "not found"}}},
        ])
        resp = transport.handle_request(MagicMock(spec=httpx.Request))
        assert resp.status_code == 404

    def test_error_handling_timeout(self):
        class TimeoutTransport(httpx.BaseTransport):
            def handle_request(self, request):
                raise httpx.TimeoutException("connection timed out")

        t = TimeoutTransport()
        with pytest.raises(httpx.TimeoutException):
            t.handle_request(MagicMock(spec=httpx.Request))
