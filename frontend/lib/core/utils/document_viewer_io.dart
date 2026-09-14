import 'dart:io';
import 'dart:typed_data';

import 'package:url_launcher/url_launcher.dart';

/// Desktop / mobile viewer: spills the bytes to a temp file and lets the OS
/// open it with its default application (PDF reader, image viewer, ...).
/// Returns true if the platform accepted the launch request.
Future<bool> displayDocument({
  required Uint8List bytes,
  required String mimeType,
  required String fileName,
}) async {
  final safeName = (fileName.isEmpty ? 'document.pdf' : fileName)
      .replaceAll(RegExp(r'[^\w.\- ]'), '_');

  final directory = await Directory.systemTemp.createTemp('tripora_doc_');
  final file = File('${directory.path}${Platform.pathSeparator}$safeName');

  await file.writeAsBytes(bytes, flush: true);

  return launchUrl(Uri.file(file.path));
}