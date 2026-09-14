/// A single travel document stored in a trip's Vault.
///
/// Mirrors the backend ``trip_documents`` row. Only metadata lives on the
/// device; the actual bytes are fetched on demand through the authenticated
/// ``GET /api/documents/<id>`` endpoint.
class TripDocumentModel {
  final int id;
  final int tripId;

  final String name;
  final String documentType;
  final String fileName;
  final String mimeType;
  final int fileSize;

  final DateTime? createdAt;

  const TripDocumentModel({
    required this.id,
    required this.tripId,
    required this.name,
    required this.documentType,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
    this.createdAt,
  });

  /// Parse from the camelCase object the backend returns in its
  /// ``documents`` / ``document`` payloads.
  factory TripDocumentModel.fromJson(Map<String, dynamic> json) {
    final dynamic rawId = json['id'];
    final int parsedId = rawId is int
        ? rawId
        : int.tryParse(rawId?.toString() ?? '') ?? 0;

    final dynamic rawTripId = json['tripId'] ?? json['trip_id'];
    final int parsedTripId = rawTripId is int
        ? rawTripId
        : int.tryParse(rawTripId?.toString() ?? '') ?? 0;

    final dynamic rawSize = json['fileSize'] ?? json['file_size'];
    final int parsedSize = rawSize is int
        ? rawSize
        : int.tryParse(rawSize?.toString() ?? '') ?? 0;

    final dynamic rawCreatedAt = json['createdAt'] ?? json['created_at'];

    return TripDocumentModel(
      id: parsedId,
      tripId: parsedTripId,
      name: json['name']?.toString() ?? 'Document',
      documentType: json['documentType']?.toString() ?? 'other',
      fileName: json['fileName']?.toString() ?? '',
      mimeType: json['mimeType']?.toString() ?? 'application/octet-stream',
      fileSize: parsedSize,
      createdAt: rawCreatedAt != null
          ? DateTime.tryParse(rawCreatedAt.toString())
          : null,
    );
  }

  // ============================================================
  // DISPLAY HELPERS
  // ============================================================

  bool get isImage {
    final mime = mimeType.toLowerCase();
    return mime.startsWith('image/');
  }

  String get extension {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0) {
      return '';
    }

    return fileName.substring(dot + 1).toUpperCase();
  }

  String get formattedSize {
    if (fileSize < 1024) {
      return '$fileSize B';
    }

    if (fileSize < 1024 * 1024) {
      final kb = fileSize / 1024;
      return '${kb.toStringAsFixed(kb >= 10 ? 0 : 1)} KB';
    }

    final mb = fileSize / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}