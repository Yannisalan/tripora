import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/design/glass/glass_tokens.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/destination_accents.dart';
import '../../core/utils/trip_dates.dart';
import '../../models/destination_model.dart';
import '../../models/trip_model.dart';
import '../../widgets/destination_image.dart';

/// Cinematic destination hero (Tripora 2.0 Home).
///
/// Two honest modes:
/// - [trip] set: the user's next real trip. The countdown and date range
///   come from the trip's own start/end dates; weather is shown only when
///   the existing per-trip weather endpoint returned a forecast.
/// - [trip] null: a discovery presentation of [destination] (the user's
///   Active Aura or a featured destination) with no dates, countdown or
///   weather, because none exist.
class HomeHero extends StatelessWidget {
  const HomeHero({
    super.key,
    required this.layout,
    required this.trip,
    required this.destination,
    required this.isActiveAura,
    required this.weather,
    required this.onOpenTrip,
    required this.onPlan,
    required this.onExplore,
  });

  final TriporaLayoutSize layout;
  final TripModel? trip;

  /// Image + description source. For a trip, the destination record whose
  /// city appears in the trip's destination text (may be null).
  final DestinationModel? destination;
  final bool isActiveAura;
  final Map<String, dynamic>? weather;
  final VoidCallback onOpenTrip;
  final ValueChanged<String> onPlan;
  final VoidCallback onExplore;

  static const Color _ink = TriporaBrand.navy;

  bool get _compact => layout == TriporaLayoutSize.compact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = (width * (_compact ? 0.95 : 0.42)).clamp(
          _compact ? 380.0 : 360.0,
          _compact ? 460.0 : 440.0,
        );

        return Semantics(
          container: true,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(
              _compact ? GlassRadius.md : GlassRadius.lg,
            ),
            // At least [height]; taller when large text or long
            // translations need it (never clipped).
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: height,
                minWidth: double.infinity,
              ),
              child: Stack(
                children: [
                  Positioned.fill(child: _buildImage(context)),
                  // Legibility scrims: a light top veil for the badges and
                  // a deep navy fall-off behind the bottom text block.
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x59080D1B),
                            Color(0x00080D1B),
                            Color(0xB3080D1B),
                            Color(0xF2080D1B),
                          ],
                          // The 70% navy stop sits above where the bottom text block
                          // begins at every hero size, so 12 px metadata stays
                          // >= 4.5:1 even over a white photo region.
                          stops: [0.0, 0.22, 0.45, 1.0],
                        ),
                      ),
                    ),
                  ),
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [Color(0x8C080D1B), Color(0x00080D1B)],
                          stops: [0.0, 0.7],
                        ),
                      ),
                    ),
                  ),
                  // Wider layouts: an extra bottom-up navy fall-off (90% at
                  // the bottom edge, clear by 60% of the height), so the
                  // left-grouped text stays readable over bright photos.
                  // Phones keep their original scrims unchanged.
                  if (!_compact)
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Color(0xE6080C1C), Color(0x00080C1C)],
                            stops: [0.0, 0.6],
                          ),
                        ),
                      ),
                    ),
                  ConstrainedBox(
                    constraints: BoxConstraints(minHeight: height),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: EdgeInsets.all(_compact ? 18 : 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildTopRow(context, width),
                            const SizedBox(height: 24),
                            const Spacer(),
                            _buildBottom(context, width),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------
  // Image
  // ---------------------------------------------------------------------

  Widget _buildImage(BuildContext context) {
    final accent = DestinationAccents.forDestination(destination).dark;
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            Color.alphaBlend(accent.withValues(alpha: 0.35), _ink),
            TriporaBrand.midnight,
            _ink,
          ],
        ),
      ),
    );

    final url = destination?.imageUrl;
    if (url == null) return fallback;

    // The navy fallback gradient doubles as the loading placeholder; the
    // photo fades in over it.
    return DestinationImage(
      url: url,
      alignment: const Alignment(0, -0.2),
      cacheWidth: 1600,
      placeholder: fallback,
      showErrorIcon: false,
    );
  }

  // ---------------------------------------------------------------------
  // Top row: countdown / context badge (left), weather (right)
  // ---------------------------------------------------------------------

  Widget _buildTopRow(BuildContext context, double width) {
    final t = trip;
    final String badge;
    final IconData badgeIcon;

    if (t != null) {
      badgeIcon = Icons.flight_takeoff_rounded;
      badge = _countdown(context, t);
    } else {
      badgeIcon = isActiveAura
          ? Icons.auto_awesome_rounded
          : Icons.explore_outlined;
      badge = context.tr(
        isActiveAura ? 'home.yourActiveAura' : 'home.featuredDestination',
      );
    }

    final weatherChip = _weatherChip(context);

    // Badge left, weather right, both at their natural width. When the
    // two do not fit on one line (a 320 px phone: "5 days to departure"
    // plus "14° / 8°") the weather chip moves to a second line instead of
    // either being cut off. Each chip is bounded by the row width, so a
    // very long translation ellipsizes rather than overflowing.
    final inner = width - (_compact ? 36 : 56);
    Widget bounded(Widget chip) => ConstrainedBox(
      constraints: BoxConstraints(maxWidth: inner),
      child: chip,
    );

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 10,
      runSpacing: 8,
      children: [
        bounded(_GlassChip(icon: badgeIcon, label: badge)),
        if (weatherChip != null) bounded(weatherChip),
      ],
    );
  }

  static String _countdown(BuildContext context, TripModel trip) {
    // Local calendar days; trip dates are date-only (see TripDates).
    final today = TripDates.today();
    final days = TripDates.daysBetween(today, trip.startDate);

    if (days > 1) {
      return context.tr('home.daysToDeparture', params: {'n': '$days'});
    }
    if (days == 1) return context.tr('home.dayToDeparture');
    if (days == 0) return context.tr('home.departsToday');

    // Trip already started (the hero only shows trips that have not ended).
    final total = trip.numberOfDays;
    final current = TripDates.daysBetween(trip.startDate, today) + 1;
    return context.tr(
      'home.tripInProgress',
      params: {'n': '$current', 'total': '$total'},
    );
  }

  Widget? _weatherChip(BuildContext context) {
    final w = weather;
    if (w == null || w['available'] != true) return null;
    final forecast = w['forecast'];
    if (forecast is! List || forecast.isEmpty || forecast.first is! Map) {
      return null;
    }
    final day = forecast.first as Map;
    final max = day['tempMax'];
    final min = day['tempMin'];
    if (max is! num || min is! num) return null;

    return _GlassChip(
      icon: _weatherIcon(day['icon']?.toString() ?? ''),
      label: '${max.round()}° / ${min.round()}°',
      caption: _compact ? null : context.tr('home.forecast'),
    );
  }

  static IconData _weatherIcon(String code) {
    switch (code) {
      case 'clear':
      case 'mostly_clear':
        return Icons.wb_sunny_outlined;
      case 'partly_cloudy':
        return Icons.wb_cloudy_outlined;
      case 'cloudy':
      case 'fog':
        return Icons.cloud_outlined;
      case 'drizzle':
      case 'rain':
      case 'freezing_rain':
        return Icons.water_drop_outlined;
      case 'snow':
        return Icons.ac_unit_rounded;
      case 'thunderstorm':
        return Icons.thunderstorm_outlined;
      default:
        return Icons.thermostat_outlined;
    }
  }

  // ---------------------------------------------------------------------
  // Bottom: metadata, title, description, then the actions, all grouped
  // on the left (no empty middle on wide heroes)
  // ---------------------------------------------------------------------

  /// Widest the bottom text group grows on wide heroes, so the title,
  /// description and buttons read as one block on the left.
  static const double _groupMaxWidth = 640;

  Widget _buildBottom(BuildContext context, double width) {
    final group = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildText(context),
        const SizedBox(height: 16),
        _buildActions(context),
      ],
    );

    if (_compact) return group;
    return Align(
      alignment: Alignment.bottomLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _groupMaxWidth),
        child: group,
      ),
    );
  }

  Widget _buildText(BuildContext context) {
    final t = trip;
    final d = destination;

    final String meta;
    final String title;
    final String? description;

    if (t != null) {
      final locale = Localizations.localeOf(context).toLanguageTag();
      final fmt = DateFormat('MMM d', locale);
      final days = t.numberOfDays;
      final dayLabel = days == 1
          ? context.tr('home.dayCount')
          : context.tr('home.daysCount', params: {'n': '$days'});
      meta =
          '${fmt.format(t.startDate)} — ${fmt.format(t.endDate)} • $dayLabel';
      title = t.destination;
      description = d?.description;
    } else if (d != null) {
      meta = [...d.tags.take(2), d.tripLength].join(' • ');
      // "Seychelles, Seychelles" -> "Seychelles" (city-states, islands).
      title = d.city == d.country ? d.city : d.fullName;
      description = d.description;
    } else {
      meta = '';
      title = context.tr('home.heroTitle');
      description = context.tr('home.heroDescription');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (meta.isNotEmpty) ...[
          Text(
            meta.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xE6FFFFFF),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.notoSerif(
            color: Colors.white,
            fontSize: _compact ? 32 : 46,
            height: 1.08,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
          ),
        ),
        if (description != null && description.isNotEmpty) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xEBFFFFFF),
                fontSize: 15,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    final t = trip;
    final d = destination;

    final buttons = <Widget>[
      if (t != null)
        _heroButton(
          label: context.tr('home.openTrip'),
          icon: Icons.arrow_outward_rounded,
          onPressed: onOpenTrip,
          primary: true,
        )
      else ...[
        _heroButton(
          label: context.tr('home.planThisTrip'),
          icon: Icons.auto_awesome_rounded,
          onPressed: () => onPlan(d?.fullName ?? ''),
          primary: true,
        ),
        _heroButton(
          label: context.tr('nav.explore'),
          icon: Icons.explore_outlined,
          onPressed: onExplore,
          primary: false,
        ),
      ],
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: buttons,
    );
  }

  Widget _heroButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    required bool primary,
  }) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(GlassRadius.sm),
    );
    const textStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w700);
    const padding = EdgeInsets.symmetric(horizontal: 16, vertical: 10);
    final label0 = Text(label, maxLines: 2, textAlign: TextAlign.center);

    if (primary) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
        label: label0,
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: padding,
          shape: shape,
          textStyle: textStyle,
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      label: label0,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: padding,
        shape: shape,
        textStyle: textStyle,
        foregroundColor: Colors.white,
        backgroundColor: const Color(0x66080D1B),
        side: const BorderSide(color: Color(0x99FFFFFF)),
      ),
    );
  }
}

/// Small frosted chip on the photo (countdown, weather).
class _GlassChip extends StatelessWidget {
  const _GlassChip({required this.icon, required this.label, this.caption});

  final IconData icon;
  final String label;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xB3080D1B),
        borderRadius: BorderRadius.circular(GlassRadius.pill),
        border: Border.all(color: const Color(0x40FFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
          if (caption != null) ...[
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                caption!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xD9FFFFFF),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
