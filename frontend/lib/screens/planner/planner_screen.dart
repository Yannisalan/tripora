import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../models/trip_model.dart';
import '../../services/trip_service.dart';
import '../../widgets/gradient_button.dart';
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

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();

    destinationController = TextEditingController(
      text: widget.initialDestination ?? '',
    );
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    destinationController.dispose();
    super.dispose();
  }

  // ============================================================
  // DATE PICKER
  // ============================================================

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

    final DateTime lastDate = DateTime(today.year + 2, today.month, today.day);

    if (initialDate.isAfter(lastDate)) {
      initialDate = lastDate;
    }

    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: today,
      lastDate: lastDate,
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

        // If the new start date is after the
        // current end date, clear the end date.
        if (endDate != null && endDate!.isBefore(selectedDate)) {
          endDate = null;
        }
      });

      return;
    }

    if (startDate != null && selectedDate.isBefore(startDate!)) {
      _showMessage('End date cannot be before the start date.');

      return;
    }

    setState(() {
      endDate = selectedDate;
    });
  }

  // ============================================================
  // DATE FORMATTING
  // ============================================================

  String formatDate(DateTime? date) {
    if (date == null) {
      return 'Select date';
    }

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  // ============================================================
  // SHOW MESSAGE
  // ============================================================

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }

    final statusColors = Theme.of(context).extension<AppStatusColors>();

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError
              ? statusColors?.error ?? Theme.of(context).colorScheme.error
              : statusColors?.info ?? Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ============================================================
  // GENERATE TRIP
  // ============================================================

  Future<void> generateTrip() async {
    if (isGenerating) {
      return;
    }

    // ----------------------------------------------------------
    // DESTINATION VALIDATION
    // ----------------------------------------------------------

    final String destination = destinationController.text.trim();

    if (destination.isEmpty) {
      _showMessage('Please enter a destination.', isError: true);

      return;
    }

    // ----------------------------------------------------------
    // DATE VALIDATION
    // ----------------------------------------------------------

    if (startDate == null || endDate == null) {
      _showMessage('Please select your travel dates.', isError: true);

      return;
    }

    if (endDate!.isBefore(startDate!)) {
      _showMessage('End date cannot be before the start date.', isError: true);

      return;
    }

    // ----------------------------------------------------------
    // TRAVELER VALIDATION
    // ----------------------------------------------------------

    if (travelers < 1) {
      _showMessage('There must be at least one traveler.', isError: true);

      return;
    }

    // ==========================================================
    // CREATE TRIP MODEL
    // ==========================================================

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

    // ==========================================================
    // SHOW LOADING DIALOG
    // ==========================================================
    // showDialog defaults to useRootNavigator: true, so it is
    // pushed onto the ROOT navigator. If this screen ever lives
    // inside a nested Navigator (e.g. a bottom-nav tab), we must
    // close it via the root navigator too — otherwise
    // Navigator.of(context).pop() can pop the wrong stack (e.g.
    // pop this screen instead of the dialog).

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) {
        return const PopScope(
          canPop: false,
          child: Center(child: CircularProgressIndicator()),
        );
      },
    );

    try {
      // ========================================================
      // CALL BACKEND
      // ========================================================

      final Map<String, dynamic> response = await tripService.generateTrip(
        trip,
      );

      // ========================================================
      // CLOSE LOADING DIALOG
      // ========================================================

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (!mounted) {
        return;
      }

      // ========================================================
      // DEBUG RESPONSE
      // ========================================================

      if (kDebugMode) {
        debugPrint('====================================');
        debugPrint('GENERATE TRIP RESPONSE');
        debugPrint(response.toString());
        debugPrint('====================================');
      }

      // ========================================================
      // CHECK SUCCESS
      // ========================================================

      if (response['success'] != true) {
        _showMessage(
          response['message']?.toString() ?? 'Trip generation failed.',
          isError: true,
        );

        return;
      }

      // ========================================================
      // GET SAVED TRIP
      // ========================================================

      final dynamic tripData = response['trip'];

      if (tripData is! Map) {
        _showMessage(
          'Trip was generated, but no trip data was returned.',
          isError: true,
        );

        return;
      }

      final Map<String, dynamic> tripMap = Map<String, dynamic>.from(tripData);

      // ========================================================
      // DEBUG TRIP
      // ========================================================

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

      // ========================================================
      // OPEN ITINERARY
      // ========================================================

      if (!mounted) {
        return;
      }

      // Success feedback: light haptic tap on the generate action.
      HapticFeedback.mediumImpact();

      await Navigator.pushNamed(context, '/itinerary', arguments: tripMap);
    } catch (error) {
      // ========================================================
      // CLOSE LOADING DIALOG
      // ========================================================

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (!mounted) {
        return;
      }

      // ========================================================
      // SHOW ERROR
      // ========================================================

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
        title: Text(
          'Plan Your Trip',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: context.triporaColors.textPrimary,
          ),
        ),
      ),

      // ========================================================
      // BODY
      // ========================================================
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 850),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 40,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ==================================================
                      // HEADER
                      // ==================================================
                      Text(
                        'Create your perfect trip',
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          color: context.triporaColors.textPrimary,
                        ),
                      ),

                      const SizedBox(height: 12),

                      Text(
                        'Tell Tripora what you want, and we will help you build the perfect itinerary.',
                        style: TextStyle(
                          fontSize: 17,
                          height: 1.5,
                          color: context.triporaColors.textSecondary,
                        ),
                      ),

                      const SizedBox(height: 40),

                      // ==================================================
                      // DESTINATION
                      // ==================================================
                      _buildSectionTitle(context, 'Where do you want to go?'),

                      const SizedBox(height: 12),

                      TextField(
                        controller: destinationController,
                        enabled: !isGenerating,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          hintText: 'e.g. Paris, France',
                          prefixIcon: const Icon(Icons.location_on_outlined),
                          filled: true,
                          fillColor: context.triporaColors.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 18,
                          ),
                        ),
                      ),

                      const SizedBox(height: 35),

                      // ==================================================
                      // DATES
                      // ==================================================
                      _buildSectionTitle(context, 'When are you travelling?'),

                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: _buildDateField(
                              label: 'Start date',
                              date: startDate,
                              onTap: () {
                                selectDate(isStartDate: true);
                              },
                            ),
                          ),

                          const SizedBox(width: 16),

                          Expanded(
                            child: _buildDateField(
                              label: 'End date',
                              date: endDate,
                              onTap: () {
                                selectDate(isStartDate: false);
                              },
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 35),

                      // ==================================================
                      // TRAVELERS
                      // ==================================================
                      _buildSectionTitle(context, 'Who is travelling?'),

                      const SizedBox(height: 12),

                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: context.triporaColors.surface,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.people_outline,
                              color: Theme.of(context).colorScheme.primary,
                            ),

                            const SizedBox(width: 15),

                            const Expanded(
                              child: Text(
                                'Travelers',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),

                            IconButton(
                              tooltip: 'Remove traveler',
                              onPressed: (!isGenerating && travelers > 1)
                                  ? () {
                                      setState(() {
                                        travelers--;
                                      });
                                    }
                                  : null,
                              icon: const Icon(Icons.remove_circle_outline),
                            ),

                            SizedBox(
                              width: 30,
                              child: Text(
                                '$travelers',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),

                            IconButton(
                              tooltip: 'Add traveler',
                              onPressed: isGenerating
                                  ? null
                                  : () {
                                      setState(() {
                                        travelers++;
                                      });
                                    },
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 35),

                      // ==================================================
                      // BUDGET
                      // ==================================================
                      _buildSectionTitle(context, 'What is your budget?'),

                      const SizedBox(height: 12),

                      DropdownButtonFormField<String>(
                        initialValue: budget,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(
                            Icons.account_balance_wallet_outlined,
                          ),
                          filled: true,
                          fillColor: context.triporaColors.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'Budget',
                            child: Text('Budget'),
                          ),
                          DropdownMenuItem(
                            value: 'Moderate',
                            child: Text('Moderate'),
                          ),
                          DropdownMenuItem(
                            value: 'Luxury',
                            child: Text('Luxury'),
                          ),
                        ],
                        onChanged: isGenerating
                            ? null
                            : (value) {
                                if (value == null) {
                                  return;
                                }

                                setState(() {
                                  budget = value;
                                });
                              },
                      ),

                      const SizedBox(height: 35),

                      // ==================================================
                      // TRAVEL STYLE
                      // ==================================================
                      _buildSectionTitle(context, 'What is your travel style?'),

                      const SizedBox(height: 12),

                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _buildChoiceChip('Relaxed', travelStyle),
                          _buildChoiceChip('Balanced', travelStyle),
                          _buildChoiceChip('Packed', travelStyle),
                        ],
                      ),

                      const SizedBox(height: 35),

                      // ==================================================
                      // INTERESTS
                      // ==================================================
                      _buildSectionTitle(context, 'What are you interested in?'),

                      const SizedBox(height: 12),

                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: interests.map((interest) {
                          final bool selected = selectedInterests.contains(
                            interest,
                          );

                          return FilterChip(
                            label: Text(interest),
                            selected: selected,
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

                      const SizedBox(height: 50),

                      // ==================================================
                      // GENERATE BUTTON
                      // ==================================================
                      SizedBox(
                        width: double.infinity,
                        height: 58,
                        child: GradientButton(
                          onPressed: isGenerating ? null : generateTrip,
                          height: 58,
                          padding: const EdgeInsets.symmetric(
                            vertical: 20,
                            horizontal: 24,
                          ),
                          child: isGenerating
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.auto_awesome,
                                      size: 20,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Generate My Trip',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
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

          // ==================================================
          // GENERATION LOADING OVERLAY
          // ==================================================
          if (isGenerating)
            Positioned.fill(
              child: ColoredBox(
                color: const Color(0x99000000),
                child: Center(
                  child: Card(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Text(
                              'Creating your itinerary...',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 24),
                            ShimmerLoader(
                              width: 280,
                              height: 16,
                              borderRadius: BorderRadius.circular(4),
                              margin: const EdgeInsets.only(bottom: 12),
                            ),
                            ShimmerLoader(
                              width: 260,
                              height: 16,
                              borderRadius: BorderRadius.circular(4),
                              margin: const EdgeInsets.only(bottom: 20),
                            ),
                            const SizedBox(height: 16),
                            ShimmerLoader(
                              width: 300,
                              height: 80,
                              borderRadius: BorderRadius.circular(8),
                              margin: const EdgeInsets.only(bottom: 12),
                            ),
                            ShimmerLoader(
                              width: 300,
                              height: 80,
                              borderRadius: BorderRadius.circular(8),
                              margin: const EdgeInsets.only(bottom: 12),
                            ),
                            ShimmerLoader(
                              width: 300,
                              height: 80,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ],
                        ),
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

  // ============================================================
  // SECTION TITLE
  // ============================================================

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: context.triporaColors.textPrimary,
      ),
    );
  }

  // ============================================================
  // DATE FIELD
  // ============================================================

  Widget _buildDateField({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: isGenerating ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        decoration: BoxDecoration(
          color: context.triporaColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_month_outlined, color: Theme.of(context).colorScheme.primary),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.triporaColors.textSecondary,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    formatDate(date),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: context.triporaColors.textPrimary,
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

  // ============================================================
  // TRAVEL STYLE CHIP
  // ============================================================

  Widget _buildChoiceChip(String label, String selectedValue) {
    return ChoiceChip(
      label: Text(label),
      selected: selectedValue == label,
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
