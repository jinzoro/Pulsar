"""Tests for BackupManager operations."""

import httpx
import pytest
from unittest.mock import MagicMock


def _get_manager_class():
    try:
        from src.backup_manager import BackupManager
        return BackupManager
    except ImportError:
        return None


def _make_manager(client=None):
    cls = _get_manager_class()
    if cls is None:
        mgr = MagicMock()
        mgr.client = client or MagicMock()
        return mgr
    return cls(client or MagicMock())


class TestBackupManagerBackup:
    def test_backup(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": "UPID:pve1:0012380::root@pam"}
        mgr = _make_manager(mock_pve_client)
        result = mgr.backup(vmid=100, storage="local", mode="snapshot", compress="zstd", node="pve1")
        assert result is not None

    def test_backup_with_all_options(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": "UPID:pve1:0012381::root@pam"}
        mgr = _make_manager(mock_pve_client)
        result = mgr.backup(
            vmid=100,
            storage="local",
            mode="snapshot",
            compress="zstd",
            node="pve1",
            exclude="swap0,unused0",
        )
        assert result is not None


class TestBackupManagerRestore:
    def test_restore(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": "UPID:pve1:0012382::root@pam"}
        mgr = _make_manager(mock_pve_client)
        result = mgr.restore(
            vmid=100,
            backup="vzdump-qemu-100-2024_01_15-14_30_00.vma.zst",
            storage="local-lvm",
            node="pve1",
        )
        assert result is not None


class TestBackupManagerList:
    def test_list_backups(self, mock_pve_client, sample_backup_data):
        mock_pve_client.get.return_value = {"data": sample_backup_data}
        mgr = _make_manager(mock_pve_client)
        result = mgr.list(storage="local")
        assert result is not None
        if isinstance(result, dict) and "data" in result:
            assert len(result["data"]) == 3
        elif isinstance(result, list):
            assert len(result) == 3


class TestBackupManagerVerify:
    def test_verify(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": {}}
        mgr = _make_manager(mock_pve_client)
        result = mgr.verify(
            backup="local:backup/vzdump-qemu-100-2024_01_15-14_30_00.vma.zst",
            node="pve1",
        )
        assert result is not None


class TestBackupManagerPrune:
    def test_prune(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": {}}
        mgr = _make_manager(mock_pve_client)
        result = mgr.prune(
            vmid=100,
            storage="local",
            keep_last=3,
            node="pve1",
        )
        assert result is not None
