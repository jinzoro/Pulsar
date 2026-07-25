#!/usr/bin/env python3
# =============================================================================
# notification.py — Multi-channel notification manager
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Pulsar contributors
# =============================================================================
# Sends alerts and reports via email, Slack, Telegram, ntfy, PagerDuty,
# and arbitrary webhook endpoints.
# =============================================================================

from __future__ import annotations

import json
import logging
import smtplib
import ssl
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from typing import Any, Dict, List, Optional
from urllib.parse import urljoin

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Attempt to import requests; fall back to urllib
# ---------------------------------------------------------------------------
try:
    import requests as _requests

    _HAS_REQUESTS = True
except ImportError:
    import urllib.request
    import urllib.error
    import urllib.parse

    _HAS_REQUESTS = False
    logger.debug("requests library not found; using urllib fallback.")


# ---------------------------------------------------------------------------
# HTTP helper (abstracts requests vs urllib)
# ---------------------------------------------------------------------------

def _http_post(
    url: str,
    payload: Dict[str, Any],
    headers: Optional[Dict[str, str]] = None,
    timeout: int = 15,
) -> tuple[int, str]:
    """POST JSON payload to a URL, return (status_code, body)."""
    data = json.dumps(payload).encode("utf-8")
    hdrs = {"Content-Type": "application/json"}
    if headers:
        hdrs.update(headers)

    if _HAS_REQUESTS:
        try:
            resp = _requests.post(
                url, json=payload, headers=hdrs, timeout=timeout
            )
            return resp.status_code, resp.text
        except Exception as exc:
            logger.error("HTTP POST failed (requests): %s", exc)
            raise
    else:
        req = urllib.request.Request(
            url, data=data, headers=hdrs, method="POST"
        )
        try:
            ctx = ssl.create_default_context()
            with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
                body = resp.read().decode("utf-8", errors="replace")
                return resp.status, body
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            return exc.code, body
        except Exception as exc:
            logger.error("HTTP POST failed (urllib): %s", exc)
            raise


# ---------------------------------------------------------------------------
# NotificationManager
# ---------------------------------------------------------------------------

class NotificationManager:
    """Send notifications through multiple configured channels.

    Parameters
    ----------
    config : dict
        Notification configuration dictionary matching the structure in
        ``config/settings.yaml`` under the ``notifications`` key.
    """

    def __init__(self, config: Dict[str, Any]) -> None:
        self._cfg = config or {}
        self._results: Dict[str, bool] = {}

    # ------------------------------------------------------------------
    # Email
    # ------------------------------------------------------------------

    def send_email(
        self,
        subject: str,
        body: str,
        priority: str = "normal",
        recipients: Optional[List[str]] = None,
    ) -> bool:
        """Send an email notification via SMTP.

        Parameters
        ----------
        subject : str
            Email subject line.
        body : str
            Email body (plain text or HTML).
        priority : str
            ``"low"``, ``"normal"``, or ``"high"``.
        recipients : list[str] or None
            Override recipients from config.

        Returns
        -------
        bool
            ``True`` on success.
        """
        cfg = self._cfg.get("email", {})
        if not cfg.get("enabled", False):
            logger.debug("Email notifications disabled; skipping.")
            return False

        smtp_host = cfg.get("smtp_host", "")
        smtp_port = int(cfg.get("smtp_port", 587))
        smtp_user = cfg.get("smtp_user", "")
        smtp_pass = cfg.get("smtp_pass", "")
        use_tls = cfg.get("use_tls", True)
        from_addr = cfg.get("from_addr", smtp_user)
        to_addrs = recipients or cfg.get("to_addrs", [])

        if not all([smtp_host, to_addrs]):
            logger.error("Email config incomplete (host or recipients missing).")
            return False

        # Build message
        msg = MIMEMultipart("alternative")
        msg["From"] = from_addr
        msg["To"] = ", ".join(to_addrs)
        msg["Subject"] = subject

        priority_map = {
            "low": "5",
            "normal": "3",
            "high": "1",
        }
        if priority in priority_map:
            msg["X-Priority"] = priority_map[priority]
            msg["X-MSMail-Priority"] = priority.capitalize()

        msg.attach(MIMEText(body, "plain", "utf-8"))

        try:
            context = ssl.create_default_context()
            with smtplib.SMTP(smtp_host, smtp_port, timeout=15) as server:
                if use_tls:
                    server.starttls(context=context)
                if smtp_user and smtp_pass:
                    server.login(smtp_user, smtp_pass)
                server.sendmail(from_addr, to_addrs, msg.as_string())
            logger.info("Email sent to %s", ", ".join(to_addrs))
            return True
        except Exception as exc:
            logger.error("Failed to send email: %s", exc)
            return False

    # ------------------------------------------------------------------
    # Slack
    # ------------------------------------------------------------------

    def send_slack(
        self,
        message: str,
        channel: Optional[str] = None,
        username: Optional[str] = None,
    ) -> bool:
        """Send a message to Slack via incoming webhook.

        Parameters
        ----------
        message : str
            Message text (supports Slack mrkdwn).
        channel : str or None
            Channel override.
        username : str or None
            Bot username override.

        Returns
        -------
        bool
            ``True`` on success.
        """
        cfg = self._cfg.get("slack", {})
        if not cfg.get("enabled", False):
            logger.debug("Slack notifications disabled; skipping.")
            return False

        webhook_url = cfg.get("webhook_url", "")
        if not webhook_url:
            logger.error("Slack webhook_url is not configured.")
            return False

        payload: Dict[str, Any] = {"text": message}
        if channel or cfg.get("channel"):
            payload["channel"] = channel or cfg["channel"]
        if username or cfg.get("username"):
            payload["username"] = username or cfg["username"]

        try:
            status, body = _http_post(webhook_url, payload)
            if 200 <= status < 300:
                logger.info("Slack message sent successfully.")
                return True
            else:
                logger.error("Slack API returned %d: %s", status, body)
                return False
        except Exception as exc:
            logger.error("Failed to send Slack message: %s", exc)
            return False

    # ------------------------------------------------------------------
    # Telegram
    # ------------------------------------------------------------------

    def send_telegram(self, message: str) -> bool:
        """Send a message via the Telegram Bot API.

        Parameters
        ----------
        message : str
            Message text (supports HTML or MarkdownV2 based on config).

        Returns
        -------
        bool
            ``True`` on success.
        """
        cfg = self._cfg.get("telegram", {})
        if not cfg.get("enabled", False):
            logger.debug("Telegram notifications disabled; skipping.")
            return False

        bot_token = cfg.get("bot_token", "")
        chat_id = cfg.get("chat_id", "")
        parse_mode = cfg.get("parse_mode", "HTML")

        if not bot_token or not chat_id:
            logger.error("Telegram bot_token or chat_id is not configured.")
            return False

        url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
        payload = {
            "chat_id": chat_id,
            "text": message,
            "parse_mode": parse_mode,
        }

        try:
            status, body = _http_post(url, payload)
            if 200 <= status < 300:
                logger.info("Telegram message sent successfully.")
                return True
            else:
                logger.error("Telegram API returned %d: %s", status, body)
                return False
        except Exception as exc:
            logger.error("Failed to send Telegram message: %s", exc)
            return False

    # ------------------------------------------------------------------
    # ntfy
    # ------------------------------------------------------------------

    def send_ntfy(
        self,
        message: str,
        topic: Optional[str] = None,
    ) -> bool:
        """Send a notification via ntfy.sh (or self-hosted instance).

        Parameters
        ----------
        message : str
            Notification body.
        topic : str or None
            Topic to publish to (overrides config).

        Returns
        -------
        bool
            ``True`` on success.
        """
        cfg = self._cfg.get("ntfy", {})
        if not cfg.get("enabled", False):
            logger.debug("ntfy notifications disabled; skipping.")
            return False

        base_url = cfg.get("url", "https://ntfy.sh").rstrip("/")
        ntfy_topic = topic or cfg.get("topic", "proxmox-alerts")
        token = cfg.get("token", "")

        url = f"{base_url}/{ntfy_topic}"
        headers: Dict[str, str] = {}
        if token:
            headers["Authorization"] = f"Bearer {token}"

        try:
            status, body = _http_post(
                url, {"message": message}, headers=headers
            )
            if 200 <= status < 300:
                logger.info("ntfy notification sent to topic '%s'.", ntfy_topic)
                return True
            else:
                logger.error("ntfy API returned %d: %s", status, body)
                return False
        except Exception as exc:
            logger.error("Failed to send ntfy notification: %s", exc)
            return False

    # ------------------------------------------------------------------
    # PagerDuty
    # ------------------------------------------------------------------

    def send_pagerduty(
        self,
        message: str,
        severity: str = "warning",
    ) -> bool:
        """Send an incident alert to PagerDuty Events API v2.

        Parameters
        ----------
        message : str
            Alert description.
        severity : str
            ``"info"``, ``"warning"``, ``"error"``, or ``"critical"``.

        Returns
        -------
        bool
            ``True`` on success.
        """
        cfg = self._cfg.get("pagerduty", {})
        if not cfg.get("enabled", False):
            logger.debug("PagerDuty notifications disabled; skipping.")
            return False

        routing_key = cfg.get("key", "")
        endpoint = cfg.get(
            "endpoint", "https://events.pagerduty.com/v2/enqueue"
        )

        if not routing_key:
            logger.error("PagerDuty routing key is not configured.")
            return False

        payload = {
            "routing_key": routing_key,
            "event_action": "trigger",
            "payload": {
                "summary": message,
                "source": "Pulsar",
                "severity": severity,
            },
        }

        try:
            status, body = _http_post(endpoint, payload)
            if 200 <= status < 300:
                logger.info("PagerDuty alert sent (severity=%s).", severity)
                return True
            else:
                logger.error("PagerDuty API returned %d: %s", status, body)
                return False
        except Exception as exc:
            logger.error("Failed to send PagerDuty alert: %s", exc)
            return False

    # ------------------------------------------------------------------
    # Generic Webhook
    # ------------------------------------------------------------------

    def send_webhook(
        self,
        url: str,
        payload: Dict[str, Any],
        method: str = "POST",
        headers: Optional[Dict[str, str]] = None,
    ) -> bool:
        """Send a notification to an arbitrary webhook endpoint.

        Parameters
        ----------
        url : str
            Webhook URL.
        payload : dict
            JSON payload.
        method : str
            HTTP method (default POST).
        headers : dict or None
            Additional headers.

        Returns
        -------
        bool
            ``True`` on success.
        """
        try:
            status, body = _http_post(url, payload, headers=headers)
            if 200 <= status < 300:
                logger.info("Webhook sent to %s.", url)
                return True
            else:
                logger.error(
                    "Webhook to %s returned %d: %s", url, status, body
                )
                return False
        except Exception as exc:
            logger.error("Failed to send webhook to %s: %s", url, exc)
            return False

    # ------------------------------------------------------------------
    # Multi-channel dispatch
    # ------------------------------------------------------------------

    def notify(
        self,
        message: str,
        channels: Optional[List[str]] = None,
        **kwargs: Any,
    ) -> Dict[str, bool]:
        """Send a notification to one or more configured channels.

        Parameters
        ----------
        message : str
            Notification message text.
        channels : list[str] or None
            Channels to notify.  Valid values: ``"email"``, ``"slack"``,
            ``"telegram"``, ``"ntfy"``, ``"pagerduty"``.  If ``None``,
            all enabled channels are used.
        **kwargs
            Additional keyword arguments passed to individual senders
            (e.g. ``subject`` for email, ``severity`` for PagerDuty).

        Returns
        -------
        dict[str, bool]
            Mapping of channel name to success status.
        """
        all_channels = ["email", "slack", "telegram", "ntfy", "pagerduty"]
        target_channels = channels or all_channels

        results: Dict[str, bool] = {}

        for ch in target_channels:
            if ch == "email":
                subject = kwargs.get("subject", "Pulsar Alert")
                priority = kwargs.get("priority", "normal")
                results["email"] = self.send_email(
                    subject=subject, body=message, priority=priority
                )
            elif ch == "slack":
                channel = kwargs.get("slack_channel")
                results["slack"] = self.send_slack(
                    message, channel=channel
                )
            elif ch == "telegram":
                results["telegram"] = self.send_telegram(message)
            elif ch == "ntfy":
                topic = kwargs.get("ntfy_topic")
                results["ntfy"] = self.send_ntfy(message, topic=topic)
            elif ch == "pagerduty":
                severity = kwargs.get("severity", "warning")
                results["pagerduty"] = self.send_pagerduty(
                    message, severity=severity
                )
            else:
                logger.warning("Unknown notification channel: %s", ch)
                results[ch] = False

        self._results = results
        succeeded = sum(1 for v in results.values() if v)
        total = len(results)
        logger.info(
            "Notification dispatch complete: %d/%d channels succeeded.",
            succeeded,
            total,
        )
        return results

    @property
    def last_results(self) -> Dict[str, bool]:
        """Return results from the most recent :meth:`notify` call."""
        return dict(self._results)
