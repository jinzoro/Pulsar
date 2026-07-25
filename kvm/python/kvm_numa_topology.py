"""
SPDX-License-Identifier: MIT
Host and VM NUMA topology detection and configuration.

Provides ``NUMATopology`` for inspecting host NUMA nodes, mapping VM
memory to specific host nodes, and querying existing VM NUMA layouts.
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


class NUMAError(Exception):
    """Raised when a NUMA operation fails."""


class NUMATopology:
    """NUMA topology management for KVM hosts and VMs.

    Example::

        numa = NUMATopology()
        host = numa.detect_host_numa()
        print(host["nodes"])
        numa.map_vm_numa("web01", host_node=0, memory_mb=4096)
    """

    SYSFS_NODE = "/sys/devices/system/node"

    # ------------------------------------------------------------------
    # Host NUMA detection
    # ------------------------------------------------------------------

    def detect_host_numa(self) -> dict[str, Any]:
        """Detect the host NUMA topology.

        Returns:
            Dict with ``node_count``, ``nodes`` (list of per-node info),
            ``total_memory_mb``, ``cpu_count``.
        """
        nodes = self.get_numa_nodes()
        total_mem = sum(n.get("memory_mb", 0) for n in nodes)
        return {
            "node_count": len(nodes),
            "nodes": nodes,
            "total_memory_mb": total_mem,
            "cpu_count": sum(len(n.get("cpus", [])) for n in nodes),
        }

    def get_numa_nodes(self) -> list[dict[str, Any]]:
        """Return detailed info per NUMA node.

        Returns:
            List of dicts with ``id``, ``cpus``, ``memory_mb``,
            ``free_memory_mb``, ``distance``.
        """
        nodes: list[dict[str, Any]] = []
        for node_dir in sorted(glob.glob(f"{self.SYSFS_NODE}/node[0-9]*")):
            node_name = os.path.basename(node_dir).replace("node", "")
            node_id = int(node_name)

            # CPUs
            cpulist = self._read_sys(f"{node_dir}/cpulist")
            cpus = self._expand_cpulist(cpulist) if cpulist else []

            # Memory
            meminfo = self._parse_meminfo(f"{node_dir}/meminfo")
            total_kb = meminfo.get("MemTotal", 0)
            free_kb = meminfo.get("MemFree", 0)

            # Distance
            dist_file = f"{node_dir}/distance"
            distances = []
            if os.path.isfile(dist_file):
                content = self._read_sys(dist_file)
                if content:
                    distances = [int(x) for x in content.split() if x.isdigit()]

            nodes.append({
                "id": node_id,
                "cpus": cpus,
                "memory_mb": total_kb // 1024,
                "free_memory_mb": free_kb // 1024,
                "distance": distances,
            })

        return nodes

    @staticmethod
    def _read_sys(path: str) -> str | None:
        try:
            return open(path).read().strip()
        except (OSError, FileNotFoundError):
            return None

    @staticmethod
    def _expand_cpulist(cpuset: str) -> list[int]:
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
    def _parse_meminfo(path: str) -> dict[str, int]:
        info: dict[str, int] = {}
        try:
            for line in open(path):
                parts = line.split()
                if len(parts) >= 2:
                    key = parts[0].rstrip(":")
                    try:
                        info[key] = int(parts[1])
                    except ValueError:
                        pass
        except (OSError, FileNotFoundError):
            pass
        return info

    # ------------------------------------------------------------------
    # VM NUMA mapping
    # ------------------------------------------------------------------

    def map_vm_numa(
        self,
        domain: str,
        host_node: int,
        vm_node: int = 0,
        memory_mb: int | None = None,
        mode: str = "strict",
    ) -> None:
        """Map a VM's NUMA node to a specific host NUMA node.

        This modifies the domain XML to add ``<numatune>`` and
        ``<memory>`` NUMA cell definitions.

        Args:
            domain: Domain name.
            host_node: Host NUMA node ID.
            vm_node: VM NUMA node ID (default 0).
            memory_mb: Memory for this VM node in MiB.
            mode: NUMA mode (``strict`` or ``interleave``).
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

        # Update numatune
        numatune = root.find("numatune")
        if numatune is not None:
            root.remove(numatune)
        numatune = ET.SubElement(root, "numatune")
        ET.SubElement(
            numatune, "memory",
            mode=mode,
            nodeset=str(host_node),
        )

        # Update memory NUMA cells (within <cpu> or as top-level <numa>)
        cpu_el = root.find("cpu")
        if cpu_el is None:
            cpu_el = ET.SubElement(root, "cpu")

        numa = cpu_el.find("numa")
        if numa is not None:
            cpu_el.remove(numa)
        numa = ET.SubElement(cpu_el, "numa")

        mem_attr: dict[str, str] = {
            "id": str(vm_node),
            "cpus": "0",
            "memory": str(memory_mb or 0),
        }
        ET.SubElement(numa, "cell", unit="MiB", **mem_attr)

        ET.indent(root, space="  ")
        new_xml = ET.tostring(root, encoding="unicode")

        client2 = LibvirtClient()
        client2.connect()
        try:
            client2.conn.defineXML(new_xml)
            logger.info(
                "Mapped VM '%s' NUMA node %d -> host node %d (%s MiB, mode=%s)",
                domain, vm_node, host_node, memory_mb, mode,
            )
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc
        finally:
            client2.disconnect()

    def get_vm_numa(self, domain: str) -> dict[str, Any]:
        """Return the NUMA configuration of a domain.

        Returns:
            Dict with ``numatune`` and ``cells`` info.
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
        result: dict[str, Any] = {"domain": domain}

        numatune = root.find("numatune")
        if numatune is not None:
            mem = numatune.find("memory")
            result["numatune"] = {
                "mode": mem.get("mode") if mem is not None else None,
                "nodeset": mem.get("nodeset") if mem is not None else None,
            }
        else:
            result["numatune"] = None

        cpu_el = root.find("cpu")
        cells: list[dict[str, str]] = []
        if cpu_el is not None:
            numa = cpu_el.find("numa")
            if numa is not None:
                for cell in numa.findall("cell"):
                    cells.append({
                        "id": cell.get("id", "0"),
                        "cpus": cell.get("cpus", "0"),
                        "memory": cell.get("memory", "0"),
                        "unit": cell.get("unit", "KiB"),
                    })
        result["cells"] = cells

        return result
