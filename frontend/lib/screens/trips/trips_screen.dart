import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/utils/logger.dart';
import '../../core/preferences/app_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../models/trip_model.dart';
import '../../services/trip_service.dart';
import '../../widgets/shimmer_loader.dart';
import '../trip_details.dart';

class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key});

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  final TripService _tripService = TripService();

  List<TripModel> _trips = [];

  bool _isLoading = true;
  int? _deletingTripId;

  String? _errorMessage;

  // ---------------------------------------------------------------------------
  // Tripora / Nocturne Voyage design tokens
  // Matches HomeScreen exactly.
  // ---------------------------------------------------------------------------

  static const Color midnight = Color(0xFF1E1B4B);
  static const Color midnightDark = Color(0xFF070235);

  static const Color porcelain = Color(0xFFF7F9FB);
  static const Color white = Color(0xFFFFFFFF);

  static const Color slate100 = Color(0xFFF1F5F9);
  static const Color slate200 = Color(0xFFE2E8F0);
  static const Color slate300 = Color(0xFFCBD5E1);
  static const Color slate400 = Color(0xFF94A3B8);
  static const Color slate500 = Color(0xFF64748B);
  static const Color slate600 = Color(0xFF475569);

  static const Color textSecondary = Color(0xFF47464F);

  static const Color blue = Color(0xFF3B82F6);
  static const Color emerald = Color(0xFF10B981);

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  // ---------------------------------------------------------------------------
  // Data
  // ---------------------------------------------------------------------------

  Future<void> _loadTrips() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final trips = await _tripService.getTrips();

      if (!mounted) return;

      setState(() {
        _trips = trips;
        _isLoading = false;
      });
    } catch (error) {
      appLog('TRIPS SCREEN ERROR: $error');

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = _extractErrorMessage(error);
      });
    }
  }

  String _extractErrorMessage(Object error) {
    final message = error.toString();

    if (message.startsWith('Exception: ')) {
      return message.replaceFirst('Exception: ', '');
    }

    return message;
  }

  bool get _isAuthError {
    final message = _errorMessage?.toLowerCase() ?? '';

    return message.contains('not logged in') ||
        message.contains('session has expired') ||
        message.contains('log in');
  }

  // ---------------------------------------------------------------------------
  // Trip actions
  // ---------------------------------------------------------------------------

  Future<void> _deleteTrip(TripModel trip) async {
    final tripId = trip.id;

    if (tripId == null) {
      _showMessage(
        'Unable to delete this trip.',
        isError: true,
      );
      return;
    }

    if (_deletingTripId != null) {
      return;
    }

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Delete Trip?',
            style: GoogleFonts.notoSerif(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: midnightDark,
            ),
          ),
          content: Text(
            'Are you sure you want to delete your trip to '
                '${trip.destination}?\n\n'
                'This action cannot be undone.',
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: textSecondary,
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: midnight,
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text(
                'Delete',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true || !mounted) {
      return;
    }

    setState(() {
      _deletingTripId = tripId;
    });

    try {
      await _tripService.deleteTrip(tripId);

      if (!mounted) return;

      setState(() {
        _trips.removeWhere((item) => item.id == tripId);
        _deletingTripId = null;
      });

      _showMessage('Trip deleted successfully.');
    } catch (error) {
      appLog('DELETE TRIP ERROR: $error');

      if (!mounted) return;

      setState(() {
        _deletingTripId = null;
      });

      _showMessage(
        _extractErrorMessage(error),
        isError: true,
      );
    }
  }

  void _showMessage(
      String message, {
        bool isError = false,
      }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          backgroundColor: isError
              ? context.appStatus.error
              : midnight,
        ),
      );
  }

  Future<void> _openTrip(TripModel trip) async {
    if (!mounted) return;

    HapticFeedback.lightImpact();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TripDetailsScreen(trip: trip),
      ),
    );

    if (!mounted) return;

    _loadTrips();
  }

  void _openPlanner() {
    if (!mounted) return;

    HapticFeedback.lightImpact();

    Navigator.pushNamed(
      context,
      '/planner',
    );
  }

  // ---------------------------------------------------------------------------
  // Formatting
  // ---------------------------------------------------------------------------

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  ({String label, IconData icon, Color color}) _tripStatus(
      TripModel trip,
      ) {
    final now = DateTime.now();

    if (now.isBefore(trip.startDate)) {
      final daysUntil = trip.startDate.difference(now).inDays;

      final label = daysUntil <= 0
          ? 'Starting today'
          : 'Upcoming in $daysUntil '
          '${daysUntil == 1 ? 'day' : 'days'}';

      return (
      label: label,
      icon: Icons.event_outlined,
      color: blue,
      );
    }

    if (now.isAfter(trip.endDate)) {
      return (
      label: 'Trip completed',
      icon: Icons.check_circle_outline,
      color: slate400,
      );
    }

    return (
    label: 'Trip in progress',
    icon: Icons.flight_takeoff_rounded,
    color: emerald,
    );
  }

  Widget _statusPill(TripModel trip) {
    final status = _tripStatus(trip);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: status.color.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            status.icon,
            size: 13,
            color: status.color,
          ),
          const SizedBox(width: 5),
          Text(
            status.label,
            style: TextStyle(
              color: status.color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Main build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppPreferences.instance,
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: porcelain,
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: porcelain,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 20,
      title: Text(
        'My Trips',
        style: GoogleFonts.manrope(
          color: midnight,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const TripsScreenShimmer();
    }

    if (_errorMessage != null) {
      return _buildErrorState();
    }

    if (_trips.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      color: midnight,
      backgroundColor: white,
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
                      _buildIntro(isMobile),
                      SizedBox(
                        height: isMobile ? 28 : 36,
                      ),
                      _buildTripsGrid(
                        isMobile,
                        isTablet,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Intro
  // ---------------------------------------------------------------------------

  Widget _buildIntro(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(
        isMobile ? 24 : 32,
      ),
      decoration: BoxDecoration(
        color: white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: slate200,
        ),
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
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: slate100,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: slate200,
              ),
            ),
            child: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.luggage_outlined,
                    size: 14,
                    color: blue,
                  ),
                  SizedBox(width: 7),
                  Text(
                    'YOUR JOURNEYS',
                    style: TextStyle(
                      color: midnight,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          Text(
            'Your travel archive.',
            style: GoogleFonts.notoSerif(
              color: midnightDark,
              fontSize: isMobile ? 32 : 40,
              height: 1.08,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.8,
            ),
          ),

          const SizedBox(height: 12),

          Text(
            '${_trips.length} saved '
                '${_trips.length == 1 ? 'journey' : 'journeys'} ready to explore.',
            style: const TextStyle(
              color: textSecondary,
              fontSize: 15,
              height: 1.5,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Trips grid
  // ---------------------------------------------------------------------------

  Widget _buildTripsGrid(
      bool isMobile,
      bool isTablet,
      ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = isMobile
            ? constraints.maxWidth
            : isTablet
            ? (constraints.maxWidth - 16) / 2
            : (constraints.maxWidth - 32) / 3;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: _trips.map((trip) {
            return SizedBox(
              width: cardWidth,
              child: _buildTripCard(trip),
            );
          }).toList(),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Error state
  // ---------------------------------------------------------------------------

  Widget _buildErrorState() {
    final authError = _isAuthError;

    return RefreshIndicator(
      color: midnight,
      backgroundColor: white,
      onRefresh: _loadTrips,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.72,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 500,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _statusIcon(
                        authError
                            ? Icons.lock_outline_rounded
                            : Icons.cloud_off_outlined,
                        authError
                            ? blue
                            : context.appStatus.error,
                      ),

                      const SizedBox(height: 24),

                      Text(
                        authError
                            ? 'Sign in required'
                            : 'Unable to load your trips',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.notoSerif(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          color: midnightDark,
                        ),
                      ),

                      const SizedBox(height: 12),

                      Text(
                        authError
                            ? 'Your session has expired. Please sign in to continue.'
                            : (_errorMessage?.toLowerCase().contains(
                          'connection',
                        ) ??
                            false)
                            ? 'Could not connect to the server. Check your internet connection.'
                            : _errorMessage ??
                            'Something went wrong while loading your trips.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.6,
                          color: slate500,
                        ),
                      ),

                      const SizedBox(height: 28),

                      _primaryButton(
                        label: authError
                            ? 'Sign In'
                            : 'Try Again',
                        icon: authError
                            ? Icons.login_outlined
                            : Icons.refresh_outlined,
                        onPressed: authError
                            ? () {
                          Navigator.pushNamed(
                            context,
                            '/login',
                          ).then((_) {
                            if (mounted) {
                              _loadTrips();
                            }
                          });
                        }
                            : _loadTrips,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Empty state
  // ---------------------------------------------------------------------------

  Widget _buildEmptyState() {
    return RefreshIndicator(
      color: midnight,
      backgroundColor: white,
      onRefresh: _loadTrips,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.72,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 560,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: slate200,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0A1E1B4B),
                          blurRadius: 10,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            color: midnight,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            Icons.flight_takeoff_outlined,
                            size: 34,
                            color: white,
                          ),
                        ),

                        const SizedBox(height: 26),

                        Text(
                          'Your next journey starts here.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.notoSerif(
                            fontSize: 28,
                            height: 1.15,
                            fontWeight: FontWeight.w600,
                            color: midnightDark,
                          ),
                        ),

                        const SizedBox(height: 12),

                        const Text(
                          'You haven’t created any trips yet. '
                              'Build an itinerary around your pace, interests, and budget.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.6,
                            color: slate500,
                          ),
                        ),

                        const SizedBox(height: 28),

                        _primaryButton(
                          label: 'Plan a Trip',
                          icon: Icons.add_rounded,
                          onPressed: _openPlanner,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Trip card
  // ---------------------------------------------------------------------------

  Widget _buildTripCard(TripModel trip) {
    final isDeleting = _deletingTripId == trip.id;

    return Material(
      color: white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: isDeleting
            ? null
            : () => _openTrip(trip),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: slate200,
            ),
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: midnight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.location_on_outlined,
                      color: white,
                      size: 21,
                    ),
                  ),

                  const SizedBox(width: 14),

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'DESTINATION',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                            color: slate500,
                          ),
                        ),

                        const SizedBox(height: 5),

                        Text(
                          trip.destination,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.notoSerif(
                            fontSize: 22,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                            color: midnightDark,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  if (isDeleting)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: midnight,
                      ),
                    )
                  else
                    PopupMenuButton<String>(
                      tooltip: 'Trip options',
                      icon: const Icon(
                        Icons.more_horiz_rounded,
                        color: slate500,
                      ),
                      onSelected: (value) {
                        switch (value) {
                          case 'view':
                            _openTrip(trip);
                            break;
                          case 'delete':
                            _deleteTrip(trip);
                            break;
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'view',
                          child: Row(
                            children: [
                              Icon(
                                Icons.visibility_outlined,
                              ),
                              SizedBox(width: 12),
                              Text('View Trip'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_outline,
                              ),
                              SizedBox(width: 12),
                              Text('Delete Trip'),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),

              const SizedBox(height: 18),

              Row(
                children: [
                  _statusPill(trip),
                ],
              ),

              const SizedBox(height: 20),

              const Divider(
                height: 1,
                color: slate200,
              ),

              const SizedBox(height: 18),

              Wrap(
                spacing: 22,
                runSpacing: 14,
                children: [
                  _metric(
                    Icons.calendar_today_outlined,
                    'DATES',
                    '${_formatDate(trip.startDate)} – '
                        '${_formatDate(trip.endDate)}',
                  ),
                  _metric(
                    Icons.people_outline,
                    'TRAVELERS',
                    '${trip.travelers}',
                  ),
                  _metric(
                    Icons.account_balance_wallet_outlined,
                    'BUDGET',
                    trip.budget,
                  ),
                  _metric(
                    Icons.explore_outlined,
                    'STYLE',
                    trip.travelStyle,
                  ),
                ],
              ),

              const SizedBox(height: 20),

              const Divider(
                height: 1,
                color: slate200,
              ),

              const SizedBox(height: 16),

              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: midnight,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${trip.numberOfDays} '
                          '${trip.numberOfDays == 1 ? 'DAY' : 'DAYS'}',
                      style: const TextStyle(
                        color: white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  const Expanded(
                    child: Text(
                      'SAVED ITINERARY',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: slate500,
                      ),
                    ),
                  ),

                  const Icon(
                    Icons.arrow_outward_rounded,
                    size: 18,
                    color: slate500,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Metric
  // ---------------------------------------------------------------------------

  Widget _metric(
      IconData icon,
      String label,
      String value,
      ) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: 130,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: slate500,
          ),

          const SizedBox(width: 8),

          Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  color: slate500,
                ),
              ),

              const SizedBox(height: 3),

              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: midnightDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Status icon
  // ---------------------------------------------------------------------------

  Widget _statusIcon(
      IconData icon,
      Color color,
      ) {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        shape: BoxShape.circle,
        border: Border.all(
          color: color.withValues(alpha: 0.15),
        ),
      ),
      child: Icon(
        icon,
        size: 34,
        color: color,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Primary button
  // ---------------------------------------------------------------------------

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(
          icon,
          size: 17,
        ),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: midnight,
          foregroundColor: white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: 22,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
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