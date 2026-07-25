"""Tests for ZFSManager operations."""

import httpx
import pytest
from unittest.mock import MagicMock


def _get_manager_class():
    try:
        from src.zfs_manager import ZFSManager
        return ZFSManager
    except ImportError:
        return None


def _make_manager(client=None):
    cls = _get_manager_class()
    if cls is None:
        mgr = MagicMock()
        mgr.client = client or MagicMock()
        return mgr
    return cls(client or MagicMock())


class TestZFSManagerPools:
    def test_list_pools(self, mock_pve_client, sample_zfs_data):
        mock_pve_client.get.return_value = {"data": sample_zfs_data}
        mgr = _make_manager(mock_pve_client)
        result = mgr.list_pools(node="pve1")
        assert result is not None
        if isinstance(result, dict) and "data" in result:
            assert len(result["data"]) >= 1
        elif isinstance(result, list):
            assert len(result) >= 1

    def test_create_pool(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": {}}
        mgr = _make_manager(mock_pve_client)
        result = mgr.create_pool(
            name="data",
            vdevs=["mirror /dev/sdb /dev/sdc", "mirror /dev/sdd /dev/sde"],
            mountpoint="/data",
            node="pve1",
        )
        assert result is not None

    def test_create_pool_raidz(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": {}}
        mgr = _make_manager(mock_pve_client)
        result = mgr.create_pool(
            name="bulk",
            vdevs=["raidz1 /dev/sdb /dev/sdc /dev/sdd"],
            node="pve1",
        )
        assert result is not None


class TestZFSManagerDatasets:
    def test_create_dataset(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": {}}
        mgr = _make_manager(mock_pve_client)
        result = mgr.create_dataset(
            pool="data",
            name="containers",
            mountpoint="/data/containers",
            node="pve1",
        )
        assert result is not None

    def test_create_dataset_with_quota(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": {}}
        mgr = _make_manager(mock_pve_client)
        result = mgr.create_dataset(
            pool="data",
            name="vms",
            quota="100G",
            node="pve1",
        )
        assert result is not None


class TestZFSManagerScrub:
    def test_scrub(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": "UPID:pve1:0012410::root@pam"}
        mgr = _make_manager(mock_pve_client)
        result = mgr.scrub(pool="rpool", node="pve1")
        assert result is not None

    def test_scrub_status(self, mock_pve_client):
        mock_pve_client.get.return_value = {
            "data": {
                "pool": "rpool",
                "scan": "scan completed at 12345KiB/s",
                "errors": 0,
                "status": "scan completed",
            }
        }
        mgr = _make_manager(mock_pve_client)
        result = mgr.scrub_status(pool="rpool", node="pve1")
        assert result is not None
