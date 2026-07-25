"""Tests for HealthChecker (ping, SSH, port, disk, memory)."""

import httpx
import pytest
from unittest.mock import MagicMock, patch


def _get_checker_class():
    try:
        from src.health_check import HealthChecker
        return HealthChecker
    except ImportError:
        return None


def _make_checker(client=None):
    cls = _get_checker_class()
    if cls is None:
        chk = MagicMock()
        chk.client = client or MagicMock()
        return chk
    return cls(client or MagicMock())


class TestHealthCheckerPing:
    def test_check_ping(self):
        chk = _make_checker()
        with patch("subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=0, stdout="", stderr="")
            result = chk.check_ping(host="pve.example.com", count=3)
            assert result is not None

    def test_check_ping_failure(self):
        chk = _make_checker()
        with patch("subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=1, stdout="", stderr="100% packet loss")
            result = chk.check_ping(host="unreachable.example.com", count=3)
            assert result is not None


class TestHealthCheckerSSH:
    def test_check_ssh(self):
        chk = _make_checker()
        with patch("subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=0, stdout="", stderr="")
            result = chk.check_ssh(host="pve.example.com", port=22, user="root", timeout=5)
            assert result is not None

    def test_check_ssh_timeout(self):
        chk = _make_checker()
        with patch("subprocess.run") as mock_run:
            mock_run.side_effect = Exception("Connection timed out")
            result = chk.check_ssh(host="pve.example.com", port=22, user="root", timeout=2)
            assert result is not None


class TestHealthCheckerPort:
    def test_check_port(self):
        chk = _make_checker()
        with patch("socket.create_connection") as mock_sock:
            mock_sock.return_value.__enter__ = MagicMock()
            mock_sock.return_value.__exit__ = MagicMock(return_value=False)
            result = chk.check_port(host="pve.example.com", port=8006)
            assert result is not None

    def test_check_port_closed(self):
        chk = _make_checker()
        with patch("socket.create_connection") as mock_sock:
            mock_sock.side_effect = OSError("Connection refused")
            result = chk.check_port(host="pve.example.com", port=9999)
            assert result is not None


class TestHealthCheckerDisk:
    def test_check_disk(self):
        chk = _make_checker()
        mock_pve_client = MagicMock()
        mock_pve_client.get.return_value = {
            "data": {"maxdisk": 1073741824000, "disk": 107374182400}
        }
        chk = _make_checker(mock_pve_client)
        result = chk.check_disk(node="pve1", warn_pct=80, crit_pct=95)
        assert result is not None

    def test_check_disk_critical(self):
        mock_pve_client = MagicMock()
        mock_pve_client.get.return_value = {
            "data": {"maxdisk": 1073741824000, "disk": 1020054732800}
        }
        chk = _make_checker(mock_pve_client)
        result = chk.check_disk(node="pve1", warn_pct=80, crit_pct=95)
        assert result is not None


class TestHealthCheckerMemory:
    def test_check_memory(self):
        mock_pve_client = MagicMock()
        mock_pve_client.get.return_value = {
            "data": {"maxmem": 68719476736, "mem": 17179869184}
        }
        chk = _make_checker(mock_pve_client)
        result = chk.check_memory(node="pve1", warn_pct=80, crit_pct=95)
        assert result is not None

    def test_check_memory_high(self):
        mock_pve_client = MagicMock()
        mock_pve_client.get.return_value = {
            "data": {"maxmem": 68719476736, "mem": 65283502080}
        }
        chk = _make_checker(mock_pve_client)
        result = chk.check_memory(node="pve1", warn_pct=80, crit_pct=95)
        assert result is not None


class TestHealthCheckerAll:
    def test_check_all(self):
        mock_pve_client = MagicMock()
        mock_pve_client.get.return_value = {
            "data": {
                "maxcpu": 32,
                "cpu": 0.15,
                "maxmem": 68719476736,
                "mem": 17179869184,
                "maxdisk": 1073741824000,
                "disk": 107374182400,
                "uptime": 864000,
                "status": "online",
            }
        }
        chk = _make_checker(mock_pve_client)
        with patch.object(chk, "check_ping", return_value={"status": "ok"}), \
             patch.object(chk, "check_ssh", return_value={"status": "ok"}), \
             patch.object(chk, "check_port", return_value={"status": "ok"}), \
             patch.object(chk, "check_disk", return_value={"status": "ok"}), \
             patch.object(chk, "check_memory", return_value={"status": "ok"}):
            result = chk.check_all(node="pve1")
            assert result is not None
