import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/l10n/app_localizations.dart';
import '../../core/preferences/app_preferences.dart';
import '../../models/trip_model.dart';
import '../../services/weather_service.dart';

/// Displays the Open-Meteo forecast for a trip.
///
/// Fetches from ``GET /api/trips/<id>/weather`` (the backend handles
/// geocoding + forecast; no API key in Flutter). Shows states:
/// loading · success · no-dates · no-destination · geocoding-failed ·
/// forecast-unavailable · trip-ended · network-error · manual-refresh.
class TripWeatherScreen extends StatefulWidget {
  final TripModel trip;

  const TripWeatherScreen({super.key, required this.trip});

  @override
  State<TripWeatherScreen> createState() => _TripWeatherScreenState();
}

class _TripWeatherScreenState extends State<TripWeatherScreen> {
  // ---- colours (Tripora palette) ----
  static const Color _midnight = Color(0xFF1E1B4B);
  static const Color _midnightDark = Color(0xFF070235);
  static const Color _blue = Color(0xFF3B82F6);
  static const Color _sky = Color(0xFF38BDF8);
  static const Color _amber = Color(0xFFF59E0B);
  static const Color _emerald = Color(0xFF10B981);
  static const Color _surface = Color(0xFFF8FAFC);
  static const Color _white = Colors.white;
  static const Color _border = Color(0xFFE2E8F0);
  static const Color _slate100 = Color(0xFFF1F5F9);
  static const Color _slate200 = Color(0xFFE2E8F0);
  static const Color _slate300 = Color(0xFFCBD5E1);
  static const Color _slate400 = Color(0xFF94A3B8);
  static const Color _slate500 = Color(0xFF64748B);
  static const Color _text = Color(0xFF191C1E);

  // ---- state ----
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _data;

  // ---- icon mapping for weather icon codes ----
  static const Map<String, IconData> _iconMap = {
    'clear': Icons.wb_sunny_outlined,
    'mostly_clear': Icons.wb_sunny_outlined,
    'partly_cloudy': Icons.cloud_outlined,
    'cloudy': Icons.cloud_outlined,
    'fog': Icons.foggy,
    'drizzle': Icons.grain_outlined,
    'rain': Icons.umbrella_outlined,
    'freezing_rain': Icons.ac_unit_outlined,
    'snow': Icons.ac_unit_outlined,
    'thunderstorm': Icons.thunderstorm_outlined,
    'unknown': Icons.help_outline,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ---- data loading ----

  Future<void> _load({bool force = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final data = await WeatherService.fetchWeather(
        widget.trip.id!,
        force: force,
      );
      if (mounted) {
        setState(() {
          _data = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    final lang = AppPreferences.instance.language;

    return Scaffold(
      backgroundColor: _surface,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(lang),
          SliverToBoxAdapter(child: _buildBody(lang)),
        ],
      ),
    );
  }

  // ---- app bar ----

  Widget _buildAppBar(String lang) {
    return SliverAppBar(
      expandedHeight: 140,
      pinned: true,
      backgroundColor: _midnightDark,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: _white, size: 18),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsetsDirectional.only(start: 20, bottom: 16),
        title: Text(
          AppLocalizations.resolve('weather.title', lang),
          style: const TextStyle(
            fontFamily: 'Manrope',
            color: _white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        background: Container(
          decoration: const BoxDecoration(color: _midnightDark),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 20, bottom: 16),
              child: Text(
                widget.trip.destination,
                style: const TextStyle(
                  fontFamily: 'Noto Serif',
                  color: Color(0xFF94A3B8),
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ),
      actions: [
        if (!_isLoading)
          IconButton(
            icon: const Icon(Icons.refresh, color: _slate300, size: 20),
            onPressed: () => _load(force: true),
          ),
      ],
    );
  }

  // ---- body ----

  Widget _buildBody(String lang) {
    if (_isLoading) return _buildLoading();
    if (_error != null) return _buildError(_error!, lang);
    if (_data == null) return _buildError('Unknown error.', lang);

    final available = _data!['available'] as bool? ?? false;
    if (!available) {
      final reason = _data!['reason'] as String? ?? 'unknown';
      final message = _data!['message'] as String? ?? '';
      return _buildUnavailable(reason, message, lang);
    }

    return _buildForecast(lang);
  }

  // ---- loading ----

  Widget _buildLoading() {
    return const Padding(
      padding: EdgeInsets.only(top: 80),
      child: Center(
        child: CircularProgressIndicator(color: _blue, strokeWidth: 2.5),
      ),
    );
  }

  // ---- error ----

  Widget _buildError(String message, String lang) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 40),
      child: Column(
        children: [
          Icon(Icons.cloud_off_outlined, color: _slate400, size: 56),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.resolve('weather.error', lang),
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: _slate500,
            ),
          ),
          const SizedBox(height: 20),
          _retryButton(lang),
        ],
      ),
    );
  }

  // ---- unavailable (no dates / geocoding failed / forecast unavailable / trip ended) ----

  Widget _buildUnavailable(String reason, String message, String lang) {
    IconData icon;
    Color iconColor;

    switch (reason) {
      case 'missing_dates':
        icon = Icons.date_range_outlined;
        iconColor = _amber;
        break;
      case 'no_destination':
        icon = Icons.location_off_outlined;
        iconColor = _slate400;
        break;
      case 'geocoding_failed':
        icon = Icons.location_off_outlined;
        iconColor = _amber;
        break;
      case 'trip_ended':
        icon = Icons.check_circle_outline;
        iconColor = _emerald;
        break;
      default:
        icon = Icons.cloud_off_outlined;
        iconColor = _slate400;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 40),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 56),
          const SizedBox(height: 16),
          Text(
            message.isNotEmpty
                ? message
                : AppLocalizations.resolve('weather.unavailable', lang),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: _text,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          _retryButton(lang),
        ],
      ),
    );
  }

  // ---- forecast (success) ----

  Widget _buildForecast(String lang) {
    final location = _data!['location'] as Map<String, dynamic>? ?? {};
    final dates = _data!['dates'] as Map<String, dynamic>? ?? {};
    final forecast = _data!['forecast'] as List? ?? [];

    final locName = location['name'] as String? ?? '';
    final locCountry = location['country'] as String? ?? '';
    final forecastStart = dates['forecastStart'] as String? ?? '';
    final forecastEnd = dates['forecastEnd'] as String? ?? '';

    final currency = AppPreferences.instance.currency;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- location chip ----
          if (locName.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: _blue.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _blue.withValues(alpha: 0.25)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.location_on_outlined, size: 14, color: _blue),
                  const SizedBox(width: 6),
                  Text(
                    [locName, locCountry].where((s) => s.isNotEmpty).join(', '),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _blue,
                    ),
                  ),
                ],
              ),
            ),

          if (locName.isNotEmpty) const SizedBox(height: 12),

          // ---- date range ----
          if (forecastStart.isNotEmpty)
            Text(
              '${_formatDate(forecastStart, lang)} – ${_formatDate(forecastEnd, lang)}',
              style: const TextStyle(
                fontSize: 12,
                color: _slate500,
                fontWeight: FontWeight.w500,
              ),
            ),

          const SizedBox(height: 20),

          // ---- forecast cards ----
          if (forecast.isEmpty)
            _buildEmptyForecast(lang)
          else
            ...forecast.map((day) => _buildDayCard(day, currency, lang)),
        ],
      ),
    );
  }

  // ---- day card ----

  Widget _buildDayCard(
    Map<String, dynamic> day,
    String currency,
    String lang,
  ) {
    final dateStr = day['date'] as String? ?? '';
    final iconCode = day['icon'] as String? ?? 'unknown';
    final label = day['label'] as String? ?? '';
    final tempMax = day['tempMax'];
    final tempMin = day['tempMin'];
    final precipProb = day['precipitationProbability'];
    final windMax = day['windSpeedMax'];

    final icon = _iconMap[iconCode] ?? Icons.help_outline;

    // Color-code by icon type
    Color accent;
    switch (iconCode) {
      case 'clear':
      case 'mostly_clear':
        accent = _amber;
        break;
      case 'rain':
      case 'drizzle':
      case 'freezing_rain':
        accent = _blue;
        break;
      case 'snow':
        accent = const Color(0xFF93C5FD);
        break;
      case 'thunderstorm':
        accent = const Color(0xFFF97316);
        break;
      default:
        accent = _slate400;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          // ---- day + date ----
          SizedBox(
            width: 72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _dayName(dateStr, lang),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _text,
                  ),
                ),
                Text(
                  _formatDate(dateStr, lang),
                  style: const TextStyle(
                    fontSize: 11,
                    color: _slate400,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // ---- icon ----
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 22, color: accent),
          ),

          const SizedBox(width: 14),

          // ---- label ----
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _slate500,
              ),
            ),
          ),

          // ---- temps ----
          Text(
            '${_fmtTemp(tempMax)}°',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _text,
            ),
          ),
          Text(
            ' / ${_fmtTemp(tempMin)}°',
            style: const TextStyle(
              fontSize: 13,
              color: _slate400,
            ),
          ),

          const SizedBox(width: 10),

          // ---- precip % ----
          if (precipProb != null)
            Column(
              children: [
                Icon(Icons.water_drop_outlined, size: 14, color: _blue),
                Text(
                  '$precipProb%',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _blue,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ---- empty forecast ----

  Widget _buildEmptyForecast(String lang) {
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        children: [
          Icon(Icons.calendar_today_outlined, color: _slate400, size: 44),
          const SizedBox(height: 12),
          Text(
            AppLocalizations.resolve('weather.noForecast', lang),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _slate500,
            ),
          ),
        ],
      ),
    );
  }

  // ---- retry button ----

  Widget _retryButton(String lang) {
    return OutlinedButton.icon(
      onPressed: () => _load(force: true),
      icon: const Icon(Icons.refresh, size: 16),
      label: Text(AppLocalizations.resolve('weather.retry', lang)),
      style: OutlinedButton.styleFrom(
        foregroundColor: _blue,
        side: const BorderSide(color: _blue),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      ),
    );
  }

  // ---- helpers ----

  static String _fmtTemp(dynamic value) {
    if (value == null) return '--';
    if (value is num) return value.round().toString();
    return value.toString();
  }

  static String _formatDate(String dateStr, String lang) {
    if (dateStr.isEmpty) return '';
    try {
      final d = DateTime.parse(dateStr);
      final locale = _localeTag(lang);
      return DateFormat('d MMM', locale).format(d);
    } catch (_) {
      return dateStr;
    }
  }

  static String _dayName(String dateStr, String lang) {
    if (dateStr.isEmpty) return '';
    try {
      final d = DateTime.parse(dateStr);
      final locale = _localeTag(lang);
      return DateFormat.EEEE(locale).format(d);
    } catch (_) {
      return '';
    }
  }

  static String _localeTag(String lang) {
    const map = {
      'en': 'en',
      'es': 'es',
      'fr': 'fr',
      'de': 'de',
      'it': 'it',
      'pt': 'pt_BR',
    };
    return map[lang] ?? 'en';
  }
}
