import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/l10n/app_localizations.dart';
import '../../core/preferences/app_preferences.dart';
import '../../models/trip_model.dart';
import '../../services/weather_service.dart';

/// Displays the Open-Meteo forecast for a trip.
///
/// Fetches from GET /api/trips/<id>/weather.
/// The backend handles geocoding + forecast, so no API key is needed
/// in Flutter.
///
/// States:
/// loading
/// success
/// no-dates
/// no-destination
/// geocoding-failed
/// forecast-unavailable
/// trip-ended
/// network-error
/// manual-refresh
class TripWeatherScreen extends StatefulWidget {
  final TripModel trip;

  const TripWeatherScreen({
    super.key,
    required this.trip,
  });

  @override
  State<TripWeatherScreen> createState() => _TripWeatherScreenState();
}

class _TripWeatherScreenState extends State<TripWeatherScreen> {
  // ---------------------------------------------------------------------------
  // COLORS
  // ---------------------------------------------------------------------------

  static const Color _midnightDark = Color(0xFF070235);
  static const Color _blue = Color(0xFF3B82F6);
  static const Color _amber = Color(0xFFF59E0B);
  static const Color _emerald = Color(0xFF10B981);
  static const Color _surface = Color(0xFFF8FAFC);
  static const Color _white = Colors.white;
  static const Color _border = Color(0xFFE2E8F0);
  static const Color _slate300 = Color(0xFFCBD5E1);
  static const Color _slate400 = Color(0xFF94A3B8);
  static const Color _slate500 = Color(0xFF64748B);
  static const Color _text = Color(0xFF191C1E);

  // ---------------------------------------------------------------------------
  // STATE
  // ---------------------------------------------------------------------------

  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _data;

  // ---------------------------------------------------------------------------
  // WEATHER ICONS
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // LIFECYCLE
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ---------------------------------------------------------------------------
  // DATA LOADING
  // ---------------------------------------------------------------------------

  Future<void> _load({bool force = false}) async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final data = await WeatherService.fetchWeather(
        widget.trip.id!,
        force: force,
      );

      if (!mounted) return;

      setState(() {
        _data = data;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '').trim();
        _isLoading = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppPreferences.instance,
      builder: (context, _) {
        return _buildScaffold(context);
      },
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final lang = AppPreferences.instance.language;

    return Scaffold(
      backgroundColor: _surface,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context, lang),
          SliverToBoxAdapter(
            child: _buildBody(context, lang),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // APP BAR
  // ---------------------------------------------------------------------------

  Widget _buildAppBar(
    BuildContext context,
    String lang,
  ) {
    return SliverAppBar(
      expandedHeight: 140,
      pinned: true,
      backgroundColor: _midnightDark,
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_new,
          color: _white,
          size: 18,
        ),
        onPressed: () {
          Navigator.of(context).maybePop();
        },
      ),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsetsDirectional.only(
          start: 20,
          bottom: 16,
        ),
        title: Text(
          context.tr('weather.title'),
          style: const TextStyle(
            fontFamily: 'Manrope',
            color: _white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        background: Container(
          decoration: const BoxDecoration(
            color: _midnightDark,
          ),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(
                start: 20,
                bottom: 16,
              ),
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
            tooltip: context.tr('weather.refresh'),
            icon: const Icon(
              Icons.refresh,
              color: _slate300,
              size: 20,
            ),
            onPressed: () => _load(force: true),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // BODY
  // ---------------------------------------------------------------------------

  Widget _buildBody(
    BuildContext context,
    String lang,
  ) {
    if (_isLoading) {
      return _buildLoading();
    }

    if (_error != null) {
      return _buildError(
        context,
        _error!,
        lang,
      );
    }

    if (_data == null) {
      return _buildError(
        context,
        context.tr('weather.unknownError'),
        lang,
      );
    }

    final available = _data!['available'] as bool? ?? false;

    if (!available) {
      final reason = _data!['reason'] as String? ?? 'unknown';

      final message = _data!['message'] as String? ?? '';

      return _buildUnavailable(
        context,
        reason,
        message,
        lang,
      );
    }

    return _buildForecast(
      context,
      lang,
    );
  }

  // ---------------------------------------------------------------------------
  // LOADING
  // ---------------------------------------------------------------------------

  Widget _buildLoading() {
    return const Padding(
      padding: EdgeInsets.only(top: 80),
      child: Center(
        child: CircularProgressIndicator(
          color: _blue,
          strokeWidth: 2.5,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ERROR
  // ---------------------------------------------------------------------------

  Widget _buildError(
    BuildContext context,
    String message,
    String lang,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        20,
        40,
        20,
        40,
      ),
      child: Column(
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            color: _slate400,
            size: 56,
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('weather.error'),
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
          _retryButton(
            context,
            lang,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UNAVAILABLE
  // ---------------------------------------------------------------------------

  Widget _buildUnavailable(
    BuildContext context,
    String reason,
    String message,
    String lang,
  ) {
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
      padding: const EdgeInsets.fromLTRB(
        20,
        40,
        20,
        40,
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: iconColor,
            size: 56,
          ),
          const SizedBox(height: 16),
          Text(
            message.isNotEmpty
                ? message
                : context.tr('weather.unavailable'),
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
          _retryButton(
            context,
            lang,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // FORECAST
  // ---------------------------------------------------------------------------

  Widget _buildForecast(
    BuildContext context,
    String lang,
  ) {
    final location =
        _data!['location'] as Map<String, dynamic>? ?? {};

    final dates =
        _data!['dates'] as Map<String, dynamic>? ?? {};

    final forecast =
        _data!['forecast'] as List? ?? [];

    final locName =
        location['name'] as String? ?? '';

    final locCountry =
        location['country'] as String? ?? '';

    final forecastStart =
        dates['forecastStart'] as String? ?? '';

    final forecastEnd =
        dates['forecastEnd'] as String? ?? '';

    final currency =
        AppPreferences.instance.currency;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        16,
        16,
        16,
        32,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // -------------------------------------------------------------------
          // LOCATION
          // -------------------------------------------------------------------

          if (locName.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 7,
              ),
              decoration: BoxDecoration(
                color: _blue.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: _blue.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    size: 14,
                    color: _blue,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    [
                      locName,
                      locCountry,
                    ].where((s) => s.isNotEmpty).join(', '),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _blue,
                    ),
                  ),
                ],
              ),
            ),

          if (locName.isNotEmpty)
            const SizedBox(height: 12),

          // -------------------------------------------------------------------
          // DATE RANGE
          // -------------------------------------------------------------------

          if (forecastStart.isNotEmpty)
            Text(
              '${_formatDate(forecastStart, lang)} – '
              '${_formatDate(forecastEnd, lang)}',
              style: const TextStyle(
                fontSize: 12,
                color: _slate500,
                fontWeight: FontWeight.w500,
              ),
            ),

          const SizedBox(height: 20),

          // -------------------------------------------------------------------
          // FORECAST CARDS
          // -------------------------------------------------------------------

          if (forecast.isEmpty)
            _buildEmptyForecast(
              context,
              lang,
            )
          else
            ...forecast.map(
              (day) => _buildDayCard(
                context,
                day as Map<String, dynamic>,
                currency,
                lang,
              ),
            ),

          const SizedBox(height: 24),

          // -------------------------------------------------------------------
          // ATTRIBUTION
          // -------------------------------------------------------------------

          Center(
            child: Text(
              context.tr('weather.attribution'),
              style: const TextStyle(
                fontSize: 11,
                color: _slate400,
                fontFamily: 'Manrope',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DAY CARD
  // ---------------------------------------------------------------------------

  Widget _buildDayCard(
    BuildContext context,
    Map<String, dynamic> day,
    String currency,
    String lang,
  ) {
    final dateStr =
        day['date'] as String? ?? '';

    final iconCode =
        day['icon'] as String? ?? 'unknown';

    final fallbackLabel =
        day['label'] as String? ?? '';

    final label = _weatherLabel(
      context,
      iconCode,
      fallbackLabel,
    );

    final tempMax =
        day['tempMax'];

    final tempMin =
        day['tempMin'];

    final precipProb =
        day['precipitationProbability'];

    final icon =
        _iconMap[iconCode] ??
            Icons.help_outline;

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
        border: Border.all(
          color: _border,
        ),
      ),
      child: Row(
        children: [
          // -------------------------------------------------------------------
          // DAY + DATE
          // -------------------------------------------------------------------

          SizedBox(
            width: 72,
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  _dayName(
                    dateStr,
                    lang,
                  ),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _text,
                  ),
                ),
                Text(
                  _formatDate(
                    dateStr,
                    lang,
                  ),
                  style: const TextStyle(
                    fontSize: 11,
                    color: _slate400,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // -------------------------------------------------------------------
          // WEATHER ICON
          // -------------------------------------------------------------------

          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 22,
              color: accent,
            ),
          ),

          const SizedBox(width: 14),

          // -------------------------------------------------------------------
          // WEATHER LABEL
          // -------------------------------------------------------------------

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

          // -------------------------------------------------------------------
          // TEMPERATURE
          // -------------------------------------------------------------------

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

          // -------------------------------------------------------------------
          // PRECIPITATION
          // -------------------------------------------------------------------

          if (precipProb != null)
            Column(
              children: [
                const Icon(
                  Icons.water_drop_outlined,
                  size: 14,
                  color: _blue,
                ),
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

  // ---------------------------------------------------------------------------
  // EMPTY FORECAST
  // ---------------------------------------------------------------------------

  Widget _buildEmptyForecast(
    BuildContext context,
    String lang,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        children: [
          const Icon(
            Icons.calendar_today_outlined,
            color: _slate400,
            size: 44,
          ),
          const SizedBox(height: 12),
          Text(
            context.tr('weather.noForecast'),
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

  // ---------------------------------------------------------------------------
  // RETRY
  // ---------------------------------------------------------------------------

  Widget _retryButton(
    BuildContext context,
    String lang,
  ) {
    return OutlinedButton.icon(
      onPressed: () => _load(force: true),
      icon: const Icon(
        Icons.refresh,
        size: 16,
      ),
      label: Text(
        context.tr('weather.retry'),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: _blue,
        side: const BorderSide(
          color: _blue,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 10,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // WEATHER LABEL LOCALIZATION
  // ---------------------------------------------------------------------------

  String _weatherLabel(
    BuildContext context,
    String iconCode,
    String fallback,
  ) {
    switch (iconCode) {
      case 'clear':
        return context.tr('weather.clear');

      case 'mostly_clear':
        return context.tr('weather.mostlyClear');

      case 'partly_cloudy':
        return context.tr('weather.partlyCloudy');

      case 'cloudy':
        return context.tr('weather.cloudy');

      case 'fog':
        return context.tr('weather.fog');

      case 'drizzle':
        return context.tr('weather.drizzle');

      case 'rain':
        return context.tr('weather.rain');

      case 'freezing_rain':
        return context.tr('weather.freezingRain');

      case 'snow':
        return context.tr('weather.snow');

      case 'thunderstorm':
        return context.tr('weather.thunderstorm');

      default:
        return fallback;
    }
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  static String _fmtTemp(dynamic value) {
    if (value == null) {
      return '--';
    }

    if (value is num) {
      return value.round().toString();
    }

    return value.toString();
  }

  static String _formatDate(
    String dateStr,
    String lang,
  ) {
    if (dateStr.isEmpty) {
      return '';
    }

    try {
      final date = DateTime.parse(dateStr);
      final locale = _localeTag(lang);

      return DateFormat(
        'd MMM',
        locale,
      ).format(date);
    } catch (_) {
      return dateStr;
    }
  }

  static String _dayName(
    String dateStr,
    String lang,
  ) {
    if (dateStr.isEmpty) {
      return '';
    }

    try {
      final date = DateTime.parse(dateStr);
      final locale = _localeTag(lang);

      return DateFormat.EEEE(
        locale,
      ).format(date);
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