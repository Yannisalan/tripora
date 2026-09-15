import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/rates_service.dart';

/// App-wide user preferences (language + currency).
///
/// Singleton [ChangeNotifier]: any widget can listen to it (or read values
/// directly) and every change is applied instantly, persisted locally in
/// SharedPreferences, and made available for the backend sync in the caller
/// (e.g. ProfileScreen -> PATCH /api/auth/me).
///
/// Money formatting routes through [formatMoney] which converts the given
/// amount from its own currency into the user's preferred currency using the
/// cached USD rate table. If rates are unavailable it honestly fallbacks to
/// the source currency label rather than quietly producing a wrong number.
class AppPreferences extends ChangeNotifier {
  AppPreferences._();

  static final AppPreferences instance = AppPreferences._();

  // ============================================================
  // VOCABULARY (kept in sync with backend VALID_LANGUAGES /
  // VALID_CURRENCIES in routes/auth.py)
  // ============================================================

  static const List<String> validLanguages = [
    'en',
    'es',
    'fr',
    'de',
    'it',
    'pt',
  ];

  static const List<String> validCurrencies = [
    'USD',
    'EUR',
    'GBP',
    'CAD',
    'AUD',
    'AED',
    'JPY',
    'CHF',
    'INR',
    'CFA',
  ];

  static const Map<String, String> _symbols = {
    'USD': r'$',
    'EUR': '€',
    'GBP': '£',
    'CAD': r'CA$',
    'AUD': r'A$',
    'AED': 'AED ',
    'JPY': '¥',
    'CHF': 'CHF ',
    'INR': '₹',
    'CFA': 'CFA ',
  };

  static const String _languageKey = 'preferred_language';
  static const String _currencyKey = 'preferred_currency';

  // ============================================================
  // STATE
  // ============================================================

  String _language = 'en';
  String _currency = 'USD';

  Map<String, double> _usdRates = const {};
  bool _ratesLoaded = false;

  String get language => _language;

  String get currency => _currency;

  Locale get locale => Locale(_language);

  bool get ratesLoaded => _ratesLoaded;

  static String symbolFor(String code) => _symbols[code] ?? '$code ';

  // ============================================================
  // PERSISTENCE
  // ============================================================

  /// Restores the persisted language/currency (called once at startup).
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    final storedLanguage = prefs.getString(_languageKey);
    final storedCurrency = prefs.getString(_currencyKey);

    if (storedLanguage != null && validLanguages.contains(storedLanguage)) {
      _language = storedLanguage;
    }

    if (storedCurrency != null && validCurrencies.contains(storedCurrency)) {
      _currency = storedCurrency;
    }

    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_languageKey, _language);
    await prefs.setString(_currencyKey, _currency);
  }

  // ============================================================
  // SETTERS (instant application + local persistence)
  // ============================================================

  /// Applies [newLanguage] immediately, notifies listeners, and persists it.
  /// Invalid codes are ignored so a stale SharedPreferences value can never
  /// leave the app in a broken state.
  Future<void> setLanguage(String newLanguage) async {
    if (!validLanguages.contains(newLanguage) || newLanguage == _language) {
      return;
    }

    _language = newLanguage;
    notifyListeners();
    await _persist();
  }

  /// Applies [newCurrency] immediately, notifies listeners, and persists it.
  Future<void> setCurrency(String newCurrency) async {
    if (!validCurrencies.contains(newCurrency) || newCurrency == _currency) {
      return;
    }

    _currency = newCurrency;
    notifyListeners();
    await _persist();

    // Refresh the conversion table in the background so amounts in the new
    // currency render as soon as possible.
    unawaited(ensureRates());
  }

  // ============================================================
  // RATES
  // ============================================================

  /// Loads (or refreshes) the USD rate table. Best-effort: failure never
  /// throws — the UI simply keeps rendering amounts in their source currency.
  Future<void> ensureRates({bool force = false}) async {
    try {
      _usdRates = await RatesService.fetchUsdRates(force: force);
      _ratesLoaded = true;
    } catch (error) {
      debugPrint('RATES FETCH ERROR: $error');
    }

    notifyListeners();
  }

  double? _usdRateFor(String code) {
    if (code == 'USD') {
      return 1.0;
    }

    return _usdRates[code];
  }

  /// Converts [value] from [from] currency into [to] (default: current
  /// preference). Returns the original value when no rate data is available.
  double convert(num value, {required String from, String? to}) {
    final target = (to ?? _currency).toUpperCase();
    final fromRate = _usdRateFor(from.toUpperCase());
    final toRate = _usdRateFor(target);

    if (fromRate == null || toRate == null || fromRate <= 0) {
      return value.toDouble();
    }

    return value.toDouble() * toRate / fromRate;
  }

  /// Formats [value] as a money string in the user's preferred currency,
  /// converting it from [from]. When conversion is impossible it shows the
  /// amount with an explicit source-code suffix so the number is never
  /// silently mislabelled.
  String formatMoney(
    num value, {
    required String from,
    String? to,
    int decimals = 2,
  }) {
    final target = (to ?? _currency).toUpperCase();
    final source = from.toUpperCase();

    final fromRate = _usdRateFor(source);
    final toRate = _usdRateFor(target);

    final String formatted;
    final String suffix;

    if (fromRate != null && toRate != null && fromRate > 0) {
      final converted = value.toDouble() * toRate / fromRate;
      formatted = converted.toStringAsFixed(decimals);
      suffix = '';
    } else {
      formatted = value.toDouble().toStringAsFixed(decimals);
      suffix = (source == target) ? '' : ' $source';
    }

    return '${symbolFor(target)}$formatted$suffix';
  }
}