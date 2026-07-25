#!/usr/bin/env python3
# =============================================================================
# report_generator.py — Markdown / HTML / JSON report generation
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 proxmox-kvm-swissknife contributors
# =============================================================================
# Generates structured reports in Markdown, HTML (with inline CSS), and
# JSON formats.  Designed for VM inventory, health-check, and backup
# summaries.
# =============================================================================

from __future__ import annotations

import json
import logging
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Union

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Default inline CSS for HTML reports
# ---------------------------------------------------------------------------

_DEFAULT_CSS = """
:root {
    --bg: #f8f9fa;
    --card-bg: #ffffff;
    --border: #dee2e6;
    --text: #212529;
    --text-muted: #6c757d;
    --accent: #0d6efd;
    --success: #198754;
    --warning: #ffc107;
    --danger: #dc3545;
    --code-bg: #f1f3f5;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto,
                 'Helvetica Neue', Arial, sans-serif;
    background: var(--bg);
    color: var(--text);
    line-height: 1.6;
    padding: 2rem;
}
.container { max-width: 960px; margin: 0 auto; }
header {
    border-bottom: 3px solid var(--accent);
    padding-bottom: 1rem;
    margin-bottom: 2rem;
}
header h1 {
    font-size: 1.75rem;
    color: var(--accent);
}
header .timestamp {
    color: var(--text-muted);
    font-size: 0.85rem;
    margin-top: 0.25rem;
}
section {
    background: var(--card-bg);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 1.5rem;
    margin-bottom: 1.5rem;
}
section h2 {
    font-size: 1.25rem;
    color: var(--accent);
    border-bottom: 1px solid var(--border);
    padding-bottom: 0.5rem;
    margin-bottom: 1rem;
}
table {
    width: 100%;
    border-collapse: collapse;
    margin-top: 0.75rem;
}
th, td {
    text-align: left;
    padding: 0.6rem 0.8rem;
    border: 1px solid var(--border);
}
th {
    background: var(--code-bg);
    font-weight: 600;
}
tr:nth-child(even) { background: var(--bg); }
code, pre {
    font-family: 'SF Mono', 'Fira Code', 'Consolas', monospace;
    font-size: 0.9rem;
}
code {
    background: var(--code-bg);
    padding: 0.15rem 0.4rem;
    border-radius: 4px;
}
pre {
    background: var(--code-bg);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 1rem;
    overflow-x: auto;
    margin-top: 0.5rem;
}
pre code { background: none; padding: 0; }
.badge {
    display: inline-block;
    padding: 0.2rem 0.6rem;
    border-radius: 12px;
    font-size: 0.8rem;
    font-weight: 600;
    color: #fff;
}
.badge-success { background: var(--success); }
.badge-warning { background: var(--warning); color: #000; }
.badge-danger { background: var(--danger); }
footer {
    text-align: center;
    color: var(--text-muted);
    font-size: 0.8rem;
    margin-top: 2rem;
    padding-top: 1rem;
    border-top: 1px solid var(--border);
}
"""


# ---------------------------------------------------------------------------
# ReportGenerator
# ---------------------------------------------------------------------------

class ReportGenerator:
    """Generate reports in Markdown, HTML, and JSON formats.

    Parameters
    ----------
    output_dir : str
        Directory where generated report files are saved.
    """

    def __init__(self, output_dir: str = "/tmp/reports") -> None:
        self._output_dir = Path(output_dir).expanduser().resolve()
        self._output_dir.mkdir(parents=True, exist_ok=True)

    # ------------------------------------------------------------------
    # Markdown
    # ------------------------------------------------------------------

    def generate_markdown(
        self,
        title: str,
        sections: List[Dict[str, Any]],
    ) -> str:
        """Generate a Markdown report.

        Parameters
        ----------
        title : str
            Report title.
        sections : list[dict]
            Each section is a dict with keys:
            - ``heading`` (str): Section heading.
            - ``content`` (str | list): Body text, or list of dicts for
              tables (``{"columns": [...], "rows": [[...], ...]}``).
            - ``level`` (int, optional): Heading level (default 2).

        Returns
        -------
        str
            Rendered Markdown string.
        """
        now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
        lines: List[str] = []

        # Title
        lines.append(f"# {title}")
        lines.append("")
        lines.append(f"*Generated: {now}*")
        lines.append("")
        lines.append("---")
        lines.append("")

        for section in sections:
            heading = section.get("heading", "Untitled")
            level = section.get("level", 2)
            content = section.get("content", "")

            prefix = "#" * min(level, 6)
            lines.append(f"{prefix} {heading}")
            lines.append("")

            if isinstance(content, str):
                lines.append(content)
            elif isinstance(content, list):
                lines.extend(self._render_md_table(content))
            else:
                lines.append(str(content))

            lines.append("")

        return "\n".join(lines)

    def _render_md_table(self, rows: List[Any]) -> List[str]:
        """Render a list of row dicts into a Markdown table."""
        if not rows:
            return ["*(empty)*"]

        # Determine if rows are dicts (with columns/rows keys) or simple
        if isinstance(rows[0], dict) and "columns" in rows[0]:
            columns = rows[0]["columns"]
            data_rows = rows[0].get("rows", [])
        elif isinstance(rows[0], dict):
            # List of dicts — use keys as columns
            columns = list(rows[0].keys())
            data_rows = [[row.get(c, "") for c in columns] for row in rows]
        else:
            return [str(r) for r in rows]

        lines: List[str] = []
        lines.append("| " + " | ".join(str(c) for c in columns) + " |")
        lines.append("| " + " | ".join("---" for _ in columns) + " |")
        for row in data_rows:
            cells = [str(c) for c in row]
            # Pad if needed
            while len(cells) < len(columns):
                cells.append("")
            lines.append("| " + " | ".join(cells[: len(columns)]) + " |")
        return lines

    # ------------------------------------------------------------------
    # HTML
    # ------------------------------------------------------------------

    def generate_html(
        self,
        title: str,
        sections: List[Dict[str, Any]],
        css: Optional[str] = None,
    ) -> str:
        """Generate a styled HTML report.

        Parameters
        ----------
        title : str
            Report title.
        sections : list[dict]
            Same structure as :meth:`generate_markdown`.
        css : str or None
            Custom CSS.  If ``None``, the built-in default CSS is used.

        Returns
        -------
        str
            Complete HTML document string.
        """
        now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
        style = css or _DEFAULT_CSS

        html_parts: List[str] = [
            "<!DOCTYPE html>",
            '<html lang="en">',
            "<head>",
            '<meta charset="UTF-8">',
            '<meta name="viewport" content="width=device-width, initial-scale=1.0">',
            f"<title>{self._escape(title)}</title>",
            f"<style>{style}</style>",
            "</head>",
            "<body>",
            '<div class="container">',
            "<header>",
            f"<h1>{self._escape(title)}</h1>",
            f'<div class="timestamp">Generated: {self._escape(now)}</div>',
            "</header>",
        ]

        for section in sections:
            heading = section.get("heading", "Untitled")
            level = section.get("level", 2)
            content = section.get("content", "")

            html_parts.append("<section>")
            html_parts.append(f"<h{level}>{self._escape(heading)}</h{level}>")

            if isinstance(content, str):
                # Convert markdown-ish content to basic HTML
                html_parts.append(self._md_to_html(content))
            elif isinstance(content, list):
                html_parts.append(self._render_html_table(content))
            else:
                html_parts.append(f"<pre>{self._escape(str(content))}</pre>")

            html_parts.append("</section>")

        html_parts.extend([
            "</div>",
            "<footer>proxmox-kvm-swissknife report</footer>",
            "</body>",
            "</html>",
        ])

        return "\n".join(html_parts)

    def _render_html_table(self, rows: List[Any]) -> str:
        """Render rows into an HTML table."""
        if not rows:
            return "<p><em>(empty)</em></p>"

        if isinstance(rows[0], dict) and "columns" in rows[0]:
            columns = rows[0]["columns"]
            data_rows = rows[0].get("rows", [])
        elif isinstance(rows[0], dict):
            columns = list(rows[0].keys())
            data_rows = [[row.get(c, "") for c in columns] for row in rows]
        else:
            return f"<pre>{self._escape(str(rows))}</pre>"

        parts = ["<table>"]
        parts.append("<thead><tr>")
        for col in columns:
            parts.append(f"<th>{self._escape(str(col))}</th>")
        parts.append("</tr></thead>")

        parts.append("<tbody>")
        for row in data_rows:
            cells = [str(c) for c in row]
            while len(cells) < len(columns):
                cells.append("")
            parts.append("<tr>")
            for cell in cells[: len(columns)]:
                parts.append(f"<td>{self._escape(cell)}</td>")
            parts.append("</tr>")
        parts.append("</tbody>")
        parts.append("</table>")
        return "\n".join(parts)

    @staticmethod
    def _escape(text: str) -> str:
        """Escape HTML special characters."""
        return (
            text.replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace('"', "&quot;")
        )

    @staticmethod
    def _md_to_html(text: str) -> str:
        """Convert a small subset of Markdown to HTML."""
        import re
        # Code blocks
        text = re.sub(
            r"```(\w*)\n(.*?)```",
            r"<pre><code>\2</code></pre>",
            text,
            flags=re.DOTALL,
        )
        # Inline code
        text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
        # Bold
        text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
        # Italic
        text = re.sub(r"\*(.+?)\*", r"<em>\1</em>", text)
        # Line breaks
        text = text.replace("\n", "<br>\n")
        return f"<p>{text}</p>"

    # ------------------------------------------------------------------
    # JSON
    # ------------------------------------------------------------------

    def generate_json(self, data: Dict[str, Any]) -> str:
        """Serialize data as a pretty-printed JSON string.

        Parameters
        ----------
        data : dict
            Data to serialize.

        Returns
        -------
        str
            JSON string with 2-space indentation.
        """
        return json.dumps(data, indent=2, default=str, ensure_ascii=False)

    # ------------------------------------------------------------------
    # Save
    # ------------------------------------------------------------------

    def save_report(
        self,
        content: str,
        filename: str,
        format: str = "md",
    ) -> str:
        """Save report content to a file.

        Parameters
        ----------
        content : str
            Report content string.
        filename : str
            Base filename (extension is appended if missing).
        format : str
            ``"md"``, ``"html"``, or ``"json"``.  Used to set the file
            extension if the filename has no extension.

        Returns
        -------
        str
            Absolute path to the saved file.
        """
        # Determine extension
        ext_map = {"md": ".md", "markdown": ".md", "html": ".html", "json": ".json"}
        ext = ext_map.get(format.lower(), f".{format}")

        # Append extension if missing
        if not Path(filename).suffix:
            filename = f"{filename}{ext}"

        dest = self._output_dir / filename
        dest.parent.mkdir(parents=True, exist_ok=True)

        dest.write_text(content, encoding="utf-8")
        logger.info("Report saved to %s", dest)
        return str(dest.resolve())

    # ------------------------------------------------------------------
    # Convenience helpers
    # ------------------------------------------------------------------

    def quick_report(
        self,
        title: str,
        body: str,
        format: str = "md",
        filename: Optional[str] = None,
    ) -> str:
        """Generate and save a simple single-section report.

        Parameters
        ----------
        title : str
            Report title.
        body : str
            Report body text.
        format : str
            Output format.
        filename : str or None
            Filename; defaults to a timestamped name.

        Returns
        -------
        str
            Path to the saved file.
        """
        sections = [{"heading": title, "content": body}]

        if format == "html":
            content = self.generate_html(title, sections)
        elif format == "json":
            content = self.generate_json({"title": title, "body": body})
        else:
            content = self.generate_markdown(title, sections)

        if filename is None:
            ts = datetime.now().strftime("%Y%m%d-%H%M%S")
            safe_title = title.lower().replace(" ", "-")[:40]
            filename = f"{ts}-{safe_title}"

        return self.save_report(content, filename, format)
