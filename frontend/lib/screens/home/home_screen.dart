import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../data/destinations.dart';
import '../../models/trip_model.dart';
import '../../routes/app_routes.dart';
import '../trip_details.dart';
import '../../services/trip_service.dart';
import '../../widgets/destination_card.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/shimmer_loader.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TripService _tripService = TripService();

  List<TripModel> _trips = [];
  bool _isLoadingTrips = true;
  String? _tripError;

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
    Navigator.pushNamed(context, AppRoutes.explore);
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

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isCompact = width < 720;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Tripora',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GradientButton(
              onPressed: () => _openPlanner(),
              icon: const Icon(Icons.add, size: 18),
              label: Text(
                isCompact ? 'Plan' : 'Plan Trip',
                style: const TextStyle(fontSize: 14),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              height: 48,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadTrips,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 16 : 40,
            vertical: isCompact ? 24 : 44,
          ),
          children: [
            _buildHero(isCompact),
            const SizedBox(height: 28),
            _buildTripSnapshot(isCompact),
            const SizedBox(height: 36),
            _buildDestinationsHeader(),
            const SizedBox(height: 16),
            _buildDestinationStrip(),
            const SizedBox(height: 36),
            _buildQuickActions(isCompact),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(bool isCompact) {
    return Column(
      crossAxisAlignment: isCompact
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                context.triporaColors.surfaceInfo,
                context.triporaColors.surfaceSecondary,
                context.triporaColors.surfaceAccent,
              ],
            ),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_awesome,
                size: 15,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'AI-powered travel planning',
                style: TextStyle(
                  color: context.appStatus.info,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Plan trips that fit your pace.',
          textAlign: isCompact ? TextAlign.left : TextAlign.center,
          style: TextStyle(
            fontSize: isCompact ? 38 : 58,
            height: 1.05,
            fontWeight: FontWeight.w900,
            color: context.triporaColors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Start with a destination, continue from your saved trips, or discover somewhere new.',
          textAlign: isCompact ? TextAlign.left : TextAlign.center,
          style: TextStyle(
            fontSize: 17,
            height: 1.45,
            color: context.triporaColors.textSecondary,
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: isCompact ? WrapAlignment.start : WrapAlignment.center,
          children: [
            GradientButton(
              onPressed: () => _openPlanner(),
              icon: const Icon(Icons.auto_awesome_outlined, size: 20),
              label: const Text('Start Planning'),
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
            ),
            OutlinedButton.icon(
              onPressed: _openExplore,
              icon: const Icon(Icons.public_outlined),
              label: const Text('Explore Destinations'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTripSnapshot(bool isCompact) {
    if (_isLoadingTrips) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Your trips',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
              ),
              TextButton.icon(
                onPressed: null,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('View All'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              TripCardShimmer(isCompact: isCompact),
              if (!isCompact) TripCardShimmer(isCompact: isCompact),
              if (!isCompact) TripCardShimmer(isCompact: isCompact),
            ],
          ),
        ],
      );
    }

    if (_tripError != null) {
      final isAuthError =
          _tripError!.contains('logged in') ||
          _tripError!.contains('session') ||
          _tripError!.contains('log in');
      final isNetworkError =
          _tripError!.contains('refused') ||
          _tripError!.contains('not found') ||
          _tripError!.contains('connection');
      final statusColors = Theme.of(context).extension<AppStatusColors>();
      final infoColor = statusColors?.info ?? AppColors.info;
      final errorColor = statusColors?.error ?? AppColors.error;

      String errorMessage;
      IconData errorIcon;

      if (isAuthError) {
        errorMessage = 'Sign in to see your saved trips.';
        errorIcon = Icons.lock_outline;
      } else if (isNetworkError) {
        errorMessage =
            'Could not connect to the server. Check your connection.';
        errorIcon = Icons.wifi_off_outlined;
      } else {
        errorMessage = 'Could not load your trips. Please try again.';
        errorIcon = Icons.cloud_off_outlined;
      }

      return Card(
        color: isAuthError
            ? infoColor.withValues(alpha: 0.08)
            : errorColor.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(errorIcon, color: isAuthError ? infoColor : errorColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  errorMessage,
                  style: TextStyle(color: isAuthError ? infoColor : errorColor),
                ),
              ),
              TextButton(
                onPressed: isAuthError
                    ? () => Navigator.pushNamed(
                        context,
                        AppRoutes.login,
                      ).then((_) => _loadTrips())
                    : _loadTrips,
                child: Text(isAuthError ? 'Sign In' : 'Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_trips.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'No saved trips yet',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Create your first itinerary and it will appear here.',
              ),
              const SizedBox(height: 16),
              GradientButton(
                onPressed: () => _openPlanner(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Plan a Trip'),
              ),
            ],
          ),
        ),
      );
    }

    final recentTrips = _trips.take(isCompact ? 2 : 3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${_trips.length} saved ${_trips.length == 1 ? 'trip' : 'trips'}',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _openTrips,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: recentTrips.map((trip) {
            return SizedBox(
              width: isCompact ? double.infinity : 290,
              child: Card(
                child: InkWell(
                  onTap: () => _openTrip(trip),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trip.destination,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${trip.numberOfDays} days - ${trip.travelers} ${trip.travelers == 1 ? 'traveler' : 'travelers'}',
                          style: TextStyle(color: context.triporaColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildDestinationsHeader() {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Container(
                width: 6,
                height: 28,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Popular Destinations',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
        TextButton(onPressed: _openExplore, child: const Text('See More')),
      ],
    );
  }

  Widget _buildDestinationStrip() {
    // Curate a mix that always features a couple of African gems.
    const featuredKeys = {
      'Seychelles',
      'Paris',
      'Cotonou',
      'Tokyo',
      'Bali',
    };

    final featured = destinations
        .where((d) => featuredKeys.contains(d.city))
        .toList();

    final list = featured.length >= 2 ? featured : destinations.take(5).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: list.map((destination) {
          return Padding(
            padding: const EdgeInsets.only(right: 16),
            child: DestinationCard(
              imageUrl: destination.imageUrl,
              city: destination.city,
              country: destination.country,
              description: destination.description,
              footer: destination.tripLength,
              tags: destination.tags,
              width: 280,
              onTap: () => _openPlanner(destination.fullName),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildQuickActions(bool isCompact) {
    final actions = [
      _ActionItem(
        icon: Icons.search_outlined,
        title: 'Find ideas',
        subtitle: 'Browse destinations by interest.',
        onTap: _openExplore,
      ),
      _ActionItem(
        icon: Icons.add_location_alt_outlined,
        title: 'Build a trip',
        subtitle: 'Create a fresh AI itinerary.',
        onTap: () => _openPlanner(),
      ),
      _ActionItem(
        icon: Icons.card_travel_outlined,
        title: 'Manage trips',
        subtitle: 'View, edit, or regenerate saved plans.',
        onTap: _openTrips,
      ),
    ];

    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: actions.map((action) {
        return SizedBox(
          width: isCompact ? double.infinity : 300,
          child: Card(
            child: InkWell(
              onTap: action.onTap,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    ExcludeSemantics(
                      child: Container(
                        width: 46,
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: AppColors.brandGradient,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(
                          action.icon,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            action.title,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            action.subtitle,
                          style: TextStyle(color: context.triporaColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    ExcludeSemantics(
                      child: Icon(
                        Icons.arrow_forward_ios,
                        size: 14,
                        color: context.triporaColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ActionItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}
