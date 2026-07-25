# SPDX-License-Identifier: MIT
# proxmox-kvm-swissknife - Template Manager

"""Proxmox VE VM template lifecycle management."""

from __future__ import annotations

import logging
from typing import Any

from pve_api_client import PVEClient

logger = logging.getLogger(__name__)


class TemplateManager:
    """High-level template operations.

    Parameters
    ----------
    client:
        An authenticated :class:`PVEClient` instance.
    """

    def __init__(self, client: PVEClient) -> None:
        self._client = client

    def convert_to_template(self, node: str, vmid: int) -> dict[str, Any]:
        """Convert an existing VM into a template.

        .. warning::
            The VM must be **stopped** before conversion.
        """
        logger.info("Converting VM %d on node %s to template", vmid, node)
        result = self._client.post(f"/api2/json/nodes/{node}/qemu/{vmid}/template")
        logger.info("VM %d converted to template", vmid)
        return result

    def list_templates(self, node: str | None = None) -> list[dict[str, Any]]:
        """List available VM templates.

        Parameters
        ----------
        node:
            If provided, list templates on that node only.
        """
        templates: list[dict[str, Any]] = []

        if node:
            nodes = [{"node": node}]
        else:
            nodes = self._client.nodes()

        for node_info in nodes:
            n = node_info["node"]
            vms = self._client.vm_list(n)
            for vm in vms:
                if vm.get("template") == 1:
                    vm["node"] = n
                    templates.append(vm)

        return templates

    def clone_from_template(
        self,
        template_vmid: int,
        new_vmid: int | None = None,
        name: str | None = None,
        full: bool = True,
        target_node: str | None = None,
        target_storage: str | None = None,
    ) -> dict[str, Any]:
        """Clone a VM from a template.

        Parameters
        ----------
        template_vmid:
            Template VM ID.
        new_vmid:
            VM ID for the clone – auto-assigned if *None*.
        name:
            Name of the new VM.
        full:
            Full clone (True) or linked clone (False).
        target_node:
            Target node for the clone.
        target_storage:
            Target storage for the clone disks.
        """
        # Find which node hosts the template
        templates = self.list_templates()
        source_node = None
        for t in templates:
            if t.get("vmid") == template_vmid:
                source_node = t.get("node")
                break
        if not source_node:
            # Fall back to first node
            nodes = self._client.nodes()
            source_node = nodes[0]["node"] if nodes else None
        if not source_node:
            raise RuntimeError(f"Cannot find template VM {template_vmid}")

        from pmx_vm_manager import VMManager

        vm_mgr = VMManager(self._client)
        logger.info("Cloning template VM %d → new VM (name=%s)", template_vmid, name)
        return vm_mgr.clone(
            node=source_node,
            vmid=template_vmid,
            new_vmid=new_vmid,
            name=name,
            full=full,
            target_node=target_node,
            target_storage=target_storage,
        )

    def delete_template(self, node: str, vmid: int) -> dict[str, Any]:
        """Delete a template (must be a template, not a running VM).

        .. warning::
            This permanently removes the template and all its disks.
        """
        logger.warning("Deleting template VM %d on node %s", vmid, node)
        return self._client.vm_delete(node, vmid)

    def update_template(
        self,
        node: str,
        vmid: int,
        description: str | None = None,
    ) -> dict[str, Any]:
        """Update template metadata (description)."""
        data: dict[str, Any] = {}
        if description is not None:
            data["description"] = description
        if not data:
            raise ValueError("At least one parameter must be provided")
        logger.info("Updating template %d on node %s", vmid, node)
        return self._client.put(f"/api2/json/nodes/{node}/qemu/{vmid}", data=data)
