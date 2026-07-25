# SPDX-License-Identifier: MIT
# Pulsar - User & ACL Manager

"""Proxmox VE user, group, role, ACL and API-token management."""

from __future__ import annotations

import logging
from typing import Any

from pve_api_client import PVEClient

logger = logging.getLogger(__name__)


class UserACLManager:
    """High-level user, group, role, ACL and token operations.

    Parameters
    ----------
    client:
        An authenticated :class:`PVEClient` instance.
    """

    def __init__(self, client: PVEClient) -> None:
        self._client = client

    # -- users ----------------------------------------------------------------

    def list_users(self) -> list[dict[str, Any]]:
        """List all users."""
        return self._client.get("/api2/json/access/users")  # type: ignore[return-value]

    def create_user(
        self,
        userid: str,
        email: str | None = None,
        groups: list[str] | None = None,
        realm: str = "pve",
        enable: bool = True,
    ) -> dict[str, Any]:
        """Create a new user.

        Parameters
        ----------
        userid:
            Full user ID, e.g. ``jdoe@pve``.
        email:
            Contact email.
        groups:
            List of group names.
        realm:
            Authentication realm.
        enable:
            Whether the user is enabled.
        """
        full_userid = userid if "@" in userid else f"{userid}@{realm}"
        data: dict[str, Any] = {
            "userid": full_userid,
            "enable": 1 if enable else 0,
        }
        if email:
            data["email"] = email
        if groups:
            data["groups"] = ",".join(groups)
        logger.info("Creating user '%s'", full_userid)
        return self._client.post("/api2/json/access/users", data=data)

    def delete_user(self, userid: str) -> dict[str, Any]:
        """Delete a user."""
        logger.info("Deleting user '%s'", userid)
        return self._client.delete(f"/api2/json/access/users/{userid}")

    def set_password(self, userid: str, password: str) -> dict[str, Any]:
        """Set a user password (admin only)."""
        logger.info("Setting password for user '%s'", userid)
        return self._client.put(
            f"/api2/json/access/users/{userid}/password",
            data={"password": password},
        )

    # -- groups ---------------------------------------------------------------

    def list_groups(self) -> list[dict[str, Any]]:
        """List all groups."""
        return self._client.get("/api2/json/access/groups")  # type: ignore[return-value]

    def create_group(self, groupid: str) -> dict[str, Any]:
        """Create a new group."""
        logger.info("Creating group '%s'", groupid)
        return self._client.post("/api2/json/access/groups", data={"groupid": groupid})

    def delete_group(self, groupid: str) -> dict[str, Any]:
        """Delete a group."""
        logger.info("Deleting group '%s'", groupid)
        return self._client.delete(f"/api2/json/access/groups/{groupid}")

    # -- roles ----------------------------------------------------------------

    def list_roles(self) -> list[dict[str, Any]]:
        """List all roles."""
        return self._client.get("/api2/json/access/roles")  # type: ignore[return-value]

    def create_role(self, roleid: str, privileges: list[str]) -> dict[str, Any]:
        """Create a role with the given privileges.

        Parameters
        ----------
        roleid:
            Role identifier.
        privileges:
            List of privilege strings, e.g. ``['VM.Allocate', 'VM.Monitor']``.
        """
        data: dict[str, Any] = {
            "roleid": roleid,
            "privs": ",".join(privileges),
        }
        logger.info("Creating role '%s' with %d privileges", roleid, len(privileges))
        return self._client.post("/api2/json/access/roles", data=data)

    def delete_role(self, roleid: str) -> dict[str, Any]:
        """Delete a role."""
        logger.info("Deleting role '%s'", roleid)
        return self._client.delete(f"/api2/json/access/roles/{roleid}")

    # -- ACLs -----------------------------------------------------------------

    def set_acl(
        self,
        path: str,
        user: str | None = None,
        group: str | None = None,
        role: str = "PVEAuditor",
    ) -> dict[str, Any]:
        """Grant a role to a user or group on a path.

        Parameters
        ----------
        path:
            ACL path, e.g. ``/``, ``/storage/local``, ``/vms/100``.
        user:
            User ID.
        group:
            Group ID.
        role:
            Role to assign.
        """
        data: dict[str, Any] = {"path": path, "role": role}
        if user:
            data["userid"] = user
        if group:
            data["groupid"] = group
        if not user and not group:
            raise ValueError("Provide either user or group")
        logger.info("Setting ACL on '%s' → role '%s'", path, role)
        return self._client.post("/api2/json/access/acl", data=data)

    def remove_acl(
        self, path: str, user: str | None = None, group: str | None = None
    ) -> dict[str, Any]:
        """Remove an ACL entry."""
        data: dict[str, Any] = {"path": path}
        if user:
            data["userid"] = user
        if group:
            data["groupid"] = group
        if not user and not group:
            raise ValueError("Provide either user or group")
        logger.info("Removing ACL on '%s'", path)
        return self._client.delete("/api2/json/access/acl", params=data)

    # -- API tokens -----------------------------------------------------------

    def list_tokens(self, userid: str) -> list[dict[str, Any]]:
        """List API tokens for a user."""
        encoded_userid = userid.replace("/", "%2F")
        return self._client.get(f"/api2/json/access/users/{encoded_userid}/token")  # type: ignore[return-value]

    def create_token(
        self,
        userid: str,
        token_id: str,
        privilege_separation: bool = True,
        expire: int | None = None,
    ) -> dict[str, Any]:
        """Create an API token.

        Parameters
        ----------
        userid:
            Owner user ID, e.g. ``root@pam``.
        token_id:
            Token name.
        privilege_separation:
            Restrict token to a subset of user privileges.
        expire:
            Expiration timestamp (epoch seconds).
        """
        encoded_userid = userid.replace("/", "%2F")
        data: dict[str, Any] = {
            "tokenid": token_id,
            "privsep": 1 if privilege_separation else 0,
        }
        if expire is not None:
            data["expire"] = expire
        logger.info("Creating API token '%s' for user '%s'", token_id, userid)
        return self._client.post(
            f"/api2/json/access/users/{encoded_userid}/token", data=data
        )

    def delete_token(self, userid: str, token_id: str) -> dict[str, Any]:
        """Delete an API token."""
        encoded_userid = userid.replace("/", "%2F")
        logger.info("Deleting API token '%s' for user '%s'", token_id, userid)
        return self._client.delete(
            f"/api2/json/access/users/{encoded_userid}/token/{token_id}"
        )
