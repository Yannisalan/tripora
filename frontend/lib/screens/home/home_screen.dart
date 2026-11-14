import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frontend/screens/main_shell.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/auth/login_gate.dart';
import '../../core/design/glass/glass_surface.dart';
import '../../core/design/glass/glass_tokens.dart';
import '../../core/preferences/active_aura.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/trip_dates.dart';
import '../../core/l10n/app_localizations.dart';
import '../../data/destinations.dart';
import '../../models/destination_model.dart';
import '../../models/trip_model.dart';
import '../../routes/app_routes.dart';
import '../../services/trip_service.dart';
import '../../services/weather_service.dart';
import '../trip_details.dart';
import '../../widgets/active_aura_selector.dart';
import '../../widgets/shimmer_loader.dart';
import '../../widgets/theme_toggle.dart';
import '../../widgets/tripora_brand.dart';
import 'home_dashboard_parts.dart';
import 'home_hero.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.showAppBar = true});

  /// When false (global web top-nav layout), the inner app bar with the
  /// inline "Tripora" brand + Plan Trip button is suppressed because the
  /// web header already provides both.
  final bool showAppBar;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TripService _tripService = TripService();

  List<TripModel> _trips = [];
  bool _isLoadingTrips = true;
  String? _tripError;

  final TextEditingController _command = TextEditingController();

  /// Forecast for the hero trip, only when the existing weather endpoint
  /// returned one; never synthesized.
  Map<String, dynamic>? _heroWeather;
  int? _heroWeatherTripId;

  /// Shown in the discovery hero when the user has no upcoming trip and no
  /// Active Aura: the first of Home's existing featured destinations.
  static const String _featuredCity = 'Seychelles';

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  @override
  void dispose() {
    _command.dispose();
    super.dispose();
  }

  /// The next trip that has not ended yet (earliest start first).
  TripModel? get _heroTrip {
    final today = TripDates.today();
    final upcoming = _trips
        .where((t) => !TripDates.calendarDate(t.endDate).isBefore(today))
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    return upcoming.isEmpty ? null : upcoming.first;
  }

  /// The destination record whose city appears in a trip's free-text
  /// destination, used only for its photo and description.
  static DestinationModel? _destinationFor(String text) {
    final lower = text.toLowerCase();
    for (final d in destinations) {
      if (lower.contains(d.city.toLowerCase())) return d;
    }
    return null;
  }

  static DestinationModel get _featured =>
      destinations.firstWhere(
        (d) => d.city == _featuredCity,
        orElse: () => destinations.first,
      );

  Future<void> _loadHeroWeather() async {
    final trip = _heroTrip;
    final id = trip?.id;
    if (id == null || id == _heroWeatherTripId) return;
    _heroWeatherTripId = id;
    try {
      final data = await WeatherService.fetchWeather(id);
      if (!mounted || _heroTrip?.id != id) return;
      setState(() => _heroWeather = data);
    } catch (_) {
      // No forecast: the hero simply shows no weather.
      if (!mounted) return;
      setState(() => _heroWeather = null);
    }
  }

  void _runCommand(String text) {
    final aura = ActiveAura.instance.destination;
    final destination = text.isNotEmpty ? text : aura?.fullName;
    _openPlanner(destination);
  }

  Future<void> _loadTrips() async {
    if (!mounted) return;

    setState(() {
      _isLoadingTrips = true;
      _tripError = null;
    });

    try {
      final trips = await _tripService.getTrips();

      if (!mounted) return;

      setState(() {
        _trips = trips;
        _isLoadingTrips = false;
      });
      _loadHeroWeather();
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isLoadingTrips = false;
        _tripError = error.toString().replaceFirst('Exception: ', '').trim();
      });
    }
  }

  void _openPlanner([String? destination]) {
    HapticFeedback.lightImpact();

    // Requires a signed-in user: guests are sent to Login and continue to
    // the Planner (with the same prefill) once they sign in.
    LoginGate.open(
      context,
      route: AppRoutes.planner,
      arguments: destination,
    );
  }

  void _openExplore() {
    MainShell.currentIndex.value = 1;
  }

  void _openTrips() {
    Navigator.pushNamed(context, AppRoutes.trips).then((_) => _loadTrips());
  }

  void _openTrip(TripModel trip) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TripDetailsScreen(trip: trip)),
    ).then((_) => _loadTrips());
  }

  // ---------------------------------------------------------------------------
  // Main build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colors = context.triporaColors;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: widget.showAppBar ? _buildAppBar() : null,
      body: RefreshIndicator(
        color: scheme.primary,
        backgroundColor: colors.surface,
        onRefresh: _loadTrips,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;

            final layout = TriporaBreakpoints.sizeFor(width);
            final isMobile = layout == TriporaLayoutSize.compact;
            final isTablet = layout == TriporaLayoutSize.medium;

            final horizontalPadding = isMobile
                ? 16.0
                : isTablet
                ? 24.0
                : 40.0;

            const maxContentWidth = 1280.0;

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(
                left: horizontalPadding,
                right: horizontalPadding,
                top: isMobile ? 16 : 28,
                bottom: (isMobile ? 24 : 36) +
                    GlassNavMetrics.bottomClearance(context),
              ),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: maxContentWidth,
                    ),
                    child: ListenableBuilder(
                      listenable: ActiveAura.instance,
                      builder: (context, _) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Below the sidebar breakpoint the Active Aura
                          // selector lives here instead of the sidebar.
                          if (widget.showAppBar) ...[
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: SizedBox(
                                width: 320,
                                child: ActiveAuraSelector(),
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                          _buildHero(layout),
                          const SizedBox(height: 16),
                          _buildCommandBar(isMobile),
                          SizedBox(height: isMobile ? 28 : 36),
                          AccentAuraStrip(
                            destinations: destinations,
                            selectedCity: ActiveAura.instance.destination?.city,
                            onSelected: (d) => ActiveAura.instance.select(d),
                          ),
                          SizedBox(height: isMobile ? 40 : 52),
                          _buildTripSnapshot(isMobile, isTablet),
                          SizedBox(height: isMobile ? 44 : 56),
                          _buildQuickActions(isMobile, isTablet),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // App bar
  // ---------------------------------------------------------------------------

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 16,
      // Same wordmark as the desktop sidebar. Scales down (never clips)
      // when a 320 px phone at large text leaves little room beside the
      // actions.
      title: const FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: TriporaWordmark(),
      ),
      actions: [
        // Compact/medium layouts have no sidebar: direct Light/Dark toggle.
        const ThemeToggleButton(),
        const SizedBox(width: 4),
        Padding(
          padding: const EdgeInsets.only(right: 16),
          // Sized to its label (no fixed width), so long translations such
          // as "Pianifica un Viaggio" fit; capped so the brand title keeps
          // its room, wrapping to a second line only when it must.
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.55,
            ),
            child: _primaryButton(
              label: context.tr('nav.planTrip'),
              icon: Icons.add_rounded,
              onPressed: () => _openPlanner(),
              height: 44,
              horizontalPadding: 12,
              shrinkWrap: true,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Hero
  // ---------------------------------------------------------------------------

  Widget _buildHero(TriporaLayoutSize layout) {
    final trip = _heroTrip;
    final aura = ActiveAura.instance.destination;

    if (trip != null) {
      return HomeHero(
        layout: layout,
        trip: trip,
        destination: _destinationFor(trip.destination),
        isActiveAura: false,
        weather: _heroWeather,
        onOpenTrip: () => _openTrip(trip),
        onPlan: _openPlanner,
        onExplore: _openExplore,
      );
    }
    return HomeHero(
      layout: layout,
      trip: null,
      destination: aura ?? _featured,
      isActiveAura: aura != null,
      weather: null,
      onOpenTrip: () {},
      onPlan: _openPlanner,
      onExplore: _openExplore,
    );
  }

  Widget _buildCommandBar(bool isMobile) {
    final aura = ActiveAura.instance.destination;

    return AiCommandBar(
      controller: _command,
      compact: isMobile,
      auraCity: aura?.city,
      onRun: _runCommand,
      chips: [
        if (aura != null)
          AiCommandChip(
            label: context.tr('home.chipPlanCity', params: {'city': aura.city}),
            icon: Icons.auto_awesome_rounded,
            onTap: () => _openPlanner(aura.fullName),
          ),
        AiCommandChip(
          label: context.tr('home.exploreDestinations'),
          icon: Icons.explore_outlined,
          onTap: _openExplore,
        ),
        AiCommandChip(
          label: context.tr('home.chipFlights'),
          icon: Icons.flight_takeoff_rounded,
          onTap: () => MainShell.currentIndex.value = 2,
        ),
        AiCommandChip(
          label: context.tr('nav.trips'),
          icon: Icons.card_travel_outlined,
          onTap: _openTrips,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Trips
  // ---------------------------------------------------------------------------

  Widget _buildTripSnapshot(bool isMobile, bool isTablet) {
    if (_isLoadingTrips) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading(
            title: context.tr('home.yourJourneys'),
            eyebrow: context.tr('home.savedTripsEyebrow'),
            trailing: null,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              TripCardShimmer(isCompact: isMobile),
              if (!isMobile) TripCardShimmer(isCompact: false),
              if (!isMobile && !isTablet) TripCardShimmer(isCompact: false),
            ],
          ),
        ],
      );
    }

    if (_tripError != null) {
      return _buildTripError();
    }

    if (_trips.isEmpty) {
      return _buildEmptyTrips();
    }

    final recentTrips = _trips
        .take(
          isMobile
              ? 2
              : isTablet
              ? 2
              : 3,
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeading(
          title: context.tr(
            'home.savedTripsCount',
            params: {'n': _trips.length.toString()},
          ),
          eyebrow: context.tr('home.yourJourneys'),
          trailing: TextButton.icon(
            onPressed: _openTrips,
            icon: const Icon(Icons.arrow_forward_rounded, size: 16),
            label: Text(context.tr('common.viewAll')),
            style: TextButton.styleFrom(
              foregroundColor: context.headingColor,
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),

        const SizedBox(height: 16),

        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = isMobile
                ? constraints.maxWidth
                : isTablet
                ? (constraints.maxWidth - 16) / 2
                : (constraints.maxWidth - 32) / 3;

            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: recentTrips.map((trip) {
                return SizedBox(width: cardWidth, child: _buildTripCard(trip));
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildTripCard(TripModel trip) {
    final colors = context.triporaColors;

    return GlassSurface(
      variant: GlassVariant.card,
      borderRadius: BorderRadius.circular(GlassRadius.md),
      padding: const EdgeInsets.all(20),
      onTap: () => _openTrip(trip),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: TriporaBrand.crimsonDeep,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.flight_takeoff_rounded,
                  color: Colors.white,
                  size: 19,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.arrow_outward_rounded,
                size: 18,
                color: colors.textMuted,
              ),
            ],
          ),

          const SizedBox(height: 22),

          Text(
            trip.destination,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.notoSerif(
              color: context.headingColor,
              fontSize: 22,
              height: 1.2,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            context.tr(
              'home.tripDuration',
              params: {
                'days': trip.numberOfDays.toString(),
                'travelers': trip.travelers.toString(),
              },
            ),
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(height: 18),

          Container(height: 1, color: colors.border),

          const SizedBox(height: 14),

          Row(
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                size: 15,
                color: context.appStatus.success,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  context.tr('home.savedItinerary'),
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyTrips() {
    final colors = context.triporaColors;
    final scheme = Theme.of(context).colorScheme;

    return GlassSurface(
      variant: GlassVariant.card,
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.surfaceSecondary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.luggage_outlined, color: scheme.primary),
          ),

          const SizedBox(width: 16),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('home.noSavedJourneys'),
                  style: GoogleFonts.notoSerif(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: context.headingColor,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  context.tr('home.createFirstItinerary'),
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          _primaryButton(
            label: context.tr('home.plan'),
            icon: Icons.add_rounded,
            onPressed: () => _openPlanner(),
            height: 44,
            horizontalPadding: 15,
          ),
        ],
      ),
    );
  }

  Widget _buildTripError() {
    final tripError = _tripError ?? '';

    final isAuthError =
        tripError.contains('logged in') ||
        tripError.contains('session') ||
        tripError.contains('log in');

    final isNetworkError =
        tripError.contains('refused') ||
        tripError.contains('not found') ||
        tripError.contains('connection');

    final Color accent = isAuthError
        ? context.appStatus.info
        : isNetworkError
        ? context.appStatus.warning
        : context.appStatus.error;

    final IconData icon = isAuthError
        ? Icons.lock_outline_rounded
        : isNetworkError
        ? Icons.wifi_off_outlined
        : Icons.cloud_off_outlined;

    final String message = isAuthError
        ? context.tr('home.signInToSeeTrips')
        : isNetworkError
        ? context.tr('home.serverConnectionError')
        : context.tr('home.loadTripsError');

    return GlassSurface(
      variant: GlassVariant.card,
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Text(
              message,
              style: TextStyle(color: accent, fontSize: 13, height: 1.4),
            ),
          ),

          const SizedBox(width: 8),

          Flexible(
            child: TextButton(
              onPressed: isAuthError
                  ? () => Navigator.pushNamed(
                      context,
                      AppRoutes.login,
                    ).then((_) => _loadTrips())
                  : _loadTrips,
              style: TextButton.styleFrom(
                foregroundColor: context.headingColor,
              ),
              child: Text(
                isAuthError
                    ? context.tr('home.signIn')
                    : context.tr('common.retry'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Quick actions
  // ---------------------------------------------------------------------------

  Widget _buildQuickActions(bool isMobile, bool isTablet) {
    final colors = context.triporaColors;

    final actions = [
      _ActionItem(
        icon: Icons.search_rounded,
        title: context.tr('home.findIdeas'),
        subtitle: context.tr('home.browseByInterest'),
        label: context.tr('home.exploreLabel'),
        onTap: _openExplore,
      ),
      _ActionItem(
        icon: Icons.auto_awesome_rounded,
        title: context.tr('home.buildTrip'),
        subtitle: context.tr('home.createAiItinerary'),
        label: context.tr('home.aiPlannerLabel'),
        onTap: () => _openPlanner(),
      ),
      _ActionItem(
        icon: Icons.luggage_outlined,
        title: context.tr('home.manageTrips'),
        subtitle: context.tr('home.viewEditPlans'),
        label: context.tr('home.yourTripsLabel'),
        onTap: _openTrips,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('home.travelDesk'),
          style: TextStyle(
            color: colors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),

        const SizedBox(height: 8),

        Text(
          context.tr('home.everythingForJourney'),
          style: GoogleFonts.notoSerif(
            color: context.headingColor,
            fontSize: 26,
            fontWeight: FontWeight.w600,
          ),
        ),

        const SizedBox(height: 18),

        LayoutBuilder(
          builder: (context, constraints) {
            final width = isMobile
                ? constraints.maxWidth
                : isTablet
                ? (constraints.maxWidth - 16) / 2
                : (constraints.maxWidth - 32) / 3;

            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: actions.map((action) {
                return SizedBox(width: width, child: _buildActionCard(action));
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildActionCard(_ActionItem action) {
    final colors = context.triporaColors;

    return GlassSurface(
      variant: GlassVariant.card,
      borderRadius: BorderRadius.circular(GlassRadius.md),
      padding: const EdgeInsets.all(20),
      onTap: action.onTap,
      child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: TriporaBrand.crimsonDeep,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(action.icon, color: Colors.white, size: 21),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.label,
                      style: TextStyle(
                        color: colors.textMuted,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.9,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      action.title,
                      style: TextStyle(
                        color: context.headingColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      action.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textMuted,
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              Icon(
                Icons.arrow_forward_rounded,
                size: 17,
                color: colors.textMuted,
              ),
            ],
          ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared components
  // ---------------------------------------------------------------------------

  Widget _sectionHeading({
    required String title,
    required String eyebrow,
    required Widget? trailing,
  }) {
    final colors = context.triporaColors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow,
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                title,
                style: GoogleFonts.notoSerif(
                  color: context.headingColor,
                  fontSize: 27,
                  height: 1.15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
        ),

        ?trailing,
      ],
    );
  }

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    double height = 48,
    double horizontalPadding = 22,
    // Size to the label instead of the theme's full-width minimum; the
    // label may wrap to two lines rather than truncate.
    bool shrinkWrap = false,
  }) {
    return SizedBox(
      height: shrinkWrap ? null : height,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
        label: shrinkWrap
            ? Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
              )
            : Text(label),
        style: ElevatedButton.styleFrom(
          minimumSize: shrinkWrap ? Size(0, height) : null,
          // Brand fill (deep AA crimson + white), as the filled buttons.
          backgroundColor: TriporaBrand.crimsonDeep,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
      ),
    );
  }

}

// -----------------------------------------------------------------------------
// Action model
// -----------------------------------------------------------------------------

class _ActionItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final String label;
  final VoidCallback onTap;

  const _ActionItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.label,
    required this.onTap,
  });
}
