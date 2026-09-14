import 'package:flutter/material.dart';
import '../../core/utils/logger.dart';
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

  static const Color _midnight = Color(0xFF1E1B4B);
  static const Color _blue = Color(0xFF3B82F6);
  static const Color _emerald = Color(0xFF10B981);
  static const Color _surface = Color(0xFFF8FAFC);
  static const Color _white = Colors.white;
  static const Color _border = Color(0xFFE2E8F0);
  static const Color _slate100 = Color(0xFFF1F5F9);
  static const Color _slate400 = Color(0xFF94A3B8);
  static const Color _slate500 = Color(0xFF64748B);
  static const Color _slate600 = Color(0xFF475569);
  static const Color _text = Color(0xFF191C1E);

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

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

  Future<void> _deleteTrip(TripModel trip) async {
    final tripId = trip.id;

    if (tripId == null) {
      _showMessage('Unable to delete this trip.', isError: true);
      return;
    }

    if (_deletingTripId != null) {
      return;
    }

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Delete Trip?',
            style: TextStyle(
              fontFamily: 'Noto Serif',
              fontWeight: FontWeight.w600,
              color: _text,
            ),
          ),
          content: Text(
            'Are you sure you want to delete your trip to '
                '${trip.destination}?\n\n'
                'This action cannot be undone.',
            style: const TextStyle(fontSize: 14, height: 1.5, color: _slate600),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
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

      _showMessage(_extractErrorMessage(error), isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          backgroundColor: isError ? context.appStatus.error : _midnight,
        ),
      );
  }

  Future<void> _openTrip(TripModel trip) async {
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TripDetailsScreen(trip: trip)),
    );

    if (!mounted) return;

    _loadTrips();
  }

  void _openPlanner() {
    if (!mounted) return;

    Navigator.pushNamed(context, '/planner');
  }

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

  /// Computes a real status (Upcoming / In progress / Completed) from
  /// the trip's actual start/end dates — same logic used on the Trip
  /// Details screen, so the two stay consistent.
  ({String label, IconData icon, Color color}) _tripStatus(TripModel trip) {
    final now = DateTime.now();

    if (now.isBefore(trip.startDate)) {
      final daysUntil = trip.startDate.difference(now).inDays;
      final label = daysUntil <= 0
          ? 'Starting today'
          : 'Upcoming in $daysUntil ${daysUntil == 1 ? 'day' : 'days'}';

      return (label: label, icon: Icons.event_outlined, color: _blue);
    }

    if (now.isAfter(trip.endDate)) {
      return (
      label: 'Trip completed',
      icon: Icons.check_circle_outline,
      color: _slate400,
      );
    }

    return (
    label: 'Trip in progress',
    icon: Icons.flight_takeoff_rounded,
    color: _emerald,
    );
  }

  Widget _statusPill(TripModel trip) {
    final status = _tripStatus(trip);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: status.color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 13, color: status.color),
          const SizedBox(width: 5),
          Text(
            status.label,
            style: TextStyle(
              color: status.color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: _surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 20,
        title: const Text(
          'My Trips',
          style: TextStyle(
            fontFamily: 'Noto Serif',
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: _midnight,
          ),
        ),
      ),
      body: _buildBody(),
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
      color: _midnight,
      onRefresh: _loadTrips,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = constraints.maxWidth >= 1024
              ? 40.0
              : constraints.maxWidth >= 768
              ? 24.0
              : 16.0;

          final maxWidth = constraints.maxWidth > 1280
              ? 1200.0
              : double.infinity;

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              8,
              horizontalPadding,
              40,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildIntro(),
                      const SizedBox(height: 28),
                      ..._trips.map(_buildTripCard),
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

  Widget _buildIntro() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your travel archive',
          style: TextStyle(
            fontFamily: 'Noto Serif',
            fontSize: 30,
            fontWeight: FontWeight.w600,
            height: 1.2,
            color: _text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${_trips.length} saved '
              '${_trips.length == 1 ? 'journey' : 'journeys'}',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: _slate500,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState() {
    final authError = _isAuthError;

    return RefreshIndicator(
      color: _midnight,
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
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _statusIcon(
                        authError
                            ? Icons.lock_outline
                            : Icons.cloud_off_outlined,
                        authError ? _blue : context.appStatus.error,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        authError
                            ? 'Sign in required'
                            : 'Unable to load your trips',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Noto Serif',
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                          color: _text,
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
                          color: _slate500,
                        ),
                      ),
                      const SizedBox(height: 28),
                      _primaryButton(
                        label: authError ? 'Sign In' : 'Try Again',
                        icon: authError
                            ? Icons.login_outlined
                            : Icons.refresh_outlined,
                        onPressed: authError
                            ? () {
                          Navigator.pushNamed(context, '/login').then((
                              _,
                              ) {
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

  Widget _buildEmptyState() {
    return RefreshIndicator(
      color: _midnight,
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
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: _midnight,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: const Icon(
                          Icons.flight_takeoff_outlined,
                          size: 34,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 26),
                      const Text(
                        'Your next journey starts here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Noto Serif',
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          color: _text,
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
                          color: _slate500,
                        ),
                      ),
                      const SizedBox(height: 28),
                      _primaryButton(
                        label: 'Plan a Trip',
                        icon: Icons.add,
                        onPressed: _openPlanner,
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

  Widget _buildTripCard(TripModel trip) {
    final isDeleting = _deletingTripId == trip.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A1E1B4B),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: isDeleting ? null : () => _openTrip(trip),
        child: Padding(
          padding: const EdgeInsets.all(20),
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
                      color: _slate100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.location_on_outlined,
                      color: _midnight,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'DESTINATION',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.4,
                                color: _slate500,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _statusPill(trip),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          trip.destination,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Noto Serif',
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: _midnight,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isDeleting)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _midnight,
                      ),
                    )
                  else
                    PopupMenuButton<String>(
                      tooltip: 'Trip options',
                      icon: const Icon(Icons.more_horiz, color: _slate500),
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
                              Icon(Icons.visibility_outlined),
                              SizedBox(width: 12),
                              Text('View Trip'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline),
                              SizedBox(width: 12),
                              Text('Delete Trip'),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),

              const SizedBox(height: 20),
              const Divider(height: 1, color: _border),
              const SizedBox(height: 18),

              Wrap(
                spacing: 22,
                runSpacing: 14,
                children: [
                  _metric(
                    Icons.calendar_today_outlined,
                    'DATES',
                    '${_formatDate(trip.startDate)} – ${_formatDate(trip.endDate)}',
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
                  _metric(Icons.explore_outlined, 'STYLE', trip.travelStyle),
                ],
              ),

              const SizedBox(height: 20),
              const Divider(height: 1, color: _border),
              const SizedBox(height: 16),

              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _midnight,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${trip.numberOfDays} '
                          '${trip.numberOfDays == 1 ? 'DAY' : 'DAYS'}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'SAVED ITINERARY',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        color: _slate500,
                      ),
                    ),
                  ),
                  const Icon(Icons.arrow_forward, size: 20, color: _midnight),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metric(IconData icon, String label, String value) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 130),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: _slate500),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: _slate500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _text,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusIcon(IconData icon, Color color) {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 34, color: color),
    );
  }

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 48,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 19),
        label: Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: _midnight,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}