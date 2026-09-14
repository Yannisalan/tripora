/// Opens a fetched document in the platform's viewer.
///
/// The rest of the app imports ``document_viewer.dart`` and calls
/// ``displayDocument(...)``. The real implementation is platform-specific:
///
/// - **Desktop / mobile** — writes the bytes to a temp file and asks the OS
///   to open it (``document_viewer_io.dart``).
/// - **Web** — builds a ``Blob`` object URL from the bytes and opens it in a
///   new tab (``document_viewer_web.dart``).
///
/// Both paths work exclusively with the authenticated bytes the API streams
/// back; no public URL is ever involved.
library;

export 'document_viewer_stub.dart'
    if (dart.library.js_interop) 'document_viewer_web.dart'
    if (dart.library.io) 'document_viewer_io.dart';