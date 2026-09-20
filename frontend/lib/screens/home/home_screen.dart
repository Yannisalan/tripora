import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frontend/screens/main_shell.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../../core/l10n/app_localizations.dart';
import '../../data/destinations.dart';
import '../../models/trip_model.dart';
import '../../routes/app_routes.dart';
import '../../services/trip_service.dart';
import '../trip_details.dart';
import '../../widgets/shimmer_loader.dart';

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

  // ---------------------------------------------------------------------------
  // Nocturne Voyage design tokens
  // ---------------------------------------------------------------------------

  static const Color midnight = Color(0xFF1E1B4B);
  static const Color white = Color(0xFFFFFFFF);

  @override
  void initState() {
    super.initState();
    _loadTrips();
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

    Navigator.pushNamed(context, AppRoutes.planner, arguments: destination);
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
      backgroundColor: colors.backgroundColor,
      appBar: widget.showAppBar ? _buildAppBar() : null,
      body: RefreshIndicator(
        color: scheme.primary,
        backgroundColor: colors.surface,
        onRefresh: _loadTrips,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;

            final isMobile = width < 768;
            final isTablet = width >= 768 && width < 1024;

            final horizontalPadding = isMobile
                ? 16.0
                : isTablet
                ? 24.0
                : 40.0;

            const maxContentWidth = 1280.0;

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: isMobile ? 24 : 36,
              ),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: maxContentWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHero(isMobile),
                        SizedBox(height: isMobile ? 40 : 56),
                        _buildTripSnapshot(isMobile, isTablet),
                        SizedBox(height: isMobile ? 44 : 56),
                        _buildDestinationsHeader(isMobile),
                        const SizedBox(height: 18),
                        _buildDestinationStrip(isMobile),
                        SizedBox(height: isMobile ? 44 : 56),
                        _buildQuickActions(isMobile, isTablet),
                      ],
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
    final colors = context.triporaColors;

    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: colors.backgroundColor,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 20,
      title: Text(
        'Tripora',
        style: GoogleFonts.manrope(
          color: context.headingColor,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: SizedBox(
            width: 120,
            child: _primaryButton(
              label: context.tr('nav.planTrip'),
              icon: Icons.add_rounded,
              onPressed: () => _openPlanner(),
              height: 44,
              horizontalPadding: 8,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Hero
  // ---------------------------------------------------------------------------

  Widget _buildHero(bool isMobile) {
    final colors = context.triporaColors;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 24 : 40),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A1E1B4B),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: colors.surfaceSecondary,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: colors.border),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome_rounded, size: 14, color: context.appStatus.info),
                  const SizedBox(width: 7),
                  Text(
                    context.tr('home.aiPoweredTravelPlanning'),
                    style: TextStyle(
                      color: context.headingColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          Text(
            context.tr('home.heroTitle'),
            style: GoogleFonts.notoSerif(
              color: context.headingColor,
              fontSize: isMobile ? 34 : 48,
              height: 1.08,
              fontWeight: FontWeight.w600,
              letterSpacing: -1.1,
            ),
          ),

          const SizedBox(height: 16),

          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: Text(
              context.tr('home.heroDescription'),
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 16,
                height: 1.55,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),

          const SizedBox(height: 28),

          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _primaryButton(
                label: context.tr('home.startPlanning'),
                icon: Icons.auto_awesome_rounded,
                onPressed: () => _openPlanner(),
                height: 48,
              ),
              _secondaryButton(
                label: context.tr('home.exploreDestinations'),
                icon: Icons.explore_outlined,
                onPressed: _openExplore,
                height: 48,
              ),
            ],
          ),

          const SizedBox(height: 28),

          Container(height: 1, color: colors.border),

          const SizedBox(height: 18),

          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _HeroMeta(
                    icon: Icons.schedule_outlined,
                    label: context.tr('home.personalized'),
                  ),
                  const SizedBox(width: 16),
                  _HeroMeta(
                    icon: Icons.auto_awesome_outlined,
                    label: context.tr('home.aiGenerated'),
                  ),
                  const SizedBox(width: 16),
                  _HeroMeta(
                    icon: Icons.public_outlined,
                    label: context.tr('home.global'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _openTrip(trip),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.flight_takeoff_rounded,
                      color: scheme.onPrimary,
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
                  Text(
                    context.tr('home.savedItinerary'),
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyTrips() {
    final colors = context.triporaColors;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
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
        : const Color(0xFFBA1A1A);

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

    final colors = context.triporaColors;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
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

          TextButton(
            onPressed: isAuthError
                ? () => Navigator.pushNamed(
                    context,
                    AppRoutes.login,
                  ).then((_) => _loadTrips())
                : _loadTrips,
            style: TextButton.styleFrom(foregroundColor: context.headingColor),
            child: Text(
              isAuthError
                  ? context.tr('home.signIn')
                  : context.tr('common.retry'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Destinations
  // ---------------------------------------------------------------------------

  Widget _buildDestinationsHeader(bool isMobile) {
    return _sectionHeading(
      title: context.tr('home.popularDestinations'),
      eyebrow: context.tr('home.curatedForYou'),
      trailing: TextButton(
        onPressed: _openExplore,
        style: TextButton.styleFrom(foregroundColor: context.headingColor),
        child: Text(
          context.tr('common.seeAll'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildDestinationStrip(bool isMobile) {
    const featuredKeys = {'Seychelles', 'Paris', 'Cotonou', 'Tokyo', 'Bali'};

    final featured = destinations
        .where((d) => featuredKeys.contains(d.city))
        .toList();

    final list = featured.length >= 2
        ? featured
        : destinations.take(5).toList();

    return SizedBox(
      height: isMobile ? 330 : 350,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final destination = list[index];

          return SizedBox(
            width: isMobile ? 280 : 310,
            child: _editorialDestinationCard(destination),
          );
        },
      ),
    );
  }

  Widget _editorialDestinationCard(dynamic destination) {
    final colors = context.triporaColors;
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openPlanner(destination.fullName),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 6,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      destination.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: colors.surfaceSecondary,
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            color: colors.textMuted,
                            size: 32,
                          ),
                        );
                      },
                    ),

                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 90,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              midnight.withValues(alpha: 0.72),
                            ],
                          ),
                        ),
                      ),
                    ),

                    Positioned(
                      left: 16,
                      bottom: 14,
                      right: 16,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              destination.city,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.notoSerif(
                                color: white,
                                fontSize: 25,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.arrow_outward_rounded,
                            color: white,
                            size: 19,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        destination.country.toUpperCase(),
                        style: TextStyle(
                          color: colors.textMuted,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),

                      const SizedBox(height: 7),

                      Expanded(
                        child: Text(
                          destination.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      Row(
                        children: [
                          Icon(
                            Icons.schedule_outlined,
                            size: 14,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              destination.tripLength,
                              style: TextStyle(
                                color: context.headingColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
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
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(action.icon, color: scheme.onPrimary, size: 21),
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
        ),
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
  }) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: height,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
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

  Widget _secondaryButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    double height = 48,
  }) {
    final colors = context.triporaColors;

    return SizedBox(
      height: height,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: context.headingColor,
          backgroundColor: Colors.transparent,
          side: BorderSide(color: colors.borderStrong),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Hero metadata
// -----------------------------------------------------------------------------

class _HeroMeta extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HeroMeta({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.triporaColors;
    final scheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: scheme.primary),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: colors.textMuted,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.7,
          ),
        ),
      ],
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
