import 'package:flutter/foundation.dart' show kReleaseMode, debugPrint;

/// Prints a log message in debug builds only.
///
/// In release mode this is a no-op, so no debug output leaks into
/// production logs or console.
void appLog(String message) {
  if (kReleaseMode) {
    return;
  }

  debugPrint(message);
}
