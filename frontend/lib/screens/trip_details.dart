import 'package:flutter/material.dart';

import '../core/utils/logger.dart';
import '../core/theme/app_theme.dart';
import '../models/trip_model.dart';
import '../services/trip_service.dart';
import '../widgets/shimmer_loader.dart';

class TripDetailsScreen extends StatefulWidget {
  final TripModel trip;

  const TripDetailsScreen({super.key, required this.trip});

  @override
  State<TripDetailsScreen> createState() => _TripDetailsScreenState();
}

class _TripDetailsScreenState extends State<TripDetailsScreen> {
  final TripService _tripService = TripService();

  late TripModel _trip;

  bool _isLoading = false;
  bool _isSaving = false;
  bool _isRegenerating = false;
  String? _errorMessage;

  static const List<String> _availableInterests = [
    'Culture',
    'Food',
    'Nature',
    'Adventure',
    'Shopping',
    'Nightlife',
    'Relaxation',
  ];

  @override
  void initState() {
    super.initState();
    _trip = widget.trip;
    _loadTripDetails();
  }

  Future<void> _loadTripDetails() async {
    final tripId = widget.trip.id;

    if (tripId == null) {
      return;
    }

    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final freshTrip = await _tripService.getTrip(tripId);

      if (!mounted) return;

      setState(() {
        _trip = freshTrip;
        _isLoading = false;
      });
    } catch (error) {
      appLog('TRIP DETAILS ERROR: $error');

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
  // GET STRING SAFELY
  // ============================================================

  String _getString(Map<String, dynamic> data, String key) {
    final value = data[key];

    if (value == null) {
      return '';
    }

    return value.toString();
  }

  // ============================================================
  // GET INTEGER SAFELY
  // ============================================================

  int? _getInt(Map<String, dynamic> data, String key) {
    final value = data[key];

    if (value is int) {
      return value;
    }

    return int.tryParse(value?.toString() ?? '');
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip Details'),
        actions: [
          if (!_isLoading && _errorMessage == null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit trip',
              onPressed: _isSaving || _isRegenerating
                  ? null
                  : _showEditTripSheet,
            ),
          if (!_isLoading && _errorMessage == null)
            IconButton(
              icon: const Icon(Icons.auto_awesome_outlined),
              tooltip: 'Regenerate itinerary',
              onPressed: _isSaving || _isRegenerating
                  ? null
                  : _regenerateItinerary,
            ),
          if (!_isLoading && _errorMessage == null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: _loadTripDetails,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _trip.destination.isEmpty) {
      return const TripDetailsShimmer();
    }

    if (_errorMessage != null && _trip.destination.isEmpty) {
      return _buildErrorState();
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadTripDetails,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              _buildHeroSection(),

              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_errorMessage != null) ...[
                      _buildInlineErrorBanner(),
                      const SizedBox(height: 16),
                    ],

                    _buildTripOverview(),

                    const SizedBox(height: 24),

                    _buildEstimatedCost(),

                    const SizedBox(height: 24),

                    _buildInterests(),

                    const SizedBox(height: 28),

                    const Text(
                      'Your Itinerary',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 16),

                    if (_trip.itinerary.isEmpty)
                      _buildEmptyItinerary()
                    else
                      ..._trip.itinerary.map((day) {
                        if (day is! Map) {
                          return const SizedBox.shrink();
                        }

                        try {
                          return _buildDayCard(Map<String, dynamic>.from(day));
                        } catch (error) {
                          appLog('INVALID DAY DATA: $error');

                          return const SizedBox.shrink();
                        }
                      }),
                  ],
                ),
              ),
            ],
          ),
        ),

        if (_isLoading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(),
          ),

        if (_isSaving || _isRegenerating)
          Positioned.fill(
            child: ColoredBox(
              color: const Color(0x66000000),
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 14),
                        Text(
                          _isRegenerating
                              ? 'Regenerating itinerary...'
                              : 'Saving trip...',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _regenerateItinerary() async {
    final tripId = _trip.id;

    if (tripId == null || _isRegenerating) {
      return;
    }

    final shouldRegenerate = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Regenerate Itinerary?'),
          content: const Text(
            'Tripora will replace the current day-by-day itinerary with a fresh AI plan.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Regenerate'),
            ),
          ],
        );
      },
    );

    if (shouldRegenerate != true || !mounted) {
      return;
    }

    setState(() {
      _isRegenerating = true;
      _errorMessage = null;
    });

    try {
      final updatedTrip = await _tripService.regenerateItinerary(tripId);

      if (!mounted) return;

      setState(() {
        _trip = updatedTrip;
        _isRegenerating = false;
      });

      _showMessage('Itinerary regenerated.');
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isRegenerating = false;
        _errorMessage = _extractErrorMessage(error);
      });

      _showMessage(_extractErrorMessage(error), isError: true);
    }
  }

  Future<void> _showEditTripSheet() async {
    final tripId = _trip.id;

    if (tripId == null || _isSaving) {
      return;
    }

    final destinationController = TextEditingController(
      text: _trip.destination,
    );
    DateTime startDate = _trip.startDate;
    DateTime endDate = _trip.endDate;
    int travelers = _trip.travelers;
    const budgetOptions = ['Budget', 'Moderate', 'Luxury'];
    String budget = budgetOptions.contains(_trip.budget)
        ? _trip.budget
        : 'Moderate';
    String travelStyle = _trip.travelStyle.isEmpty
        ? 'Balanced'
        : _trip.travelStyle;
    final selectedInterests = _trip.interests.toSet();

    final updatedTrip = await showModalBottomSheet<TripModel>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> pickDate({required bool isStartDate}) async {
              final pickedDate = await showDatePicker(
                context: context,
                initialDate: isStartDate ? startDate : endDate,
                firstDate: DateTime(2000),
                lastDate: DateTime(DateTime.now().year + 3),
              );

              if (pickedDate == null) {
                return;
              }

              setSheetState(() {
                if (isStartDate) {
                  startDate = pickedDate;
                  if (endDate.isBefore(startDate)) {
                    endDate = startDate;
                  }
                } else {
                  endDate = pickedDate.isBefore(startDate)
                      ? startDate
                      : pickedDate;
                }
              });
            }

            void submit() {
              final destination = destinationController.text.trim();

              if (destination.isEmpty) {
                _showMessage('Please enter a destination.', isError: true);
                return;
              }

              Navigator.of(sheetContext).pop(
                TripModel(
                  id: _trip.id,
                  destination: destination,
                  startDate: startDate,
                  endDate: endDate,
                  travelers: travelers,
                  budget: budget,
                  travelStyle: travelStyle,
                  interests: selectedInterests.toList(),
                  itinerary: _trip.itinerary,
                  estimatedCost: _trip.estimatedCost,
                  createdAt: _trip.createdAt,
                ),
              );
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 18,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Edit Trip',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: destinationController,
                        decoration: const InputDecoration(
                          labelText: 'Destination',
                          prefixIcon: Icon(Icons.location_on_outlined),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => pickDate(isStartDate: true),
                              icon: const Icon(Icons.calendar_month_outlined),
                              label: Text(_formatDate(startDate)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => pickDate(isStartDate: false),
                              icon: const Icon(Icons.event_outlined),
                              label: Text(_formatDate(endDate)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Expanded(child: Text('Travelers')),
                          IconButton(
                            tooltip: 'Remove traveler',
                            onPressed: travelers > 1
                                ? () {
                                    setSheetState(() {
                                      travelers--;
                                    });
                                  }
                                : null,
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          Text(
                            '$travelers',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            tooltip: 'Add traveler',
                            onPressed: () {
                              setSheetState(() {
                                travelers++;
                              });
                            },
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: budget,
                        decoration: const InputDecoration(
                          labelText: 'Budget',
                          prefixIcon: Icon(
                            Icons.account_balance_wallet_outlined,
                          ),
                        ),
                        items: budgetOptions.map((option) {
                          return DropdownMenuItem(
                            value: option,
                            child: Text(option),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setSheetState(() {
                              budget = value;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        children: ['Relaxed', 'Balanced', 'Packed'].map((
                          style,
                        ) {
                          return ChoiceChip(
                            label: Text(style),
                            selected: travelStyle == style,
                            onSelected: (_) {
                              setSheetState(() {
                                travelStyle = style;
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _availableInterests.map((interest) {
                          return FilterChip(
                            label: Text(interest),
                            selected: selectedInterests.contains(interest),
                            onSelected: (selected) {
                              setSheetState(() {
                                if (selected) {
                                  selectedInterests.add(interest);
                                } else {
                                  selectedInterests.remove(interest);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: submit,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Save Changes'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    destinationController.dispose();

    if (updatedTrip == null || !mounted) {
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final savedTrip = await _tripService.updateTrip(
        tripId: tripId,
        trip: updatedTrip,
      );

      if (!mounted) return;

      setState(() {
        _trip = savedTrip;
        _isSaving = false;
      });

      _showMessage('Trip updated.');
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
        _errorMessage = _extractErrorMessage(error);
      });

      _showMessage(_extractErrorMessage(error), isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    final statusColors = Theme.of(context).extension<AppStatusColors>();

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError
              ? statusColors?.error ?? Theme.of(context).colorScheme.error
              : statusColors?.success ?? AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Widget _buildErrorState() {
    return Center(
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
                Icons.error_outline,
                size: 42,
                color: context.appStatus.error,
              ),
            ),

            const SizedBox(height: 20),

            const Text(
              'Unable to load trip details',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            Text(
              _errorMessage ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: context.triporaColors.textMuted,
              ),
            ),

            const SizedBox(height: 24),

            ElevatedButton.icon(
              onPressed: _loadTripDetails,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.appStatus.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.appStatus.warning.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_outlined,
            color: context.appStatus.warning,
            size: 20,
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Text(
              'Could not refresh: $_errorMessage. '
              'Showing cached data.',
              style: TextStyle(fontSize: 13, color: context.appStatus.warning),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // HERO SECTION
  // ============================================================

  Widget _buildHeroSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
      decoration: const BoxDecoration(
        gradient: AppColors.brandGradient,
      ),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ExcludeSemantics(
            child: Icon(Icons.flight_takeoff, color: Colors.white, size: 42),
          ),

          const SizedBox(height: 16),

          Text(
            _trip.destination,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            '${_formatDate(_trip.startDate)} - '
            '${_formatDate(_trip.endDate)}',
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TRIP OVERVIEW
  // ============================================================

  Widget _buildTripOverview() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildInfoItem(
                    Icons.calendar_month_outlined,
                    'Duration',
                    '${_trip.numberOfDays} days',
                  ),
                ),

                Expanded(
                  child: _buildInfoItem(
                    Icons.people_outline,
                    'Travelers',
                    '${_trip.travelers}',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: _buildInfoItem(
                    Icons.account_balance_wallet_outlined,
                    'Budget',
                    _trip.budget.isNotEmpty ? _trip.budget : 'Not specified',
                  ),
                ),

                Expanded(
                  child: _buildInfoItem(
                    Icons.explore_outlined,
                    'Style',
                    _trip.travelStyle.isNotEmpty
                        ? _trip.travelStyle
                        : 'Not specified',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // INFO ITEM
  // ============================================================

  Widget _buildInfoItem(IconData icon, String label, String value) {
    return Row(
      children: [
        ExcludeSemantics(child: Icon(icon, size: 22)),

        const SizedBox(width: 10),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 12, color: context.triporaColors.textMuted),
              ),

              const SizedBox(height: 3),

              Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // ESTIMATED COST
  // ============================================================

  Widget _buildEstimatedCost() {
    final cost = _trip.estimatedCost;

    if (cost == null || cost.isEmpty) {
      return const SizedBox.shrink();
    }

    final breakdown = cost['breakdown'];

    final currency = cost['currency']?.toString() ?? 'USD';

    final total = cost['estimatedTotal'] ?? cost['estimated_total'] ?? 0;

    if (breakdown is! Map) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Estimated Cost',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 6),

              Text(
                '$currency $total',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final accommodation = breakdown['accommodation']?.toString() ?? '0';

    final food = breakdown['food']?.toString() ?? '0';

    final activities = breakdown['activities']?.toString() ?? '0';

    final transportation = breakdown['transportation']?.toString() ?? '0';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Estimated Cost',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 6),

            Text(
              '$currency $total',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 20),

            _buildCostRow(
              Icons.hotel_outlined,
              'Accommodation',
              '$currency $accommodation',
            ),

            _buildCostRow(Icons.restaurant_outlined, 'Food', '$currency $food'),

            _buildCostRow(
              Icons.local_activity_outlined,
              'Activities',
              '$currency $activities',
            ),

            _buildCostRow(
              Icons.directions_car_outlined,
              'Transportation',
              '$currency $transportation',
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // COST ROW
  // ============================================================

  Widget _buildCostRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          ExcludeSemantics(child: Icon(icon, size: 20)),

          const SizedBox(width: 12),

          Expanded(child: Text(label)),

          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ============================================================
  // INTERESTS
  // ============================================================

  Widget _buildInterests() {
    if (_trip.interests.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Interests',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),

        const SizedBox(height: 10),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _trip.interests.map((interest) {
            return Chip(
              avatar: const Icon(Icons.favorite_outline, size: 16),
              label: Text(interest),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ============================================================
  // EMPTY ITINERARY
  // ============================================================

  Widget _buildEmptyItinerary() {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('No itinerary available.')),
      ),
    );
  }

  // ============================================================
  // DAY CARD
  // ============================================================

  Widget _buildDayCard(Map<String, dynamic> day) {
    final dayNumber = _getInt(day, 'day');

    final title = _getString(day, 'title');

    final date = _getString(day, 'date');

    final rawActivities = day['activities'];

    final List<Map<String, dynamic>> activities = [];

    if (rawActivities is List) {
      for (final activity in rawActivities) {
        if (activity is Map) {
          try {
            activities.add(Map<String, dynamic>.from(activity));
          } catch (error) {
            appLog('INVALID ACTIVITY DATA: $error');
          }
        }
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 18),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(child: Text(dayNumber?.toString() ?? '?')),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Day ${dayNumber ?? ''}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 3),

                      if (title.isNotEmpty)
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                      if (date.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(_formatItineraryDate(date)),
                        ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            if (activities.isEmpty)
              Text(
                'No activities available for this day.',
                style: TextStyle(color: context.triporaColors.textMuted),
              )
            else
              ...activities.map(_buildActivity),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // FORMAT ITINERARY DATE
  // ============================================================

  String _formatItineraryDate(String dateString) {
    final parsed = DateTime.tryParse(dateString);

    if (parsed == null) {
      return dateString;
    }

    return _formatDate(parsed);
  }

  // ============================================================
  // ACTIVITY
  // ============================================================

  Widget _buildActivity(Map<String, dynamic> activity) {
    final time = _getString(activity, 'time');

    final title = _getString(activity, 'title');

    final description = _getString(activity, 'description');

    final category = _getString(activity, 'category');

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: context.triporaColors.surfaceSecondary,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _getTimeIcon(time),

              const SizedBox(width: 10),

              Expanded(
                child: Text(
                  time.isEmpty ? 'Activity' : time,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),

              if (category.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: context.triporaColors.surface,
                  ),
                  child: Text(category, style: const TextStyle(fontSize: 12)),
                ),
            ],
          ),

          const SizedBox(height: 8),

          Text(
            title.isEmpty ? 'Activity' : title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),

          if (description.isNotEmpty) ...[
            const SizedBox(height: 6),

            Text(description, style: const TextStyle(height: 1.4)),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // TIME ICON
  // ============================================================

  Widget _getTimeIcon(String time) {
    final lowerTime = time.toLowerCase();

    if (lowerTime.contains('morning')) {
      return const Icon(Icons.wb_sunny_outlined, size: 22);
    }

    if (lowerTime.contains('afternoon')) {
      return const Icon(Icons.wb_sunny, size: 22);
    }

    if (lowerTime.contains('evening')) {
      return const Icon(Icons.nightlight_outlined, size: 22);
    }

    return const Icon(Icons.access_time, size: 22);
  }
}
