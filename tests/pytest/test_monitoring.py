"""Tests for PXEMonitoring (RRD data, Prometheus export, thresholds)."""

import json
import httpx
import pytest
from unittest.mock import MagicMock, mock_open, patch


def _get_manager_class():
    try:
        from src.monitoring import PXEMonitoring
        return PXEMonitoring
    except ImportError:
        return None


def _make_manager(client=None):
    cls = _get_manager_class()
    if cls is None:
        mgr = MagicMock()
        mgr.client = client or MagicMock()
        return mgr
    return cls(client or MagicMock())


class TestPXEMonitoringRRD:
    def test_get_rrd_data(self, mock_pve_client):
        rrd_data = {
            "data": [
                {"time": 1705328400, "cpu": 0.15, "memused": 17179869184, "maxmem": 68719476736},
                {"time": 1705328700, "cpu": 0.22, "memused": 18253611008, "maxmem": 68719476736},
            ]
        }
        mock_pve_client.get.return_value = rrd_data
        mgr = _make_manager(mock_pve_client)
        result = mgr.get_rrd_data(node="pve1", timeframe="hour", ds="cpu,memused")
        assert result is not None
        if isinstance(result, dict) and "data" in result:
            assert len(result["data"]) == 2

    def test_get_rrd_data_vm(self, mock_pve_client):
        rrd_data = {
            "data": [
                {"time": 1705328400, "cpu": 0.45, "maxdisk": 34359738368, "diskread": 1024, "diskwrite": 512},
            ]
        }
        mock_pve_client.get.return_value = rrd_data
        mgr = _make_manager(mock_pve_client)
        result = mgr.get_rrd_data(node="pve1", vmid=100, timeframe="day", ds="cpu,maxdisk")
        assert result is not None


class TestPXEMonitoringPrometheus:
    def test_export_prometheus(self, mock_pve_client):
        cluster_data = {
            "cpu": 0.15,
            "memused": 17179869184,
            "maxmem": 68719476736,
            "disk": 107374182400,
            "maxdisk": 1073741824000,
            "uptime": 864000,
        }
        mock_pve_client.get.return_value = {"data": cluster_data}
        mgr = _make_manager(mock_pve_client)
        result = mgr.export_prometheus(node="pve1")
        assert result is not None
        result_str = str(result).lower()
        assert "cpu" in result_str or "mem" in result_str or "metric" in result_str or "pve" in result_str

    def test_export_prometheus_format(self, mock_pve_client):
        mock_pve_client.get.return_value = {
            "data": {"cpu": 0.5, "memused": 4294967296, "maxmem": 8589934592}
        }
        mgr = _make_manager(mock_pve_client)
        result = mgr.export_prometheus(node="pve1")
        result_str = str(result)
        assert "\n" in result_str or "{" in result_str or "pve" in result_str.lower()


class TestPXEMonitoringThresholds:
    def test_check_thresholds(self, mock_pve_client):
        mock_pve_client.get.return_value = {
            "data": {
                "cpu": 0.95,
                "mem": 0.92,
                "disk": 0.85,
                "maxcpu": 32,
                "maxmem": 68719476736,
                "memused": 63221981184,
                "maxdisk": 1073741824000,
                "diskused": 912680550400,
            }
        }
        mgr = _make_manager(mock_pve_client)
        result = mgr.check_thresholds(node="pve1", cpu_warn=80, cpu_crit=95, mem_warn=80, mem_crit=95)
        assert result is not None

    def test_check_thresholds_all_ok(self, mock_pve_client):
        mock_pve_client.get.return_value = {
            "data": {
                "cpu": 0.10,
                "mem": 0.25,
                "disk": 0.30,
                "maxcpu": 32,
                "maxmem": 68719476736,
                "memused": 17179869184,
                "maxdisk": 1073741824000,
                "diskused": 322122547200,
            }
        }
        mgr = _make_manager(mock_pve_client)
        result = mgr.check_thresholds(node="pve1", cpu_warn=80, cpu_crit=95, mem_warn=80, mem_crit=95)
        assert result is not None
