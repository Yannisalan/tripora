import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'runtime_env.dart';

/// Single source of truth for the stored login session.
///
/// Both the short-lived **access token** and long-lived **refresh token** are
/// stored in the platform secure storage ([FlutterSecureStorage]) where
/// available. There is no plaintext fallback to [SharedPreferences].
///
/// On platforms where secure storage is unavailable (e.g. some web contexts
/// without secure context, or unit tests where the native plugin is not
/// registered), tokens are retained only in memory for the lifetime of this
/// process. Legacy tokens stored in [SharedPreferences] under
/// [accessTokenKey] are migrated into secure storage on first access and then
/// deleted from [SharedPreferences].
class TokenStore {
  TokenStore._();

  static final TokenStore instance = TokenStore._();

  /// Preference / keystore key for the access token.
  static const String accessTokenKey = 'access_token';

  /// Key for the refresh token.
  static const String refreshTokenKey = 'refresh_token';

  static const FlutterSecureStorage _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  /// Forces secure storage usage for testing. When `true`, secure storage is
  /// attempted even on platforms that would normally skip it. When `false`,
  /// secure storage is skipped (memory-only). Leave `null` for platform
  /// defaults.
  @visibleForTesting
  static bool? debugForceSecureStorage;

  /// In-memory cache used when secure storage is unavailable or throws.
  String? _memoryAccessToken;
  String? _memoryRefreshToken;
  bool _legacyMigrated = false;

  /// Resets in-memory state for testing.
  @visibleForTesting
  void resetForTesting() {
    _memoryAccessToken = null;
    _memoryRefreshToken = null;
    _legacyMigrated = false;
  }

  bool get _useSecureStorage {
    if (debugForceSecureStorage != null) {
      if (debugForceSecureStorage!) {
        // Allow forcing secure storage even in tests to exercise the keystore
        // path; actual plugin availability is still handled defensively.
        return true;
      }
      return false;
    }
    // Use secure storage on all platforms where the plugin is available.
    if (kIsWeb) {
      return true;
    }
    if (kIsTest) {
      // In unit tests the native plugin is typically not registered. Attempt
      // secure storage but fall back to memory-only on failure (no plaintext
      // prefs fallback).
      return true;
    }
    return true;
  }

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<void> _migrateLegacyAccessToken() async {
    if (_legacyMigrated) {
      return;
    }
    _legacyMigrated = true;

    try {
      final prefs = await _prefs;
      final legacy = prefs.getString(accessTokenKey);
      if (legacy == null || legacy.trim().isEmpty) {
        return;
      }

      // Migrate to secure storage if possible.
      if (_useSecureStorage) {
        try {
          await _secure.write(key: accessTokenKey, value: legacy);
          await prefs.remove(accessTokenKey);
          _memoryAccessToken = null;
          // Try to read back from secure storage
          try {
            final stored = await _secure.read(key: accessTokenKey);
            if (stored != null && stored.trim().isNotEmpty) {
              _memoryAccessToken = stored;
            }
          } catch (_) {}
          return;
        } catch (_) {
          // If migration to secure storage fails, keep in memory only (no
          // plaintext fallback) and still remove the legacy prefs copy.
          _memoryAccessToken = legacy;
          await prefs.remove(accessTokenKey);
          return;
        }
      } else {
        _memoryAccessToken ??= legacy;
        await prefs.remove(accessTokenKey);
        return;
      }
    } catch (_) {
      // Migration is best-effort.
    }
  }

  /// Persists a freshly issued session. Both tokens are written to secure
  /// storage when available. If secure storage is unavailable, tokens are kept
  /// only in memory (no SharedPreferences fallback). When [refreshToken] is
  /// null or empty the previous refresh token (if any) is left untouched.
  Future<void> saveSession({
    required String accessToken,
    String? refreshToken,
  }) async {
    await _migrateLegacyAccessToken();

    final access = accessToken.trim();
    if (access.isEmpty) {
      // Do not clear existing session if an empty access token is passed.
    } else {
      if (_useSecureStorage) {
        try {
          await _secure.write(key: accessTokenKey, value: access);
          _memoryAccessToken = null;
        } catch (_) {
          // Secure storage unavailable - keep in memory only.
          _memoryAccessToken = access;
        }
      } else {
        _memoryAccessToken = access;
      }
    }

    final refresh = refreshToken?.trim() ?? '';
    if (refresh.isEmpty) {
      return;
    }

    if (_useSecureStorage) {
      try {
        await _secure.write(key: refreshTokenKey, value: refresh);
        _memoryRefreshToken = null;
      } catch (_) {
        // Secure storage unavailable - keep in memory only.
        _memoryRefreshToken = refresh;
      }
    } else {
      _memoryRefreshToken = refresh;
    }
  }

  Future<String?> readAccessToken() async {
    await _migrateLegacyAccessToken();

    if (_memoryAccessToken != null && _memoryAccessToken!.trim().isNotEmpty) {
      return _memoryAccessToken;
    }

    if (_useSecureStorage) {
      try {
        final stored = await _secure.read(key: accessTokenKey);
        if (stored != null && stored.trim().isNotEmpty) {
          return stored;
        }
      } catch (_) {
        // Fall through to memory (already checked).
      }
    }

    // Fallback for tests/pre-migration scenarios where secure storage is
    // unavailable - check memory again and also check if it was just migrated
    // to memory.
    if (_memoryAccessToken != null && _memoryAccessToken!.trim().isNotEmpty) {
      return _memoryAccessToken;
    }

    return null;
  }

  Future<String?> readRefreshToken() async {
    await _migrateLegacyAccessToken();

    if (_memoryRefreshToken != null && _memoryRefreshToken!.trim().isNotEmpty) {
      return _memoryRefreshToken;
    }

    if (_useSecureStorage) {
      try {
        final stored = await _secure.read(key: refreshTokenKey);
        if (stored != null && stored.trim().isNotEmpty) {
          return stored;
        }
      } catch (_) {
        // Fall through to memory.
      }
    }

    return null;
  }

  /// True when any part of a session is present. A missing access token is
  /// fine as long as a refresh token exists — it will be renewed on demand.
  Future<bool> hasSession() async {
    final access = await readAccessToken();
    if (access != null && access.trim().isNotEmpty) {
      return true;
    }

    final refresh = await readRefreshToken();
    return refresh != null && refresh.trim().isNotEmpty;
  }

  /// Removes every trace of the session from both stores.
  Future<void> clear() async {
    await _migrateLegacyAccessToken();

    _memoryAccessToken = null;
    _memoryRefreshToken = null;

    try {
      final prefs = await _prefs;
      await prefs.remove(accessTokenKey);
      await prefs.remove(refreshTokenKey);
    } catch (_) {}

    if (_useSecureStorage) {
      try {
        await _secure.delete(key: accessTokenKey);
      } catch (_) {}
      try {
        await _secure.delete(key: refreshTokenKey);
      } catch (_) {}
    }
  }
}


