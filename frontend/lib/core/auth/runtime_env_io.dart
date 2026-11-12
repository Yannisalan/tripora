import 'dart:io' show Platform;

/// True while the app is running under `flutter test` / `dart test`.
///
/// The test runner sets the `FLUTTER_TEST` environment variable. Unit tests
/// run inside a fake-async zone where the native keystore plugin never
/// completes, so [TokenStore] uses its plain-storage path there.
final bool kIsTest = _detectTest();

bool _detectTest() {
  final env = Platform.environment;
  return env['FLUTTER_TEST'] == 'true' || env['DART_TEST'] == 'true';
}
