import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/preferences/app_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../core/l10n/app_localizations.dart';
import '../../data/destinations.dart';
import '../../models/trip_model.dart';
import '../../services/trip_service.dart';
import '../../widgets/shimmer_loader.dart';

class PlannerScreen extends StatefulWidget {
  final String? initialDestination;

  const PlannerScreen({
    super.key,
    this.initialDestination,
  });

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> {
  late final TextEditingController destinationController;

  final TripService tripService = TripService();

  DateTime? startDate;
  DateTime? endDate;

  int travelers = 1;

  // Internal values. These are translated only when displayed.
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

  // ============================================================
  // LOCALIZED VALUES
  // ============================================================

  String _localizedInterest(
    BuildContext context,
    String value,
  ) {
    switch (value) {
      case 'Culture':
        return context.tr('planner.culture');
      case 'Food':
        return context.tr('planner.food');
      case 'Nature':
        return context.tr('planner.nature');
      case 'Adventure':
        return context.tr('planner.adventure');
      case 'Shopping':
        return context.tr('planner.shopping');
      case 'Nightlife':
        return context.tr('planner.nightlife');
      case 'Relaxation':
        return context.tr('planner.relaxation');
      default:
        return value;
    }
  }

  String _localizedBudget(
    BuildContext context,
    String value,
  ) {
    switch (value) {
      case 'Moderate':
        return context.tr('planner.moderate');
      case 'High':
        return context.tr('planner.high');
      case 'Luxury':
        return context.tr('planner.luxury');
      case 'Budget':
        return context.tr('planner.budget');
      default:
        return value;
    }
  }

  String _localizedTravelStyle(
    BuildContext context,
    String value,
  ) {
    switch (value) {
      case 'Relaxed':
        return context.tr('planner.relaxed');
      case 'Balanced':
        return context.tr('planner.balanced');
      case 'Adventure':
        return context.tr('planner.adventure');
      case 'Luxury':
        return context.tr('planner.luxury');
      case 'Packed':
        return context.tr('planner.packed');
      default:
        return value;
    }
  }

  String _localizedTravelerType(
    BuildContext context,
    String value,
  ) {
    switch (value) {
      case 'Solo':
        return context.tr('planner.solo');
      case 'Couple':
        return context.tr('planner.couple');
      case 'Family':
        return context.tr('planner.family');
      case 'Friends':
        return context.tr('planner.friends');
      default:
        return value;
    }
  }

  String _localizedPacingPreset(
    BuildContext context,
    String value,
  ) {
    switch (value) {
      case 'Flexible':
        return context.tr('planner.flexible');
      case 'Weekend':
        return context.tr('planner.weekend');
      case '1 Week':
        return context.tr('planner.oneWeek');
      case '2 Weeks':
        return context.tr('planner.twoWeeks');
      default:
        return value;
    }
  }

  // ============================================================
  // PROGRESS
  // ============================================================

  double get _completionProgress {
    int filled = 0;
    const int total = 4;

    if (destinationController.text.trim().isNotEmpty) {
      filled++;
    }

    if (startDate != null && endDate != null) {
      filled++;
    }

    if (travelers >= 1) {
      filled++;
    }

    if (budget.isNotEmpty) {
      filled++;
    }

    return filled / total;
  }

  // ============================================================
  // RESET
  // ============================================================

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

  // ============================================================
  // DATE HANDLING
  // ============================================================

  Future<void> selectDate({
    required bool isStartDate,
  }) async {
    final DateTime now = DateTime.now();

    final DateTime today = DateTime(
      now.year,
      now.month,
      now.day,
    );

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
                  primary: Theme.of(context).colorScheme.primary,
                  surface: Theme.of(context).colorScheme.surface,
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

        if (endDate != null &&
            endDate!.isBefore(selectedDate)) {
          endDate = null;
        }
      });

      return;
    }

    if (startDate != null &&
        selectedDate.isBefore(startDate!)) {
      _showMessage(
        context.tr('planner.endDateBeforeStart'),
        isError: true,
      );
      return;
    }

    setState(() {
      endDate = selectedDate;
    });
  }

  // ============================================================
  // PACING
  // ============================================================

  void _applyPacingPreset(String preset) {
    final DateTime base = startDate ?? DateTime.now();

    final DateTime start = DateTime(
      base.year,
      base.month,
      base.day,
    );

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
        setState(() {
          startDate = null;
          endDate = null;
        });
        return;
    }

    setState(() {
      startDate = start;
      endDate = start.add(
        Duration(days: days - 1),
      );
    });
  }

  String? _activePacingPreset() {
    if (startDate == null || endDate == null) {
      return null;
    }

    final int days =
        endDate!.difference(startDate!).inDays + 1;

    if (days == 2) {
      return 'Weekend';
    }

    if (days == 7) {
      return '1 Week';
    }

    if (days == 14) {
      return '2 Weeks';
    }

    return null;
  }

  // ============================================================
  // DATE DISPLAY
  // ============================================================

  String _displayDate(
    BuildContext context,
    DateTime? date,
  ) {
    if (date == null) {
      return context.tr('planner.selectDate');
    }

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
      'date.short.${months[date.month - 1]}',
    );

    return '$month ${date.day}, ${date.year}';
  }

  String _dayOfWeek(
    BuildContext context,
    DateTime date,
  ) {
    const days = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ];

    return context.tr(
      'date.${days[date.weekday - 1]}',
    );
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _showMessage(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) {
      return;
    }

    final statusColors =
        Theme.of(context).extension<AppStatusColors>();

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
              ? statusColors?.error ??
                  Theme.of(context).colorScheme.error
              : statusColors?.info ??
                  context.appStatus.info,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
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

    final String destination =
        destinationController.text.trim();

    if (destination.isEmpty) {
      _showMessage(
        context.tr('planner.enterDestination'),
        isError: true,
      );
      return;
    }

    if (startDate == null || endDate == null) {
      _showMessage(
        context.tr('planner.selectDates'),
        isError: true,
      );
      return;
    }

    if (endDate!.isBefore(startDate!)) {
      _showMessage(
        context.tr('planner.endDateBeforeStart'),
        isError: true,
      );
      return;
    }

    if (travelers < 1) {
      _showMessage(
        context.tr('planner.atLeastOneTraveler'),
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
              context.tr('planner.generationFailed'),
          isError: true,
        );
        return;
      }

      final dynamic tripData = response['trip'];

      if (tripData is! Map) {
        _showMessage(
          context.tr('planner.noTripData'),
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
        debugPrint(
          'DESTINATION: ${tripMap['destination']}',
        );
        debugPrint(
          'START DATE: ${tripMap['startDate']}',
        );
        debugPrint(
          'END DATE: ${tripMap['endDate']}',
        );
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
            ? context.tr('planner.generationError')
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
    final colors = context.triporaColors;

    return ListenableBuilder(
      listenable: AppPreferences.instance,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: colors.backgroundColor,
          body: SafeArea(
            child: Column(
              children: [
                _buildTopBar(context),
                _buildProgressBar(),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 920,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            16,
                            20,
                            16,
                            48,
                          ),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.tr(
                                  'planner.essentials',
                                ),
                                style: TextStyle(
                                  fontFamily: 'Noto Serif',
                                  fontSize: 28,
                                  fontWeight: FontWeight.w600,
                                  color: context.headingColor,
                                ),
                              ),

                              const SizedBox(height: 20),

                              _buildDestinationSection(
                                context,
                              ),

                              const SizedBox(height: 20),

                              _buildDatesSection(
                                context,
                              ),

                              const SizedBox(height: 20),

                              _buildTravelersSection(
                                context,
                              ),

                              const SizedBox(height: 20),

                              _buildBudgetSection(
                                context,
                              ),

                              const SizedBox(height: 20),

                              _buildTravelStyleSection(
                                context,
                              ),

                              const SizedBox(height: 40),

                              _buildGenerateButton(
                                context,
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
          ),
        );
      },
    );
  }

  // ============================================================
  // TOP BAR
  // ============================================================

  Widget _buildTopBar(
    BuildContext context,
  ) {
    final colors = context.triporaColors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        12,
        8,
        12,
        8,
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: isGenerating
                ? null
                : () => Navigator.maybePop(context),
            icon: Icon(
              Icons.close,
              size: 20,
              color: colors.textPrimary,
            ),
            label: Text(
              context.tr('common.cancel'),
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ),

          const Spacer(),

          Text(
            '${(_completionProgress * 100).round()}% '
            '${context.tr('planner.complete').toUpperCase()}',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: context.appStatus.info,
            ),
          ),

          const Spacer(),

          TextButton(
            onPressed: isGenerating
                ? null
                : _resetForm,
            child: Text(
              context.tr('planner.reset'),
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    final colors = context.triporaColors;
    final scheme = Theme.of(context).colorScheme;

    return ClipRRect(
      child: LinearProgressIndicator(
        value: _completionProgress,
        minHeight: 3,
        backgroundColor: colors.border,
        color: scheme.primary,
      ),
    );
  }

  // ============================================================
  // DESTINATION
  // ============================================================

  Widget _buildDestinationSection(
    BuildContext context,
  ) {
    final colors = context.triporaColors;
    final scheme = Theme.of(context).colorScheme;

    final matchedDestination =
        _matchDestination(
      destinationController.text,
    );

    return _buildSection(
      context: context,
      number: 1,
      title: context.tr(
        'planner.destinationQuestion',
      ),
      trailingIcon: Icons.public,
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          TextField(
            controller: destinationController,
            enabled: !isGenerating,
            textInputAction: TextInputAction.done,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 14,
              color: colors.textPrimary,
            ),
            onChanged: (_) => setState(() {}),
            decoration: _inputDecoration(
              hintText: context.tr(
                'planner.destinationHint',
              ),
              icon: Icons.location_on_outlined,
              colors: colors,
              scheme: scheme,
              suffixIcon:
                  destinationController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(
                            Icons.close,
                            size: 18,
                          ),
                          onPressed: isGenerating
                              ? null
                              : () {
                                  setState(() {
                                    destinationController
                                        .clear();
                                  });
                                },
                        ),
            ),
          ),

          const SizedBox(height: 16),

          Text(
            context
                .tr('planner.trendingCurations')
                .toUpperCase(),
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: colors.textMuted,
            ),
          ),

          const SizedBox(height: 10),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                _trendingCities.map((city) {
              final destination =
                  destinations.firstWhere(
                (d) => d.city == city,
                orElse: () =>
                    destinations.first,
              );

              final selected =
                  destinationController.text
                          .trim()
                          .toLowerCase() ==
                      destination.fullName
                          .toLowerCase();

              return ChoiceChip(
                label: Text(
                  destination.city,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 12,
                    fontWeight: selected
                        ? FontWeight.w700
                        : FontWeight.w600,
                    color: selected
                        ? scheme.onPrimary
                        : context.headingColor,
                  ),
                ),
                selected: selected,
                showCheckmark: false,
                backgroundColor:
                    colors.surfaceSecondary,
                selectedColor: scheme.primary,
                side: BorderSide(
                  color: selected
                      ? scheme.primary
                      : colors.borderStrong,
                ),
                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(999),
                ),
                onSelected: isGenerating
                    ? null
                    : (_) {
                        setState(() {
                          destinationController
                                  .text =
                              destination.fullName;

                          destinationController
                                  .selection =
                              TextSelection
                                  .collapsed(
                            offset:
                                destinationController
                                    .text
                                    .length,
                          );
                        });
                      },
              );
            }).toList(),
          ),

          if (matchedDestination != null) ...[
            const SizedBox(height: 16),
            _buildDestinationCard(
              context,
              matchedDestination,
            ),
          ],
        ],
      ),
    );
  }

  dynamic _matchDestination(
    String query,
  ) {
    final trimmed =
        query.trim().toLowerCase();

    if (trimmed.isEmpty) {
      return null;
    }

    for (final destination in destinations) {
      if (destination.fullName
              .toLowerCase() ==
          trimmed ||
          destination.city
                  .toLowerCase() ==
              trimmed) {
        return destination;
      }
    }

    return null;
  }

  Widget _buildDestinationCard(
    BuildContext context,
    dynamic destination,
  ) {
    final colors = context.triporaColors;

    return ClipRRect(
      borderRadius:
          BorderRadius.circular(16),
      child: SizedBox(
        height: 140,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              destination.imageUrl,
              fit: BoxFit.cover,
errorBuilder: (_, _, _) =>
                    Container(
                  color: colors.surfaceSecondary,
                  child: Icon(
                    Icons
                        .image_not_supported_outlined,
                    color: colors.textMuted,
                  ),
                ),
            ),

            DecoratedBox(
              decoration:
                  BoxDecoration(
                gradient:
                    LinearGradient(
                  begin:
                      Alignment.topCenter,
                  end:
                      Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Color(0xFF1E1B4B).withValues(
                      alpha: 0.78,
                    ),
                  ],
                ),
              ),
            ),

            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    '${destination.city} '
                    '${destination.country}',
                    style:
                        const TextStyle(
                      fontFamily:
                          'Noto Serif',
                      color:
                          Colors.white,
                      fontSize: 18,
                      fontWeight:
                          FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 3),

                  Text(
                    destination.description,
                    maxLines: 1,
                    overflow:
                        TextOverflow.ellipsis,
                    style:
                        const TextStyle(
                      color:
                          Color(0xFFE2E8F0),
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

  // ============================================================
  // DATES
  // ============================================================

  Widget _buildDatesSection(
    BuildContext context,
  ) {
    final colors = context.triporaColors;
    final scheme = Theme.of(context).colorScheme;

    final activePreset =
        _activePacingPreset();

    return _buildSection(
      context: context,
      number: 2,
      title: context.tr(
        'planner.datesDuration',
      ),
      trailingIcon:
          Icons.calendar_month_outlined,
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Container(
            padding:
                const EdgeInsets.all(14),
            decoration:
                BoxDecoration(
              color:
                  colors.surfaceSecondary,
              borderRadius:
                  BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child:
                          _buildDateField(
                        context: context,
                        label: context.tr(
                          'planner.departure',
                        ),
                        date: startDate,
                        onTap: () =>
                            selectDate(
                          isStartDate:
                              true,
                        ),
                      ),
                    ),

                    const SizedBox(
                      width: 10,
                    ),

                    if (startDate !=
                            null &&
                        endDate !=
                            null)
                      Padding(
                        padding:
                            const EdgeInsets
                                .only(
                          top: 20,
                        ),
                        child:
                            Column(
                          children: [
                            Icon(
                              Icons
                                  .arrow_forward,
                              size: 16,
                              color:
                                  colors.appStatus.info,
                            ),
                            const SizedBox(
                              height: 2,
                            ),
                            Text(
                              '${endDate!.difference(startDate!).inDays + 1} '
                              '${context.tr('planner.days')}',
                              style:
                                  TextStyle(
                                fontFamily:
                                    'Manrope',
                                fontSize:
                                    10,
                                fontWeight:
                                    FontWeight
                                        .w700,
                                color:
                                    colors.appStatus.info,
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(
                      width: 10,
                    ),

                    Expanded(
                      child:
                          _buildDateField(
                        context: context,
                        label: context.tr(
                          'planner.return',
                        ),
                        date: endDate,
                        onTap: () =>
                            selectDate(
                          isStartDate:
                              false,
                        ),
                      ),
                    ),
                  ],
                ),

                if (startDate != null) ...[
                  const SizedBox(height: 10),

                  Text(
                    _dayOfWeek(
                      context,
                      startDate!,
                    ),
                    style:
                        TextStyle(
                      fontFamily:
                          'Manrope',
                      fontSize: 11,
                      color:
                          colors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          Text(
            context
                .tr('planner.pacingPresets')
                .toUpperCase(),
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: colors.textMuted,
            ),
          ),

          const SizedBox(height: 10),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              'Flexible',
              'Weekend',
              '1 Week',
              '2 Weeks',
            ].map((preset) {
              final selected =
                  activePreset == preset ||
                  (preset == 'Flexible' &&
                      startDate == null &&
                      endDate == null);

              return ChoiceChip(
                label: Text(
                  _localizedPacingPreset(
                    context,
                    preset,
                  ),
                  style: TextStyle(
                    fontFamily:
                        'Manrope',
                    fontSize: 12,
                    fontWeight: selected
                        ? FontWeight.w700
                        : FontWeight.w600,
                    color: selected
                        ? scheme.onPrimary
                        : context.headingColor,
                  ),
                ),
                selected: selected,
                showCheckmark: false,
                backgroundColor:
                    colors.surfaceSecondary,
                selectedColor:
                    scheme.primary,
                side: BorderSide(
                  color: selected
                      ? scheme.primary
                      : colors.borderStrong,
                ),
                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(
                    999,
                  ),
                ),
                onSelected: isGenerating
                    ? null
                    : (_) =>
                        _applyPacingPreset(
                          preset,
                        ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TRAVELERS
  // ============================================================

  Widget _buildTravelersSection(
    BuildContext context,
  ) {
    return _buildSection(
      context: context,
      number: 3,
      title: context.tr(
        'planner.travelers',
      ),
      trailingIcon:
          Icons.people_alt_outlined,
      child: LayoutBuilder(
        builder: (
          context,
          constraints,
        ) {
          final columns =
              constraints.maxWidth >= 500
                  ? 2
                  : 1;

          final cards = [
            _travelerCard(
              context: context,
              icon: Icons.person_outline,
              type: 'Solo',
              subtitle: context.tr(
                'planner.independentPace',
              ),
              rangeLabel: context.tr(
                'planner.travelers.rangeOne',
              ),
              isSelected:
                  travelers == 1,
              onTap: () => setState(
                () => travelers = 1,
              ),
            ),

            _travelerCard(
              context: context,
              icon: Icons.favorite_border,
              type: 'Couple',
              subtitle: context.tr(
                'planner.curatedForTwo',
              ),
              rangeLabel: context.tr(
                'planner.travelers.rangeTwo',
              ),
              isSelected:
                  travelers == 2,
              onTap: () => setState(
                () => travelers = 2,
              ),
            ),

            _travelerCard(
              context: context,
              icon:
                  Icons.escalator_warning_outlined,
              type: 'Family',
              subtitle: context.tr(
                'planner.kidFriendlyRhythm',
              ),
              rangeLabel: context.tr(
                'planner.travelers.rangeFamily',
              ),
              isSelected:
                  travelers >= 3 &&
                  travelers <= 5,
              onTap: () => setState(
                () => travelers = 4,
              ),
            ),

            _travelerCard(
              context: context,
              icon: Icons.groups_outlined,
              type: 'Friends',
              subtitle: context.tr(
                'planner.sharedMemories',
              ),
              rangeLabel: context.tr(
                'planner.travelers.rangeFriends',
              ),
              isSelected:
                  travelers >= 6,
              onTap: () => setState(
                () => travelers = 6,
              ),
            ),
          ];

          return GridView.count(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            shrinkWrap: true,
            physics:
                const NeverScrollableScrollPhysics(),
            childAspectRatio:
                columns == 2
                    ? 1.7
                    : 3.0,
            children: cards,
          );
        },
      ),
    );
  }

  Widget _travelerCard({
    required BuildContext context,
    required IconData icon,
    required String type,
    required String subtitle,
    required String rangeLabel,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colors = context.triporaColors;
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: isSelected
          ? scheme.primary
          : colors.surface,
      borderRadius:
          BorderRadius.circular(14),
      child: InkWell(
        borderRadius:
            BorderRadius.circular(14),
        onTap: isGenerating
            ? null
            : onTap,
        child: Container(
          padding:
              const EdgeInsets.all(14),
          decoration:
              BoxDecoration(
            borderRadius:
                BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? scheme.primary
                  : colors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: isSelected
                        ? scheme.onPrimary
                        : scheme.primary,
                  ),

                  const Spacer(),

                  Text(
                    rangeLabel,
                    style: TextStyle(
                      fontFamily:
                          'Manrope',
                      fontSize: 11,
                      fontWeight:
                          FontWeight.w700,
                      color: isSelected
                          ? scheme.onPrimary
                              .withValues(
                              alpha: 0.7,
                            )
                          : colors.textMuted,
                    ),
                  ),
                ],
              ),

              const Spacer(),

              Text(
                _localizedTravelerType(
                  context,
                  type,
                ),
                style: TextStyle(
                  fontFamily:
                      'Manrope',
                  fontSize: 15,
                  fontWeight:
                      FontWeight.w700,
                  color: isSelected
                      ? scheme.onPrimary
                      : colors.textPrimary,
                ),
              ),

              const SizedBox(height: 2),

              Text(
                subtitle,
                style: TextStyle(
                  fontFamily:
                      'Manrope',
                  fontSize: 11,
                  color: isSelected
                      ? scheme.onPrimary
                          .withValues(
                          alpha: 0.75,
                        )
                      : colors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // BUDGET
  // ============================================================

  Widget _buildBudgetSection(
    BuildContext context,
  ) {
    final colors = context.triporaColors;
    final scheme = Theme.of(context).colorScheme;

    return _buildSection(
      context: context,
      number: 4,
      title: context.tr(
        'planner.budgetTier',
      ),
      trailingWidget: Container(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 5,
        ),
        decoration:
            BoxDecoration(
          color:
              colors.surfaceSecondary,
          borderRadius:
              BorderRadius.circular(999),
        ),
        child: Text(
          budgetEstimateLabel(
            context,
          ),
          style:
              TextStyle(
            fontFamily:
                'Manrope',
            fontSize: 11,
            fontWeight:
                FontWeight.w700,
            color:
                colors.textMuted,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child:
                    _budgetTierChip(
                  context,
                  'Backpacker',
                  r'($)',
                ),
              ),

              const SizedBox(
                width: 8,
              ),

              Expanded(
                child:
                    _budgetTierChip(
                  context,
                  'Comfort',
                  r'($$)',
                ),
              ),

              const SizedBox(
                width: 8,
              ),

              Expanded(
                child:
                    _budgetTierChip(
                  context,
                  'Luxury',
                  r'($$$)',
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          Row(
            children: [
              Text(
                context
                    .tr(
                      'planner.highlightsPriority',
                    )
                    .toUpperCase(),
                style:
                    TextStyle(
                  fontFamily:
                      'Manrope',
                  fontSize: 10,
                  fontWeight:
                      FontWeight.w700,
                  letterSpacing: 1,
                  color:
                      colors.textMuted,
                ),
              ),

              const Spacer(),

              Text(
                context.tr(
                  'planner.selectAsMany',
                ),
                style:
                    TextStyle(
                  fontFamily:
                      'Manrope',
                  fontSize: 10,
                  fontWeight:
                      FontWeight.w600,
                  color:
                      context.appStatus.info,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                interests.map(
              (interest) {
                final selected =
                    selectedInterests
                        .contains(
                  interest,
                );

                return FilterChip(
                  label: Text(
                    _localizedInterest(
                      context,
                      interest,
                    ),
                    style: TextStyle(
                      fontFamily:
                          'Manrope',
                      fontSize: 12,
                      fontWeight: selected
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: selected
                          ? scheme.onPrimary
                          : context.headingColor,
                    ),
                  ),
                  selected: selected,
                  showCheckmark: false,
                  backgroundColor:
                      colors.surfaceSecondary,
                  selectedColor:
                      context.appStatus.info,
                  side: BorderSide(
                    color: selected
                        ? context.appStatus.info
                        : colors.borderStrong,
                  ),
                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(
                      999,
                    ),
                  ),
                  onSelected:
                      isGenerating
                          ? null
                          : (value) {
                              setState(() {
                                if (value) {
                                  selectedInterests
                                      .add(
                                    interest,
                                  );
                                } else {
                                  selectedInterests
                                      .remove(
                                    interest,
                                  );
                                }
                              });
                            },
                );
              },
            ).toList(),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BUDGET ESTIMATE
  // ============================================================

  String budgetEstimateLabel(
    BuildContext context,
  ) {
    final int days =
        (startDate != null &&
                endDate != null)
            ? (endDate!
                    .difference(
                      startDate!,
                    )
                    .inDays +
                1)
            : 5;

    final int perDayPerPerson =
        switch (budget) {
      'Budget' => 60,
      'Luxury' => 400,
      _ => 150,
    };

    final int estimate =
        perDayPerPerson *
            days *
            travelers;

    return context.tr(
      'planner.estimatedAmount',
      params: {
        'amount': estimate.toString(),
      },
    );
  }

  Widget _budgetTierChip(
    BuildContext context,
    String label,
    String priceHint,
  ) {
    final colors = context.triporaColors;
    final scheme = Theme.of(context).colorScheme;

    final String mapped =
        switch (label) {
      'Backpacker' => 'Budget',
      'Luxury' => 'Luxury',
      _ => 'Moderate',
    };

    final selected =
        budget == mapped;

    return InkWell(
      onTap: isGenerating
          ? null
          : () {
              setState(() {
                budget = mapped;
              });
            },
      borderRadius:
          BorderRadius.circular(10),
      child: Container(
        padding:
            const EdgeInsets.symmetric(
          vertical: 12,
        ),
        alignment:
            Alignment.center,
        decoration:
            BoxDecoration(
          color: selected
              ? colors.surface
              : colors.surfaceSecondary,
          borderRadius:
              BorderRadius.circular(
            10,
          ),
          border: Border.all(
            color: selected
                ? scheme.primary
                : Colors.transparent,
            width:
                selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              context.tr(
                label == 'Backpacker'
                    ? 'planner.backpacker'
                    : label == 'Comfort'
                        ? 'planner.comfort'
                        : 'planner.luxury',
              ),
              style: TextStyle(
                fontFamily:
                    'Manrope',
                fontSize: 12,
                fontWeight:
                    FontWeight.w700,
                color: selected
                    ? context.headingColor
                    : colors.textSecondary,
              ),
            ),

            const SizedBox(
              height: 2,
            ),

            Text(
              priceHint,
              style: TextStyle(
                fontFamily:
                    'Manrope',
                fontSize: 10,
                color: selected
                    ? context.headingColor
                    : colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // TRAVEL STYLE
  // ============================================================

  Widget _buildTravelStyleSection(
    BuildContext context,
  ) {
    return _buildSection(
      context: context,
      number: 5,
      title: context.tr(
        'planner.travelStyleQuestion',
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _buildChoiceChip(
            context,
            'Relaxed',
          ),
          _buildChoiceChip(
            context,
            'Balanced',
          ),
          _buildChoiceChip(
            context,
            'Packed',
          ),
        ],
      ),
    );
  }

  // ============================================================
  // GENERATE BUTTON
  // ============================================================

  Widget _buildGenerateButton(
    BuildContext context,
  ) {
    final colors = context.triporaColors;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton.icon(
            onPressed:
                isGenerating
                    ? null
                    : generateTrip,
            style:
                FilledButton.styleFrom(
              backgroundColor:
                  scheme.primary,
              foregroundColor:
                  scheme.onPrimary,
              disabledBackgroundColor:
                  scheme.primary
                      .withValues(
                alpha: 0.55,
              ),
              shape:
                  RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(
                  12,
                ),
              ),
              elevation: 0,
            ),
            icon: isGenerating
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child:
                        CircularProgressIndicator(
                      strokeWidth: 2,
                      color:
                          scheme.onPrimary,
                    ),
                  )
                : const Icon(
                    Icons.auto_awesome,
                    size: 19,
                  ),
            label: Text(
              isGenerating
                  ? context.tr(
                      'planner.buildingItinerary',
                    )
                  : context.tr(
                      'planner.createWithAI',
                    ),
              style:
                  const TextStyle(
                fontFamily:
                    'Manrope',
                fontSize: 15,
                fontWeight:
                    FontWeight.w700,
              ),
            ),
          ),
        ),

        const SizedBox(height: 10),

        Center(
          child: Row(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              Icon(
                Icons.verified_outlined,
                size: 14,
                color: colors.textMuted,
              ),

              const SizedBox(width: 6),

              Flexible(
                child: Text(
                  context.tr(
                    'planner.aiDisclaimer',
                  ),
                  textAlign:
                      TextAlign.center,
                  style:
                      TextStyle(
                    fontFamily:
                        'Manrope',
                    fontSize: 11,
                    color:
                        colors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // SECTION
  // ============================================================

  Widget _buildSection({
    required BuildContext context,
    required int number,
    required String title,
    required Widget child,
    IconData? trailingIcon,
    Widget? trailingWidget,
  }) {
    final colors = context.triporaColors;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(18),
      decoration:
          BoxDecoration(
        color: colors.surface,
        borderRadius:
            BorderRadius.circular(20),
        border:
            Border.all(color: colors.border),
        boxShadow: const [
          BoxShadow(
            color:
                Color(0x081E1B4B),
            blurRadius: 12,
            offset:
                Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment:
                    Alignment.center,
                decoration:
                    BoxDecoration(
                  color: scheme.primary,
                  shape:
                      BoxShape.circle,
                ),
                child: Text(
                  '$number',
                  style:
                      TextStyle(
                    fontFamily:
                        'Manrope',
                    fontSize: 12,
                    fontWeight:
                        FontWeight.w800,
                    color:
                        scheme.onPrimary,
                  ),
                ),
              ),

              const SizedBox(
                width: 12,
              ),

              Expanded(
                child: Text(
                  title,
                  style:
                      TextStyle(
                    fontFamily:
                        'Noto Serif',
                    fontSize: 19,
                    fontWeight:
                        FontWeight.w600,
                    color:
                        context.headingColor,
                  ),
                ),
              ),

              if (trailingWidget != null)
                trailingWidget
              else if (trailingIcon !=
                  null)
                Icon(
                  trailingIcon,
                  size: 20,
                  color: colors.textMuted,
                ),
            ],
          ),

          const SizedBox(height: 14),

          child,
        ],
      ),
    );
  }

  // ============================================================
  // INPUT DECORATION
  // ============================================================

  InputDecoration _inputDecoration({
    required String hintText,
    required IconData icon,
    required TriporaColors colors,
    required ColorScheme scheme,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle:
          TextStyle(
        fontFamily:
            'Manrope',
        fontSize: 14,
        color:
            colors.textMuted,
      ),
      prefixIcon: Icon(
        icon,
        color: colors.textMuted,
        size: 21,
      ),
      suffixIcon:
          suffixIcon,
      filled: true,
      fillColor:
          colors.backgroundColor,
      contentPadding:
          const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 15,
      ),
      border:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(
          10,
        ),
        borderSide:
            BorderSide(
          color: colors.border,
        ),
      ),
      enabledBorder:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(
          10,
        ),
        borderSide:
            BorderSide(
          color: colors.border,
        ),
      ),
      focusedBorder:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(
          10,
        ),
        borderSide:
            BorderSide(
          color: scheme.primary,
          width: 1.3,
        ),
      ),
      disabledBorder:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(
          10,
        ),
        borderSide:
            BorderSide(
          color: colors.border,
        ),
      ),
    );
  }

  // ============================================================
  // DATE FIELD
  // ============================================================

  Widget _buildDateField({
    required BuildContext context,
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    final colors = context.triporaColors;

    final selected =
        date != null;

    return InkWell(
      onTap: isGenerating
          ? null
          : onTap,
      borderRadius:
          BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style:
                TextStyle(
              fontFamily:
                  'Manrope',
              fontSize: 9,
              fontWeight:
                  FontWeight.w700,
              letterSpacing: 1,
              color:
                  colors.textMuted,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            _displayDate(
              context,
              date,
            ),
            overflow:
                TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily:
                  'Manrope',
              fontSize: 15,
              fontWeight:
                  FontWeight.w700,
              color: selected
                  ? colors.textPrimary
                  : colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TRAVEL STYLE CHIP
  // ============================================================

  Widget _buildChoiceChip(
    BuildContext context,
    String label,
  ) {
    final colors = context.triporaColors;
    final scheme = Theme.of(context).colorScheme;

    final selected =
        travelStyle == label;

    return ChoiceChip(
      label: Text(
        _localizedTravelStyle(
          context,
          label,
        ),
        style: TextStyle(
          fontFamily:
              'Manrope',
          fontSize: 12,
          fontWeight: selected
              ? FontWeight.w700
              : FontWeight.w600,
          color: selected
              ? scheme.onPrimary
              : context.headingColor,
        ),
      ),
      selected: selected,
      showCheckmark: false,
      backgroundColor:
          colors.surfaceSecondary,
      selectedColor:
          scheme.primary,
      side: BorderSide(
        color: selected
            ? scheme.primary
            : colors.borderStrong,
      ),
      shape:
          RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(
          999,
        ),
      ),
      padding:
          const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 7,
      ),
      onSelected:
          isGenerating
              ? null
              : (_) {
                  setState(() {
                    travelStyle =
                        label;
                  });
                },
    );
  }
}

// ================================================================
// GENERATION DIALOG
// ================================================================

class _GenerationDialog
    extends StatelessWidget {
  const _GenerationDialog();

  @override
  Widget build(
    BuildContext context,
  ) {
    final colors = context.triporaColors;

    return Container(
      width: double.infinity,
      constraints:
          const BoxConstraints(
        maxWidth: 390,
      ),
      margin:
          const EdgeInsets.symmetric(
        horizontal: 24,
      ),
      padding:
          const EdgeInsets.all(26),
      decoration:
          BoxDecoration(
        color: colors.surface,
        borderRadius:
            BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color:
                Color(0x331E1B4B),
            blurRadius: 30,
            offset:
                Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            alignment:
                Alignment.center,
            decoration:
                BoxDecoration(
              color: colors.surfaceInfo,
              borderRadius:
                  BorderRadius.circular(
                16,
              ),
            ),
            child:
                SizedBox(
              width: 25,
              height: 25,
              child:
                  CircularProgressIndicator(
                strokeWidth: 2.5,
                color: colors.appStatus.info,
              ),
            ),
          ),

          const SizedBox(
            height: 18,
          ),

          Text(
            context.tr(
              'planner.creatingItinerary',
            ),
            textAlign:
                TextAlign.center,
            style:
                TextStyle(
              fontFamily:
                  'Noto Serif',
              fontSize: 22,
              fontWeight:
                  FontWeight.w600,
              color:
                  context.headingColor,
            ),
          ),

          const SizedBox(
            height: 7,
          ),

          Text(
            context.tr(
              'planner.shapingPlan',
            ),
            textAlign:
                TextAlign.center,
            style:
                TextStyle(
              fontFamily:
                  'Manrope',
              fontSize: 12,
              height: 1.45,
              color:
                  colors.textMuted,
            ),
          ),

          const SizedBox(
            height: 22,
          ),

          const ShimmerLoader(
            width: double.infinity,
            height: 12,
            borderRadius:
                BorderRadius.all(
              Radius.circular(6),
            ),
            margin:
                EdgeInsets.only(
              bottom: 9,
            ),
          ),

          const ShimmerLoader(
            width: double.infinity,
            height: 12,
            borderRadius:
                BorderRadius.all(
              Radius.circular(6),
            ),
            margin:
                EdgeInsets.only(
              bottom: 18,
            ),
          ),

          const ShimmerLoader(
            width: double.infinity,
            height: 72,
            borderRadius:
                BorderRadius.all(
              Radius.circular(10),
            ),
            margin:
                EdgeInsets.only(
              bottom: 9,
            ),
          ),

          const ShimmerLoader(
            width: double.infinity,
            height: 72,
            borderRadius:
                BorderRadius.all(
              Radius.circular(10),
            ),
            margin:
                EdgeInsets.only(
              bottom: 9,
            ),
          ),

          const ShimmerLoader(
            width: double.infinity,
            height: 72,
            borderRadius:
                BorderRadius.all(
              Radius.circular(10),
            ),
          ),
        ],
      ),
    );
  }
}