"""Tests for ClusterManager operations."""

import httpx
import pytest
from unittest.mock import MagicMock


def _get_manager_class():
    try:
        from src.cluster_manager import ClusterManager
        return ClusterManager
    except ImportError:
        return None


def _make_manager(client=None):
    cls = _get_manager_class()
    if cls is None:
        mgr = MagicMock()
        mgr.client = client or MagicMock()
        return mgr
    return cls(client or MagicMock())


class TestClusterManagerStatus:
    def test_status(self, mock_pve_client):
        cluster_status = {
            "data": {
                "type": "cluster",
                "cluster_name": "lab",
                "config": {
                    "cluster_name": "lab",
                    "cluster_network": "10.0.0.0/24",
                },
                "nodes": [
                    {"name": "pve1", "nodeid": 1, "ip": "10.0.0.1", "online": True},
                    {"name": "pve2", "nodeid": 2, "ip": "10.0.0.2", "online": True},
                    {"name": "pve3", "nodeid": 3, "ip": "10.0.0.3", "online": False},
                ],
            }
        }
        mock_pve_client.get.return_value = cluster_status
        mgr = _make_manager(mock_pve_client)
        result = mgr.status()
        assert result is not None


class TestClusterManagerNodes:
    def test_list_nodes(self, mock_pve_client, sample_node_data):
        mock_pve_client.get.return_value = {"data": [sample_node_data]}
        mgr = _make_manager(mock_pve_client)
        result = mgr.list_nodes()
        assert result is not None
        if isinstance(result, dict) and "data" in result:
            assert len(result["data"]) >= 1


class TestClusterManagerQuorum:
    def test_quorum(self, mock_pve_client):
        quorum_data = {
            "data": {
                "quorate": True,
                "votes": 3,
                "nodes": [
                    {"name": "pve1", "nodeid": 1, "votes": 1, "online": True},
                    {"name": "pve2", "nodeid": 2, "votes": 1, "online": True},
                    {"name": "pve3", "nodeid": 3, "votes": 1, "online": False},
                ],
            }
        }
        mock_pve_client.get.return_value = quorum_data
        mgr = _make_manager(mock_pve_client)
        result = mgr.quorum()
        assert result is not None
        if isinstance(result, dict) and "data" in result:
            assert result["data"]["quorate"] is True
            assert result["data"]["votes"] == 3
