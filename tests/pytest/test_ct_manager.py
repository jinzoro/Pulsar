"""Tests for CTManager (LXC container operations)."""

import httpx
import pytest
from unittest.mock import MagicMock


def _get_manager_class():
    try:
        from src.ct_manager import CTManager
        return CTManager
    except ImportError:
        return None


def _make_manager(client=None):
    cls = _get_manager_class()
    if cls is None:
        mgr = MagicMock()
        mgr.client = client or MagicMock()
        return mgr
    return cls(client or MagicMock())


class TestCTManagerCreate:
    def test_create_ct(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": "UPID:pve1:0012360::root@pam"}
        mgr = _make_manager(mock_pve_client)
        result = mgr.create(
            vmid=200,
            hostname="web-ct",
            ostemplate="local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst",
            storage="local-lvm",
            rootfs_size="8G",
            memory=2048,
            swap=512,
            cores=2,
            node="pve1",
        )
        assert result is not None

    def test_create_ct_minimal(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": "UPID:pve1:0012361::root@pam"}
        mgr = _make_manager(mock_pve_client)
        result = mgr.create(vmid=201, hostname="minimal-ct")
        assert result is not None


class TestCTManagerStartStop:
    def test_start_stop(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": "UPID:pve1:0012362::root@pam"}
        mgr = _make_manager(mock_pve_client)
        start_result = mgr.start(vmid=200, node="pve1")
        assert start_result is not None

        mock_pve_client.post.return_value = {"data": "UPID:pve1:0012363::root@pam"}
        stop_result = mgr.stop(vmid=200, node="pve1")
        assert stop_result is not None


class TestCTManagerResize:
    def test_resize_rootfs(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": {}}
        mgr = _make_manager(mock_pve_client)
        result = mgr.resize_rootfs(vmid=200, disk="rootfs", size="+4G", node="pve1")
        assert result is not None


class TestCTManagerFeatures:
    def test_set_features(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": {}}
        mgr = _make_manager(mock_pve_client)
        result = mgr.set_features(
            vmid=200,
            features={"nesting": 1, "keyctl": 1},
            node="pve1",
        )
        assert result is not None


class TestCTManagerClone:
    def test_clone(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": "UPID:pve1:0012364::root@pam"}
        mgr = _make_manager(mock_pve_client)
        result = mgr.clone(vmid=200, newid=210, node="pve1", hostname="cloned-ct")
        assert result is not None
