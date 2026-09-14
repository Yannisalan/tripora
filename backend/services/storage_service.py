"""Persistent document storage for the Trip Vault.

Render's local filesystem is ephemeral (it resets on every redeploy), so trip
documents are never stored there in production. Instead they live in an
S3-compatible object store (AWS S3, Cloudflare R2, Backblaze B2, MinIO,
Supabase Storage, ...) configured through environment variables.

Two backends are provided:

- ``S3StorageBackend`` —— the production backend. boto3 talks to any
  S3-compatible endpoint. Documents are private: the object ACL/block-public
  settings keep them off the internet and every read is streamed through the
  authenticated Flask route (no presigned URL is ever handed to the client).
- ``LocalStorageBackend`` —— a local-development fallback that writes files
  under ``STORAGE_LOCAL_DIR``. It only exists so the feature can be exercised
  without a cloud account. It is NOT persistent (fine for a laptop, dangerous
  on a server) so it logs a loud warning every time it is constructed and is
  never acceptable as the production backend.

Selection: ``STORAGE_BACKEND`` forces a backend ("s3" or "local"). When unset,
a fully-configured S3 backend is preferred; otherwise the local backend is
used so local dev / tests keep working out of the box.

The storage key is always server-generated (``trips/<trip_id>/<uuid>.<ext>``)
and validated here; a caller-supplied file name is never used as a key.
"""
import logging
import os
from abc import ABC, abstractmethod
from urllib.parse import quote

logger = logging.getLogger(__name__)


class StorageError(Exception):
    """Raised when a storage operation fails and the request must fail cleanly."""


def _default_local_dir():
    """Storage directory relative to the backend package (backend/storage)."""
    backend_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(backend_dir, "storage")


def storage_backend_name():
    """Resolve which backend is active without constructing it."""
    forced = (os.environ.get("STORAGE_BACKEND", "") or "").strip().lower()
    if forced in ("s3", "local"):
        return forced
    s3_ready = (
        os.environ.get("S3_BUCKET", "")
        and os.environ.get("S3_ACCESS_KEY", "")
        and os.environ.get("S3_SECRET_KEY", "")
    )
    return "s3" if s3_ready else "local"


class StorageBackend(ABC):
    """Common interface for the Trip Vault storage backends."""

    @abstractmethod
    def upload(self, key, content, content_type):
        """Store ``content`` (bytes) under ``key``."""

    @abstractmethod
    def download(self, key):
        """Return a byte iterator for the object at ``key``.

        A missing object raises ``StorageError``.
        """

    @abstractmethod
    def delete(self, key):
        """Remove the object at ``key``. Missing objects are a no-op."""


def validate_key(key):
    """Reject any storage key that could escape the bucket / documents root.

    Keys are server-generated UUIDs, but defense-in-depth still applies: we
    only allow plain segments under a ``trips/`` prefix.
    """
    if not key or not isinstance(key, str):
        raise StorageError("Invalid storage key.")
    parts = key.split("/")
    if parts[0] != "trips":
        raise StorageError("Invalid storage key.")
    if len(parts) != 3 or not all(parts):
        raise StorageError("Invalid storage key.")
    if any(part in (".", "..") for part in parts):
        raise StorageError("Invalid storage key.")
    return key


class S3StorageBackend(StorageBackend):
    """boto3 S3-compatible object storage (private, server-side)."""

    def __init__(self):
        import boto3
        from botocore.client import Config

        self.bucket = os.environ.get("S3_BUCKET", "").strip()
        if not self.bucket:
            raise StorageError("S3_BUCKET is not configured.")

        self.client = boto3.client(
            "s3",
            region_name=os.environ.get("S3_REGION", "").strip() or None,
            aws_access_key_id=os.environ.get("S3_ACCESS_KEY", "").strip(),
            aws_secret_access_key=os.environ.get("S3_SECRET_KEY", "").strip(),
            endpoint_url=(
                os.environ.get("S3_ENDPOINT_URL", "").strip() or None
            ),
            config=Config(
                signature_version="s3v4",
                s3={"addressing_style": "path"},
            ),
        )

    def upload(self, key, content, content_type):
        validate_key(key)
        try:
            self.client.put_object(
                Bucket=self.bucket,
                Key=key,
                Body=content,
                ContentType=content_type,
            )
        except Exception as error:
            logger.error("S3 upload failed for key=%s", key)
            raise StorageError("Failed to store the document.") from error

    def download(self, key):
        validate_key(key)
        try:
            response = self.client.get_object(
                Bucket=self.bucket,
                Key=key,
            )
        except self.client.exceptions.NoSuchKey:
            raise StorageError("The stored document could not be found.") from None
        except Exception as error:
            logger.error("S3 download failed for key=%s", key)
            raise StorageError("Failed to read the document.") from error

        body = response.get("Body")
        if body is None:
            raise StorageError("The stored document could not be read.")

        return body.iter_chunks(chunk_size=65536)

    def delete(self, key):
        validate_key(key)
        try:
            self.client.delete_object(
                Bucket=self.bucket,
                Key=key,
            )
        except Exception as error:
            logger.error("S3 delete failed for key=%s", key)
            raise StorageError("Failed to delete the stored document.") from error


class LocalStorageBackend(StorageBackend):
    """Local filesystem fallback for development/tests only.

    Logs a warning at construction because Render redeploys wipe this
    directory; uploads made here are not durable across deploys.
    """

    WARNING_LOGGED = False

    def __init__(self):
        self.root = os.environ.get("STORAGE_LOCAL_DIR", "") or _default_local_dir()
        os.makedirs(self.root, exist_ok=True)
        if not LocalStorageBackend.WARNING_LOGGED:
            logger.warning(
                "Trip Vault is using LOCAL filesystem storage under %s. "
                "This is for local development only and is NOT persistent "
                "on Render. Configure S3_* / STORAGE_BACKEND=s3 for "
                "production.",
                self.root,
            )
            LocalStorageBackend.WARNING_LOGGED = True

    def _path(self, key):
        validate_key(key)

        relative = os.path.normpath(key)
        if relative.startswith("..") or os.path.isabs(relative):
            raise StorageError("Invalid storage key.")

        return os.path.join(self.root, relative)

    def upload(self, key, content, content_type):
        path = self._path(key)
        directory = os.path.dirname(path)
        os.makedirs(directory, exist_ok=True)
        try:
            with open(path, "wb") as handle:
                handle.write(content)
        except OSError as error:
            logger.error("Local storage upload failed for key=%s", key)
            raise StorageError("Failed to store the document.") from error

    def download(self, key):
        path = self._path(key)
        if not os.path.isfile(path):
            raise StorageError("The stored document could not be found.")
        try:
            with open(path, "rb") as handle:
                while True:
                    chunk = handle.read(65536)
                    if not chunk:
                        break
                    yield chunk
        except OSError as error:
            logger.error("Local storage download failed for key=%s", key)
            raise StorageError("Failed to read the document.") from error

    def delete(self, key):
        path = self._path(key)
        try:
            if os.path.isfile(path):
                os.remove(path)
        except OSError as error:
            logger.error("Local storage delete failed for key=%s", key)
            raise StorageError("Failed to delete the stored document.") from error


def get_storage_backend():
    """Return the configured storage backend singleton per name."""
    name = storage_backend_name()
    if name == "s3":
        return S3StorageBackend()
    return LocalStorageBackend()


def safe_content_disposition(file_name, is_inline):
    """Build a header-safe ``Content-Disposition`` value from a display name.

    ASCII ``filename`` plus a UTF-8 ``filename*`` fallback (RFC 6266) so
    accented / non-Latin file names survive browsers and download managers.
    """
    media_type = "inline" if is_inline else "attachment"
    ascii_name = (file_name or "document").encode("ascii", "replace").decode()
    ascii_name = ascii_name.replace('"', "_")
    disposition = '{}; filename="{}"'.format(media_type, ascii_name)
    if file_name and "\\" not in file_name:
        encoded = quote(file_name)
        disposition += "; filename*=UTF-8''{}".format(encoded)
    return disposition