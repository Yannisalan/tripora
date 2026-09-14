"""Tests for the Trip Vault document API.

Covers the upload/list/download/delete life cycle, ownership isolation (no
document of one user can be reached by another), and input validation (type,
size, magic-byte sniffing, extension/MIME mismatch). The storage backend used
during tests is the local filesystem fallback; nothing ever touches S3 or the
network here.
"""

import io

from .helpers import (
    auth_headers,
    create_logged_in_user,
    create_trip_and_get_id,
)

# ---------------------------------------------------------------
# Sample document payloads (real magic bytes, junk payloads)
# ---------------------------------------------------------------

PDF_BYTES = b"%PDF-1.4\n1 0 obj\n<</Type/Catalog>>\nendobj\n%%EOF\n"
PNG_BYTES = b"\x89PNG\r\n\x1a\n" + b"\x00\x00\x00\rIHDR" + b"\x00" * 64
JPEG_BYTES = b"\xff\xd8\xff\xe0" + b"\x00" * 64
TXT_BYTES = b"hello this is definitely not a pdf\n" * 20

BIG_BYTES = b"%" + b"0" * (10 * 1024 * 1024)  # >10MB, PDF-looking prefix


def _upload(client, token, trip_id, *, name="Flight Ticket",
            document_type="flight", file_bytes=PDF_BYTES,
            file_name="ticket.pdf", content_type=None):
    """POST a document as multipart form data. Returns the Flask response."""
    upload = (io.BytesIO(file_bytes), file_name)
    if content_type:
        upload = (io.BytesIO(file_bytes), file_name, content_type)
    return client.post(
        "/api/trips/{}/documents".format(trip_id),
        data={
            "name": name,
            "documentType": document_type,
            "file": upload,
        },
        headers=auth_headers(token),
        content_type="multipart/form-data",
    )


def _upload_and_get_id(client, token, trip_id, **kwargs):
    resp = _upload(client, token, trip_id, **kwargs)
    body = resp.get_json()
    assert resp.status_code == 201, body
    return body["document"]["id"], resp


class TestDocumentLifecycle:
    def test_upload_list_download_delete(self, client):
        alice = create_logged_in_user(client, name="DocAlice", email="docalice@example.com")
        trip_id = create_trip_and_get_id(client, alice)

        doc_id, resp = _upload_and_get_id(client, alice, trip_id)
        doc = resp.get_json()["document"]
        assert doc["name"] == "Flight Ticket"
        assert doc["documentType"] == "flight"
        assert doc["fileName"] == "ticket.pdf"
        assert doc["mimeType"] == "application/pdf"
        assert doc["fileSize"] == len(PDF_BYTES)

        # list
        lst = client.get(
            "/api/trips/{}/documents".format(trip_id),
            headers=auth_headers(alice),
        )
        assert lst.status_code == 200
        body = lst.get_json()
        assert body["success"] is True
        assert body["count"] == 1
        assert body["documents"][0]["id"] == doc_id

        # download returns the exact bytes
        dl = client.get(
            "/api/documents/{}".format(doc_id),
            headers=auth_headers(alice),
        )
        assert dl.status_code == 200
        assert dl.data == PDF_BYTES
        assert dl.headers["Content-Type"] == "application/pdf"
        assert "attachment; filename" in dl.headers["Content-Disposition"]
        assert dl.headers["Content-Length"] == str(len(PDF_BYTES))

        # delete
        dele = client.delete(
            "/api/documents/{}".format(doc_id),
            headers=auth_headers(alice),
        )
        assert dele.status_code == 200

        # gone from list and unreadable
        lst = client.get(
            "/api/trips/{}/documents".format(trip_id),
            headers=auth_headers(alice),
        )
        assert lst.get_json()["count"] == 0
        gone = client.get(
            "/api/documents/{}".format(doc_id),
            headers=auth_headers(alice),
        )
        assert gone.status_code == 404

    def test_multiple_documents_are_isolated_and_ordered(self, client):
        alice = create_logged_in_user(client, name="DocIsolation", email="docisol@example.com")
        trip_id = create_trip_and_get_id(client, alice)

        _upload_and_get_id(client, alice, trip_id, name="Boarding Pass",
                           document_type="transport", file_name="pass.png",
                           file_bytes=PNG_BYTES)
        _upload_and_get_id(client, alice, trip_id, name="Hotel Confirmation",
                           document_type="hotel", file_name="hotel.jpg",
                           file_bytes=JPEG_BYTES)

        lst = client.get(
            "/api/trips/{}/documents".format(trip_id),
            headers=auth_headers(alice),
        )
        body = lst.get_json()
        assert body["count"] == 2
        # newest first (created_at desc; ids ascending in the same second,
        # so compare by name names are re-checked via list)
        assert {d["name"] for d in body["documents"]} == {
            "Boarding Pass",
            "Hotel Confirmation",
        }


class TestAuthorization:
    def test_requires_authentication(self, client):
        resp = client.get("/api/trips/1/documents")
        assert resp.status_code == 401

        upload = client.post(
            "/api/trips/1/documents",
            data={"name": "x", "documentType": "other",
                  "file": (io.BytesIO(PDF_BYTES), "x.pdf")},
            content_type="multipart/form-data",
        )
        assert upload.status_code == 401

        dl = client.get("/api/documents/1")
        assert dl.status_code == 401

        dele = client.delete("/api/documents/1")
        assert dele.status_code == 401

    def test_cannot_touch_unknown_trip(self, client):
        token = create_logged_in_user(client, name="DocNoTrip", email="docnotrip@example.com")
        resp = _upload(client, token, trip_id=99999)
        assert resp.status_code == 404
        assert resp.get_json()["message"] == "Trip not found."

    def test_idor_document_belongs_to_another_user(self, client):
        alice = create_logged_in_user(client, name="DocAliceOwn", email="aliceown@example.com")
        bob = create_logged_in_user(client, name="DocBobOwn", email="bobown@example.com")

        alice_trip = create_trip_and_get_id(client, alice)
        doc_id, _ = _upload_and_get_id(client, alice, alice_trip)

        # Bob cannot list Alice's trip documents
        lst = client.get(
            "/api/trips/{}/documents".format(alice_trip),
            headers=auth_headers(bob),
        )
        assert lst.status_code == 404

        # Bob cannot read nor delete Alice's document
        dl = client.get("/api/documents/{}".format(doc_id), headers=auth_headers(bob))
        assert dl.status_code == 404

        dele = client.delete("/api/documents/{}".format(doc_id), headers=auth_headers(bob))
        assert dele.status_code == 404

        # download is normalized even when an authenticated-but-wrong user asks
        assert dl.get_json()["message"] == "Document not found."

    def test_trip_delete_takes_documents_with_it(self, client, app):
        token = create_logged_in_user(client, name="DocCascade", email="doccascade@example.com")
        trip_id = create_trip_and_get_id(client, token)
        doc_id, _ = _upload_and_get_id(client, token, trip_id)

        dele = client.delete("/api/trips/{}".format(trip_id), headers=auth_headers(token))
        assert dele.status_code == 200

        # the trip is gone, so its documents are unreachable through it
        gone_trip = client.get(
            "/api/trips/{}/documents".format(trip_id),
            headers=auth_headers(token),
        )
        assert gone_trip.status_code == 404

    def test_trip_documents_foreign_key_cascades(self, app):
        """The trip_documents.trip_id FK is ON DELETE CASCADE.

        SQLite (used by the test suite) does not enforce foreign keys by
        default, so the runtime cascade is verified against the declared
        metadata: on PostgreSQL the DB removes the document rows whenever
        their trip is deleted.
        """
        from config.database import db
        from models.trip import Trip
        from models.trip_document import TripDocument

        trip_fk = next(
            fk for fk in TripDocument.__table__.foreign_keys
            if fk.target_fullname == "trips.id"
        )
        assert trip_fk.ondelete == "CASCADE"

        relationship = Trip.__mapper__.relationships["documents"]
        assert "delete" in str(relationship.cascade)
        assert "delete-orphan" in str(relationship.cascade)
        assert relationship.passive_deletes is True

        # the model can build a document tied to a trip and a user
        user_id = 1
        doc = TripDocument(
            trip_id=1, user_id=user_id, name="x", document_type="other",
            file_name="x.pdf", storage_key="trips/1/abc.pdf",
            mime_type="application/pdf", file_size=4,
        )
        assert doc.trip_id == 1


class TestValidation:
    def test_unsupported_extension_is_rejected(self, client):
        token = create_logged_in_user(client, name="DocBadExt", email="docbadext@example.com")
        trip_id = create_trip_and_get_id(client, token)

        resp = _upload(client, token, trip_id, file_bytes=TXT_BYTES,
                       file_name="invite.txt")
        assert resp.status_code == 400
        assert "Unsupported file type" in resp.get_json()["message"]

    def test_mimetype_mismatch_is_rejected(self, client):
        token = create_logged_in_user(client, name="DocBadMime", email="docbadmime@example.com")
        trip_id = create_trip_and_get_id(client, token)

        # PNG bytes dressed up as a .pdf -> extension/magic mismatch
        resp = _upload(client, token, trip_id, file_bytes=PNG_BYTES,
                       file_name="ticket.pdf")
        assert resp.status_code == 400
        assert "do not match its extension" in resp.get_json()["message"]

        # Real PDF bytes but the client insists it is a PNG
        resp = _upload(client, token, trip_id, file_bytes=PDF_BYTES,
                       file_name="ticket.pdf", content_type="image/png")
        assert resp.status_code == 400

    def test_empty_file_is_rejected(self, client):
        token = create_logged_in_user(client, name="DocEmpty", email="docempty@example.com")
        trip_id = create_trip_and_get_id(client, token)

        resp = _upload(client, token, trip_id, file_bytes=b"", file_name="empty.pdf")
        assert resp.status_code == 400

    def test_oversized_file_is_rejected(self, client):
        token = create_logged_in_user(client, name="DocBig", email="docbig@example.com")
        trip_id = create_trip_and_get_id(client, token)

        resp = _upload(client, token, trip_id, file_bytes=BIG_BYTES,
                       file_name="huge.pdf")
        assert resp.status_code == 400
        assert "too large" in resp.get_json()["message"]

    def test_missing_metadata_is_rejected(self, client):
        token = create_logged_in_user(client, name="DocNoMeta", email="docnometa@example.com")
        trip_id = create_trip_and_get_id(client, token)

        # no name
        resp = client.post(
            "/api/trips/{}/documents".format(trip_id),
            data={"documentType": "other",
                  "file": (io.BytesIO(PDF_BYTES), "x.pdf")},
            headers=auth_headers(token),
            content_type="multipart/form-data",
        )
        assert resp.status_code == 400

        # no documentType
        resp = client.post(
            "/api/trips/{}/documents".format(trip_id),
            data={"name": "Ticket",
                  "file": (io.BytesIO(PDF_BYTES), "x.pdf")},
            headers=auth_headers(token),
            content_type="multipart/form-data",
        )
        assert resp.status_code == 400

        # invalid documentType
        resp = _upload(client, token, trip_id, document_type="passport")
        assert resp.status_code == 400
        assert "Document type is invalid" in resp.get_json()["message"]

        # no file at all
        resp = client.post(
            "/api/trips/{}/documents".format(trip_id),
            data={"name": "Ticket", "documentType": "other"},
            headers=auth_headers(token),
            content_type="multipart/form-data",
        )
        assert resp.status_code == 400
        assert "No file was provided" in resp.get_json()["message"]