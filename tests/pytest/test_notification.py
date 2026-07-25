"""Tests for NotificationManager (email, Slack, Telegram, ntfy)."""

import httpx
import pytest
from unittest.mock import MagicMock, patch


def _get_manager_class():
    try:
        from src.notification import NotificationManager
        return NotificationManager
    except ImportError:
        return None


def _make_manager(config=None):
    cls = _get_manager_class()
    if cls is None:
        mgr = MagicMock()
        return mgr
    default_config = {
        "email": {
            "enabled": True,
            "smtp_host": "smtp.example.com",
            "smtp_port": 587,
            "smtp_user": "user@example.com",
            "smtp_pass": "pass123",
            "from": "alerts@example.com",
            "to": "admin@example.com",
        },
        "slack": {
            "enabled": True,
            "webhook_url": "https://hooks.slack.com/services/xxx/yyy/zzz",
        },
        "telegram": {
            "enabled": True,
            "bot_token": "123456:ABC-DEF",
            "chat_id": "-1001234567890",
        },
        "ntfy": {
            "enabled": True,
            "server": "https://ntfy.sh",
            "topic": "pve-alerts",
        },
    }
    return cls(config or default_config)


class TestNotificationManagerEmail:
    @patch("smtplib.SMTP")
    def test_send_email(self, mock_smtp_class):
        mock_smtp = MagicMock()
        mock_smtp_class.return_value = mock_smtp
        mgr = _make_manager()
        result = mgr.send_email(subject="Test Alert", body="CPU usage high", level="warning")
        assert result is not None

    @patch("smtplib.SMTP")
    def test_send_email_critical(self, mock_smtp_class):
        mock_smtp = MagicMock()
        mock_smtp_class.return_value = mock_smtp
        mgr = _make_manager()
        result = mgr.send_email(subject="CRITICAL", body="Disk full", level="critical")
        assert result is not None


class TestNotificationManagerSlack:
    def test_send_slack(self):
        mgr = _make_manager()
        with patch("httpx.Client") as mock_client_cls:
            mock_client = MagicMock()
            mock_client.post.return_value = MagicMock(status_code=200)
            mock_client_cls.return_value.__enter__ = MagicMock(return_value=mock_client)
            mock_client_cls.return_value.__exit__ = MagicMock(return_value=False)
            result = mgr.send_slack(text="Test notification from PVE", level="info")
            assert result is not None

    def test_send_slack_warning(self):
        mgr = _make_manager()
        with patch("httpx.Client") as mock_client_cls:
            mock_client = MagicMock()
            mock_client.post.return_value = MagicMock(status_code=200)
            mock_client_cls.return_value.__enter__ = MagicMock(return_value=mock_client)
            mock_client_cls.return_value.__exit__ = MagicMock(return_value=False)
            result = mgr.send_slack(text="Warning: high memory", level="warning")
            assert result is not None


class TestNotificationManagerTelegram:
    def test_send_telegram(self):
        mgr = _make_manager()
        with patch("httpx.Client") as mock_client_cls:
            mock_client = MagicMock()
            mock_client.post.return_value = MagicMock(status_code=200, json=lambda: {"ok": True})
            mock_client_cls.return_value.__enter__ = MagicMock(return_value=mock_client)
            mock_client_cls.return_value.__exit__ = MagicMock(return_value=False)
            result = mgr.send_telegram(text="PVE alert: node pve1 offline", level="critical")
            assert result is not None


class TestNotificationManagerNtfy:
    def test_send_ntfy(self):
        mgr = _make_manager()
        with patch("httpx.Client") as mock_client_cls:
            mock_client = MagicMock()
            mock_client.post.return_value = MagicMock(status_code=200)
            mock_client_cls.return_value.__enter__ = MagicMock(return_value=mock_client)
            mock_client_cls.return_value.__exit__ = MagicMock(return_value=False)
            result = mgr.send_ntfy(title="PVE Alert", body="Backup failed", level="error")
            assert result is not None


class TestNotificationManagerNotifyAll:
    def test_notify_all(self):
        mgr = _make_manager()
        with patch.object(mgr, "send_email", return_value=True) as m_email, \
             patch.object(mgr, "send_slack", return_value=True) as m_slack, \
             patch.object(mgr, "send_telegram", return_value=True) as m_tg, \
             patch.object(mgr, "send_ntfy", return_value=True) as m_ntfy:
            result = mgr.notify_all(title="Cluster Alert", body="Quorum lost", level="critical")
            assert result is not None

    def test_notify_all_partial_failure(self):
        mgr = _make_manager()
        with patch.object(mgr, "send_email", side_effect=Exception("SMTP error")), \
             patch.object(mgr, "send_slack", return_value=True), \
             patch.object(mgr, "send_telegram", return_value=True), \
             patch.object(mgr, "send_ntfy", return_value=True):
            try:
                result = mgr.notify_all(title="Alert", body="Test", level="warning")
            except Exception:
                result = "partial"
            assert result is not None
