import 'package:flutter/material.dart';

import '../../core/utils/logger.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/shimmer_loader.dart';
import '../trip_details.dart';
import '../../models/trip_model.dart';
import '../../services/trip_service.dart';

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

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  // ============================================================
  // LOAD TRIPS
  // ============================================================

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

  // ============================================================
  // DELETE TRIP
  // ============================================================

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
          title: const Text('Delete Trip?'),
          content: Text(
            'Are you sure you want to delete your trip to '
            '${trip.destination}?\n\n'
            'This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
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

  // ============================================================
  // SHOW MESSAGE
  // ============================================================

  void _showMessage(String message, {bool isError = false}) {
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
              : null,
        ),
      );
  }

  // ============================================================
  // OPEN TRIP
  // ============================================================

  Future<void> _openTrip(TripModel trip) async {
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TripDetailsScreen(trip: trip)),
    );

    if (!mounted) return;

    _loadTrips();
  }

  // ============================================================
  // OPEN PLANNER
  // ============================================================

  void _openPlanner() {
    if (!mounted) return;

    Navigator.pushNamed(context, '/planner');
  }

  // ============================================================
  // FORMAT DATE
  // ============================================================

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

    return '${months[date.month - 1]} '
        '${date.day}, '
        '${date.year}';
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Trips',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: _buildBody(),
    );
  }

  // ============================================================
  // BODY
  // ============================================================

  Widget _buildBody() {
    // ----------------------------------------------------------
    // LOADING
    // ----------------------------------------------------------

    if (_isLoading) {
      return const TripsScreenShimmer();
    }

    // ----------------------------------------------------------
    // ERROR
    // ----------------------------------------------------------

    if (_errorMessage != null) {
      return _buildErrorState();
    }

    // ----------------------------------------------------------
    // EMPTY
    // ----------------------------------------------------------

    if (_trips.isEmpty) {
      return _buildEmptyState();
    }

    // ----------------------------------------------------------
    // TRIPS
    // ----------------------------------------------------------

    return RefreshIndicator(
      onRefresh: _loadTrips,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _trips.length,
        itemBuilder: (context, index) {
          final trip = _trips[index];

          return _buildTripCard(trip);
        },
      ),
    );
  }

  // ============================================================
  // ERROR STATE
  // ============================================================

  Widget _buildErrorState() {
    return RefreshIndicator(
      onRefresh: _loadTrips,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.72,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: context.appStatus.error.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isAuthError
                          ? Icons.lock_outline
                          : Icons.cloud_off_outlined,
                      size: 42,
                      color: _isAuthError
                          ? context.appStatus.info
                          : context.appStatus.error,
                    ),
                  ),

                  const SizedBox(height: 20),

                  Text(
                    _isAuthError
                        ? 'Sign in required'
                        : 'Unable to load your trips',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    _isAuthError
                        ? 'Your session has expired. Please sign in to continue.'
                        : _errorMessage?.contains('connection') ?? false
                        ? 'Could not connect to the server. Check your internet connection.'
                        : _errorMessage ??
                              'Something went wrong while loading your trips.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: context.triporaColors.textSecondary,
                    ),
                  ),

                  const SizedBox(height: 24),

                  if (_isAuthError)
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pushNamed(context, '/login').then((_) {
                          if (mounted) {
                            _loadTrips();
                          }
                        });
                      },
                      icon: const Icon(Icons.login),
                      label: const Text('Sign In'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                      ),
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: _loadTrips,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // EMPTY STATE
  // ============================================================

  Widget _buildEmptyState() {
    return RefreshIndicator(
      onRefresh: _loadTrips,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.72,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.flight_takeoff_outlined,
                      size: 52,
                      color: Colors.white,
                    ),
                  ),

                  const SizedBox(height: 24),

                  const Text(
                    'No trips yet',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    'You haven\'t created any trips yet.\n'
                    'Plan your next adventure with Tripora.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: context.triporaColors.textMuted,
                    ),
                  ),

                  const SizedBox(height: 28),

                  GradientButton(
                    onPressed: _openPlanner,
                    icon: const Icon(Icons.add),
                    label: const Text('Plan a Trip'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TRIP CARD
  // ============================================================

  Widget _buildTripCard(TripModel trip) {
    final bool isDeleting = _deletingTripId == trip.id;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isDeleting
            ? null
            : () {
                _openTrip(trip);
              },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ==================================================
                  // DESTINATION + MENU
                  // ==================================================
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const ExcludeSemantics(
                        child: Icon(Icons.location_on_outlined),
                      ),

                      const SizedBox(width: 8),

                  Expanded(
                    child: Text(
                      trip.destination,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  if (isDeleting)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    PopupMenuButton<String>(
                      tooltip: 'Trip options',
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
                      itemBuilder: (context) {
                        return const [
                          PopupMenuItem<String>(
                            value: 'view',
                            child: Row(
                              children: [
                                Icon(Icons.visibility_outlined),
                                SizedBox(width: 12),
                                Text('View Trip'),
                              ],
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline),
                                SizedBox(width: 12),
                                Text('Delete Trip'),
                              ],
                            ),
                          ),
                        ];
                      },
                    ),
                ],
              ),

              const SizedBox(height: 14),

              // ==================================================
              // DATES
              // ==================================================
              _infoRow(
                icon: Icons.calendar_today_outlined,
                text:
                    '${_formatDate(trip.startDate)} - '
                    '${_formatDate(trip.endDate)}',
              ),

              const SizedBox(height: 8),

              // ==================================================
              // TRAVELERS
              // ==================================================
              _infoRow(
                icon: Icons.people_outline,
                text:
                    '${trip.travelers} '
                    '${trip.travelers == 1 ? 'traveler' : 'travelers'}',
              ),

              const SizedBox(height: 8),

              // ==================================================
              // BUDGET
              // ==================================================
              _infoRow(
                icon: Icons.account_balance_wallet_outlined,
                text: trip.budget,
              ),

              const SizedBox(height: 8),

              // ==================================================
              // TRAVEL STYLE
              // ==================================================
              _infoRow(icon: Icons.explore_outlined, text: trip.travelStyle),

              const SizedBox(height: 16),

              const Divider(),

              const SizedBox(height: 8),

              // ==================================================
              // ITINERARY
              // ==================================================
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${trip.numberOfDays} '
                    '${trip.numberOfDays == 1 ? 'day' : 'days'} itinerary',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),

                  const Icon(Icons.arrow_forward_ios, size: 16),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // INFO ROW
  // ============================================================

  Widget _infoRow({required IconData icon, required String text}) {
    return Row(
      children: [
        ExcludeSemantics(child: Icon(icon, size: 18)),

        const SizedBox(width: 8),

        Expanded(child: Text(text, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}
