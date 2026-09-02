import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../routes/app_routes.dart';

class ItineraryScreen extends StatelessWidget {
  final Map<String, dynamic> tripData;

  const ItineraryScreen({super.key, required this.tripData});

  // ============================================================
  // SAFE VALUE HELPERS
  // ============================================================

  String _stringValue(dynamic value, [String fallback = '']) {
    if (value == null) {
      return fallback;
    }

    return value.toString();
  }

  int _intValue(dynamic value, [int fallback = 0]) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  DateTime? _dateValue(dynamic value) {
    if (value == null) {
      return null;
    }

    return DateTime.tryParse(value.toString());
  }

  // ============================================================
  // GET ACTUAL TRIP OBJECT
  //
  // Supports:
  //
  // {
  //   success: true,
  //   trip: {...}
  // }
  //
  // OR directly:
  //
  // {
  //   id: 11,
  //   destination: "...",
  //   itinerary: [...]
  // }
  // ============================================================

  Map<String, dynamic> get trip {
    final nestedTrip = tripData['trip'];

    if (nestedTrip is Map) {
      return Map<String, dynamic>.from(nestedTrip);
    }

    return tripData;
  }

  // ============================================================
  // DESTINATION
  // ============================================================

  String get destination {
    return _stringValue(trip['destination'], 'Your Destination');
  }

  // ============================================================
  // START DATE
  // ============================================================

  DateTime get startDate {
    final date = _dateValue(trip['startDate'] ?? trip['start_date']);

    return date ?? DateTime.now();
  }

  // ============================================================
  // END DATE
  // ============================================================

  DateTime get endDate {
    final date = _dateValue(trip['endDate'] ?? trip['end_date']);

    return date ?? startDate;
  }

  // ============================================================
  // TRAVELERS
  // ============================================================

  int get travelers {
    return _intValue(trip['travelers'], 1);
  }

  // ============================================================
  // BUDGET
  // ============================================================

  String get budget {
    return _stringValue(trip['budget'], 'Moderate');
  }

  // ============================================================
  // TRAVEL STYLE
  // ============================================================

  String get travelStyle {
    return _stringValue(
      trip['travelStyle'] ?? trip['travel_style'],
      'Balanced',
    );
  }

  // ============================================================
  // INTERESTS
  // ============================================================

  Set<String> get interests {
    final value = trip['interests'];

    if (value is List) {
      return value
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toSet();
    }

    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);

        if (decoded is List) {
          return decoded
              .map((item) => item.toString())
              .where((item) => item.isNotEmpty)
              .toSet();
        }
      } catch (_) {
        return {value};
      }
    }

    return {};
  }

  // ============================================================
  // ESTIMATED COST
  // ============================================================

  Map<String, dynamic>? get estimatedCost {
    dynamic value = trip['estimatedCost'] ?? trip['estimated_cost'];

    // Sometimes estimated cost may be
    // returned outside the nested trip object.
    value ??= tripData['estimatedCost'];
    value ??= tripData['estimated_cost'];

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return null;
  }

  // ============================================================
  // ITINERARY
  //
  // Supports:
  //
  // itinerary: [...]
  //
  // AND:
  //
  // itinerary: "[...]"
  // ============================================================

  List<Map<String, dynamic>> get itinerary {
    dynamic value = trip['itinerary'];

    // ----------------------------------------------------------
    // Already a List
    // ----------------------------------------------------------

    if (value is List) {
      return _parseItineraryList(value);
    }

    // ----------------------------------------------------------
    // JSON string
    // ----------------------------------------------------------

    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);

        if (decoded is List) {
          return _parseItineraryList(decoded);
        }
      } catch (_) {
        return [];
      }
    }

    return [];
  }

  // ============================================================
  // PARSE ITINERARY
  // ============================================================

  List<Map<String, dynamic>> _parseItineraryList(List value) {
    final result = <Map<String, dynamic>>[];

    for (final item in value) {
      if (item is Map) {
        result.add(Map<String, dynamic>.from(item));
      }
    }

    return result;
  }

  // ============================================================
  // NUMBER OF DAYS
  // ============================================================

  int get numberOfDays {
    final difference = endDate.difference(startDate).inDays;

    return difference >= 0 ? difference + 1 : 1;
  }

  // ============================================================
  // FORMAT DATE
  // ============================================================

  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) {
      return '';
    }

    final date = DateTime.tryParse(dateString);

    if (date == null) {
      return dateString;
    }

    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return '${months[date.month - 1]} '
        '${date.day}, '
        '${date.year}';
  }

  // ============================================================
  // ACTIVITY ICON
  // ============================================================

  IconData _getActivityIcon(String? category) {
    switch (category?.toLowerCase()) {
      case 'food':
      case 'dining':
      case 'restaurant':
        return Icons.restaurant_outlined;

      case 'culture':
      case 'cultural':
        return Icons.museum_outlined;

      case 'sightseeing':
      case 'exploration':
        return Icons.explore_outlined;

      case 'history':
        return Icons.account_balance_outlined;

      case 'arts':
      case 'art':
        return Icons.palette_outlined;

      case 'shopping':
        return Icons.shopping_bag_outlined;

      case 'relaxation':
      case 'beach':
        return Icons.beach_access_outlined;

      case 'architecture':
        return Icons.architecture_outlined;

      case 'travel':
      case 'transportation':
        return Icons.flight_outlined;

      case 'nature':
        return Icons.park_outlined;

      case 'nightlife':
        return Icons.nightlife_outlined;

      case 'adventure':
        return Icons.hiking_outlined;

      default:
        return Icons.place_outlined;
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.triporaColors.backgroundColor,

      // ========================================================
      // APP BAR
      // ========================================================
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,

        leading: IconButton(
          tooltip: 'Go back',
          icon: Icon(
            Icons.arrow_back,
            color: context.triporaColors.textPrimary,
          ),
          onPressed: () {
            Navigator.pop(context);
          },
        ),

        title: Text(
          'Your Itinerary',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: context.triporaColors.textPrimary,
          ),
        ),
      ),

      // ========================================================
      // BODY
      // ========================================================
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ==================================================
                  // TRIP HEADER
                  // ==================================================
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: context.triporaColors.surface,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '\u2726 Your AI Travel Plan',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),

                        const SizedBox(height: 12),

                        Text(
                          destination,
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            color: context.triporaColors.textPrimary,
                          ),
                        ),

                        const SizedBox(height: 20),

                        Wrap(
                          spacing: 20,
                          runSpacing: 12,
                          children: [
                            _buildInfo(
                              context,
                              Icons.calendar_month_outlined,
                              '$numberOfDays days',
                            ),

                            _buildInfo(
                              context,
                              Icons.people_outline,
                              '$travelers traveler'
                              '${travelers == 1 ? '' : 's'}',
                            ),

                            _buildInfo(
                              context,
                              Icons.account_balance_wallet_outlined,
                              budget,
                            ),

                            _buildInfo(
                              context,
                              Icons.explore_outlined,
                              travelStyle,
                            ),
                          ],
                        ),

                        if (interests.isNotEmpty) ...[
                          const SizedBox(height: 20),

                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: interests.map((interest) {
                              return Chip(label: Text(interest));
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // ==================================================
                  // COST
                  // ==================================================
                  if (estimatedCost != null) ...[
                    const SizedBox(height: 30),

                    _buildCostCard(context),
                  ],

                  const SizedBox(height: 40),

                  // ==================================================
                  // ITINERARY TITLE
                  // ==================================================
                  Text(
                    'Your Itinerary',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: context.triporaColors.textPrimary,
                    ),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    'A suggested plan based on your preferences.',
                    style: TextStyle(
                      fontSize: 16,
                      color: context.triporaColors.textSecondary,
                    ),
                  ),

                  const SizedBox(height: 30),

                  // ==================================================
                  // ITINERARY
                  // ==================================================
                  if (itinerary.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: context.triporaColors.surface,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        'No itinerary was generated.',
                        style: TextStyle(
                          fontSize: 16,
                          color: context.triporaColors.textSecondary,
                        ),
                      ),
                    ),

                  ...itinerary.map((day) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: _buildDayCard(
                        context: context,
                        day: _intValue(day['day'], 1),
                        date: day['date']?.toString(),
                        title: _stringValue(day['title'], 'Travel Day'),
                        activities: _parseActivities(day['activities']),
                      ),
                    );
                  }),

                  const SizedBox(height: 40),

                  // ==================================================
                  // EDIT TRIP
                  // ==================================================
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text(
                        'Edit Trip',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ==================================================
                  // CHECK FLIGHT PRICES
                  // ==================================================
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _openFlightPrices(context),
                      icon: const Icon(Icons.flight_takeoff),
                      label: const Text(
                        'Check flight prices',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // OPEN FLIGHT PRICES
  // ============================================================

  void _openFlightPrices(BuildContext context) {
    final d = destination;
    // The itinerary doesn't know the traveller's home airport, so we leave
    // the origin blank and prefill only the destination + date. The user can
    // type their origin airport on the price screen.
    Navigator.pushNamed(
      context,
      AppRoutes.checkFlightPrices,
      arguments: <String, dynamic>{
        if (d.isNotEmpty) 'destination': d,
        'departDate': _dateIso(startDate),
      },
    );
  }

  String _dateIso(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  // ============================================================
  // PARSE ACTIVITIES
  // ============================================================

  List<_Activity> _parseActivities(dynamic activities) {
    final result = <_Activity>[];

    if (activities is! List) {
      return result;
    }

    for (final activity in activities) {
      if (activity is! Map) {
        continue;
      }

      final category = activity['category']?.toString();

      result.add(
        _Activity(
          icon: _getActivityIcon(category),
          time: _stringValue(activity['time']),
          title: _stringValue(activity['title'], 'Activity'),
          description: _stringValue(activity['description']),
        ),
      );
    }

    return result;
  }

  // ============================================================
  // INFO ITEM
  // ============================================================

  Widget _buildInfo(BuildContext context, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Icon(
            icon,
            size: 19,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),

        const SizedBox(width: 7),

        Text(
          text,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: context.triporaColors.textSecondary,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // COST CARD
  // ============================================================

  Widget _buildCostCard(BuildContext context) {
    final cost = estimatedCost!;

    final currency = _stringValue(cost['currency'], 'USD');

    final total = cost['estimatedTotal'] ?? cost['estimated_total'] ?? 0;

    final breakdown = cost['breakdown'];

    final Map<String, dynamic> costs = breakdown is Map
        ? Map<String, dynamic>.from(breakdown)
        : {};

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: context.triporaColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.triporaColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),

              const SizedBox(width: 10),

              Text(
                'Estimated Trip Cost',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: context.triporaColors.textPrimary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          Text(
            '$currency $total',
            style: TextStyle(
              fontSize: 38,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'Approximate cost for your trip. '
            'Actual prices may vary.',
            style: TextStyle(
              fontSize: 14,
              color: context.triporaColors.textSecondary,
            ),
          ),

          if (costs.isNotEmpty) ...[
            const SizedBox(height: 25),

            const Divider(),

            const SizedBox(height: 18),

            _buildCostRow(
              context,
              'Accommodation',
              costs['accommodation'],
              currency,
            ),

            _buildCostRow(context, 'Food', costs['food'], currency),

            _buildCostRow(
              context,
              'Transportation',
              costs['transportation'],
              currency,
            ),

            _buildCostRow(context, 'Activities', costs['activities'], currency),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // COST ROW
  // ============================================================

  Widget _buildCostRow(
    BuildContext context,
    String label,
    dynamic value,
    String currency,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                color: context.triporaColors.textSecondary,
              ),
            ),
          ),

          Text(
            '$currency ${value ?? 0}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: context.triporaColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DAY CARD
  // ============================================================

  Widget _buildDayCard({
    required BuildContext context,
    required int day,
    required String? date,
    required String title,
    required List<_Activity> activities,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.triporaColors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ------------------------------------------------------
          // DAY HEADER
          // ------------------------------------------------------
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '$day',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),

              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Day $day',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.triporaColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    if (date != null && date.isNotEmpty) ...[
                      const SizedBox(height: 3),

                      Text(
                        _formatDate(date),
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],

                    const SizedBox(height: 5),

                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: context.triporaColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ------------------------------------------------------
          // ACTIVITIES
          // ------------------------------------------------------
          if (activities.isEmpty)
            Text(
              'No activities available for this day.',
              style: TextStyle(color: context.triporaColors.textMuted),
            ),

          ...activities.map((activity) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: Icon(
                      activity.icon,
                      size: 22,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),

                  const SizedBox(width: 14),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (activity.time.isNotEmpty)
                          Text(
                            activity.time,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),

                        const SizedBox(height: 3),

                        Text(
                          activity.title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: context.triporaColors.textPrimary,
                          ),
                        ),

                        const SizedBox(height: 5),

                        Text(
                          activity.description,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: context.triporaColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ================================================================
// ACTIVITY MODEL
// ================================================================

class _Activity {
  final IconData icon;
  final String time;
  final String title;
  final String description;

  const _Activity({
    required this.icon,
    required this.time,
    required this.title,
    required this.description,
  });
}
