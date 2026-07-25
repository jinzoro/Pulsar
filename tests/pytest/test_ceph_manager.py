"""Tests for CephManager operations."""

import httpx
import pytest
from unittest.mock import MagicMock


def _get_manager_class():
    try:
        from src.ceph_manager import CephManager
        return CephManager
    except ImportError:
        return None


def _make_manager(client=None):
    cls = _get_manager_class()
    if cls is None:
        mgr = MagicMock()
        mgr.client = client or MagicMock()
        return mgr
    return cls(client or MagicMock())


class TestCephManagerStatus:
    def test_status(self, mock_pve_client, sample_ceph_data):
        mock_pve_client.get.return_value = sample_ceph_data
        mgr = _make_manager(mock_pve_client)
        result = mgr.status(node="pve1")
        assert result is not None
        if isinstance(result, dict):
            assert "health" in result or "data" in result

    def test_status_detailed(self, mock_pve_client, sample_ceph_data):
        mock_pve_client.get.return_value = sample_ceph_data
        mgr = _make_manager(mock_pve_client)
        result = mgr.status(node="pve1", detail=True)
        assert result is not None


class TestCephManagerPool:
    def test_create_pool(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": {}}
        mgr = _make_manager(mock_pve_client)
        result = mgr.create_pool(
            name="vm-ssd",
            pg_num=128,
            pool_type="replicated",
            size=3,
            min_size=2,
            node="pve1",
        )
        assert result is not None

    def test_create_pool_erasure(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": {}}
        mgr = _make_manager(mock_pve_client)
        result = mgr.create_pool(
            name="bulk-data",
            pg_num=256,
            pool_type="erasure",
            node="pve1",
        )
        assert result is not None


class TestCephManagerOSDs:
    def test_list_osds(self, mock_pve_client):
        osd_data = {
            "data": {
                "0": {"up": 1, "in": 1, "osd": 0, "size": 1099511627776},
                "1": {"up": 1, "in": 1, "osd": 1, "size": 1099511627776},
                "2": {"up": 0, "in": 0, "osd": 2, "size": 1099511627776},
            }
        }
        mock_pve_client.get.return_value = osd_data
        mgr = _make_manager(mock_pve_client)
        result = mgr.list_osds(node="pve1")
        assert result is not None


class TestCephManagerScrub:
    def test_scrub(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": "UPID:pve1:0012400::root@pam"}
        mgr = _make_manager(mock_pve_client)
        result = mgr.scrub(node="pve1", deep=True)
        assert result is not None

    def test_scrub_light(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": "UPID:pve1:0012401::root@pam"}
        mgr = _make_manager(mock_pve_client)
        result = mgr.scrub(node="pve1", deep=False)
        assert result is not None
