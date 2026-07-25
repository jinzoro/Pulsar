# SPDX-License-Identifier: MIT
# Pulsar - VM Console

"""Proxmox VE VNC / SPICE console access helpers."""

from __future__ import annotations

import logging
from typing import Any
from urllib.parse import quote

from pve_api_client import PVEClient

logger = logging.getLogger(__name__)


class VMConsole:
    """Console access helpers for VNC, SPICE and noVNC.

    Parameters
    ----------
    client:
        An authenticated :class:`PVEClient` instance.
    """

    def __init__(self, client: PVEClient) -> None:
        self._client = client

    def get_vnc_ticket(self, node: str, vmid: int) -> dict[str, Any]:
        """Obtain a VNC proxy ticket for a VM.

        Returns the VNC connection parameters including port and password.
        """
        logger.info("Requesting VNC ticket for VM %d on node %s", vmid, node)
        return self._client.post(
            f"/api2/json/nodes/{node}/qemu/{vmid}/vncproxy",
            data={"websocket": 1},
        )

    def get_spice_ticket(self, node: str, vmid: int) -> dict[str, Any]:
        """Obtain a SPICE proxy ticket for a VM.

        Returns the SPICE connection data including the ``proxy`` URL and
        ticket/password.
        """
        logger.info("Requesting SPICE ticket for VM %d on node %s", vmid, node)
        return self._client.post(
            f"/api2/json/nodes/{node}/qemu/{vmid}/spiceproxy",
            data={"proxy": "1"},
        )

    def generate_novnc_url(
        self,
        node: str,
        vmid: int,
        port: int | None = None,
    ) -> str:
        """Generate a noVNC websocket URL for browser-based console access.

        Parameters
        ----------
        node:
            Node name.
        vmid:
            VM ID.
        port:
            noVNC port – if *None*, the API URL base port is used.

        Returns
        -------
        str
            A URL string pointing to the noVNC endpoint.
        """
        vnc = self.get_vnc_ticket(node, vmid)
        ws_port = vnc.get("port", port or 6000)
        tls_port = vnc.get("tls_port", ws_port)
        ticket = vnc.get("ticket", "")

        # Build the base URL from the client's configured API URL
        base_url = self._client._api_url  # noqa: SLF001
        encoded_ticket = quote(ticket)

        url = f"{base_url}/?console=qemu&vmid={vmid}&node={node}&port={tls_port}&ticket={encoded_ticket}"
        logger.debug("Generated noVNC URL for VM %d", vmid)
        return url

    def get_console_info(self, node: str, vmid: int) -> dict[str, Any]:
        """Return comprehensive console connection information.

        Includes VNC, SPICE and noVNC details where available.
        """
        info: dict[str, Any] = {
            "vmid": vmid,
            "node": node,
            "vnc": None,
            "spice": None,
            "novnc_url": None,
        }

        try:
            vnc = self.get_vnc_ticket(node, vmid)
            info["vnc"] = {
                "host": vnc.get("host", "localhost"),
                "port": vnc.get("port"),
                "tls_port": vnc.get("tls_port"),
                "ticket": vnc.get("ticket"),
                "cert": vnc.get("cert"),
            }
            info["novnc_url"] = self.generate_novnc_url(node, vmid)
        except Exception as exc:
            logger.warning("VNC ticket unavailable for VM %d: %s", vmid, exc)
            info["vnc_error"] = str(exc)

        try:
            spice = self.get_spice_ticket(node, vmid)
            info["spice"] = spice
        except Exception as exc:
            logger.warning("SPICE ticket unavailable for VM %d: %s", vmid, exc)
            info["spice_error"] = str(exc)

        return info
