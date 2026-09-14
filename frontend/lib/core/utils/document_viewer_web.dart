import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web viewer: wraps the bytes in a ``Blob`` and opens its object URL in a
/// new tab. Works for every stored type — the browser renders PDFs and
/// images directly and downloads anything it cannot display.
Future<bool> displayDocument({
  required Uint8List bytes,
  required String mimeType,
  required String fileName,
}) async {
  final blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );

  final url = web.URL.createObjectURL(blob);

  if (url.isEmpty) {
    return false;
  }

  web.window.open(url, '_blank');

  return true;
}