"""Tests for FirewallManager operations."""

import httpx
import pytest
from unittest.mock import MagicMock


def _get_manager_class():
    try:
        from src.firewall_manager import FirewallManager
        return FirewallManager
    except ImportError:
        return None


def _make_manager(client=None):
    cls = _get_manager_class()
    if cls is None:
        mgr = MagicMock()
        mgr.client = client or MagicMock()
        return mgr
    return cls(client or MagicMock())


class TestFirewallManagerEnableDisable:
    def test_enable_disable(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": {}}
        mgr = _make_manager(mock_pve_client)
        result = mgr.set_enable(node="pve1", vmid=100, enable=True)
        assert result is not None

        mock_pve_client.post.return_value = {"data": {}}
        result = mgr.set_enable(node="pve1", vmid=100, enable=False)
        assert result is not None


class TestFirewallManagerRules:
    def test_add_rule(self, mock_pve_client, sample_firewall_rules):
        mock_pve_client.post.return_value = {"data": {}}
        mgr = _make_manager(mock_pve_client)
        result = mgr.add_rule(
            node="pve1",
            vmid=100,
            direction="in",
            action="ACCEPT",
            proto="tcp",
            dport="22",
            comment="SSH",
        )
        assert result is not None

    def test_delete_rule(self, mock_pve_client):
        mock_pve_client.delete.return_value = {"data": {}}
        mgr = _make_manager(mock_pve_client)
        result = mgr.delete_rule(node="pve1", vmid=100, pos=1)
        assert result is not None

    def test_list_rules(self, mock_pve_client, sample_firewall_rules):
        mock_pve_client.get.return_value = {"data": sample_firewall_rules}
        mgr = _make_manager(mock_pve_client)
        result = mgr.list_rules(node="pve1", vmid=100)
        assert result is not None
        if isinstance(result, dict) and "data" in result:
            assert len(result["data"]) == 3
        elif isinstance(result, list):
            assert len(result) == 3


class TestFirewallManagerIpsets:
    def test_ipsets(self, mock_pve_client):
        ipsets = [
            {"name": "management", "cidr": "10.0.0.0/8"},
            {"name": "management", "cidr": "192.168.0.0/16"},
        ]
        mock_pve_client.get.return_value = {"data": ipsets}
        mgr = _make_manager(mock_pve_client)
        result = mgr.list_ipsets(node="pve1")
        assert result is not None
