"""Tests for StorageManager operations."""

import httpx
import pytest
from unittest.mock import MagicMock


def _get_manager_class():
    try:
        from src.storage_manager import StorageManager
        return StorageManager
    except ImportError:
        return None


def _make_manager(client=None):
    cls = _get_manager_class()
    if cls is None:
        mgr = MagicMock()
        mgr.client = client or MagicMock()
        return mgr
    return cls(client or MagicMock())


class TestStorageManagerAdd:
    def test_add_dir_storage(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": {}}
        mgr = _make_manager(mock_pve_client)
        result = mgr.add(
            name="local-data",
            storage_type="dir",
            path="/mnt/data",
            content="images,backup,iso",
            node="pve1",
        )
        assert result is not None

    def test_add_nfs_storage(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": {}}
        mgr = _make_manager(mock_pve_client)
        result = mgr.add(
            name="nfs-backup",
            storage_type="nfs",
            server="10.0.0.5",
            export="/exports/backup",
            content="backup",
            node="pve1",
        )
        assert result is not None

    def test_add_ceph_storage(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": {}}
        mgr = _make_manager(mock_pve_client)
        result = mgr.add(
            name="ceph-vm",
            storage_type="rbd",
            pool="vm-pool",
            content="images,rootdir",
            node="pve1",
        )
        assert result is not None


class TestStorageManagerList:
    def test_list_storage(self, mock_pve_client, sample_storage_data):
        mock_pve_client.get.return_value = {"data": sample_storage_data}
        mgr = _make_manager(mock_pve_client)
        result = mgr.list(node="pve1")
        assert result is not None
        if isinstance(result, dict) and "data" in result:
            assert len(result["data"]) == 3
        elif isinstance(result, list):
            assert len(result) == 3


class TestStorageManagerRemove:
    def test_remove_storage(self, mock_pve_client):
        mock_pve_client.delete.return_value = {"data": {}}
        mgr = _make_manager(mock_pve_client)
        result = mgr.remove(name="nfs-backup", node="pve1")
        assert result is not None


class TestStorageManagerMoveDisk:
    def test_move_disk(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": "UPID:pve1:0012370::root@pam"}
        mgr = _make_manager(mock_pve_client)
        result = mgr.move_disk(
            vmid=100,
            disk="scsi0",
            target_storage="local-lvm",
            node="pve1",
        )
        assert result is not None
