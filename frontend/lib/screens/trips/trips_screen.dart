import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/l10n/app_localizations.dart';
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
        context.tr('trips.deleteUnable'),
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
            dialogContext.tr('trips.deleteTitle'),
            style: GoogleFonts.notoSerif(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: midnightDark,
            ),
          ),
          content: Text(
            dialogContext.tr(
              'trips.deleteConfirmation',
              params: {
                'destination': trip.destination,
              },
            ),
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: textSecondary,
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(
            20,
            0,
            20,
            16,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              style: TextButton.styleFrom(
                foregroundColor: midnight,
              ),
              child: Text(
                dialogContext.tr('trips.cancel'),
                style: const TextStyle(
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
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: Text(
                dialogContext.tr('trips.delete'),
                style: const TextStyle(
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

      _showMessage(
        context.tr('trips.deleted'),
      );
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
      'jan',
      'feb',
      'mar',
      'apr',
      'may',
      'jun',
      'jul',
      'aug',
      'sep',
      'oct',
      'nov',
      'dec',
    ];

    final month = context.tr(
      'date.monthShort.${months[date.month - 1]}',
    );

    return '$month ${date.day}, ${date.year}';
  }

  // ---------------------------------------------------------------------------
  // Trip status
  // ---------------------------------------------------------------------------

  ({
    String label,
    IconData icon,
    Color color,
  }) _tripStatus(TripModel trip) {
    final now = DateTime.now();

    if (now.isBefore(trip.startDate)) {
      final daysUntil =
          trip.startDate.difference(now).inDays;

      final String label;

      if (daysUntil <= 0) {
        label = context.tr('trips.startingToday');
      } else if (daysUntil == 1) {
        label = context.tr(
          'trips.upcomingOne',
        );
      } else {
        label = context.tr(
          'trips.upcomingMany',
          params: {
            'count': daysUntil.toString(),
          },
        );
      }

      return (
        label: label,
        icon: Icons.event_outlined,
        color: blue,
      );
    }

    if (now.isAfter(trip.endDate)) {
      return (
        label: context.tr('trips.completed'),
        icon: Icons.check_circle_outline,
        color: slate400,
      );
    }

    return (
      label: context.tr('trips.inProgress'),
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
      builder: (context, _) {
        return _buildScaffold(context);
      },
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: porcelain,
      appBar: _buildAppBar(context),
      body: _buildBody(context),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
  ) {
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: porcelain,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 20,
      title: Text(
        context.tr('trips.title'),
        style: GoogleFonts.manrope(
          color: midnight,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const TripsScreenShimmer();
    }

    if (_errorMessage != null) {
      return _buildErrorState(context);
    }

    if (_trips.isEmpty) {
      return _buildEmptyState(context);
    }

    return RefreshIndicator(
      color: midnight,
      backgroundColor: white,
      onRefresh: _loadTrips,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;

          final isMobile = width < 768;
          final isTablet =
              width >= 768 && width < 1024;

          final horizontalPadding = isMobile
              ? 16.0
              : isTablet
                  ? 24.0
                  : 40.0;

          const maxContentWidth = 1280.0;

          return ListView(
            physics:
                const AlwaysScrollableScrollPhysics(),
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
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      _buildIntro(
                        context,
                        isMobile,
                      ),
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

  Widget _buildIntro(
    BuildContext context,
    bool isMobile,
  ) {
    final journeyText = _trips.length == 1
        ? context.tr('trips.journeyOne')
        : context.tr(
            'trips.journeyMany',
            params: {
              'count': _trips.length.toString(),
            },
          );

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
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: slate100,
              borderRadius:
                  BorderRadius.circular(999),
              border: Border.all(
                color: slate200,
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.luggage_outlined,
                    size: 14,
                    color: blue,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    context.tr(
                      'trips.journeysBadge',
                    ),
                    style: const TextStyle(
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
            context.tr('trips.archiveTitle'),
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
            journeyText,
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

  Widget _buildErrorState(
    BuildContext context,
  ) {
    final authError = _isAuthError;

    final errorText =
        _errorMessage?.toLowerCase() ?? '';

    final description = authError
        ? context.tr('trips.sessionExpired')
        : errorText.contains('connection')
            ? context.tr('trips.connectionError')
            : context.tr('trips.genericError');

    return RefreshIndicator(
      color: midnight,
      backgroundColor: white,
      onRefresh: _loadTrips,
      child: ListView(
        physics:
            const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height:
                MediaQuery.of(context).size.height *
                    0.72,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(
                    maxWidth: 500,
                  ),
                  child: Column(
                    mainAxisAlignment:
                        MainAxisAlignment.center,
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
                            ? context.tr(
                                'trips.signInRequired',
                              )
                            : context.tr(
                                'trips.loadError',
                              ),
                        textAlign: TextAlign.center,
                        style:
                            GoogleFonts.notoSerif(
                          fontSize: 28,
                          fontWeight:
                              FontWeight.w600,
                          color: midnightDark,
                        ),
                      ),

                      const SizedBox(height: 12),

                      Text(
                        description,
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
                            ? context.tr(
                                'trips.signIn',
                              )
                            : context.tr(
                                'trips.tryAgain',
                              ),
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

  Widget _buildEmptyState(
    BuildContext context,
  ) {
    return RefreshIndicator(
      color: midnight,
      backgroundColor: white,
      onRefresh: _loadTrips,
      child: ListView(
        physics:
            const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height:
                MediaQuery.of(context).size.height *
                    0.72,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(
                    maxWidth: 560,
                  ),
                  child: Container(
                    padding:
                        const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: white,
                      borderRadius:
                          BorderRadius.circular(24),
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
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            color: midnight,
                            borderRadius:
                                BorderRadius.circular(
                              20,
                            ),
                          ),
                          child: const Icon(
                            Icons
                                .flight_takeoff_outlined,
                            size: 34,
                            color: white,
                          ),
                        ),

                        const SizedBox(height: 26),

                        Text(
                          context.tr(
                            'trips.emptyTitle',
                          ),
                          textAlign:
                              TextAlign.center,
                          style:
                              GoogleFonts.notoSerif(
                            fontSize: 28,
                            height: 1.15,
                            fontWeight:
                                FontWeight.w600,
                            color: midnightDark,
                          ),
                        ),

                        const SizedBox(height: 12),

                        Text(
                          context.tr(
                            'trips.emptyDescription',
                          ),
                          textAlign:
                              TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.6,
                            color: slate500,
                          ),
                        ),

                        const SizedBox(height: 28),

                        _primaryButton(
                          label: context.tr(
                            'trips.planTrip',
                          ),
                          icon:
                              Icons.add_rounded,
                          onPressed:
                              _openPlanner,
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

  Widget _buildTripCard(
    TripModel trip,
  ) {
    final isDeleting =
        _deletingTripId == trip.id;

    return Material(
      color: white,
      borderRadius:
          BorderRadius.circular(16),
      child: InkWell(
        borderRadius:
            BorderRadius.circular(16),
        onTap: isDeleting
            ? null
            : () => _openTrip(trip),
        child: Container(
          padding:
              const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius:
                BorderRadius.circular(16),
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
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration:
                        BoxDecoration(
                      color: midnight,
                      borderRadius:
                          BorderRadius.circular(
                        12,
                      ),
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
                          CrossAxisAlignment
                              .start,
                      children: [
                        Text(
                          context.tr(
                            'trips.destination',
                          ),
                          style:
                              const TextStyle(
                            fontSize: 9,
                            fontWeight:
                                FontWeight.w800,
                            letterSpacing: 1.1,
                            color: slate500,
                          ),
                        ),

                        const SizedBox(
                          height: 5,
                        ),

                        Text(
                          trip.destination,
                          maxLines: 2,
                          overflow:
                              TextOverflow.ellipsis,
                          style:
                              GoogleFonts.notoSerif(
                            fontSize: 22,
                            height: 1.2,
                            fontWeight:
                                FontWeight.w600,
                            color:
                                midnightDark,
                            letterSpacing:
                                -0.3,
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
                      child:
                          CircularProgressIndicator(
                        strokeWidth: 2,
                        color: midnight,
                      ),
                    )
                  else
                    PopupMenuButton<String>(
                      tooltip: context.tr(
                        'trips.options',
                      ),
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
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'view',
                          child: Row(
                            children: [
                              const Icon(
                                Icons
                                    .visibility_outlined,
                              ),
                              const SizedBox(
                                width: 12,
                              ),
                              Text(
                                context.tr(
                                  'trips.view',
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              const Icon(
                                Icons
                                    .delete_outline,
                              ),
                              const SizedBox(
                                width: 12,
                              ),
                              Text(
                                context.tr(
                                  'trips.delete',
                                ),
                              ),
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
                    context.tr('trips.dates'),
                    '${_formatDate(trip.startDate)} – '
                        '${_formatDate(trip.endDate)}',
                  ),
                  _metric(
                    Icons.people_outline,
                    context.tr('trips.travelers'),
                    '${trip.travelers}',
                  ),
                  _metric(
                    Icons
                        .account_balance_wallet_outlined,
                    context.tr('trips.budget'),
                    trip.budget,
                  ),
                  _metric(
                    Icons.explore_outlined,
                    context.tr('trips.style'),
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
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: midnight,
                      borderRadius:
                          BorderRadius.circular(
                        999,
                      ),
                    ),
                    child: Text(
                      '${trip.numberOfDays} '
                      '${trip.numberOfDays == 1 ? context.tr('trips.day') : context.tr('trips.days')}',
                      style:
                          const TextStyle(
                        color: white,
                        fontSize: 10,
                        fontWeight:
                            FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Text(
                      context.tr(
                        'trips.savedItinerary',
                      ),
                      style:
                          const TextStyle(
                        fontSize: 9,
                        fontWeight:
                            FontWeight.w800,
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
      constraints:
          const BoxConstraints(
        minWidth: 130,
      ),
      child: Row(
        mainAxisSize:
            MainAxisSize.min,
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
                style:
                    const TextStyle(
                  fontSize: 9,
                  fontWeight:
                      FontWeight.w800,
                  letterSpacing: 1,
                  color: slate500,
                ),
              ),

              const SizedBox(height: 3),

              Text(
                value,
                maxLines: 2,
                overflow:
                    TextOverflow.ellipsis,
                style:
                    const TextStyle(
                  fontSize: 13,
                  fontWeight:
                      FontWeight.w600,
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
        color: color.withValues(
          alpha: 0.08,
        ),
        shape: BoxShape.circle,
        border: Border.all(
          color: color.withValues(
            alpha: 0.15,
          ),
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
          padding:
              const EdgeInsets.symmetric(
            horizontal: 22,
          ),
          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(8),
          ),
          textStyle:
              const TextStyle(
            fontSize: 13,
            fontWeight:
                FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
      ),
    );
  }
}