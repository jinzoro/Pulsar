"""
SPDX-License-Identifier: MIT
VM performance tuning: hugepages, CPU pinning, NUMA, I/O, ballooning,
and kernel-level tuning.

Provides ``PerformanceManager`` for applying performance optimizations
to KVM virtual machines and the underlying host.
"""

from __future__ import annotations

import glob
import logging
import os
import subprocess
from typing import Any

import libvirt

from kvm_libvirt_client import LibvirtClient, LibvirtError, _wrap_libvirt_error

logger = logging.getLogger(__name__)


class PerformanceError(Exception):
    """Raised when a performance tuning operation fails."""


class PerformanceManager:
    """Host and VM performance tuning.

    Example::

        pm = PerformanceManager()
        pm.setup_hugepages(count_1g=4)
        pm.set_cpu_pin("web01", {"0": "0", "1": "1"}, emulator_pcpu="2-3")
    """

    def __init__(self, client: LibvirtClient | None = None) -> None:
        self._client = client

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _run(cmd: list[str], check: bool = True) -> subprocess.CompletedProcess[str]:
        logger.debug("Running: %s", " ".join(cmd))
        result = subprocess.run(cmd, capture_output=True, text=True, check=False)
        if check and result.returncode != 0:
            raise PerformanceError(
                f"Command failed (rc={result.returncode}): "
                f"{result.stderr.strip() or result.stdout.strip()}"
            )
        return result

    @staticmethod
    def _read_sys(path: str) -> str | None:
        try:
            return open(path).read().strip()
        except (OSError, FileNotFoundError):
            return None

    @staticmethod
    def _write_sys(path: str, value: str) -> None:
        try:
            with open(path, "w") as fh:
                fh.write(value)
        except OSError as exc:
            raise PerformanceError(f"Failed to write {value} to {path}: {exc}") from exc

    # ------------------------------------------------------------------
    # Hugepages
    # ------------------------------------------------------------------

    def setup_hugepages(self, count_2m: int = 0, count_1g: int = 0) -> None:
        """Allocate hugepages on the host.

        Args:
            count_2m: Number of 2 MiB hugepages.
            count_1g: Number of 1 GiB hugepages.
        """
        if count_2m > 0:
            self._write_sys("/proc/sys/vm/nr_hugepages", str(count_2m))
            logger.info("Allocated %d x 2 MiB hugepages", count_2m)
        if count_1g > 0:
            # 1 GiB pages are allocated via hugetlbfs mount + sysfs
            hugetlb_path = "/sys/kernel/mm/hugepages/hugepages-1048576kB"
            self._write_sys(f"{hugetlb_path}/nr_hugepages", str(count_1g))
            logger.info("Allocated %d x 1 GiB hugepages", count_1g)

    def get_hugepages_info(self) -> dict[str, Any]:
        """Return current hugepage allocation statistics.

        Returns:
            Dict with ``total_2m``, ``free_2m``, ``total_1g``,
            ``free_1g``.
        """
        info: dict[str, Any] = {}
        for suffix, label in [("2048kB", "2m"), ("1048576kB", "1g")]:
            path = f"/sys/kernel/mm/hugepages/hugepages-{suffix}"
            total = self._read_sys(f"{path}/nr_hugepages")
            free = self._read_sys(f"{path}/free_hugepages")
            info[f"total_{label}"] = int(total) if total else 0
            info[f"free_{label}"] = int(free) if free else 0
        return info

    # ------------------------------------------------------------------
    # CPU pinning
    # ------------------------------------------------------------------

    def set_cpu_pin(
        self,
        domain: str,
        vcpu_map: dict[str, str],
        emulator_pcpu: str | None = None,
    ) -> None:
        """Pin vCPUs to physical CPUs via libvirt XML.

        Args:
            domain: Domain name.
            vcpu_map: Mapping of ``{vcpu_index: pcpu_list}``, e.g.
                ``{"0": "0", "1": "1"}`` or ``{"0": "0-3"}``.
            emulator_pcpu: CPU set for the emulator/emulatorpin
                (e.g. ``"4-7"``).
        """
        import xml.etree.ElementTree as ET

        client = self._client or LibvirtClient()
        if not client._conn:
            client.connect()
        try:
            dom = client.get_domain(domain)
            xml_desc = dom.XMLDesc(libvirt.VIR_DOMAIN_XML_CONFIG)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc

        root = ET.fromstring(xml_desc)

        # Remove existing cputune
        cputune = root.find("cputune")
        if cputune is not None:
            root.remove(cputune)

        cputune = ET.SubElement(root, "cputune")
        for vcpu_idx, pcpu in vcpu_map.items():
            vcpu_el = ET.SubElement(
                cputune, "vcpupin",
                vcpu=str(vcpu_idx), cpuset=str(pcpu),
            )
        if emulator_pcpu:
            ET.SubElement(cputune, "emulatorpin", cpuset=emulator_pcpu)

        ET.indent(root, space="  ")
        new_xml = ET.tostring(root, encoding="unicode")
        try:
            client.conn.defineXML(new_xml)
            logger.info(
                "Pinned vCPUs for '%s': %s (emulator=%s)",
                domain, vcpu_map, emulator_pcpu,
            )
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc
        finally:
            if self._client is None:
                client.disconnect()

    # ------------------------------------------------------------------
    # NUMA
    # ------------------------------------------------------------------

    def set_numa(
        self,
        domain: str,
        mode: str = "strict",
        node_bind: str | None = None,
    ) -> None:
        """Configure NUMA tuning for a domain.

        Args:
            domain: Domain name.
            mode: ``strict`` or ``interleave``.
            node_bind: NUMA node(s) to bind to (e.g. ``"0"`` or ``"0-1"``).
        """
        import xml.etree.ElementTree as ET

        client = self._client or LibvirtClient()
        if not client._conn:
            client.connect()
        try:
            dom = client.get_domain(domain)
            xml_desc = dom.XMLDesc(libvirt.VIR_DOMAIN_XML_CONFIG)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc

        root = ET.fromstring(xml_desc)

        # Remove existing numatune
        numatune = root.find("numatune")
        if numatune is not None:
            root.remove(numatune)

        numatune = ET.SubElement(root, "numatune")
        mem_el = ET.SubElement(numatune, "memory", mode=mode)
        if node_bind:
            mem_el.set("nodeset", node_bind)

        ET.indent(root, space="  ")
        new_xml = ET.tostring(root, encoding="unicode")
        try:
            client.conn.defineXML(new_xml)
            logger.info("Set NUMA for '%s': mode=%s nodeset=%s", domain, mode, node_bind)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc
        finally:
            if self._client is None:
                client.disconnect()

    # ------------------------------------------------------------------
    # I/O tuning
    # ------------------------------------------------------------------

    def set_io_tuning(
        self,
        domain: str,
        disk: str,
        scheduler: str | None = None,
        cache: str | None = None,
        iothread: bool = False,
        weight: int | None = None,
    ) -> None:
        """Apply I/O tuning parameters to a disk device.

        Args:
            domain: Domain name.
            disk: Target device name (e.g. ``vda``).
            scheduler: I/O scheduler (e.g. ``none``, ``mq-deadline``).
            cache: Cache mode (``none``, ``writethrough``, ``writeback``,
                ``directsync``).
            iothread: Enable I/O thread.
            weight: I/O weight (100–1000).
        """
        import xml.etree.ElementTree as ET

        client = self._client or LibvirtClient()
        if not client._conn:
            client.connect()
        try:
            dom = client.get_domain(domain)
            xml_desc = dom.XMLDesc(libvirt.VIR_DOMAIN_XML_CONFIG)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc

        root = ET.fromstring(xml_dict := xml_desc)
        devices = root.find("devices")

        for disk_el in (devices.findall("disk") if devices is not None else []):
            target = disk_el.find("target")
            if target is not None and target.get("dev") == disk:
                if cache:
                    driver = disk_el.find("driver")
                    if driver is not None:
                        driver.set("cache", cache)
                if iothread:
                    disk_el.set("iothread", "1")
                if weight:
                    blk = ET.SubElement(disk_el, "iotune")
                    ET.SubElement(blk, "weight").text = str(weight)

                # Apply scheduler via sysfs if available
                if scheduler:
                    sysfs_disk = f"/sys/block/{disk}/queue/scheduler"
                    self._write_sys(sysfs_disk, scheduler)
                break

        ET.indent(root, space="  ")
        new_xml = ET.tostring(root, encoding="unicode")
        try:
            client.conn.defineXML(new_xml)
            logger.info(
                "Set I/O tuning for '%s' disk '%s': scheduler=%s cache=%s",
                domain, disk, scheduler, cache,
            )
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc
        finally:
            if self._client is None:
                client.disconnect()

    # ------------------------------------------------------------------
    # Memory ballooning
    # ------------------------------------------------------------------

    def set_balloon(
        self,
        domain: str,
        current: int | None = None,
        min_mb: int | None = None,
        max_mb: int | None = None,
    ) -> None:
        """Configure memory ballooning limits.

        Args:
            domain: Domain name.
            current: Current memory in MiB.
            min_mb: Minimum memory in MiB.
            max_mb: Maximum memory in MiB.
        """
        import xml.etree.ElementTree as ET

        client = self._client or LibvirtClient()
        if not client._conn:
            client.connect()
        try:
            dom = client.get_domain(domain)
            xml_desc = dom.XMLDesc(libvirt.VIR_DOMAIN_XML_CONFIG)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc

        root = ET.fromstring(xml_desc)

        if current is not None:
            cur_el = root.find("currentMemory")
            if cur_el is None:
                cur_el = ET.SubElement(root, "currentMemory", unit="MiB")
            cur_el.text = str(current)

        if min_mb is not None or max_mb is not None:
            # Remove existing memtune
            memtune = root.find("memtune")
            if memtune is not None:
                root.remove(memtune)
            memtune = ET.SubElement(root, "memtune")
            if min_mb is not None:
                ET.SubElement(memtune, "hard_limit", unit="MiB").text = str(min_mb * 4)
            if max_mb is not None:
                ET.SubElement(memtune, "soft_limit", unit="MiB").text = str(max_mb)
            if min_mb is not None:
                ET.SubElement(memtune, "min_guarantee", unit="MiB").text = str(min_mb)

        ET.indent(root, space="  ")
        new_xml = ET.tostring(root, encoding="unicode")
        try:
            client.conn.defineXML(new_xml)
            logger.info(
                "Set balloon for '%s': current=%s min=%s max=%s",
                domain, current, min_mb, max_mb,
            )
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc
        finally:
            if self._client is None:
                client.disconnect()

    # ------------------------------------------------------------------
    # Status / tuning info
    # ------------------------------------------------------------------

    def get_tuning_status(self, domain: str) -> dict[str, Any]:
        """Return the current tuning status of a domain.

        Returns:
            Dict with ``vcpus``, ``memory_mb``, ``current_memory_mb``,
            ``numa``, ``cputune``.
        """
        import xml.etree.ElementTree as ET

        client = self._client or LibvirtClient()
        if not client._conn:
            client.connect()
        try:
            dom = client.get_domain(domain)
            xml_desc = dom.XMLDesc(0)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc
        finally:
            if self._client is None:
                client.disconnect()

        root = ET.fromstring(xml_desc)
        result: dict[str, Any] = {"domain": domain}

        # vCPUs
        vcpu_el = root.find("vcpu")
        if vcpu_el is not None:
            result["vcpus"] = int(vcpu_el.text or 0)

        # Memory
        mem_el = root.find("memory")
        if mem_el is not None:
            result["memory_mb"] = int(mem_el.text or 0)

        cur_el = root.find("currentMemory")
        if cur_el is not None:
            result["current_memory_mb"] = int(cur_el.text or 0)

        # NUMA
        numatune = root.find("numatune")
        if numatune is not None:
            mem = numatune.find("memory")
            result["numa"] = {
                "mode": mem.get("mode") if mem is not None else None,
                "nodeset": mem.get("nodeset") if mem is not None else None,
            }

        # CPU pinning
        cputune = root.find("cputune")
        if cputune is not None:
            pinning = {}
            for vpin in cputune.findall("vcpupin"):
                pinning[vpin.get("vcpu")] = vpin.get("cpuset")
            emupin = cputune.find("emulatorpin")
            result["cputune"] = {
                "vcpupin": pinning,
                "emulatorpin": emupin.get("cpuset") if emupin is not None else None,
            }

        return result

    # ------------------------------------------------------------------
    # Kernel tuning
    # ------------------------------------------------------------------

    def set_kernel_tuning(
        self,
        hugepages: bool = True,
        ksm: bool = False,
        swappiness: int = 10,
        dirty_ratio: int = 10,
    ) -> None:
        """Apply host kernel-level performance tuning.

        Args:
            hugepages: Enable transparent hugepages (madvise) or
                disable entirely.
            ksm: Enable Kernel Same-page Merging.
            swappiness: Kernel swappiness value (0–100).
            dirty_ratio: Percentage of dirty memory before writeback.
        """
        # Hugepages
        thp_path = "/sys/kernel/mm/transparent_hugepage/enabled"
        if hugepages:
            self._write_sys(thp_path, "madvise")
        else:
            self._write_sys(thp_path, "never")

        # KSM
        ksm_paths = {
            "run": "/sys/kernel/mm/ksm/run",
            "pages_to_scan": "/sys/kernel/mm/ksm/pages_to_scan",
            "sleep_millisecs": "/sys/kernel/mm/ksm/sleep_millisecs",
        }
        if os.path.isdir("/sys/kernel/mm/ksm"):
            self._write_sys(ksm_paths["run"], "1" if ksm else "0")

        # Swappiness
        self._write_sys("/proc/sys/vm/swappiness", str(swappiness))

        # Dirty ratio
        self._write_sys("/proc/sys/vm/dirty_ratio", str(dirty_ratio))

        logger.info(
            "Kernel tuning applied: hugepages=%s ksm=%s swappiness=%d dirty_ratio=%d",
            hugepages, ksm, swappiness, dirty_ratio,
        )
