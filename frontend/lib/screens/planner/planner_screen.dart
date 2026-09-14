import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../data/destinations.dart';
import '../../models/trip_model.dart';
import '../../services/trip_service.dart';
import '../../widgets/shimmer_loader.dart';

class PlannerScreen extends StatefulWidget {
  final String? initialDestination;

  const PlannerScreen({super.key, this.initialDestination});

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> {
  late final TextEditingController destinationController;

  final TripService tripService = TripService();

  DateTime? startDate;
  DateTime? endDate;

  int travelers = 1;
  String budget = 'Moderate';
  String travelStyle = 'Balanced';

  bool isGenerating = false;

  final List<String> interests = const [
    'Culture',
    'Food',
    'Nature',
    'Adventure',
    'Shopping',
    'Nightlife',
    'Relaxation',
  ];

  final Set<String> selectedInterests = {};

  static const List<String> _trendingCities = [
    'Tokyo',
    'Paris',
    'Bali',
    'Rome',
    'New York',
    'Bangkok',
  ];

  static const Color _midnight = Color(0xFF1E1B4B);
  static const Color _midnightDark = Color(0xFF070235);
  static const Color _blue = Color(0xFF3B82F6);
  static const Color _canvas = Color(0xFFF8FAFC);
  static const Color _white = Colors.white;
  static const Color _border = Color(0xFFE2E8F0);
  static const Color _borderStrong = Color(0xFFCBD5E1);
  static const Color _textPrimary = Color(0xFF191C1E);
  static const Color _textSecondary = Color(0xFF475569);
  static const Color _textMuted = Color(0xFF64748B);

  @override
  void initState() {
    super.initState();

    destinationController = TextEditingController(
      text: widget.initialDestination ?? '',
    );
  }

  @override
  void dispose() {
    destinationController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Progress (real, based on filled fields — not a fabricated step count)
  // ---------------------------------------------------------------------

  double get _completionProgress {
    int filled = 0;
    const int total = 4;

    if (destinationController.text.trim().isNotEmpty) filled++;
    if (startDate != null && endDate != null) filled++;
    if (travelers >= 1) filled++;
    if (budget.isNotEmpty) filled++;

    return filled / total;
  }

  void _resetForm() {
    setState(() {
      destinationController.clear();
      startDate = null;
      endDate = null;
      travelers = 1;
      budget = 'Moderate';
      travelStyle = 'Balanced';
      selectedInterests.clear();
    });
  }

  // ---------------------------------------------------------------------
  // Date handling
  // ---------------------------------------------------------------------

  Future<void> selectDate({required bool isStartDate}) async {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);

    DateTime initialDate;

    if (isStartDate) {
      initialDate = startDate ?? today;
    } else {
      initialDate = endDate ?? startDate ?? today;
    }

    initialDate = DateTime(
      initialDate.year,
      initialDate.month,
      initialDate.day,
    );

    if (initialDate.isBefore(today)) {
      initialDate = today;
    }

    final DateTime lastDate = DateTime(
      today.year + 2,
      today.month,
      today.day,
    );

    if (initialDate.isAfter(lastDate)) {
      initialDate = lastDate;
    }

    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: today,
      lastDate: lastDate,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: _midnight,
              surface: _white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate == null || !mounted) {
      return;
    }

    final DateTime selectedDate = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
    );

    if (isStartDate) {
      setState(() {
        startDate = selectedDate;

        if (endDate != null && endDate!.isBefore(selectedDate)) {
          endDate = null;
        }
      });

      return;
    }

    if (startDate != null && selectedDate.isBefore(startDate!)) {
      _showMessage(
        'End date cannot be before the start date.',
        isError: true,
      );
      return;
    }

    setState(() {
      endDate = selectedDate;
    });
  }

  /// Applies a pacing preset by setting dates relative to today (or the
  /// existing start date, if one is already chosen).
  void _applyPacingPreset(String preset) {
    final DateTime base = startDate ?? DateTime.now();
    final DateTime start = DateTime(base.year, base.month, base.day);

    int days;
    switch (preset) {
      case 'Weekend':
        days = 2;
        break;
      case '1 Week':
        days = 7;
        break;
      case '2 Weeks':
        days = 14;
        break;
      case 'Flexible':
      default:
      // Flexible just clears dates so the user can pick their own.
        setState(() {
          startDate = null;
          endDate = null;
        });
        return;
    }

    setState(() {
      startDate = start;
      endDate = start.add(Duration(days: days));
    });
  }

  String? _activePacingPreset() {
    if (startDate == null || endDate == null) {
      return null;
    }

    final int days = endDate!.difference(startDate!).inDays;

    if (days == 2) return 'Weekend';
    if (days == 7) return '1 Week';
    if (days == 14) return '2 Weeks';

    return null;
  }

  String _displayDate(DateTime? date) {
    if (date == null) {
      return 'Select date';
    }

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

  String _dayOfWeek(DateTime date) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    return days[date.weekday - 1];
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }

    final statusColors = Theme.of(context).extension<AppStatusColors>();

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: isError
              ? statusColors?.error ?? Theme.of(context).colorScheme.error
              : statusColors?.info ?? _blue,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
  }

  // ---------------------------------------------------------------------
  // Trip generation
  // ---------------------------------------------------------------------

  Future<void> generateTrip() async {
    if (isGenerating) {
      return;
    }

    final String destination = destinationController.text.trim();

    if (destination.isEmpty) {
      _showMessage(
        'Please enter a destination.',
        isError: true,
      );
      return;
    }

    if (startDate == null || endDate == null) {
      _showMessage(
        'Please select your travel dates.',
        isError: true,
      );
      return;
    }

    if (endDate!.isBefore(startDate!)) {
      _showMessage(
        'End date cannot be before the start date.',
        isError: true,
      );
      return;
    }

    if (travelers < 1) {
      _showMessage(
        'There must be at least one traveler.',
        isError: true,
      );
      return;
    }

    final TripModel trip = TripModel(
      destination: destination,
      startDate: startDate!,
      endDate: endDate!,
      travelers: travelers,
      budget: budget,
      travelStyle: travelStyle,
      interests: selectedInterests.toList(),
    );

    setState(() {
      isGenerating = true;
    });

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      barrierColor: const Color(0xB3070235),
      builder: (_) {
        return const PopScope(
          canPop: false,
          child: Center(
            child: _GenerationDialog(),
          ),
        );
      },
    );

    try {
      final Map<String, dynamic> response =
      await tripService.generateTrip(trip);

      if (mounted) {
        Navigator.of(
          context,
          rootNavigator: true,
        ).pop();
      }

      if (!mounted) {
        return;
      }

      if (kDebugMode) {
        debugPrint('====================================');
        debugPrint('GENERATE TRIP RESPONSE');
        debugPrint(response.toString());
        debugPrint('====================================');
      }

      if (response['success'] != true) {
        _showMessage(
          response['message']?.toString() ??
              'Trip generation failed.',
          isError: true,
        );
        return;
      }

      final dynamic tripData = response['trip'];

      if (tripData is! Map) {
        _showMessage(
          'Trip was generated, but no trip data was returned.',
          isError: true,
        );
        return;
      }

      final Map<String, dynamic> tripMap =
      Map<String, dynamic>.from(tripData);

      if (kDebugMode) {
        debugPrint('====================================');
        debugPrint('GENERATED TRIP');
        debugPrint('TRIP ID: ${tripMap['id']}');
        debugPrint('DESTINATION: ${tripMap['destination']}');
        debugPrint('START DATE: ${tripMap['startDate']}');
        debugPrint('END DATE: ${tripMap['endDate']}');
        debugPrint(
          'ITINERARY TYPE: '
              '${tripMap['itinerary']?.runtimeType}',
        );
        debugPrint(
          'ITINERARY LENGTH: '
              '${tripMap['itinerary'] is List ? (tripMap['itinerary'] as List).length : 0}',
        );
        debugPrint('====================================');
      }

      if (!mounted) {
        return;
      }

      HapticFeedback.mediumImpact();

      await Navigator.pushNamed(
        context,
        '/itinerary',
        arguments: tripMap,
      );
    } catch (error) {
      if (mounted) {
        Navigator.of(
          context,
          rootNavigator: true,
        ).pop();
      }

      if (!mounted) {
        return;
      }

      final String message = error
          .toString()
          .replaceFirst('Exception: ', '')
          .trim();

      _showMessage(
        message.isEmpty
            ? 'Something went wrong while generating your trip.'
            : message,
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          isGenerating = false;
        });
      }
    }
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _canvas,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            _buildProgressBar(),
            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 920),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 48),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'The Essentials',
                            style: TextStyle(
                              fontFamily: 'Noto Serif',
                              fontSize: 28,
                              fontWeight: FontWeight.w600,
                              color: _midnight,
                            ),
                          ),
                          const SizedBox(height: 20),

                          _buildDestinationSection(),
                          const SizedBox(height: 20),

                          _buildDatesSection(),
                          const SizedBox(height: 20),

                          _buildTravelersSection(),
                          const SizedBox(height: 20),

                          _buildBudgetSection(),
                          const SizedBox(height: 20),

                          _buildTravelStyleSection(),
                          const SizedBox(height: 40),

                          _buildGenerateButton(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Top bar + progress
  // ---------------------------------------------------------------------

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: isGenerating ? null : () => Navigator.maybePop(context),
            icon: const Icon(Icons.close, size: 20, color: _textPrimary),
            label: const Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _textPrimary,
              ),
            ),
          ),
          const Spacer(),
          Text(
            '${(_completionProgress * 100).round()}% COMPLETE',
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: _blue,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: isGenerating ? null : _resetForm,
            child: const Text(
              'Reset',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return ClipRRect(
      child: LinearProgressIndicator(
        value: _completionProgress,
        minHeight: 3,
        backgroundColor: _border,
        color: _midnight,
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Destination section (with trending curations)
  // ---------------------------------------------------------------------

  Widget _buildDestinationSection() {
    final matchedDestination = _matchDestination(destinationController.text);

    return _buildSection(
      number: 1,
      title: 'Where does your story begin?',
      trailingIcon: Icons.public,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: destinationController,
            enabled: !isGenerating,
            textInputAction: TextInputAction.done,
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 14,
              color: _textPrimary,
            ),
            onChanged: (_) => setState(() {}),
            decoration: _inputDecoration(
              hintText: 'e.g. Paris, France',
              icon: Icons.location_on_outlined,
              suffixIcon: destinationController.text.isEmpty
                  ? null
                  : IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: isGenerating
                    ? null
                    : () {
                  setState(() {
                    destinationController.clear();
                  });
                },
              ),
            ),
          ),

          const SizedBox(height: 16),

          const Text(
            'TRENDING CURATIONS',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: _textMuted,
            ),
          ),

          const SizedBox(height: 10),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _trendingCities.map((city) {
              final destination = destinations.firstWhere(
                    (d) => d.city == city,
                orElse: () => destinations.first,
              );

              final selected =
                  destinationController.text.trim().toLowerCase() ==
                      destination.fullName.toLowerCase();

              return ChoiceChip(
                label: Text(
                  destination.city,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 12,
                    fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected ? Colors.white : _midnight,
                  ),
                ),
                selected: selected,
                showCheckmark: false,
                backgroundColor: const Color(0xFFF1F5F9),
                selectedColor: _midnight,
                side: BorderSide(
                  color: selected ? _midnight : _borderStrong,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                onSelected: isGenerating
                    ? null
                    : (_) {
                  setState(() {
                    destinationController.text = destination.fullName;
                    destinationController.selection =
                        TextSelection.collapsed(
                          offset: destinationController.text.length,
                        );
                  });
                },
              );
            }).toList(),
          ),

          if (matchedDestination != null) ...[
            const SizedBox(height: 16),
            _buildDestinationCard(matchedDestination),
          ],
        ],
      ),
    );
  }

  dynamic _matchDestination(String query) {
    final trimmed = query.trim().toLowerCase();

    if (trimmed.isEmpty) {
      return null;
    }

    for (final destination in destinations) {
      if (destination.fullName.toLowerCase() == trimmed ||
          destination.city.toLowerCase() == trimmed) {
        return destination;
      }
    }

    return null;
  }

  Widget _buildDestinationCard(dynamic destination) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 140,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              destination.imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: const Color(0xFFF1F5F9),
                child: const Icon(
                  Icons.image_not_supported_outlined,
                  color: _textMuted,
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    _midnight.withValues(alpha: 0.78),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${destination.city} ${destination.country}',
                    style: const TextStyle(
                      fontFamily: 'Noto Serif',
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    destination.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFE2E8F0),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Dates + pacing presets
  // ---------------------------------------------------------------------

  Widget _buildDatesSection() {
    final activePreset = _activePacingPreset();

    return _buildSection(
      number: 2,
      title: 'Dates & Duration',
      trailingIcon: Icons.calendar_month_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildDateField(
                        label: 'Departure',
                        date: startDate,
                        onTap: () => selectDate(isStartDate: true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (startDate != null && endDate != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.arrow_forward,
                              size: 16,
                              color: _blue,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${endDate!.difference(startDate!).inDays} Days',
                              style: const TextStyle(
                                fontFamily: 'Manrope',
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _blue,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildDateField(
                        label: 'Return',
                        date: endDate,
                        onTap: () => selectDate(isStartDate: false),
                      ),
                    ),
                  ],
                ),
                if (startDate != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _dayOfWeek(startDate!),
                    style: const TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 11,
                      color: _textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          const Text(
            'PACING PRESETS',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: _textMuted,
            ),
          ),

          const SizedBox(height: 10),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['Flexible', 'Weekend', '1 Week', '2 Weeks'].map((
                preset,
                ) {
              final selected = activePreset == preset ||
                  (preset == 'Flexible' &&
                      startDate == null &&
                      endDate == null);

              return ChoiceChip(
                label: Text(
                  preset,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 12,
                    fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected ? Colors.white : _midnight,
                  ),
                ),
                selected: selected,
                showCheckmark: false,
                backgroundColor: const Color(0xFFF1F5F9),
                selectedColor: _midnight,
                side: BorderSide(
                  color: selected ? _midnight : _borderStrong,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                onSelected: isGenerating
                    ? null
                    : (_) => _applyPacingPreset(preset),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Travelers (type cards)
  // ---------------------------------------------------------------------

  Widget _buildTravelersSection() {
    return _buildSection(
      number: 3,
      title: 'Travelers',
      trailingIcon: Icons.people_alt_outlined,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 500 ? 2 : 1;

          final cards = [
            _travelerCard(
              icon: Icons.person_outline,
              title: 'Solo',
              subtitle: 'Independent pace',
              rangeLabel: '1',
              isSelected: travelers == 1,
              onTap: () => setState(() => travelers = 1),
            ),
            _travelerCard(
              icon: Icons.favorite_border,
              title: 'Couple',
              subtitle: 'Curated for two',
              rangeLabel: '2',
              isSelected: travelers == 2,
              onTap: () => setState(() => travelers = 2),
            ),
            _travelerCard(
              icon: Icons.escalator_warning_outlined,
              title: 'Family',
              subtitle: 'Kid-friendly rhythm',
              rangeLabel: '3–5',
              isSelected: travelers >= 3 && travelers <= 5,
              onTap: () => setState(() => travelers = 4),
            ),
            _travelerCard(
              icon: Icons.groups_outlined,
              title: 'Friends',
              subtitle: 'Shared memories',
              rangeLabel: '6+',
              isSelected: travelers >= 6,
              onTap: () => setState(() => travelers = 6),
            ),
          ];

          return GridView.count(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: columns == 2 ? 1.7 : 3.0,
            children: cards,
          );
        },
      ),
    );
  }

  Widget _travelerCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String rangeLabel,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isSelected ? _midnight : _white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: isGenerating ? null : onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? _midnight : _border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: isSelected ? Colors.white : _midnight,
                  ),
                  const Spacer(),
                  Text(
                    rangeLabel,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.7)
                          : _textMuted,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : _textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 11,
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.75)
                      : _textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Budget tier + highlights priority (interests)
  // ---------------------------------------------------------------------

  Widget _buildBudgetSection() {
    return _buildSection(
      number: 4,
      title: 'Budget Tier',
      trailingWidget: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          budgetEstimateLabel(),
          style: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: _textMuted,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _budgetTierChip('Backpacker', r'($)')),
              const SizedBox(width: 8),
              Expanded(child: _budgetTierChip('Comfort', r'($$)')),
              const SizedBox(width: 8),
              Expanded(child: _budgetTierChip('Luxury', r'($$$)')),
            ],
          ),

          const SizedBox(height: 20),

          Row(
            children: [
              const Text(
                'HIGHLIGHTS PRIORITY',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: _textMuted,
                ),
              ),
              const Spacer(),
              Text(
                'Select as many as you like',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _blue,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: interests.map((interest) {
              final selected = selectedInterests.contains(interest);

              return FilterChip(
                label: Text(
                  interest,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 12,
                    fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected ? Colors.white : _midnight,
                  ),
                ),
                selected: selected,
                showCheckmark: false,
                backgroundColor: const Color(0xFFF1F5F9),
                selectedColor: _blue,
                side: BorderSide(
                  color: selected ? _blue : _borderStrong,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                onSelected: isGenerating
                    ? null
                    : (value) {
                  setState(() {
                    if (value) {
                      selectedInterests.add(interest);
                    } else {
                      selectedInterests.remove(interest);
                    }
                  });
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// Rough per-tier estimate for display only — a lightweight visual
  /// echo of the mockup's "Est. $2,500" badge. Not used for trip
  /// generation; the backend/AI still computes the real estimate.
  String budgetEstimateLabel() {
    final int days = (startDate != null && endDate != null)
        ? endDate!.difference(startDate!).inDays.clamp(1, 60)
        : 5;

    final int perDayPerPerson = switch (budget) {
      'Budget' => 60,
      'Luxury' => 400,
      _ => 150,
    };

    final int estimate = perDayPerPerson * days * travelers;

    return 'Est. \$$estimate';
  }

  Widget _budgetTierChip(String label, String priceHint) {
    final String mapped = switch (label) {
      'Backpacker' => 'Budget',
      'Luxury' => 'Luxury',
      _ => 'Moderate',
    };

    final selected = budget == mapped;

    return InkWell(
      onTap: isGenerating
          ? null
          : () {
        setState(() {
          budget = mapped;
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? _white : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? _midnight : Colors.transparent,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? _midnight : _textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              priceHint,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 10,
                color: selected ? _midnight : _textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Travel style (kept from the original — pacing beyond dates)
  // ---------------------------------------------------------------------

  Widget _buildTravelStyleSection() {
    return _buildSection(
      number: 5,
      title: 'What is your travel style?',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _buildChoiceChip('Relaxed', travelStyle),
          _buildChoiceChip('Balanced', travelStyle),
          _buildChoiceChip('Packed', travelStyle),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Generate button
  // ---------------------------------------------------------------------

  Widget _buildGenerateButton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton.icon(
            onPressed: isGenerating ? null : generateTrip,
            style: FilledButton.styleFrom(
              backgroundColor: _midnightDark,
              foregroundColor: Colors.white,
              disabledBackgroundColor:
              _midnightDark.withValues(alpha: 0.55),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            icon: isGenerating
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
                : const Icon(Icons.auto_awesome, size: 19),
            label: Text(
              isGenerating
                  ? 'Building your itinerary...'
                  : 'Create My Trip with AI',
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.verified_outlined, size: 14, color: _textMuted),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Tripora AI will build your route and daily plan based on what you selected above.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 11,
                    color: _textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Shared building blocks
  // ---------------------------------------------------------------------

  Widget _buildSection({
    required int number,
    required String title,
    required Widget child,
    IconData? trailingIcon,
    Widget? trailingWidget,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x081E1B4B),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: _midnight,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$number',
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Noto Serif',
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    color: _midnight,
                  ),
                ),
              ),
              if (trailingWidget != null)
                trailingWidget
              else if (trailingIcon != null)
                Icon(trailingIcon, size: 20, color: _textMuted),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hintText,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(
        fontFamily: 'Manrope',
        fontSize: 14,
        color: _textMuted,
      ),
      prefixIcon: Icon(icon, color: _textMuted, size: 21),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 15,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _midnight, width: 1.3),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _border),
      ),
    );
  }

  Widget _buildDateField({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    final selected = date != null;

    return InkWell(
      onTap: isGenerating ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: _textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _displayDate(date),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: selected ? _textPrimary : _textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChoiceChip(String label, String selectedValue) {
    final selected = selectedValue == label;

    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          color: selected ? Colors.white : _midnight,
        ),
      ),
      selected: selected,
      showCheckmark: false,
      backgroundColor: const Color(0xFFF1F5F9),
      selectedColor: _midnight,
      side: BorderSide(color: selected ? _midnight : _borderStrong),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      onSelected: isGenerating
          ? null
          : (_) {
        setState(() {
          travelStyle = label;
        });
      },
    );
  }
}

class _GenerationDialog extends StatelessWidget {
  const _GenerationDialog();

  static const Color _midnight = Color(0xFF1E1B4B);
  static const Color _blue = Color(0xFF3B82F6);
  static const Color _white = Colors.white;
  static const Color _textMuted = Color(0xFF64748B);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 390),
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x331E1B4B),
            blurRadius: 30,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const SizedBox(
              width: 25,
              height: 25,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: _blue,
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Creating your itinerary',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Noto Serif',
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: _midnight,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'Tripora is shaping your route, activities, and daily plan.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 12,
              height: 1.45,
              color: _textMuted,
            ),
          ),
          const SizedBox(height: 22),
          const ShimmerLoader(
            width: double.infinity,
            height: 12,
            borderRadius: BorderRadius.all(Radius.circular(6)),
            margin: EdgeInsets.only(bottom: 9),
          ),
          const ShimmerLoader(
            width: double.infinity,
            height: 12,
            borderRadius: BorderRadius.all(Radius.circular(6)),
            margin: EdgeInsets.only(bottom: 18),
          ),
          const ShimmerLoader(
            width: double.infinity,
            height: 72,
            borderRadius: BorderRadius.all(Radius.circular(10)),
            margin: EdgeInsets.only(bottom: 9),
          ),
          const ShimmerLoader(
            width: double.infinity,
            height: 72,
            borderRadius: BorderRadius.all(Radius.circular(10)),
            margin: EdgeInsets.only(bottom: 9),
          ),
          const ShimmerLoader(
            width: double.infinity,
            height: 72,
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
        ],
      ),
    );
  }
}