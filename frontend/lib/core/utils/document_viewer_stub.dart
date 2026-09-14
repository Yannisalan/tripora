import 'dart:typed_data';

/// Fallback viewer for platforms that are neither IO nor web (unused in
/// practice). Kept so the conditional import in ``document_viewer.dart``
/// always has a default branch to resolve against.
Future<bool> displayDocument({
  required Uint8List bytes,
  required String mimeType,
  required String fileName,
}) async {
  return false;
}