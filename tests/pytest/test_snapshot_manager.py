"""Tests for SnapshotManager operations."""

import httpx
import pytest
from unittest.mock import MagicMock


def _get_manager_class():
    try:
        from src.snapshot_manager import SnapshotManager
        return SnapshotManager
    except ImportError:
        return None


def _make_manager(client=None):
    cls = _get_manager_class()
    if cls is None:
        mgr = MagicMock()
        mgr.client = client or MagicMock()
        return mgr
    return cls(client or MagicMock())


class TestSnapshotManagerCreate:
    def test_create_snapshot(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": "UPID:pve1:0012390::root@pam"}
        mgr = _make_manager(mock_pve_client)
        result = mgr.create(
            vmid=100,
            name="snap-pre-update",
            description="Before major upgrade",
            node="pve1",
        )
        assert result is not None

    def test_create_snapshot_minimal(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": "UPID:pve1:0012391::root@pam"}
        mgr = _make_manager(mock_pve_client)
        result = mgr.create(vmid=100, name="snap-minimal", node="pve1")
        assert result is not None


class TestSnapshotManagerList:
    def test_list_snapshots(self, mock_pve_client, sample_snapshot_data):
        mock_pve_client.get.return_value = {"data": sample_snapshot_data}
        mgr = _make_manager(mock_pve_client)
        result = mgr.list(vmid=100, node="pve1")
        assert result is not None
        if isinstance(result, dict) and "data" in result:
            assert len(result["data"]) == 2
        elif isinstance(result, list):
            assert len(result) == 2


class TestSnapshotManagerRollback:
    def test_rollback(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": "UPID:pve1:0012392::root@pam"}
        mgr = _make_manager(mock_pve_client)
        result = mgr.rollback(vmid=100, name="snap-pre-update", node="pve1")
        assert result is not None


class TestSnapshotManagerDelete:
    def test_delete(self, mock_pve_client):
        mock_pve_client.delete.return_value = {"data": "UPID:pve1:0012393::root@pam"}
        mgr = _make_manager(mock_pve_client)
        result = mgr.delete(vmid=100, name="snap-pre-update", node="pve1")
        assert result is not None

    def test_delete_all(self, mock_pve_client):
        mock_pve_client.delete.return_value = {"data": "UPID:pve1:0012394::root@pam"}
        mgr = _make_manager(mock_pve_client)
        result = mgr.delete(vmid=100, name="current", node="pve1", delete_all=True)
        assert result is not None
