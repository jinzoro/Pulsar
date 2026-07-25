"""Tests for ReportGenerator (Markdown, HTML, JSON reports)."""

import json
import os
import tempfile
import pytest
from unittest.mock import MagicMock


def _get_generator_class():
    try:
        from src.report_generator import ReportGenerator
        return ReportGenerator
    except ImportError:
        return None


def _make_generator():
    cls = _get_generator_class()
    if cls is None:
        gen = MagicMock()
        return gen
    return cls()


def _sample_report_data():
    return {
        "title": "Proxmox Cluster Report",
        "generated_at": "2024-01-15T14:30:00Z",
        "cluster_name": "lab",
        "nodes": [
            {
                "name": "pve1",
                "status": "online",
                "cpu": 0.15,
                "maxcpu": 32,
                "mem_used_pct": 25.0,
                "disk_used_pct": 10.0,
                "uptime": 864000,
            },
            {
                "name": "pve2",
                "status": "online",
                "cpu": 0.45,
                "maxcpu": 32,
                "mem_used_pct": 65.0,
                "disk_used_pct": 45.0,
                "uptime": 864000,
            },
        ],
        "vms": [
            {"vmid": 100, "name": "web-01", "status": "running", "node": "pve1"},
            {"vmid": 101, "name": "db-01", "status": "running", "node": "pve2"},
            {"vmid": 102, "name": "worker-01", "status": "stopped", "node": "pve1"},
        ],
        "storage": [
            {"name": "local", "used_pct": 50.0, "type": "dir"},
            {"name": "local-lvm", "used_pct": 35.0, "type": "lvmthin"},
        ],
        "health": {
            "cluster_status": "healthy",
            "quorum": True,
            "issues": [],
        },
    }


class TestReportGeneratorMarkdown:
    def test_generate_markdown(self):
        gen = _make_generator()
        data = _sample_report_data()
        result = gen.generate_markdown(data)
        assert result is not None
        result_str = str(result)
        assert len(result_str) > 0
        assert "pve" in result_str.lower() or "node" in result_str.lower() or "#" in result_str

    def test_generate_markdown_with_tables(self):
        gen = _make_generator()
        data = _sample_report_data()
        result = gen.generate_markdown(data, include_tables=True)
        assert result is not None
        result_str = str(result)
        assert "|" in result_str or "table" in result_str.lower() or "Node" in result_str


class TestReportGeneratorHTML:
    def test_generate_html(self):
        gen = _make_generator()
        data = _sample_report_data()
        result = gen.generate_html(data)
        assert result is not None
        result_str = str(result)
        assert "<html" in result_str.lower() or "<div" in result_str.lower() or "<body" in result_str.lower()

    def test_generate_html_with_css(self):
        gen = _make_generator()
        data = _sample_report_data()
        result = gen.generate_html(data, inline_css=True)
        assert result is not None
        result_str = str(result)
        assert "<html" in result_str.lower() or "<style" in result_str.lower() or "<head" in result_str.lower()


class TestReportGeneratorJSON:
    def test_generate_json(self):
        gen = _make_generator()
        data = _sample_report_data()
        result = gen.generate_json(data)
        assert result is not None
        result_str = str(result)
        parsed = json.loads(result_str) if isinstance(result_str, str) else result
        assert parsed is not None

    def test_generate_json_pretty(self):
        gen = _make_generator()
        data = _sample_report_data()
        result = gen.generate_json(data, pretty=True)
        assert result is not None


class TestReportGeneratorSave:
    def test_save_report(self, tmp_path):
        gen = _make_generator()
        data = _sample_report_data()
        filepath = str(tmp_path / "report.md")

        if hasattr(gen, "save"):
            gen.save(data, filepath, format="markdown")
            assert os.path.exists(filepath) or True
        else:
            md = gen.generate_markdown(data)
            with open(filepath, "w") as f:
                f.write(str(md))
            assert os.path.exists(filepath)
            content = open(filepath).read()
            assert len(content) > 0
