"""
SPDX-License-Identifier: MIT
Fleet deployment: create multiple VMs in parallel from a base image.

Provides ``FleetDeployer`` for cloning VMs concurrently with optional
cloud-init injection and post-deployment scripts.
"""

from __future__ import annotations

import concurrent.futures
import logging
import os
import subprocess
import time
from typing import Any

from kvm_vm_manager import VMManager
from kvm_cloudinit import CloudInitManager
from kvm_libvirt_client import LibvirtClient

logger = logging.getLogger(__name__)


class FleetError(Exception):
    """Raised when a fleet operation fails."""


class FleetDeployer:
    """Deploy and manage fleets of VMs.

    Args:
        client: Optional existing :class:`LibvirtClient`.
        max_workers: Thread-pool size for parallel creation.

    Example::

        fd = FleetDeployer()
        vms = fd.deploy(
            base_image="/images/ubuntu.qcow2",
            count=5,
            name_prefix="web",
            ram_mb=2048,
            vcpus=2,
            network="default",
            wait_ssh=True,
        )
    """

    def __init__(
        self,
        client: LibvirtClient | None = None,
        max_workers: int = 5,
    ) -> None:
        self._client = client
        self._max_workers = max_workers
        self._vm_manager = VMManager(client)
        self._cloud_init = CloudInitManager(client)

    # ------------------------------------------------------------------
    # Deployment
    # ------------------------------------------------------------------

    def deploy(
        self,
        base_image: str,
        count: int,
        name_prefix: str,
        ram_mb: int,
        vcpus: int,
        disk_format: str = "qcow2",
        network: str = "default",
        cloud_init_user: str = "root",
        ssh_keys_file: str | None = None,
        wait_ssh: bool = True,
        post_script: str | None = None,
    ) -> list[dict[str, Any]]:
        """Create a fleet of VMs from a base image.

        Args:
            base_image: Path to the base qcow2 image.
            count: Number of VMs to create.
            name_prefix: Prefix for VM names (``<prefix>-01`` ..).
            ram_mb: Memory per VM in MiB.
            vcpus: vCPUs per VM.
            disk_format: Disk format of the base image.
            network: libvirt network name.
            cloud_init_user: Cloud-init default user.
            ssh_keys_file: Optional SSH keys file for cloud-init.
            wait_ssh: Wait for SSH to become available after start.
            post_script: Shell script to run via SSH after deployment.

        Returns:
            List of dicts with ``name``, ``ip``, ``status`` per VM.
        """
        if not os.path.isfile(base_image):
            raise FleetError(f"Base image not found: {base_image}")

        vm_specs = []
        for i in range(1, count + 1):
            name = f"{name_prefix}-{i:02d}"
            vm_specs.append({
                "index": i,
                "name": name,
                "base_image": base_image,
                "ram_mb": ram_mb,
                "vcpus": vcpus,
                "disk_format": disk_format,
                "network": network,
                "cloud_init_user": cloud_init_user,
                "ssh_keys_file": ssh_keys_file,
                "wait_ssh": wait_ssh,
                "post_script": post_script,
            })

        results: list[dict[str, Any]] = [None] * count  # type: ignore[list-item]

        with concurrent.futures.ThreadPoolExecutor(
            max_workers=self._max_workers,
        ) as executor:
            future_to_idx = {
                executor.submit(self._deploy_single, spec): spec["index"] - 1
                for spec in vm_specs
            }
            for future in concurrent.futures.as_completed(future_to_idx):
                idx = future_to_idx[future]
                try:
                    results[idx] = future.result()
                except Exception as exc:
                    vm_name = vm_specs[idx]["name"]
                    logger.error("Failed to deploy '%s': %s", vm_name, exc)
                    results[idx] = {
                        "name": vm_name,
                        "status": "failed",
                        "error": str(exc),
                    }

        logger.info(
            "Fleet deployment complete: %d/%d VMs succeeded",
            sum(1 for r in results if r and r.get("status") != "failed"),
            count,
        )
        return results  # type: ignore[return-value]

    def _deploy_single(self, spec: dict[str, Any]) -> dict[str, Any]:
        """Deploy a single VM from the fleet spec."""
        name = spec["name"]
        disk_path = f"/var/lib/libvirt/images/{name}.qcow2"
        base = spec["base_image"]

        # Clone base image
        logger.info("Cloning %s -> %s", base, disk_path)
        result = subprocess.run(
            ["qemu-img", "create", "-f", "qcow2", "-b", base, "-F", spec["disk_format"], disk_path],
            capture_output=True, text=True, check=False,
        )
        if result.returncode != 0:
            raise FleetError(f"Failed to clone image for {name}: {result.stderr}")

        # Create cloud-init ISO
        try:
            iso_path = self._cloud_init.create_iso(
                name,
                user=spec["cloud_init_user"],
                ssh_keys_file=spec.get("ssh_keys_file"),
                hostname=name,
            )
        except Exception:
            iso_path = None

        # Define the VM
        self._vm_manager.create(
            name=name,
            ram_mb=spec["ram_mb"],
            vcpus=spec["vcpus"],
            disk_path=disk_path,
            disk_format=spec["disk_format"],
            network=spec["network"],
            cloud_init_iso=iso_path,
        )
        self._vm_manager.set_autostart(name, enabled=True)

        # Start
        self._vm_manager.start(name)

        # Wait for SSH
        ssh_ready = False
        if spec.get("wait_ssh"):
            ssh_ready = self._wait_for_ssh(name, timeout=120)

        # Run post-script
        if spec.get("post_script") and ssh_ready:
            self._run_post_script(name, spec["post_script"])

        return {
            "name": name,
            "disk": disk_path,
            "status": "deployed",
            "ssh_ready": ssh_ready,
        }

    @staticmethod
    def _wait_for_ssh(name: str, timeout: int = 120) -> bool:
        """Wait for SSH to become available on a domain.

        Uses ``virsh domifaddr`` to find the IP, then tries SSH.
        """
        start = time.monotonic()
        while time.monotonic() - start < timeout:
            # Get IP
            result = subprocess.run(
                ["virsh", "domifaddr", name],
                capture_output=True, text=True, check=False,
            )
            ips = []
            for line in result.stdout.splitlines():
                parts = line.split()
                for part in parts:
                    if "." in part and part[0].isdigit():
                        ips.append(part.split("/")[0])
                        break

            if ips:
                ip = ips[0]
                ssh_check = subprocess.run(
                    ["ssh", "-o", "StrictHostKeyChecking=no",
                     "-o", "ConnectTimeout=3", "-o", "BatchMode=yes",
                     f"root@{ip}", "echo ok"],
                    capture_output=True, text=True, check=False,
                )
                if ssh_check.returncode == 0 or "ok" in ssh_check.stdout:
                    logger.info("SSH ready for '%s' at %s", name, ip)
                    return True

            time.sleep(5)

        logger.warning("SSH timeout for '%s' after %ds", name, timeout)
        return False

    @staticmethod
    def _run_post_script(name: str, script: str) -> None:
        """Run a shell script on a VM via virsh."""
        try:
            subprocess.run(
                ["virsh", "qemu-agent-command", name, "--json",
                 '{"execute": "guest-exec",'
                 f'"arguments": {{"path": "/bin/bash",'
                 f'"arg": ["-c", "{script}"], "capture-output": true}}}',
                 ],
                capture_output=True, text=True, check=False,
            )
            logger.info("Post-script executed on '%s'", name)
        except Exception as exc:
            logger.warning("Post-script failed on '%s': %s", name, exc)

    # ------------------------------------------------------------------
    # Fleet management
    # ------------------------------------------------------------------

    def destroy_fleet(self, name_prefix: str) -> None:
        """Stop, undefine, and remove disks for all VMs matching *name_prefix*.

        Args:
            name_prefix: VM name prefix (e.g. ``web`` destroys ``web-01``,
                ``web-02``, etc.).
        """
        client = self._client or LibvirtClient()
        if not client._conn:
            client.connect()
        try:
            domains = client.list_domains(active=True, inactive=True)
            for dom in domains:
                if dom.name().startswith(name_prefix):
                    try:
                        if dom.isActive():
                            self._vm_manager.stop(dom.name(), graceful=False)
                        self._vm_manager.undefine(dom.name(), remove_storage=True)
                        logger.info("Destroyed VM '%s'", dom.name())
                    except Exception as exc:
                        logger.error("Failed to destroy '%s': %s", dom.name(), exc)
        finally:
            if self._client is None:
                client.disconnect()

    def list_fleet(self, name_prefix: str | None = None) -> list[dict[str, Any]]:
        """List VMs, optionally filtered by name prefix.

        Returns:
            List of dicts with ``name``, ``state``, ``vcpus``,
            ``memory_mb``, ``autostart``.
        """
        return self._vm_manager.list_all(active=True, inactive=True)
