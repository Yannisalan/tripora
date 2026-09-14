import logging
import uuid

from flask import Blueprint, Response, jsonify, request
from flask_jwt_extended import get_jwt_identity, jwt_required

from config.database import db
from models.trip import Trip
from models.trip_document import TripDocument
from services.storage_service import (
    StorageError,
    get_storage_backend,
    safe_content_disposition,
)

logger = logging.getLogger(__name__)


documents_bp = Blueprint(
    "documents",
    __name__,
    url_prefix="/api",
)

# ============================================================
# DOCUMENT VALIDATION CONSTANTS
# ============================================================
#
# Only PDF/PNG/JPG/JPEG documents are accepted for now. Validation never
# trusts the client: the extension, the declared MIME type and the first
# bytes of the file must all agree before a file is stored.

VALID_DOCUMENT_TYPES = {
    "flight",
    "hotel",
    "visa",
    "insurance",
    "transport",
    "activity",
    "other",
}

# extension -> (allowed MIME types, magic-byte matcher)
_PDF_MAGIC = b"%PDF-"
_PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
_JPEG_MAGIC = b"\xff\xd8\xff"

ALLOWED_FILES = {
    ".pdf": {
        "mime_types": {"application/pdf"},
        "magic": _PDF_MAGIC,
    },
    ".png": {
        "mime_types": {"image/png"},
        "magic": _PNG_MAGIC,
    },
    ".jpg": {
        "mime_types": {"image/jpeg", "image/pjpeg"},
        "magic": _JPEG_MAGIC,
    },
    ".jpeg": {
        "mime_types": {"image/jpeg", "image/pjpeg"},
        "magic": _JPEG_MAGIC,
    },
}

# 10 MB is comfortable for boarding passes, confirmations and insurance PDFs.
MAX_DOCUMENT_SIZE = 10 * 1024 * 1024


def _get_authenticated_user_id():
    user_id = get_jwt_identity()

    try:
        return int(user_id)
    except (TypeError, ValueError) as error:
        raise ValueError("Invalid authenticated user.") from error


def _lookup_owned_trip(trip_id, user_id):
    return Trip.query.filter_by(
        id=trip_id,
        user_id=user_id,
    ).first()


def _lookup_owned_document(document_id, user_id):
    return TripDocument.query.filter_by(
        id=document_id,
        user_id=user_id,
    ).first()


# ============================================================
# HELPERS — VALIDATION
# ============================================================

def _extension_of(file_name):
    name = (file_name or "").strip().lower()
    if not name or "." not in name:
        return None
    return "." + name.rsplit(".", 1)[-1]


def _sniff_magic(data):
    """Return the detected file type from magic bytes, or None."""
    if data.startswith(_PDF_MAGIC):
        return "pdf"
    if data.startswith(_PNG_MAGIC):
        return "png"
    if data.startswith(_JPEG_MAGIC):
        return "jpeg"
    return None


def _read_uploaded_file(upload):
    """Read a Werkzeug FileStorage into memory with a size guard.

    Parses nothing the client sent beyond the raw bytes; returns
    (bytes, declared_mime, original_name) or raises ValueError on
    an oversized/malformed upload.
    """
    if upload is None or not upload.filename:
        raise ValueError("No file was provided.")

    declared_mime = (upload.mimetype or "").split(";")[0].strip().lower()

    content_length = request.content_length
    if content_length is not None and content_length > MAX_DOCUMENT_SIZE:
        raise ValueError("File is too large. Maximum size is 10 MB.")

    data = upload.read(MAX_DOCUMENT_SIZE + 1)
    if len(data) > MAX_DOCUMENT_SIZE:
        raise ValueError("File is too large. Maximum size is 10 MB.")

    if not data:
        raise ValueError("The uploaded file is empty.")

    return data, declared_mime, upload.filename


def _validate_document_upload(name, document_type, data, declared_mime, original_name):
    """Validate metadata and file bytes. Returns (mime_type, storage_ext)."""
    if not name or not str(name).strip():
        raise ValueError("Document name is required.")

    if len(str(name).strip()) > 255:
        raise ValueError("Document name is too long.")

    if document_type not in VALID_DOCUMENT_TYPES:
        raise ValueError("Document type is invalid.")

    extension = _extension_of(original_name)
    if extension not in ALLOWED_FILES:
        raise ValueError("Unsupported file type. Please use PDF, PNG, JPG or JPEG.")

    rules = ALLOWED_FILES[extension]

    # Magic bytes are the final word on what the file actually is.
    detected = _sniff_magic(data)
    if detected is None:
        raise ValueError("Unsupported file type. Please use PDF, PNG, JPG or JPEG.")

    # "pdf" magic -> .pdf; "png" magic -> .png; "jpeg" magic matches .jpg/.jpeg.
    if (detected == "pdf" and extension != ".pdf") or \
       (detected == "png" and extension != ".png") or \
       (detected == "jpeg" and extension not in (".jpg", ".jpeg")):
        raise ValueError(
            "The file contents do not match its extension. "
            "Please upload a valid PDF, PNG, JPG or JPEG file."
        )

    if declared_mime and declared_mime not in rules["mime_types"]:
        raise ValueError(
            "The file type is not supported. Please use PDF, PNG, JPG or JPEG."
        )

    if detected == "pdf":
        mime_type = "application/pdf"
    elif detected == "png":
        mime_type = "image/png"
    else:
        mime_type = "image/jpeg"

    return mime_type, extension


# ============================================================
# LIST DOCUMENTS
# GET /api/trips/<trip_id>/documents
# ============================================================

@documents_bp.route("/trips/<int:trip_id>/documents", methods=["GET"])
@jwt_required()
def get_trip_documents(trip_id):

    try:
        user_id = _get_authenticated_user_id()
    except ValueError as error:
        return jsonify({
            "success": False,
            "message": str(error),
        }), 401

    try:
        trip = _lookup_owned_trip(trip_id, user_id)

        if trip is None:
            return jsonify({
                "success": False,
                "message": "Trip not found.",
            }), 404

        documents = TripDocument.query.filter_by(
            trip_id=trip_id,
            user_id=user_id,
        ).order_by(
            TripDocument.created_at.desc(),
        ).all()

        return jsonify({
            "success": True,
            "count": len(documents),
            "documents": [
                document.to_dict()
                for document in documents
            ],
        }), 200

    except Exception as error:

        logger.exception("Retrieving trip documents failed")

        return jsonify({
            "success": False,
            "message": "Failed to retrieve documents.",
            "error": "Internal server error.",
        }), 500


# ============================================================
# UPLOAD DOCUMENT
# POST /api/trips/<trip_id>/documents
# ============================================================

@documents_bp.route("/trips/<int:trip_id>/documents", methods=["POST"])
@jwt_required()
def upload_trip_document(trip_id):

    try:
        user_id = _get_authenticated_user_id()
    except ValueError as error:
        return jsonify({
            "success": False,
            "message": str(error),
        }), 401

    try:
        trip = _lookup_owned_trip(trip_id, user_id)

        if trip is None:
            return jsonify({
                "success": False,
                "message": "Trip not found.",
            }), 404
    except Exception as error:
        logger.exception("Looking up trip for document upload failed")
        return jsonify({
            "success": False,
            "message": "Failed to upload document.",
            "error": "Internal server error.",
        }), 500

    name = (request.form.get("name") or "").strip()
    document_type = (request.form.get("documentType") or "").strip().lower()

    try:
        data, declared_mime, original_name = _read_uploaded_file(
            request.files.get("file"),
        )
        mime_type, extension = _validate_document_upload(
            name,
            document_type,
            data,
            declared_mime,
            original_name,
        )
    except ValueError as error:
        return jsonify({
            "success": False,
            "message": str(error),
        }), 400

    storage_key = "trips/{}/{}".format(trip_id, uuid.uuid4().hex) + extension

    try:
        storage = get_storage_backend()
        storage.upload(storage_key, data, mime_type)
    except StorageError as error:
        logger.error("Document upload storage failure (trip=%s)", trip_id)
        return jsonify({
            "success": False,
            "message": str(error),
        }), 500

    document = TripDocument(
        trip_id=trip_id,
        user_id=user_id,
        name=name,
        document_type=document_type,
        file_name=original_name,
        storage_key=storage_key,
        mime_type=mime_type,
        file_size=len(data),
    )

    try:
        db.session.add(document)
        db.session.commit()
        logger.info("Document uploaded: id=%s trip=%s user=%s", document.id, trip_id, user_id)
    except Exception as error:
        db.session.rollback()

        # Best-effort cleanup so a failed metadata insert does not leave an
        # orphaned object in storage.
        try:
            storage.delete(storage_key)
        except Exception:
            logger.exception("Cleanup of orphaned document object failed")

        logger.exception("Saving trip document failed")

        return jsonify({
            "success": False,
            "message": "Failed to save document.",
            "error": "Internal server error.",
        }), 500

    return jsonify({
        "success": True,
        "message": "Document uploaded successfully.",
        "document": document.to_dict(),
    }), 201


# ============================================================
# ACCESS DOCUMENT FILE
# GET /api/documents/<document_id>
# ============================================================
#
# Streams the raw file to the authenticated owner only. The bytes are read
# from the storage backend and streamed here; no presigned/public URL is ever
# returned, and nothing about the document content is logged.

@documents_bp.route("/documents/<int:document_id>", methods=["GET"])
@jwt_required()
def get_document_file(document_id):

    try:
        user_id = _get_authenticated_user_id()
    except ValueError as error:
        return jsonify({
            "success": False,
            "message": str(error),
        }), 401

    try:
        document = _lookup_owned_document(document_id, user_id)

        if document is None:
            return jsonify({
                "success": False,
                "message": "Document not found.",
            }), 404

        is_image = document.mime_type.startswith("image/")

        def stream():
            try:
                storage = get_storage_backend()
                yield from storage.download(document.storage_key)
            except StorageError as error:
                logger.warning("Document stream failure id=%s: %s", document_id, error)
                raise

        return Response(
            stream(),
            status=200,
            headers={
                "Content-Type": document.mime_type,
                "Content-Disposition": safe_content_disposition(
                    document.file_name,
                    is_inline=is_image,
                ),
                "Content-Length": str(document.file_size),
                "Cache-Control": "private, no-store",
                "X-Content-Type-Options": "nosniff",
            },
        )

    except Exception as error:
        logger.exception("Accessing document failed")

        return jsonify({
            "success": False,
            "message": "Failed to access document.",
            "error": "Internal server error.",
        }), 500


# ============================================================
# DELETE DOCUMENT
# DELETE /api/documents/<document_id>
# ============================================================

@documents_bp.route("/documents/<int:document_id>", methods=["DELETE"])
@jwt_required()
def delete_trip_document(document_id):

    try:
        user_id = _get_authenticated_user_id()
    except ValueError as error:
        return jsonify({
            "success": False,
            "message": str(error),
        }), 401

    try:
        document = _lookup_owned_document(document_id, user_id)

        if document is None:
            return jsonify({
                "success": False,
                "message": "Document not found.",
            }), 404

        storage_key = document.storage_key

        # Remove the object first so a failed delete never leaves a metadata
        # row pointing at a missing file. If storage removal fails we keep the
        # row (the client keeps showing the document and can retry).
        storage = get_storage_backend()
        try:
            storage.delete(storage_key)
        except StorageError as error:
            logger.error("Document delete storage failure id=%s", document_id)
            return jsonify({
                "success": False,
                "message": str(error),
            }), 500

        db.session.delete(document)
        db.session.commit()

        logger.info("Document deleted: id=%s user=%s", document_id, user_id)

        return jsonify({
            "success": True,
            "message": "Document deleted successfully.",
            "documentId": document_id,
        }), 200

    except Exception as error:
        db.session.rollback()
        logger.exception("Deleting document failed")

        return jsonify({
            "success": False,
            "message": "Failed to delete document.",
            "error": "Internal server error.",
        }), 500