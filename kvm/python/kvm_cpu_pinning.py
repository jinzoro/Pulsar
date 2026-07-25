"""
SPDX-License-Identifier: MIT
CPU topology detection and vCPU-to-pCPU pinning.

Provides ``CPUPinning`` for detecting the host CPU topology and
generating / applying libvirt ``cputune`` and ``numatune`` XML.
"""

from __future__ import annotations

import glob
import logging
import os
import re
import subprocess
from typing import Any

import libvirt
import xml.etree.ElementTree as ET

from kvm_libvirt_client import LibvirtClient, LibvirtError, _wrap_libvirt_error

logger = logging.getLogger(__name__)


class CPUError(Exception):
    """Raised when a CPU pinning operation fails."""


class CPUPinning:
    """CPU topology detection and vCPU pinning.

    Example::

        cp = CPUPinning()
        topo = cp.detect_topology()
        print(topo)
        xml = cp.generate_cputune_xml({"0": "0", "1": "1"})
        cp.apply_pinning("web01", {"0": "0", "1": "1"}, emulator_pcpu="2-3")
    """

    SYSFS_CPU = "/sys/devices/system/cpu"

    # ------------------------------------------------------------------
    # Topology detection
    # ------------------------------------------------------------------

    def detect_topology(self) -> dict[str, Any]:
        """Detect the host CPU topology.

        Returns:
            Dict with ``sockets``, ``cores_per_socket``,
            ``threads_per_core``, ``total_cpus``, ``online_cpus``,
            ``sockets_topology``, ``numa_nodes``, ``numa_topology``.
        """
        result: dict[str, Any] = {}
        online = self._read_sys(f"{self.SYSFS_CPU}/online")
        result["online_cpus"] = online
        result["total_cpus"] = self._count_cpu_dirs()

        # Per-socket topology
        sockets: dict[str, list[int]] = {}
        for cpu_dir in sorted(glob.glob(f"{self.SYSFS_CPU}/cpu[0-9]*")):
            cpu_name = os.path.basename(cpu_dir)
            if not re.match(r"cpu\d+$", cpu_name):
                continue
            cpu_id = int(cpu_name.replace("cpu", ""))

            package_id = self._read_sys(f"{cpu_dir}/topology/physical_package_id")
            core_id = self._read_sys(f"{cpu_dir}/topology/core_id")
            if package_id is not None:
                sockets.setdefault(package_id, []).append(cpu_id)

        result["sockets"] = len(sockets)
        result["sockets_topology"] = {
            pid: sorted(cpus) for pid, cpus in sockets.items()
        }

        # Cores and threads
        first_socket_cpus = next(iter(sockets.values()), [])
        core_ids: set[str] = set()
        for cpu_id in first_socket_cpus:
            core_id = self._read_sys(
                f"{self.SYSFS_CPU}/cpu{cpu_id}/topology/core_id"
            )
            if core_id:
                core_ids.add(core_id)

        if first_socket_cpus:
            result["cores_per_socket"] = len(core_ids)
            # Threads per core: count CPUs sharing the same core_id
            core_map: dict[str, int] = {}
            for cpu_id in first_socket_cpus:
                cid = self._read_sys(
                    f"{self.SYSFS_CPU}/cpu{cpu_id}/topology/core_id"
                )
                if cid:
                    core_map[cid] = core_map.get(cid, 0) + 1
            result["threads_per_core"] = max(core_map.values()) if core_map else 1
        else:
            result["cores_per_socket"] = 0
            result["threads_per_core"] = 1

        # NUMA nodes
        numa_nodes = self._detect_numa_nodes()
        result["numa_nodes"] = len(numa_nodes)
        result["numa_topology"] = numa_nodes

        return result

    def _detect_numa_nodes(self) -> dict[str, list[int]]:
        """Return NUMA node to CPU mapping."""
        nodes: dict[str, list[int]] = {}
        for node_dir in sorted(glob.glob("/sys/devices/system/node/node[0-9]*")):
            node_name = os.path.basename(node_dir).replace("node", "")
            cpulist = self._read_sys(f"{node_dir}/cpulist")
            if cpulist:
                nodes[node_name] = self._expand_cpulist(cpulist)
        return nodes

    @staticmethod
    def _expand_cpulist(cpuset: str) -> list[int]:
        """Expand a CPU set string like ``0-3,8`` into a list of ints."""
        result: list[int] = []
        for part in cpuset.split(","):
            part = part.strip()
            if "-" in part:
                start, end = part.split("-", 1)
                result.extend(range(int(start), int(end) + 1))
            elif part.isdigit():
                result.append(int(part))
        return sorted(result)

    @staticmethod
    def _count_cpu_dirs() -> int:
        count = 0
        for entry in os.listdir(CPUPinning.SYSFS_CPU):
            if re.match(r"cpu\d+$", entry):
                count += 1
        return count

    @staticmethod
    def _read_sys(path: str) -> str | None:
        try:
            return open(path).read().strip()
        except (OSError, FileNotFoundError):
            return None

    # ------------------------------------------------------------------
    # XML generation
    # ------------------------------------------------------------------

    def generate_cputune_xml(self, vcpu_map: dict[str, str]) -> str:
        """Generate ``<cputune>`` XML for the given vCPU-to-pCPU mapping.

        Args:
            vcpu_map: ``{vcpu_index: pcpu_set}``, e.g.
                ``{"0": "0", "1": "1", "2": "2-3"}``.

        Returns:
            XML string of the ``<cputune>`` element.
        """
        root = ET.Element("cputune")
        for vcpu, pcpu in vcpu_map.items():
            ET.SubElement(root, "vcpupin", vcpu=str(vcpu), cpuset=str(pcpu))
        ET.indent(root, space="  ")
        return ET.tostring(root, encoding="unicode")

    def generate_numatune_xml(
        self,
        mode: str = "strict",
        nodeset: str | None = None,
    ) -> str:
        """Generate ``<numatune>`` XML.

        Args:
            mode: ``strict`` or ``interleave``.
            nodeset: NUMA node set string (e.g. ``"0"`` or ``"0-1"``).

        Returns:
            XML string of the ``<numatune>`` element.
        """
        root = ET.Element("numatune")
        mem = ET.SubElement(root, "memory", mode=mode)
        if nodeset:
            mem.set("nodeset", nodeset)
        ET.indent(root, space="  ")
        return ET.tostring(root, encoding="unicode")

    # ------------------------------------------------------------------
    # Apply / query
    # ------------------------------------------------------------------

    def apply_pinning(
        self,
        domain: str,
        vcpu_map: dict[str, str],
        emulator_pcpu: str | None = None,
    ) -> None:
        """Apply vCPU pinning and optional NUMA settings to a domain.

        Args:
            domain: Domain name.
            vcpu_map: ``{vcpu_index: pcpu_set}``.
            emulator_pcpu: CPU set for the emulator thread.
        """
        client = LibvirtClient()
        client.connect()
        try:
            dom = client.get_domain(domain)
            xml_desc = dom.XMLDesc(libvirt.VIR_DOMAIN_XML_CONFIG)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc
        finally:
            client.disconnect()

        root = ET.fromstring(xml_desc)

        # Remove existing cputune
        old_cputune = root.find("cputune")
        if old_cputune is not None:
            root.remove(old_cputune)

        # Add new cputune
        cputune = ET.Element("cputune")
        for vcpu, pcpu in vcpu_map.items():
            ET.SubElement(cputune, "vcpupin", vcpu=str(vcpu), cpuset=str(pcpu))
        if emulator_pcpu:
            ET.SubElement(cputune, "emulatorpin", cpuset=emulator_pcpu)
        root.insert(root.index(root.find("vcpu")) + 1, cputune)

        ET.indent(root, space="  ")
        new_xml = ET.tostring(root, encoding="unicode")

        client2 = LibvirtClient()
        client2.connect()
        try:
            client2.conn.defineXML(new_xml)
            logger.info(
                "Applied CPU pinning to '%s': %s (emulator=%s)",
                domain, vcpu_map, emulator_pcpu,
            )
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc
        finally:
            client2.disconnect()

    def get_current_pinning(self, domain: str) -> dict[str, Any]:
        """Return the current CPU pinning configuration for a domain.

        Returns:
            Dict with ``vcpupin`` mapping and ``emulatorpin``.
        """
        client = LibvirtClient()
        client.connect()
        try:
            dom = client.get_domain(domain)
            xml_desc = dom.XMLDesc(0)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc
        finally:
            client.disconnect()

        root = ET.fromstring(xml_desc)
        cputune = root.find("cputune")
        if cputune is None:
            return {"vcpupin": {}, "emulatorpin": None}

        vcpupin: dict[str, str] = {}
        for pin in cputune.findall("vcpupin"):
            vcpupin[pin.get("vcpu", "")] = pin.get("cpuset", "")

        emupin = cputune.find("emulatorpin")
        return {
            "vcpupin": vcpupin,
            "emulatorpin": emupin.get("cpuset") if emupin is not None else None,
        }
