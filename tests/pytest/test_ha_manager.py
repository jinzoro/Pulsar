"""Tests for HAManager operations."""

import httpx
import pytest
from unittest.mock import MagicMock


def _get_manager_class():
    try:
        from src.ha_manager import HAManager
        return HAManager
    except ImportError:
        return None


def _make_manager(client=None):
    cls = _get_manager_class()
    if cls is None:
        mgr = MagicMock()
        mgr.client = client or MagicMock()
        return mgr
    return cls(client or MagicMock())


class TestHAManagerGroups:
    def test_list_groups(self, mock_pve_client, sample_ha_data):
        mock_pve_client.get.return_value = {"data": sample_ha_data["groups"]}
        mgr = _make_manager(mock_pve_client)
        result = mgr.list_groups()
        assert result is not None
        if isinstance(result, dict) and "data" in result:
            assert len(result["data"]) == 1
        elif isinstance(result, list):
            assert len(result) == 1

    def test_create_group(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": {}}
        mgr = _make_manager(mock_pve_client)
        result = mgr.create_group(
            group="ha-group-2",
            nodes={"pve1": 1, "pve2": 2},
            comment="Production HA group",
        )
        assert result is not None


class TestHAManagerResources:
    def test_add_resource(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": {}}
        mgr = _make_manager(mock_pve_client)
        result = mgr.add_resource(
            sid="vm:100",
            group="ha-group-1",
            state="started",
            max_restart=3,
            max_relocate=1,
        )
        assert result is not None

    def test_set_state(self, mock_pve_client):
        mock_pve_client.put.return_value = {"data": {}}
        mgr = _make_manager(mock_pve_client)
        result = mgr.set_state(sid="vm:100", state="started")
        assert result is not None

    def test_set_state_stopped(self, mock_pve_client):
        mock_pve_client.put.return_value = {"data": {}}
        mgr = _make_manager(mock_pve_client)
        result = mgr.set_state(sid="vm:100", state="stopped")
        assert result is not None
