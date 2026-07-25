"""Shared fixtures for proxmox-kvm-swissknife pytest tests."""

import json
import os
import tempfile
import textwrap
from pathlib import Path
from unittest.mock import MagicMock, patch

import httpx
import pytest


# ---------------------------------------------------------------------------
# HTTP Mock Transport
# ---------------------------------------------------------------------------

class MockTransport(httpx.BaseTransport):
    """Lightweight httpx transport that returns pre-configured responses."""

    def __init__(self, responses=None):
        self.responses = responses or []
        self._call_log = []

    def handle_request(self, request):
        self._call_log.append(request)
        if self.responses:
            resp = self.responses.pop(0)
            if isinstance(resp, dict):
                return httpx.Response(
                    status_code=resp.get("status", 200),
                    json=resp.get("json", {}),
                    headers=resp.get("headers", {}),
                    request=request,
                )
            return resp
        return httpx.Response(status_code=200, json={}, request=request)


# ---------------------------------------------------------------------------
# Mock PVEClient
# ---------------------------------------------------------------------------

@pytest.fixture
def mock_pve_client():
    """Return a PVEClient backed by MockTransport with default success responses."""
    responses = [
        {"status": 200, "json": {"data": {"ticket": "PVE:root@pam:1234::xxxx"}}},
        {"status": 200, "json": {"data": "value"}},
    ]
    transport = MockTransport(responses)

    with patch("httpx.Client", return_value=httpx.Client(transport=transport)):
        try:
            from src.proxmox_api_client import PVEClient
            client = PVEClient(
                host="pve.example.com",
                token_id="root@pam",
                token_secret="test-secret",
                node="pve1",
            )
        except ImportError:
            client = MagicMock()
            client.host = "pve.example.com"
            client.node = "pve1"
            client._transport = transport

    client._transport = transport
    return client


# ---------------------------------------------------------------------------
# Mock libvirt connection
# ---------------------------------------------------------------------------

@pytest.fixture
def mock_libvirt():
    """Return a mocked libvirt connection with common test VMs."""
    conn = MagicMock()
    conn.listAllDomains.return_value = [
        MagicMock(id=1, name="testvm1", isActive=lambda: True, info=lambda: (1, 2048, 2, 0)),
        MagicMock(id=2, name="testvm2", isActive=lambda: False, info=lambda: (0, 1024, 1, 0)),
    ]

    def lookup_by_name(name):
        for d in conn.listAllDomains():
            if d.name == name:
                return d
        return None

    conn.lookupByUUIDString.return_value = conn.listAllDomains()[0]
    conn.lookupByName.side_effect = lookup_by_name
    return conn


# ---------------------------------------------------------------------------
# Sample data fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def sample_vm_data():
    """Dictionary with typical VM configuration from Proxmox API."""
    return {
        "vmid": "100",
        "name": "web-server-01",
        "status": "running",
        "node": "pve1",
        "cores": 4,
        "memory": 8192,
        "maxdisk": 34359738368,
        "disk": 1073741824,
        "net0": "virtio=AA:BB:CC:DD:EE:FF,bridge=vmbr0",
        "scsihw": "virtio-scsi-pci",
        "scsi0": "local-lvm:vm-100-disk-0,size=32G",
        "ide2": "local:iso/ubuntu-22.04.iso,media=cdrom",
        "ostype": "l26",
        "cpu": "x86-64-v2-AES",
        "sockets": 1,
        "agent": "1",
        "balloon": 0,
        "hotplug": "network,disk,cpu,memory",
        "machine": "q35",
        "bios": "ovmf",
        "efidisk0": "local:vm-100-disk-1,efitype=4m,pre-enrolled-keys=1",
    }


@pytest.fixture
def sample_node_data():
    """Dictionary with typical node info from Proxmox API."""
    return {
        "node": "pve1",
        "status": "online",
        "cpu": 0.15,
        "maxcpu": 32,
        "mem": 17179869184,
        "maxmem": 68719476736,
        "disk": 107374182400,
        "maxdisk": 1073741824000,
        "uptime": 864000,
        "ssl_fingerprint": "AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99",
        "level": "",
        "type": "node",
        "id": "node/pve1",
        "disks": {
            "sda": {"size": 1073741824000, "used": 536870912000, "type": "local"},
        },
    }


@pytest.fixture
def sample_storage_data():
    """List of storage entries from Proxmox API."""
    return [
        {
            "storage": "local",
            "type": "dir",
            "status": "active",
            "content": ["backup", "iso", "vztmpl"],
            "total": 1073741824000,
            "used": 536870912000,
            "avail": 536870912000,
        },
        {
            "storage": "local-lvm",
            "type": "lvmthin",
            "status": "active",
            "content": ["images", "rootdir"],
            "total": 214748364800,
            "used": 107374182400,
            "avail": 107374182400,
        },
        {
            "storage": "nfs-store",
            "type": "nfs",
            "status": "active",
            "content": ["backup", "images"],
            "total": 1099511627776,
            "used": 219902325555,
            "avail": 879609302221,
        },
    ]


@pytest.fixture
def sample_backup_data():
    """List of backup entries from Proxmox API."""
    return [
        {
            "volid": "local:backup/vzdump-qemu-100-2024_01_15-14_30_00.vma.zst",
            "size": 4294967296,
            "ctime": 1705328400,
            "format": "vma.zst",
            "vmid": 100,
        },
        {
            "volid": "local:backup/vzdump-qemu-100-2024_01_10-08_00_00.vma.zst",
            "size": 3221225472,
            "ctime": 1704883200,
            "format": "vma.zst",
            "vmid": 100,
        },
        {
            "volid": "nfs-store:backup/vzdump-qemu-200-2024_01_12-22_00_00.vma.zst",
            "size": 2147483648,
            "ctime": 1705096800,
            "format": "vma.zst",
            "vmid": 200,
        },
    ]


@pytest.fixture
def sample_snapshot_data():
    """List of snapshot entries."""
    return [
        {
            "name": "snap-pre-update",
            "description": "Before major upgrade",
            "snaptime": 1705328400,
            "running": 0,
        },
        {
            "name": "snap-post-install",
            "description": "After initial install",
            "snaptime": 1704883200,
            "running": 0,
        },
    ]


@pytest.fixture
def sample_firewall_rules():
    """List of firewall rules."""
    return [
        {"pos": 1, "type": "in", "action": "ACCEPT", "proto": "tcp", "dport": "22", "comment": "SSH"},
        {"pos": 2, "type": "in", "action": "ACCEPT", "proto": "tcp", "dport": "443", "comment": "HTTPS"},
        {"pos": 3, "type": "in", "action": "DROP", "proto": "tcp", "dport": "3306", "comment": "Block MySQL"},
    ]


@pytest.fixture
def sample_ceph_data():
    """Ceph cluster status data."""
    return {
        "cluster": "ceph-cluster",
        "fsid": "12345678-1234-1234-1234-123456789abc",
        "health": {"status": "HEALTH_OK"},
        "mon": {"pve1": {"state": "leader"}},
        "osd": {
            "0": {"up": 1, "in": 1},
            "1": {"up": 1, "in": 1},
            "2": {"up": 1, "in": 1},
        },
        "pgs": {"total": 128, "active_clean": 128},
    }


@pytest.fixture
def sample_zfs_data():
    """ZFS pool data."""
    return [
        {
            "name": "rpool",
            "size": 214748364800,
            "alloc": 107374182400,
            "free": 107374182400,
            "frag": 5,
            "health": "ONLINE",
        },
    ]


# ---------------------------------------------------------------------------
# Temporary config
# ---------------------------------------------------------------------------

@pytest.fixture
def tmp_config(tmp_path):
    """Create a temporary settings.yaml and return its path."""
    config = tmp_path / "settings.yaml"
    config.write_text(textwrap.dedent("""\
        pve:
          host: pve.example.com
          port: 8006
          token_id: root@pam
          token_secret: test-secret-123
          node: pve1
          verify_ssl: false

        kvm:
          default_bridge: vmbr0
          default_storage: local-lvm
          default_ostype: l26

        backup:
          default_storage: local
          keep_last: 3
          compress: zstd

        notifications:
          email:
            enabled: true
            smtp_host: smtp.example.com
            smtp_port: 587
            from: alerts@example.com
            to: admin@example.com
          slack:
            enabled: false
            webhook_url: ""
          telegram:
            enabled: false
            bot_token: ""
            chat_id: ""
          ntfy:
            enabled: false
            topic: ""
    """))
    return str(config)


@pytest.fixture
def sample_ha_data():
    """HA group and resource data."""
    return {
        "groups": [
            {
                "group": "ha-group-1",
                "nodes": "pve1:1,pve2:2",
                "type": "group",
            },
        ],
        "resources": [
            {
                "sid": "vm:100",
                "type": "vm",
                "state": "started",
                "node": "pve1",
                "group": "ha-group-1",
            },
        ],
    }


@pytest.fixture
def sample_user_data():
    """User and ACL data."""
    return {
        "users": [
            {"userid": "monitoring@pam", "comment": "Monitoring user", "enable": 1},
        ],
        "groups": [
            {"groupid": "admin", "comment": "Admin group"},
        ],
        "tokens": [
            {"tokenid": "monitoring@pam!automation", "comment": "API token"},
        ],
    }
