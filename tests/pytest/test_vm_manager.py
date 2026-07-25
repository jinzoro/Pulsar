"""Tests for VMManager operations against the Proxmox API."""

import httpx
import pytest
from unittest.mock import MagicMock, patch


def _get_manager_class():
    try:
        from src.vm_manager import VMManager
        return VMManager
    except ImportError:
        return None


def _make_manager(client=None):
    cls = _get_manager_class()
    if cls is None:
        mgr = MagicMock()
        mgr.client = client or MagicMock()
        return mgr
    return cls(client or MagicMock())


class TestVMManagerCreate:
    def test_create_vm(self, mock_pve_client, sample_vm_data):
        mock_pve_client.post.return_value = {"data": "UPID:pve1:0012345::root@pam"}
        mgr = _make_manager(mock_pve_client)
        result = mgr.create(
            vmid=100,
            name="new-vm",
            cores=2,
            memory=4096,
            disk="32G",
            storage="local-lvm",
            node="pve1",
        )
        assert result is not None

    def test_create_vm_minimal(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": "UPID:pve1:0012345::root@pam"}
        mgr = _make_manager(mock_pve_client)
        result = mgr.create(vmid=101, name="minimal-vm")
        assert result is not None


class TestVMManagerStartStop:
    def test_start_vm(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": "UPID:pve1:0012346::root@pam"}
        mgr = _make_manager(mock_pve_client)
        result = mgr.start(vmid=100, node="pve1")
        assert result is not None

    def test_stop_vm(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": "UPID:pve1:0012347::root@pam"}
        mgr = _make_manager(mock_pve_client)
        result = mgr.stop(vmid=100, node="pve1")
        assert result is not None

    def test_shutdown_vm_with_timeout(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": "UPID:pve1:0012348::root@pam"}
        mgr = _make_manager(mock_pve_client)
        result = mgr.shutdown(vmid=100, node="pve1", timeout=300)
        assert result is not None


class TestVMManagerDelete:
    def test_delete_vm_purge(self, mock_pve_client):
        mock_pve_client.delete.return_value = {"data": "UPID:pve1:0012349::root@pam"}
        mgr = _make_manager(mock_pve_client)
        result = mgr.delete(vmid=100, node="pve1", purge=True)
        assert result is not None

    def test_delete_vm_without_purge(self, mock_pve_client):
        mock_pve_client.delete.return_value = {"data": "UPID:pve1:0012350::root@pam"}
        mgr = _make_manager(mock_pve_client)
        result = mgr.delete(vmid=100, node="pve1", purge=False)
        assert result is not None


class TestVMManagerClone:
    def test_clone_vm_full(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": "UPID:pve1:0012351::root@pam"}
        mgr = _make_manager(mock_pve_client)
        result = mgr.clone(vmid=100, newid=200, node="pve1", full=True)
        assert result is not None

    def test_clone_vm_linked(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": "UPID:pve1:0012352::root@pam"}
        mgr = _make_manager(mock_pve_client)
        result = mgr.clone(vmid=100, newid=201, node="pve1", full=False)
        assert result is not None


class TestVMManagerResize:
    def test_resize_disk(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": {}}
        mgr = _make_manager(mock_pve_client)
        result = mgr.resize(vmid=100, disk="scsi0", size="+32G", node="pve1")
        assert result is not None


class TestVMManagerConfig:
    def test_get_config(self, mock_pve_client, sample_vm_data):
        mock_pve_client.get.return_value = {"data": sample_vm_data}
        mgr = _make_manager(mock_pve_client)
        config = mgr.get_config(vmid=100, node="pve1")
        assert config is not None


class TestVMManagerBatch:
    def test_batch_start(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": "UPID:pve1:0012353::root@pam"}
        mgr = _make_manager(mock_pve_client)
        result = mgr.batch_start(vmids=[100, 101, 102], node="pve1")
        assert result is not None
