# SPDX-License-Identifier: MIT
# proxmox-kvm-swissknife - VM Manager

"""Qemu virtual machine lifecycle management."""

from __future__ import annotations

import logging
from typing import Any

from pve_api_client import PVEClient

logger = logging.getLogger(__name__)


class VMManager:
    """High-level Qemu VM lifecycle operations.

    Parameters
    ----------
    client:
        An authenticated :class:`PVEClient` instance.
    """

    def __init__(self, client: PVEClient) -> None:
        self._client = client

    def create(
        self,
        node: str,
        vmid: int | None = None,
        name: str = "vm",
        cores: int = 2,
        memory: int = 2048,
        disk_size: str = "32G",
        storage: str = "local-lvm",
        os_type: str = "l26",
        bios: str = "seabios",
        machine: str = "q35",
        scsihw: str = "virtio-scsi-single",
        net_model: str = "virtio",
        net_bridge: str = "vmbr0",
        iso: str | None = None,
        template: int | None = None,
        cloud_init: bool = False,
        cpu_type: str = "host",
    ) -> dict[str, Any]:
        """Create a new Qemu virtual machine.

        Parameters
        ----------
        node:
            Target Proxmox node name.
        vmid:
            VM ID – auto-assigned if *None*.
        name:
            Name of the VM.
        cores:
            Number of CPU cores.
        memory:
            Memory in MiB.
        disk_size:
            Root disk size, e.g. ``32G``.
        storage:
            Target storage for the disk.
        os_type:
            Guest OS type (LSCPU flag).
        bios:
            BIOS implementation (``seabios`` or ``ovmf``).
        machine:
            Machine type.
        scsihw:
            SCSI controller model.
        net_model:
            Network adapter model.
        net_bridge:
            Bridge to attach the NIC to.
        iso:
            ISO image to attach as IDE cdrom.
        template:
            VMID of a template to base the VM on.
        cloud_init:
            Enable CloudInit drive.
        cpu_type:
            CPU emulation type.

        Returns
        -------
        dict
            API response containing the new VMID.
        """
        data: dict[str, Any] = {
            "name": name,
            "cores": cores,
            "memory": memory,
            "ostype": os_type,
            "bios": bios,
            "machine": machine,
            "scsihw": scsihw,
            "cpu": cpu_type,
        }
        if vmid is not None:
            data["vmid"] = vmid

        data["scsi0"] = f"{storage}:size={disk_size}"
        data["net0"] = f"{net_model},bridge={net_bridge}"

        if iso:
            data["ide2"] = f"{iso},media=cdrom"
        if template is not None:
            data["template"] = template
        if cloud_init:
            data["ide0"] = f"cloudinit" if "cloudinit" in storage else f"{storage}:cloudinit"

        logger.info("Creating VM '%s' on node %s", name, node)
        result = self._client.vm_create(node, data)
        logger.info("VM created: %s", result)
        return result

    def start(self, node: str, vmid: int) -> dict[str, Any]:
        """Start a VM."""
        logger.info("Starting VM %d on node %s", vmid, node)
        return self._client.vm_start(node, vmid)

    def stop(self, node: str, vmid: int) -> dict[str, Any]:
        """Force-stop a VM."""
        logger.info("Stopping VM %d on node %s", vmid, node)
        return self._client.vm_stop(node, vmid)

    def shutdown(self, node: str, vmid: int, timeout: int = 30, force: bool = False) -> dict[str, Any]:
        """Gracefully shut down a VM.

        Parameters
        ----------
        node:
            Node name.
        vmid:
            VM ID.
        timeout:
            Seconds to wait before a forced stop.
        force:
            If *True*, issue a stop instead of ACPI shutdown.
        """
        if force:
            logger.info("Force-stopping VM %d on node %s", vmid, node)
            return self._client.vm_stop(node, vmid)
        logger.info("Shutting down VM %d on node %s (timeout=%ds)", vmid, node, timeout)
        return self._client.vm_shutdown(node, vmid, timeout=timeout)

    def reboot(self, node: str, vmid: int, timeout: int = 30) -> dict[str, Any]:
        """Reboot a VM via shutdown + start."""
        logger.info("Rebooting VM %d on node %s", vmid, node)
        self._client.vm_shutdown(node, vmid, timeout=timeout)
        return self._client.vm_start(node, vmid)

    def suspend(self, node: str, vmid: int) -> dict[str, Any]:
        """Suspend (pause) a VM."""
        logger.info("Suspending VM %d on node %s", vmid, node)
        return self._client.post(f"/api2/json/nodes/{node}/qemu/{vmid}/status/suspend")

    def resume(self, node: str, vmid: int) -> dict[str, Any]:
        """Resume a suspended VM."""
        logger.info("Resuming VM %d on node %s", vmid, node)
        return self._client.post(f"/api2/json/nodes/{node}/qemu/{vmid}/status/resume")

    def delete(self, node: str, vmid: int, purge: bool = False) -> dict[str, Any]:
        """Delete a VM, optionally purging HA and replication configs.

        Parameters
        ----------
        purge:
            When *True* the VM is purged from all configurations.
        """
        logger.info("Deleting VM %d on node %s (purge=%s)", vmid, node, purge)
        params: dict[str, Any] = {}
        if purge:
            params["purge"] = 1
        if params:
            return self._client.post(
                f"/api2/json/nodes/{node}/qemu/{vmid}", data=params
            )
        return self._client.vm_delete(node, vmid)

    def clone(
        self,
        node: str,
        vmid: int,
        new_vmid: int | None = None,
        name: str | None = None,
        full: bool = True,
        target_node: str | None = None,
        target_storage: str | None = None,
    ) -> dict[str, Any]:
        """Clone a VM.

        Parameters
        ----------
        new_vmid:
            VMID for the clone – auto-assigned if *None*.
        name:
            Name of the new VM.
        full:
            Full clone (True) or linked clone (False).
        target_node:
            Target node for the clone.
        target_storage:
            Target storage for the clone disks.
        """
        data: dict[str, Any] = {"newid": new_vmid} if new_vmid else {}
        if name:
            data["name"] = name
        data["full"] = 1 if full else 0
        if target_node:
            data["target"] = target_node
        if target_storage:
            data["storage"] = target_storage

        logger.info("Cloning VM %d on node %s → new VMID %s", vmid, node, new_vmid)
        return self._client.vm_clone(node, vmid, data)

    def rename(self, node: str, vmid: int, new_name: str) -> dict[str, Any]:
        """Rename a VM."""
        logger.info("Renaming VM %d on node %s to '%s'", vmid, node, new_name)
        return self._client.put(
            f"/api2/json/nodes/{node}/qemu/{vmid}", data={"name": new_name}
        )

    def resize_disk(self, node: str, vmid: int, disk: str, size: str) -> dict[str, Any]:
        """Resize a VM disk.

        Parameters
        ----------
        disk:
            Disk identifier, e.g. ``scsi0``.
        size:
            New absolute size, e.g. ``64G``.
        """
        logger.info("Resizing disk %s of VM %d on node %s to %s", disk, vmid, node, size)
        return self._client.put(
            f"/api2/json/nodes/{node}/qemu/{vmid}/resize",
            data={"disk": disk, "size": size},
        )

    def set_cpu(
        self,
        node: str,
        vmid: int,
        cores: int | None = None,
        sockets: int | None = None,
        cpu_type: str | None = None,
    ) -> dict[str, Any]:
        """Update CPU settings."""
        data: dict[str, Any] = {}
        if cores is not None:
            data["cores"] = cores
        if sockets is not None:
            data["sockets"] = sockets
        if cpu_type is not None:
            data["cpu"] = cpu_type
        logger.info("Updating CPU config for VM %d on node %s: %s", vmid, node, data)
        return self._client.put(f"/api2/json/nodes/{node}/qemu/{vmid}", data=data)

    def set_memory(
        self, node: str, vmid: int, memory: int | None = None, balloon: int | None = None
    ) -> dict[str, Any]:
        """Update memory settings."""
        data: dict[str, Any] = {}
        if memory is not None:
            data["memory"] = memory
        if balloon is not None:
            data["balloon"] = balloon
        logger.info("Updating memory config for VM %d on node %s: %s", vmid, node, data)
        return self._client.put(f"/api2/json/nodes/{node}/qemu/{vmid}", data=data)

    def set_boot_order(self, node: str, vmid: int, order: str) -> dict[str, Any]:
        """Set boot device order.

        Parameters
        ----------
        order:
            Boot order string, e.g. ``scsi0,ide2,net0``.
        """
        logger.info("Setting boot order for VM %d on node %s: %s", vmid, node, order)
        return self._client.put(
            f"/api2/json/nodes/{node}/qemu/{vmid}", data={"boot": order}
        )

    def set_description(self, node: str, vmid: int, description: str) -> dict[str, Any]:
        """Set the VM description."""
        logger.info("Setting description for VM %d on node %s", vmid, node)
        return self._client.put(
            f"/api2/json/nodes/{node}/qemu/{vmid}", data={"description": description}
        )

    def get_config(self, node: str, vmid: int) -> dict[str, Any]:
        """Return the full configuration of a VM."""
        return self._client.get(f"/api2/json/nodes/{node}/qemu/{vmid}/config")

    def batch_operation(
        self, node: str, vmids: list[int], operation: str, **kwargs: Any
    ) -> dict[str, dict[str, Any]]:
        """Execute the same operation on multiple VMs.

        Parameters
        ----------
        vmids:
            List of VM IDs.
        operation:
            One of ``start``, ``stop``, ``shutdown``, ``delete``.
        **kwargs:
            Extra keyword arguments forwarded to the individual method.

        Returns
        -------
        dict
            Mapping of VMID → result dict.
        """
        ops = {
            "start": self.start,
            "stop": self.stop,
            "shutdown": self.shutdown,
            "delete": self.delete,
        }
        func = ops.get(operation)
        if func is None:
            raise ValueError(f"Unsupported operation: {operation!r}. Choose from {list(ops)}")

        results: dict[str, dict[str, Any]] = {}
        for vmid in vmids:
            try:
                results[str(vmid)] = func(node, vmid, **kwargs)  # type: ignore[misc]
            except Exception as exc:
                logger.error("Operation %s on VM %d failed: %s", operation, vmid, exc)
                results[str(vmid)] = {"error": str(exc)}
        return results
