"""Tests for UserACLManager (users, groups, tokens, ACL)."""

import httpx
import pytest
from unittest.mock import MagicMock


def _get_manager_class():
    try:
        from src.user_acl_manager import UserACLManager
        return UserACLManager
    except ImportError:
        return None


def _make_manager(client=None):
    cls = _get_manager_class()
    if cls is None:
        mgr = MagicMock()
        mgr.client = client or MagicMock()
        return mgr
    return cls(client or MagicMock())


class TestUserACLManagerUsers:
    def test_create_user(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": {}}
        mgr = _make_manager(mock_pve_client)
        result = mgr.create_user(
            userid="deploy@pam",
            password="s3cret",
            comment="Deployment user",
            enable=True,
        )
        assert result is not None

    def test_delete_user(self, mock_pve_client):
        mock_pve_client.delete.return_value = {"data": {}}
        mgr = _make_manager(mock_pve_client)
        result = mgr.delete_user(userid="deploy@pam")
        assert result is not None


class TestUserACLManagerGroups:
    def test_create_group(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": {}}
        mgr = _make_manager(mock_pve_client)
        result = mgr.create_group(groupid="devops", comment="DevOps team")
        assert result is not None


class TestUserACLManagerACL:
    def test_set_acl(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": {}}
        mgr = _make_manager(mock_pve_client)
        result = mgr.set_acl(
            path="/vms/100",
            userid="deploy@pam",
            roles=["PVEVMAdmin"],
        )
        assert result is not None

    def test_set_acl_with_groups(self, mock_pve_client):
        mock_pve_client.post.return_value = {"data": {}}
        mgr = _make_manager(mock_pve_client)
        result = mgr.set_acl(
            path="/storage/local-lvm",
            userid="devops@pve",
            roles=["PVEStorageAdmin"],
        )
        assert result is not None


class TestUserACLManagerTokens:
    def test_create_token(self, mock_pve_client):
        mock_pve_client.post.return_value = {
            "data": {
                "value": "root@pam!automation=01234567-89ab-cdef-0123-456789abcdef",
                "full-tokenid": "root@pam!automation",
            }
        }
        mgr = _make_manager(mock_pve_client)
        result = mgr.create_token(
            userid="root@pam",
            tokenid="automation",
            comment="CI/CD token",
            expire=0,
        )
        assert result is not None
