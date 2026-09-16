import 'dart:convert';
import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:flutter/material.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/preferences/app_preferences.dart';
import '../../routes/app_routes.dart';

class ItineraryScreen extends StatelessWidget {
  final Map<String, dynamic> tripData;

  const ItineraryScreen({
    super.key,
    required this.tripData,
  });

  // ============================================================
  // COLORS
  // ============================================================

  static const Color _background = Color(0xFFF8FAFC);
  static const Color _surface = Colors.white;
  static const Color _midnight = Color(0xFF1E1B4B);
  static const Color _blue = Color(0xFF3B82F6);
  static const Color _amber = Color(0xFFF59E0B);
  static const Color _text = Color(0xFF191C1E);
  static const Color _secondaryText = Color(0xFF475569);
  static const Color _mutedText = Color(0xFF64748B);
  static const Color _border = Color(0xFFE2E8F0);
  static const Color _strongBorder = Color(0xFFCBD5E1);

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
    return _stringValue(
      trip['destination'],
      'Your Destination',
    );
  }

  // ============================================================
  // START DATE
  // ============================================================

  DateTime get startDate {
    final date = _dateValue(
      trip['startDate'] ?? trip['start_date'],
    );

    return date ?? DateTime.now();
  }

  // ============================================================
  // END DATE
  // ============================================================

  DateTime get endDate {
    final date = _dateValue(
      trip['endDate'] ?? trip['end_date'],
    );

    return date ?? startDate;
  }

  // ============================================================
  // TRAVELERS
  // ============================================================

  int get travelers {
    return _intValue(
      trip['travelers'],
      1,
    );
  }

  // ============================================================
  // BUDGET
  // ============================================================

  String get budget {
    return _stringValue(
      trip['budget'],
      'Moderate',
    );
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
    dynamic value =
        trip['estimatedCost'] ?? trip['estimated_cost'];

    value ??= tripData['estimatedCost'];
    value ??= tripData['estimated_cost'];

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return null;
  }

  // ============================================================
  // ITINERARY
  // ============================================================

  List<Map<String, dynamic>> get itinerary {
    dynamic value = trip['itinerary'];

    if (value is List) {
      return _parseItineraryList(value);
    }

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
        result.add(
          Map<String, dynamic>.from(item),
        );
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
    return ListenableBuilder(
      listenable: AppPreferences.instance,
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,

      // ========================================================
      // APP BAR
      // ========================================================

      appBar: AppBar(
        backgroundColor: _background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,

        leading: IconButton(
          tooltip: 'Go back',
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: _midnight,
          ),
          onPressed: () {
            Navigator.pop(context);
          },
        ),

        title: const Text(
          'Your Itinerary',
          style: TextStyle(
            fontFamily: 'Noto Serif',
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: _midnight,
          ),
        ),
      ),

      // ========================================================
      // BODY
      // ========================================================

      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 1080,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                16,
                12,
                16,
                40,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ==================================================
                  // EDITORIAL TRIP HEADER
                  // ==================================================

                  _buildTripHeader(context),

                  // ==================================================
                  // COST
                  // ==================================================

                  if (estimatedCost != null) ...[
                    const SizedBox(height: 24),
                    _buildCostCard(context),
                  ],

                  const SizedBox(height: 48),

                  // ==================================================
                  // ITINERARY INTRO
                  // ==================================================

                  _buildSectionHeading(),

                  const SizedBox(height: 28),

                  // ==================================================
                  // ITINERARY
                  // ==================================================

                  if (itinerary.isEmpty)
                    _buildEmptyItinerary(context),

                  ...itinerary.map(
                    (day) {
                      return Padding(
                        padding: const EdgeInsets.only(
                          bottom: 20,
                        ),
                        child: _buildDayCard(
                          context: context,
                          day: _intValue(
                            day['day'],
                            1,
                          ),
                          date: day['date']?.toString(),
                          title: _stringValue(
                            day['title'],
                            'Travel Day',
                          ),
                          activities: _parseActivities(
                            day['activities'],
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // ==================================================
                  // ACTIONS
                  // ==================================================

                  _buildActionButtons(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // TRIP HEADER
  // ============================================================

  Widget _buildTripHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: _midnight,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AI LABEL

          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 11,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.16),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 14,
                  color: Color(0xFF93C5FD),
                ),
                SizedBox(width: 7),
                Text(
                  'AI-GENERATED TRAVEL PLAN',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 22),

          // DESTINATION

          Text(
            destination,
            style: const TextStyle(
              fontFamily: 'Noto Serif',
              fontSize: 38,
              height: 1.08,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),

          const SizedBox(height: 10),

          Text(
            '${_formatDate(_dateIso(startDate))} — '
            '${_formatDate(_dateIso(endDate))}',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.70),
            ),
          ),

          const SizedBox(height: 28),

          // INFO ROW

          Wrap(
            spacing: 20,
            runSpacing: 14,
            children: [
              _buildHeaderInfo(
                Icons.calendar_today_outlined,
                '$numberOfDays ${context.tr('it.days')}',
              ),
              _buildHeaderInfo(
                Icons.people_outline,
                travelers == 1
                    ? '1 ${context.tr('it.travelerOne')}'
                    : '$travelers ${context.tr('it.travelerPlural')}',
              ),
              _buildHeaderInfo(
                Icons.account_balance_wallet_outlined,
                budget,
              ),
              _buildHeaderInfo(
                Icons.explore_outlined,
                travelStyle,
              ),
            ],
          ),

          if (interests.isNotEmpty) ...[
            const SizedBox(height: 24),

            Divider(
              color: Colors.white.withValues(alpha: 0.12),
              height: 1,
            ),

            const SizedBox(height: 18),

            Text(
              'INTERESTS',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),

            const SizedBox(height: 10),

            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: interests.map(
                (interest) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Text(
                      interest,
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  );
                },
              ).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // HEADER INFO
  // ============================================================

  Widget _buildHeaderInfo(
    IconData icon,
    String text,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: const Color(0xFF93C5FD),
        ),
        const SizedBox(width: 7),
        Text(
          text,
          style: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // SECTION HEADING
  // ============================================================

  Widget _buildSectionHeading() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'YOUR ITINERARY',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
            color: _blue,
          ),
        ),

        const SizedBox(height: 7),

        const Text(
          'Days designed around you.',
          style: TextStyle(
            fontFamily: 'Noto Serif',
            fontSize: 31,
            height: 1.15,
            fontWeight: FontWeight.w700,
            color: _midnight,
          ),
        ),

        const SizedBox(height: 8),

        const Text(
          'A suggested plan based on your preferences.',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 14,
            height: 1.5,
            color: _secondaryText,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // EMPTY ITINERARY
  // ============================================================

  Widget _buildEmptyItinerary(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.event_note_outlined,
              color: _blue,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'No itinerary was generated.',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _secondaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // COST CARD
  // ============================================================

  Widget _buildCostCard(BuildContext context) {
    final cost = estimatedCost!;

    final currency = _stringValue(
      cost['currency'],
      'USD',
    );

    final total =
        cost['estimatedTotal'] ??
        cost['estimated_total'] ??
        0;

    final breakdown = cost['breakdown'];

    final Map<String, dynamic> costs =
        breakdown is Map
            ? Map<String, dynamic>.from(breakdown)
            : {};

    final prefs = AppPreferences.instance;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 20,
                  color: _amber,
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('it.estimatedCost'),
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: _mutedText,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      context.tr('it.tripBudgetOverview'),
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _text,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          Text(
            prefs.formatMoney(total, from: currency),
            style: const TextStyle(
              fontFamily: 'Noto Serif',
              fontSize: 34,
              fontWeight: FontWeight.w700,
              color: _midnight,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            context.tr('it.approxCost'),
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 12,
              height: 1.5,
              color: _mutedText,
            ),
          ),

          if (costs.isNotEmpty) ...[
            const SizedBox(height: 20),

            const Divider(
              color: _border,
            ),

            const SizedBox(height: 16),

            _buildCostRow(
              context,
              context.tr('it.accommodation'),
              costs['accommodation'],
              currency,
            ),

            _buildCostRow(
              context,
              context.tr('it.food'),
              costs['food'],
              currency,
            ),

            _buildCostRow(
              context,
              context.tr('it.transportation'),
              costs['transportation'],
              currency,
            ),

            _buildCostRow(
              context,
              context.tr('it.activities'),
              costs['activities'],
              currency,
            ),
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
      padding: const EdgeInsets.only(
        bottom: 13,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 13,
                color: _secondaryText,
              ),
            ),
          ),
          Text(
            AppPreferences.instance.formatMoney(value ?? 0, from: currency),
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _text,
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
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _border,
        ),
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
                width: 50,
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _midnight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '$day',
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),

              const SizedBox(width: 15),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DAY ${day.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: _blue,
                      ),
                    ),

                    if (date != null && date.isNotEmpty) ...[
                      const SizedBox(height: 4),

                      Text(
                        _formatDate(date),
                        style: const TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _mutedText,
                        ),
                      ),
                    ],

                    const SizedBox(height: 5),

                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'Noto Serif',
                        fontSize: 21,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: _text,
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
            const Text(
              'No activities available for this day.',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 13,
                color: _mutedText,
              ),
            ),

          ...activities.asMap().entries.map(
            (entry) {
              final index = entry.key;
              final activity = entry.value;

              return _buildActivity(
                context,
                activity,
                isLast: index == activities.length - 1,
              );
            },
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ACTIVITY
  // ============================================================

  Widget _buildActivity(
    BuildContext context,
    _Activity activity, {
    required bool isLast,
  }) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: isLast ? 0 : 20,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ICON

          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              activity.icon,
              size: 19,
              color: _blue,
            ),
          ),

          const SizedBox(width: 13),

          // CONTENT

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (activity.time.isNotEmpty)
                  Text(
                    activity.time,
                    style: const TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: _blue,
                    ),
                  ),

                if (activity.time.isNotEmpty)
                  const SizedBox(height: 3),

                Text(
                  activity.title,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _text,
                  ),
                ),

                if (activity.description.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    activity.description,
                    style: const TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 13,
                      height: 1.55,
                      color: _secondaryText,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ACTION BUTTONS
  // ============================================================

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      children: [
        // EDIT

        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
            },
            icon: const Icon(
              Icons.edit_outlined,
              size: 18,
            ),
            label: const Text(
              'Edit Trip',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: _midnight,
              side: const BorderSide(
                color: _strongBorder,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // FLIGHTS

        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            onPressed: () {
              _openFlightPrices(context);
            },
            icon: const Icon(
              Icons.flight_takeoff_outlined,
              size: 18,
            ),
            label: const Text(
              'Check flight prices',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _midnight,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // CALENDAR

        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton.icon(
            onPressed: () {
              _addToCalendar(context);
            },
            icon: const Icon(
              Icons.event_outlined,
              size: 18,
            ),
            label: const Text(
              'Add to calendar',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: _midnight,
              side: const BorderSide(
                color: _strongBorder,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // OPEN FLIGHT PRICES
  // ============================================================

  void _openFlightPrices(BuildContext context) {
    final d = destination;

    Navigator.pushNamed(
      context,
      AppRoutes.checkFlightPrices,
      arguments: <String, dynamic>{
        if (d.isNotEmpty) 'destination': d,
        'departDate': _dateIso(startDate),
      },
    );
  }

  // ============================================================
  // ADD TO CALENDAR
  // ============================================================

  Future<void> _addToCalendar(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      final event = Event(
        title: 'Trip to $destination',
        description: budget.isNotEmpty
            ? 'Budget: $budget'
            : null,
        location: destination,
        startDate: startDate,
        endDate: endDate,
        allDay: true,
      );

      final added = await Add2Calendar.addEvent2Cal(event);

      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              added
                  ? 'Trip added to calendar'
                  : 'Could not open the calendar.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open the calendar.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  // ============================================================
  // DATE ISO
  // ============================================================

  String _dateIso(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  // ============================================================
  // PARSE ACTIVITIES
  // ============================================================

  List<_Activity> _parseActivities(
    dynamic activities,
  ) {
    final result = <_Activity>[];

    if (activities is! List) {
      return result;
    }

    for (final activity in activities) {
      if (activity is! Map) {
        continue;
      }

      final category =
          activity['category']?.toString();

      result.add(
        _Activity(
          icon: _getActivityIcon(category),
          time: _stringValue(
            activity['time'],
          ),
          title: _stringValue(
            activity['title'],
            'Activity',
          ),
          description: _stringValue(
            activity['description'],
          ),
        ),
      );
    }

    return result;
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
