"""
SPDX-License-Identifier: MIT
LUKS disk encryption and libvirt secret management.

Provides ``DiskEncryption`` for creating LUKS-encrypted volumes,
managing ``cryptsetup`` mappings, and storing passphrases as
libvirt secrets.
"""

from __future__ import annotations

import logging
import subprocess
from typing import Any

from kvm_libvirt_client import LibvirtClient, LibvirtError, _wrap_libvirt_error

import libvirt

logger = logging.getLogger(__name__)


class EncryptionError(Exception):
    """Raised when an encryption operation fails."""


class DiskEncryption:
    """LUKS encryption helpers.

    Args:
        client: Optional pre-existing :class:`LibvirtClient`.

    Example::

        enc = DiskEncryption()
        secret_name = "my-vm-luks"
        enc.create_libvirt_secret(secret_name, "s3cret!")
        enc.create_luks("/var/lib/libvirt/images/vm.luks", 20, "s3cret!")
        enc.open_luks("/var/lib/libvirt/images/vm.luks", "vm_crypt", "s3cret!")
    """

    def __init__(self, client: LibvirtClient | None = None) -> None:
        self._client = client

    # ------------------------------------------------------------------
    # CLI helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _run(cmd: list[str], check: bool = True) -> subprocess.CompletedProcess[str]:
        """Run a system command.

        Raises:
            EncryptionError: On failure when *check* is True.
        """
        logger.debug("Running: %s", " ".join(cmd))
        result = subprocess.run(cmd, capture_output=True, text=True, check=False)
        if check and result.returncode != 0:
            raise EncryptionError(
                f"Command failed (rc={result.returncode}): "
                f"{result.stderr.strip() or result.stdout.strip()}"
            )
        return result

    # ------------------------------------------------------------------
    # LUKS operations
    # ------------------------------------------------------------------

    def create_luks(self, path: str, size_gb: int, passphrase: str) -> str:
        """Create a LUKS-encrypted volume from scratch.

        Steps:
        1. Create a raw file with ``qemu-img create``.
        2. Format it with ``cryptsetup luksFormat``.
        3. Open the LUKS device.
        4. Create an ext4 filesystem inside.
        5. Close the mapping.

        Args:
            path: Destination file path.
            size_gb: Size in GiB.
            passphrase: LUKS passphrase.

        Returns:
            The same *path* on success.
        """
        # Step 1 – create the backing file
        self._run(["qemu-img", "create", "-f", "raw", path, f"{size_gb}G"])

        # Step 2 – LUKS format
        self._run(
            [
                "cryptsetup",
                "luksFormat",
                "--batch-mode",
                "--type", "luks2",
                "--key-file=-",
                path,
            ],
            check=False,
        )
        # pipe passphrase via stdin
        proc = subprocess.run(
            [
                "cryptsetup",
                "luksFormat",
                "--batch-mode",
                "--type", "luks2",
                path,
            ],
            input=passphrase.encode(),
            capture_output=True,
            check=False,
        )
        if proc.returncode != 0:
            raise EncryptionError(f"luksFormat failed: {proc.stderr.decode().strip()}")

        # Step 3 – open
        self.open_luks(path, "luks_create_tmp", passphrase)

        # Step 4 – create filesystem
        self._run(["mkfs.ext4", "-F", f"/dev/mapper/luks_create_tmp"])

        # Step 5 – close
        self.close_luks("luks_create_tmp")

        logger.info("Created LUKS volume at %s (%d GiB)", path, size_gb)
        return path

    def open_luks(self, encrypted_path: str, name: str, passphrase: str) -> str:
        """Open a LUKS volume and expose it as a device-mapper mapping.

        Args:
            encrypted_path: Path to the LUKS container.
            name: Device-mapper name (e.g. ``myvm_crypt``).
            passphrase: LUKS passphrase.

        Returns:
            The device-mapper path, e.g. ``/dev/mapper/myvm_crypt``.
        """
        proc = subprocess.run(
            ["cryptsetup", "open", "--type", "luks", encrypted_path, name],
            input=passphrase.encode(),
            capture_output=True,
            check=False,
        )
        if proc.returncode != 0:
            raise EncryptionError(f"cryptsetup open failed: {proc.stderr.decode().strip()}")
        mapper_path = f"/dev/mapper/{name}"
        logger.info("Opened LUKS mapping '%s' -> %s", name, mapper_path)
        return mapper_path

    def close_luks(self, name: str) -> None:
        """Close (lock) a device-mapper LUKS mapping.

        Args:
            name: Device-mapper name to close.
        """
        self._run(["cryptsetup", "close", name])
        logger.info("Closed LUKS mapping '%s'", name)

    # ------------------------------------------------------------------
    # Libvirt secret management
    # ------------------------------------------------------------------

    def create_libvirt_secret(self, name: str, passphrase: str) -> None:
        """Create a libvirt ``volume`` secret for LUKS passphrases.

        The secret is defined with ``usage type='volume'`` and the
        passphrase is set as its private value.

        Args:
            name: Secret name (UUID is auto-generated).
            passphrase: Passphrase to store.
        """
        secret_xml = (
            f"<volume>"
            f"  <name>{name}</name>"
            f"  <usage type='volume'>"
            f"    <volume>{name}</volume>"
            f"  </usage>"
            f"</volume>"
        )
        conn = self._client or LibvirtClient()
        if not conn._conn:
            conn.connect()
        try:
            secret = conn.conn.secretDefineXML(secret_xml)
            secret.setPrivateValue(passphrase.encode("utf-8"))
            logger.info("Created libvirt secret '%s'", name)
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc
        finally:
            if self._client is None:
                conn.disconnect()

    def delete_libvirt_secret(self, name: str) -> None:
        """Remove a libvirt secret by name.

        Args:
            name: Secret name.
        """
        conn = self._client or LibvirtClient()
        if not conn._conn:
            conn.connect()
        try:
            secrets = conn.conn.listAllSecrets()
            for secret in secrets:
                if secret.usageID() == name:
                    secret.undefine()
                    logger.info("Deleted libvirt secret '%s'", name)
                    return
            raise LibvirtError(f"Secret '{name}' not found")
        except libvirt.libvirtError as exc:
            raise _wrap_libvirt_error(exc) from exc
        finally:
            if self._client is None:
                conn.disconnect()
