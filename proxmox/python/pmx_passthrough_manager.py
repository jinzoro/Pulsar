# SPDX-License-Identifier: MIT
# proxmox-kvm-swissknife - PCI Passthrough Manager

"""Proxmox VE PCI / GPU passthrough management."""

from __future__ import annotations

import logging
import re
from collections import defaultdict
from typing import Any

from pve_api_client import PVEClient

logger = logging.getLogger(__name__)


class PassthroughManager:
    """High-level PCI passthrough operations.

    Parameters
    ----------
    client:
        An authenticated :class:`PVEClient` instance.
    """

    def __init__(self, client: PVEClient) -> None:
        self._client = client

    def list_pci_devices(self, node: str) -> list[dict[str, Any]]:
        """List PCI devices on a node."""
        return self._client.get(f"/api2/json/nodes/{node}/hardware/pci")  # type: ignore[return-value]

    def get_iommu_groups(self, node: str) -> dict[str, list[dict[str, Any]]]:
        """Group PCI devices by their IOMMU group.

        Returns a dict mapping group-id → list of device dicts.
        """
        devices = self.list_pci_devices(node)
        groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
        for dev in devices:
            iommu_group = dev.get("iommu_group", "unknown")
            groups[str(iommu_group)].append(dev)
        return dict(groups)

    def enable_iommu(self, node: str) -> dict[str, Any]:
        """Enable IOMMU on a node by modifying kernel boot parameters.

        This writes ``intel_iommu=on iommu=pt`` (or ``amd_iommu=on``)
        to ``/etc/default/grub`` and updates grub.

        .. warning::
            A **reboot** is required after this operation.
        """
        cmdline = self._client.get(f"/api2/json/nodes/{node}/config")
        current_extra = ""
        if isinstance(cmdle := cmdline.get("cmdline", ""), str):
            current_extra = cmdle

        # Detect CPU vendor
        cpu_info = self._client.get(f"/api2/json/nodes/{node}/status")
        cpu_model = ""
        if isinstance(info := cpu_info.get("cpuinfo", {}), dict):
            cpu_model = info.get("model", "").lower()

        if "intel" in cpu_model:
            iommu_param = "intel_iommu=on"
        elif "amd" in cpu_model:
            iommu_param = "amd_iommu=on"
        else:
            iommu_param = "intel_iommu=on iommu=on"

        target_params = f"{iommu_param} iommu=pt"
        if target_params in current_extra:
            logger.info("IOMMU already enabled on node %s", node)
            return {"status": "already_enabled"}

        new_extra = f"{current_extra} {target_params}".strip()
        logger.info("Enabling IOMMU on node %s: %s", node, target_params)

        # Write grub config and update
        cmd = (
            f"sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"quiet {new_extra}\"/' "
            f"/etc/default/grub && update-grub"
        )
        result = self._client.post(
            f"/api2/json/nodes/{node}/execute",
            data={"command": cmd},
        )
        logger.warning("IOMMU enabled – reboot node %s for changes to take effect", node)
        return {"status": "enabled", "params": target_params, "reboot_required": True, **result}

    def assign_gpu(
        self,
        node: str,
        vmid: int,
        pci_address: str,
        rombar: bool = False,
        x_vga: bool = False,
    ) -> dict[str, Any]:
        """Assign a GPU to a VM via PCI passthrough.

        Parameters
        ----------
        pci_address:
            PCI address, e.g. ``0000:01:00.0``.
        rombar:
            Expose GPU ROM BAR.
        x_vga:
            Enable x-vga (GPU as primary display).
        """
        data: dict[str, Any] = {
            "host": pci_address,
            "rombar": 1 if rombar else 0,
        }
        if x_vga:
            data["x-vga"] = 1

        logger.info("Assigning GPU %s to VM %d on node %s", pci_address, vmid, node)
        result = self._client.post(
            f"/api2/json/nodes/{node}/qemu/{vmid}/hostpci",
            data=data,
        )
        logger.info("GPU %s assigned to VM %d", pci_address, vmid)
        return result

    def assign_pci(self, node: str, vmid: int, pci_address: str) -> dict[str, Any]:
        """Assign a generic PCI device to a VM."""
        logger.info("Assigning PCI device %s to VM %d on node %s", pci_address, vmid, node)
        return self._client.post(
            f"/api2/json/nodes/{node}/qemu/{vmid}/hostpci",
            data={"host": pci_address},
        )

    def verify_passthrough(self, node: str, vmid: int) -> dict[str, Any]:
        """Verify PCI passthrough configuration for a VM.

        Returns a dict with IOMMU status, assigned devices, and any warnings.
        """
        config = self._client.get(f"/api2/json/nodes/{node}/qemu/{vmid}/config")
        assigned: list[dict[str, str]] = []
        for key, value in config.items():
            if key.startswith("hostpci"):
                assigned.append({"key": key, "value": value})

        iommu_groups = self.get_iommu_groups(node)
        iommu_enabled = len(iommu_groups) > 0 and "unknown" not in iommu_groups

        warnings: list[str] = []
        if not iommu_enabled:
            warnings.append("IOMMU may not be enabled on this node")

        for dev in assigned:
            address = dev["value"].split(",")[0] if "," in dev["value"] else dev["value"]
            # Check if device is in a multi-function IOMMU group
            for group_id, devices in iommu_groups.items():
                if len(devices) > 1:
                    for d in devices:
                        if d.get("pci_addr") == address:
                            warnings.append(
                                f"Device {address} shares IOMMU group {group_id} with "
                                f"{len(devices) - 1} other device(s)"
                            )

        return {
            "iommu_enabled": iommu_enabled,
            "assigned_devices": assigned,
            "iommu_groups": len(iommu_groups),
            "warnings": warnings,
        }
