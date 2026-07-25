# SPDX-License-Identifier: MIT
# Pulsar - Certificate Manager

"""Proxmox VE SSL/TLS certificate and ACME management."""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

from pve_api_client import PVEClient

logger = logging.getLogger(__name__)


class CertificateManager:
    """High-level certificate and ACME operations.

    Parameters
    ----------
    client:
        An authenticated :class:`PVEClient` instance.
    """

    def __init__(self, client: PVEClient) -> None:
        self._client = client

    def list_certificates(self, node: str) -> list[dict[str, Any]]:
        """List SSL certificates on a node."""
        return self._client.get(f"/api2/json/nodes/{node}/certificates")  # type: ignore[return-value]

    def upload_certificate(self, node: str, cert_path: str, key_path: str) -> dict[str, Any]:
        """Upload a custom SSL certificate and private key.

        Parameters
        ----------
        cert_path:
            Path to the PEM certificate file on the Proxmox host.
        key_path:
            Path to the PEM private key file on the Proxmox host.
        """
        logger.info("Uploading certificate to node %s", node)

        # Read the files locally and upload via the API
        cert_pem = Path(cert_path).read_text(encoding="utf-8")
        key_pem = Path(key_path).read_text(encoding="utf-8")

        import httpx

        assert self._client._http is not None  # noqa: SLF001
        url = f"{self._client._api_url}/api2/json/nodes/{node}/certificates/custom"  # noqa: SLF001

        resp = self._client._http.post(  # noqa: SLF001
            url,
            files={
                "certificates": ("cert.pem", cert_pem.encode(), "application/x-pem-file"),
                "private_key": ("key.pem", key_pem.encode(), "application/x-pem-file"),
            },
        )
        resp.raise_for_status()
        result = resp.json().get("data", {})
        logger.info("Certificate uploaded to node %s", node)
        return result

    def upload_ca(self, node: str, ca_path: str) -> dict[str, Any]:
        """Upload a CA certificate.

        Parameters
        ----------
        ca_path:
            Path to the CA PEM file on the Proxmox host.
        """
        logger.info("Uploading CA certificate to node %s", node)
        ca_pem = Path(ca_path).read_text(encoding="utf-8")

        import httpx

        assert self._client._http is not None  # noqa: SLF001
        url = f"{self._client._api_url}/api2/json/nodes/{node}/certificates/custom"  # noqa: SLF001

        resp = self._client._http.post(  # noqa: SLF001
            url,
            files={
                "certificates": ("ca.pem", ca_pem.encode(), "application/x-pem-file"),
            },
        )
        resp.raise_for_status()
        return resp.json().get("data", {})

    def delete_certificate(self, node: str, certificate_name: str) -> dict[str, Any]:
        """Delete a custom certificate.

        Parameters
        ----------
        certificate_name:
            Name of the certificate to remove, e.g. ``custom``.
        """
        logger.info("Deleting certificate '%s' from node %s", certificate_name, node)
        return self._client.delete(
            f"/api2/json/nodes/{node}/certificates/custom"
        )

    def acme_request(
        self, node: str, domain: str, plugin: str = "standalone"
    ) -> dict[str, Any]:
        """Request an ACME certificate for a domain.

        Parameters
        ----------
        domain:
            Fully qualified domain name.
        plugin:
            ACME plugin – ``standalone``, ``apache`` or ``nginx``.
        """
        logger.info("Requesting ACME certificate for '%s' on node %s (plugin=%s)", domain, node, plugin)
        result = self._client.post(
            f"/api2/json/nodes/{node}/certificates/acme",
            data={"domain": domain, "plugin": plugin},
        )
        logger.info("ACME certificate request initiated for %s", domain)
        return result

    def acme_accounts(self, node: str) -> list[dict[str, Any]]:
        """List registered ACME accounts."""
        return self._client.get(f"/api2/json/nodes/{node}/certificates/acme/account")  # type: ignore[return-value]

    def acme_register(
        self, node: str, email: str, tos: bool = True
    ) -> dict[str, Any]:
        """Register a new ACME account.

        Parameters
        ----------
        email:
            Contact email for the ACME account.
        tos:
            Accept the Terms of Service.
        """
        logger.info("Registering ACME account with email '%s' on node %s", email, node)
        result = self._client.post(
            f"/api2/json/nodes/{node}/certificates/acme/account",
            data={"email": email, "tos_url": "" if tos else None},
        )
        logger.info("ACME account registered for %s", email)
        return result
