import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/preferences/app_preferences.dart';
import '../../core/utils/logger.dart';
import '../../core/theme/app_theme.dart';
import '../../models/trip_model.dart';
import '../../services/trip_service.dart';
import '../../widgets/shimmer_loader.dart';
import 'expenses/expense_tracker_screen.dart';
import 'weather/trip_weather_screen.dart';

class TripDetailsScreen extends StatefulWidget {
  final TripModel trip;

  const TripDetailsScreen({
    super.key,
    required this.trip,
  });

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

  String _formatDate(DateTime date) {
    final locale = Localizations.localeOf(context).toLanguageTag();

    return DateFormat(
      'MMM d, yyyy',
      locale,
    ).format(date);
  }

  String _getString(Map<String, dynamic> data, String key) {
    final value = data[key];

    if (value == null) {
      return '';
    }

    return value.toString();
  }

  int? _getInt(Map<String, dynamic> data, String key) {
    final value = data[key];

    if (value is int) {
      return value;
    }

    return int.tryParse(value?.toString() ?? '');
  }

  String _interestLabel(String interest) {
    switch (interest.toLowerCase()) {
      case 'culture':
        return context.tr('planner.culture');
      case 'food':
        return context.tr('planner.food');
      case 'nature':
        return context.tr('planner.nature');
      case 'adventure':
        return context.tr('planner.adventure');
      case 'shopping':
        return context.tr('planner.shopping');
      case 'nightlife':
        return context.tr('planner.nightlife');
      case 'relaxation':
        return context.tr('planner.relaxation');
      default:
        return interest;
    }
  }

  String _budgetLabel(String budget) {
    switch (budget.toLowerCase()) {
      case 'budget':
        return context.tr('planner.budget');
      case 'moderate':
        return context.tr('planner.moderate');
      case 'luxury':
        return context.tr('planner.luxury');
      default:
        return budget;
    }
  }

  String _travelStyleLabel(String style) {
    switch (style.toLowerCase()) {
      case 'relaxed':
        return context.tr('planner.relaxed');
      case 'balanced':
        return context.tr('planner.balanced');
      case 'packed':
        return context.tr('planner.packed');
      default:
        return style;
    }
  }

  // Trip progress based on the actual trip dates.
  //
  // Before the trip starts -> 0%
  // First day -> 0%
  // During the trip -> proportional progress
  // Last day -> 100%
  // After the trip -> 100%
  double _getTripProgress() {
    final now = DateTime.now();

    final today = DateTime(
      now.year,
      now.month,
      now.day,
    );

    final start = DateTime(
      _trip.startDate.year,
      _trip.startDate.month,
      _trip.startDate.day,
    );

    final end = DateTime(
      _trip.endDate.year,
      _trip.endDate.month,
      _trip.endDate.day,
    );

    if (today.isBefore(start)) {
      return 0.0;
    }

    if (!today.isBefore(end)) {
      return 1.0;
    }

    final totalTravelDays = end.difference(start).inDays;

    if (totalTravelDays <= 0) {
      return 1.0;
    }

    final elapsedDays = today.difference(start).inDays;

    return (elapsedDays / totalTravelDays).clamp(0.0, 1.0);
  }

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
    final colors = context.triporaColors;

    return Scaffold(
      backgroundColor: colors.backgroundColor,
      appBar: AppBar(
        backgroundColor: colors.backgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 8,
        title: Text(
          context.tr('details.title'),
          style: TextStyle(
            fontFamily: 'Noto Serif',
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: context.headingColor,
          ),
        ),
        actions: [
          if (!_isLoading && _errorMessage == null)
            IconButton(
              tooltip: context.tr('details.editTrip'),
              icon: const Icon(Icons.edit_outlined),
              onPressed: _isSaving || _isRegenerating
                  ? null
                  : _showEditTripSheet,
            ),
          if (!_isLoading && _errorMessage == null)
            IconButton(
              tooltip: context.tr('details.regenerateItinerary'),
              icon: const Icon(Icons.auto_awesome_outlined),
              color: context.appStatus.info,
              onPressed: _isSaving || _isRegenerating
                  ? null
                  : _regenerateItinerary,
            ),
          if (!_isLoading && _errorMessage == null)
            IconButton(
              tooltip: context.tr('common.refresh'),
              icon: const Icon(Icons.refresh_outlined),
              onPressed: _loadTripDetails,
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final colors = context.triporaColors;
    final scheme = Theme.of(context).colorScheme;

    if (_isLoading && _trip.destination.isEmpty) {
      return const TripDetailsShimmer();
    }

    if (_errorMessage != null && _trip.destination.isEmpty) {
      return _buildErrorState();
    }

    return Stack(
      children: [
        RefreshIndicator(
          color: scheme.primary,
          onRefresh: _loadTripDetails,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              _buildHeroSection(),
              LayoutBuilder(
                builder: (context, constraints) {
                  final horizontalPadding = constraints.maxWidth >= 1024
                      ? 40.0
                      : constraints.maxWidth >= 768
                          ? 24.0
                          : 16.0;

                  final maxWidth = constraints.maxWidth > 1280
                      ? 1100.0
                      : double.infinity;

                  return Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: maxWidth,
                      ),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          24,
                          horizontalPadding,
                          0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_errorMessage != null) ...[
                              _buildInlineErrorBanner(),
                              const SizedBox(height: 18),
                            ],
                            _buildTripOverview(),
                            const SizedBox(height: 24),
                            _buildStatsRow(),
                            const SizedBox(height: 24),
                            _buildCommandDeck(),
                            const SizedBox(height: 24),
                            _buildEstimatedCost(),
                            if (_trip.estimatedCost != null &&
                                _trip.estimatedCost!.isNotEmpty)
                              const SizedBox(height: 24),
                            _buildInterests(),
                            if (_trip.interests.isNotEmpty)
                              const SizedBox(height: 32),
                            _buildItineraryHeader(),
                            const SizedBox(height: 18),
                            if (_trip.itinerary.isEmpty)
                              _buildEmptyItinerary()
                            else
                              ..._trip.itinerary.map((day) {
                                if (day is! Map) {
                                  return const SizedBox.shrink();
                                }

                                try {
                                  return _buildDayCard(
                                    Map<String, dynamic>.from(day),
                                  );
                                } catch (error) {
                                  appLog('INVALID DAY DATA: $error');
                                  return const SizedBox.shrink();
                                }
                              }),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        if (_isLoading)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              minHeight: 2,
              color: colors.appStatus.info,
              backgroundColor: Colors.transparent,
            ),
          ),
        if (_isSaving || _isRegenerating)
          Positioned.fill(
            child: ColoredBox(
              color: Color(0x66070235),
              child: Center(
                child: Container(
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: colors.border),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x241E1B4B),
                        blurRadius: 30,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: colors.appStatus.info.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: colors.appStatus.info,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _isRegenerating
                            ? context.tr(
                                'details.regeneratingItinerary',
                              )
                            : context.tr(
                                'details.savingTrip',
                              ),
                        style: TextStyle(
                          fontFamily: 'Noto Serif',
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: context.headingColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _isRegenerating
                            ? context.tr(
                                'details.regeneratingDescription',
                              )
                            : context.tr(
                                'details.savingDescription',
                              ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: colors.textMuted,
                        ),
                      ),
                    ],
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
        final colors = dialogContext.triporaColors;
        final scheme = Theme.of(dialogContext).colorScheme;

        return AlertDialog(
          backgroundColor: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            context.tr('details.regenerateQuestion'),
            style: TextStyle(
              fontFamily: 'Noto Serif',
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          content: Text(
            context.tr('details.regenerateDescription'),
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: colors.textSecondary,
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
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                context.tr('common.cancel'),
              ),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: colors.appStatus.info,
                foregroundColor: scheme.onPrimary,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(
                Icons.auto_awesome_outlined,
                size: 18,
              ),
              label: Text(
                context.tr('details.regenerate'),
              ),
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
      final updatedTrip =
          await _tripService.regenerateItinerary(tripId);

      if (!mounted) return;

      setState(() {
        _trip = updatedTrip;
        _isRegenerating = false;
      });

      _showMessage(
        context.tr('details.itineraryRegenerated'),
      );
    } catch (error) {
      if (!mounted) return;

      final message = _extractErrorMessage(error);

      setState(() {
        _isRegenerating = false;
        _errorMessage = message;
      });

      _showMessage(
        message,
        isError: true,
      );
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

    const budgetOptions = [
      'Budget',
      'Moderate',
      'Luxury',
    ];

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
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final colors = context.triporaColors;
            final scheme = Theme.of(context).colorScheme;

            Future<void> pickDate({
              required bool isStartDate,
            }) async {
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
              final destination =
                  destinationController.text.trim();

              if (destination.isEmpty) {
                _showMessage(
                  context.tr('details.destinationRequired'),
                  isError: true,
                );
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

            return Container(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    MediaQuery.of(context).viewInsets.bottom + 20,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Center(
                          child: Container(
                            width: 42,
                            height: 4,
                            decoration: BoxDecoration(
                              color: colors.borderStrong,
                              borderRadius:
                                  BorderRadius.circular(99),
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          context.tr('details.editJourney'),
                          style: TextStyle(
                            fontFamily: 'Noto Serif',
                            fontSize: 26,
                            fontWeight: FontWeight.w600,
                            color: context.headingColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          context.tr(
                            'details.editJourneyDescription',
                          ),
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: colors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 22),

                        _sheetLabel(
                          context.tr('planner.destination')
                              .toUpperCase(),
                        ),
                        const SizedBox(height: 7),

                        TextField(
                          controller: destinationController,
                          decoration: _inputDecoration(
                            context.tr(
                              'details.destinationHint',
                            ),
                            Icons.location_on_outlined,
                          ),
                        ),

                        const SizedBox(height: 18),

                        _sheetLabel(
                          context.tr('planner.dates')
                              .toUpperCase(),
                        ),
                        const SizedBox(height: 7),

                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => pickDate(
                                  isStartDate: true,
                                ),
                                icon: const Icon(
                                  Icons.calendar_month_outlined,
                                  size: 18,
                                ),
                                label: Text(
                                  _formatDate(startDate),
                                ),
                                style: _outlinedButtonStyle(),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => pickDate(
                                  isStartDate: false,
                                ),
                                icon: const Icon(
                                  Icons.event_outlined,
                                  size: 18,
                                ),
                                label: Text(
                                  _formatDate(endDate),
                                ),
                                style: _outlinedButtonStyle(),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 18),

                        _sheetLabel(
                          context.tr('planner.travelers')
                              .toUpperCase(),
                        ),
                        const SizedBox(height: 7),

                        Container(
                          height: 52,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          decoration: BoxDecoration(
                            color: colors.backgroundColor,
                            borderRadius:
                                BorderRadius.circular(8),
                            border:
                                Border.all(color: colors.border),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.people_outline,
                                color: colors.textMuted,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  context.tr(
                                    'planner.travelers',
                                  ),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: colors.textPrimary,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: context.tr(
                                  'details.removeTraveler',
                                ),
                                onPressed: travelers > 1
                                    ? () {
                                        setSheetState(() {
                                          travelers--;
                                        });
                                      }
                                    : null,
                                icon: const Icon(
                                  Icons.remove_circle_outline,
                                ),
                              ),
                              Text(
                                '$travelers',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              IconButton(
                                tooltip: context.tr(
                                  'details.addTraveler',
                                ),
                                onPressed: () {
                                  setSheetState(() {
                                    travelers++;
                                  });
                                },
                                icon: const Icon(
                                  Icons.add_circle_outline,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 18),

                        _sheetLabel(
                          context.tr('planner.budget')
                              .toUpperCase(),
                        ),
                        const SizedBox(height: 7),

                        DropdownButtonFormField<String>(
                          initialValue: budget,
                          decoration: _inputDecoration(
                            context.tr('planner.budget'),
                            Icons
                                .account_balance_wallet_outlined,
                          ),
                          items: budgetOptions.map((option) {
                            return DropdownMenuItem<String>(
                              value: option,
                              child: Text(
                                _budgetLabel(option),
                              ),
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

                        const SizedBox(height: 18),

                        _sheetLabel(
                          context.tr('planner.travelStyle')
                              .toUpperCase(),
                        ),
                        const SizedBox(height: 9),

                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            'Relaxed',
                            'Balanced',
                            'Packed',
                          ].map((style) {
                            final selected =
                                travelStyle == style;

                            return ChoiceChip(
                              label: Text(
                                _travelStyleLabel(style),
                              ),
                              selected: selected,
                              onSelected: (_) {
                                setSheetState(() {
                                  travelStyle = style;
                                });
                              },
                              selectedColor: scheme.primary,
                              backgroundColor: colors.surfaceSecondary,
                              labelStyle: TextStyle(
                                color: selected
                                    ? scheme.onPrimary
                                    : context.headingColor,
                                fontWeight:
                                    FontWeight.w600,
                              ),
                              side: BorderSide(
                                color: selected
                                    ? scheme.primary
                                    : colors.border,
                              ),
                            );
                          }).toList(),
                        ),

                        const SizedBox(height: 18),

                        _sheetLabel(
                          context.tr('planner.interests')
                              .toUpperCase(),
                        ),
                        const SizedBox(height: 9),

                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _availableInterests.map(
                            (interest) {
                              final selected =
                                  selectedInterests
                                      .contains(interest);

                              return FilterChip(
                                label: Text(
                                  _interestLabel(interest),
                                ),
                                selected: selected,
                                onSelected: (value) {
                                  setSheetState(() {
                                    if (value) {
                                      selectedInterests
                                          .add(interest);
                                    } else {
                                      selectedInterests
                                          .remove(interest);
                                    }
                                  });
                                },
                                selectedColor: colors.appStatus.info,
                                backgroundColor: colors.surfaceSecondary,
                                labelStyle: TextStyle(
                                  color: selected
                                      ? scheme.onPrimary
                                      : context.headingColor,
                                  fontWeight:
                                      FontWeight.w600,
                                ),
                                checkmarkColor:
                                    scheme.onPrimary,
                                side: BorderSide(
                                  color: selected
                                      ? colors.appStatus.info
                                      : colors.border,
                                ),
                              );
                            },
                          ).toList(),
                        ),

                        const SizedBox(height: 24),

                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: FilledButton.icon(
                            onPressed: submit,
                            icon: const Icon(
                              Icons.save_outlined,
                              size: 19,
                            ),
                            label: Text(
                              context.tr(
                                'details.saveChanges',
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: scheme.primary,
                              foregroundColor: scheme.onPrimary,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
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

      _showMessage(
        context.tr('details.tripUpdated'),
      );
    } catch (error) {
      if (!mounted) return;

      final message = _extractErrorMessage(error);

      setState(() {
        _isSaving = false;
        _errorMessage = message;
      });

      _showMessage(
        message,
        isError: true,
      );
    }
  }

  InputDecoration _inputDecoration(
    String label,
    IconData icon,
  ) {
    final colors = context.triporaColors;
    final scheme = Theme.of(context).colorScheme;

    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(
        icon,
        color: colors.textMuted,
      ),
      filled: true,
      fillColor: colors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: colors.border,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: colors.border,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: scheme.primary,
          width: 1.5,
        ),
      ),
    );
  }

  ButtonStyle _outlinedButtonStyle() {
    final colors = context.triporaColors;

    return OutlinedButton.styleFrom(
      foregroundColor: context.headingColor,
      minimumSize: const Size(0, 52),
      side: BorderSide(
        color: colors.border,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _sheetLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: context.triporaColors.textMuted,
      ),
    );
  }

  void _showMessage(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) return;

    final statusColors =
        Theme.of(context).extension<AppStatusColors>();

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError
              ? statusColors?.error ??
                  Theme.of(context).colorScheme.error
              : statusColors?.success ??
                  context.triporaColors.appStatus.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 440,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: context.appStatus.error
                      .withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.error_outline,
                  size: 36,
                  color: context.appStatus.error,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                context.tr('details.loadError'),
                textAlign: TextAlign.center,
style: TextStyle(
                fontFamily: 'Noto Serif',
                fontSize: 26,
                fontWeight: FontWeight.w600,
                color: context.triporaColors.textPrimary,
              ),
              ),
              const SizedBox(height: 10),
              Text(
                _errorMessage ??
                    context.tr(
                      'details.somethingWentWrong',
                    ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: context.triporaColors.textMuted,
                ),
              ),
              const SizedBox(height: 26),
              FilledButton.icon(
                onPressed: _loadTripDetails,
                icon: const Icon(
                  Icons.refresh_outlined,
                ),
                label: Text(
                  context.tr('common.tryAgain'),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  minimumSize: const Size(
                    140,
                    48,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInlineErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appStatus.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: context.appStatus.warning.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_outlined,
            color: context.appStatus.warning,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.tr(
                'details.refreshError',
                params: {
                  'error': _errorMessage ?? '',
                },
              ),
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Color(0xFF8A5A00),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        20,
        30,
        20,
        30,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF070235),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth > 1100
              ? 1100.0
              : double.infinity;

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth,
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding:
                            const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: context.appStatus.info
                              .withValues(alpha: 0.16),
                          borderRadius:
                              BorderRadius.circular(999),
                          border: Border.all(
                            color: context.appStatus.info
                                .withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.auto_awesome,
                              size: 13,
                              color: Color(0xFF93C5FD),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              context.tr(
                                'details.aiTravelPlan',
                              ),
                              style: const TextStyle(
                                color: Color(0xFFBFDBFE),
                                fontSize: 10,
                                fontWeight:
                                    FontWeight.w700,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildStatusPill(),
                  const SizedBox(height: 20),
                  Text(
                    _trip.destination,
                    style: const TextStyle(
                      fontFamily: 'Noto Serif',
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 16,
                        color: Color(0xFFCBD5E1),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '${_formatDate(_trip.startDate)} – '
                          '${_formatDate(_trip.endDate)}',
                          style: const TextStyle(
                            color: Color(0xFFCBD5E1),
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _heroMetric(
                        '${_trip.numberOfDays}',
                        _trip.numberOfDays == 1
                            ? context.tr('details.day')
                            : context.tr('details.days'),
                      ),
                      _heroMetric(
                        '${_trip.travelers}',
                        _trip.travelers == 1
                            ? context.tr('details.traveler')
                            : context.tr('details.travelers'),
                      ),
                      _heroMetric(
                        _trip.budget.isEmpty
                            ? '—'
                            : _budgetLabel(_trip.budget)
                                .toUpperCase(),
                        context
                            .tr('planner.budget')
                            .toUpperCase(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusPill() {
    final now = DateTime.now();

    String label;
    IconData icon;
    Color color;

    if (now.isBefore(_trip.startDate)) {
      final daysUntil =
          _trip.startDate.difference(now).inDays;

      // Pass the number under every name a translation might use
      // ({days}, {n} or {count}) so the placeholder is always replaced.
      label = daysUntil <= 0
          ? context.tr('details.startingToday')
          : context.tr(
              'details.upcomingIn',
              params: {
                'days': '$daysUntil',
                'n': '$daysUntil',
                'count': '$daysUntil',
              },
            );

      icon = Icons.event_outlined;
      color = context.appStatus.info;
    } else if (now.isAfter(_trip.endDate)) {
      label = context.tr('details.tripCompleted');
      icon = Icons.check_circle_outline;
      color = context.triporaColors.textMuted;
    } else {
      label = context.tr('details.tripInProgress');
      icon = Icons.flight_takeoff_rounded;
      color = context.appStatus.success;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroMetric(
    String value,
    String label,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$value ',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: label,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTripOverview() {
    return _sectionCard(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          _sectionEyebrow(
            context.tr('details.tripOverview'),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns =
                  constraints.maxWidth >= 650 ? 4 : 2;

              final items = [
                _overviewItem(
                  Icons.calendar_month_outlined,
                  context.tr('details.duration'),
                  '${_trip.numberOfDays} '
                  '${_trip.numberOfDays == 1 ? context.tr('details.day') : context.tr('details.days')}',
                ),
                _overviewItem(
                  Icons.people_outline,
                  context.tr('details.travelers'),
                  '${_trip.travelers}',
                ),
                _overviewItem(
                  Icons.account_balance_wallet_outlined,
                  context.tr('details.budget'),
                  _trip.budget.isNotEmpty
                      ? _budgetLabel(_trip.budget)
                      : context.tr('details.notSpecified'),
                ),
                _overviewItem(
                  Icons.explore_outlined,
                  context.tr('details.style'),
                  _trip.travelStyle.isNotEmpty
                      ? _travelStyleLabel(
                          _trip.travelStyle,
                        )
                      : context.tr('details.notSpecified'),
                ),
              ];

              return GridView.count(
                crossAxisCount: columns,
                crossAxisSpacing: 16,
                mainAxisSpacing: 18,
                childAspectRatio:
                    columns == 4 ? 2.8 : 3.4,
                shrinkWrap: true,
                physics:
                    const NeverScrollableScrollPhysics(),
                children: items,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _overviewItem(
    IconData icon,
    String label,
    String value,
  ) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: context.triporaColors.surfaceSecondary,
            borderRadius:
                BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 19,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment:
                MainAxisAlignment.center,
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: context.triporaColors.textMuted,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.triporaColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow() {
    // Progress is based on the actual trip dates,
    // not the number of itinerary activities.
    final tripProgress = _getTripProgress();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow =
            constraints.maxWidth < 500;

        final tiles = [
          _statTile(
            label: context.tr('details.budget'),
            value: _trip.budget.isEmpty
                ? '—'
                : _budgetLabel(_trip.budget),
            icon: Icons.account_balance_wallet_outlined,
          ),
          _statTile(
            label: context.tr('details.planComplete'),
            value:
                '${(tripProgress * 100).round()}%',
            icon: Icons.map_outlined,
            progress: tripProgress,
          ),
          _statTile(
            label: context.tr('details.duration'),
            value:
                '${_trip.numberOfDays} '
                '${_trip.numberOfDays == 1 ? context.tr('details.day') : context.tr('details.days')}',
            icon: Icons.schedule_outlined,
          ),
        ];

        if (isNarrow) {
          return Column(
            children: tiles
                .map(
                  (tile) => Padding(
                    padding:
                        const EdgeInsets.only(
                      bottom: 12,
                    ),
                    child: tile,
                  ),
                )
                .toList(),
          );
        }

        // IntrinsicHeight gives the Row a bounded height inside the
        // scrollable (which otherwise passes unbounded heights), so
        // CrossAxisAlignment.stretch can equalize the three cards'
        // heights without stretching them to an infinite height.
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: tiles
                .map(
                  (tile) => Expanded(
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 6,
                      ),
                      child: tile,
                    ),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }

  Widget _statTile({
    required String label,
    required String value,
    required IconData icon,
    double? progress,
  }) {
    final colors = context.triporaColors;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius:
            BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 15,
                color: colors.textMuted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: colors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: context.headingColor,
            ),
          ),
          if (progress != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius:
                  BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: colors.surfaceSecondary,
                color: colors.appStatus.info,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCommandDeck() {
    final totalActivities =
        _trip.itinerary.fold<int>(
      0,
      (sum, day) {
        if (day is! Map) return sum;

        final acts = day['activities'];

        return sum +
            (acts is List ? acts.length : 0);
      },
    );

    // Pass the number under every name a translation might use, then also
    // replace a literal {n} in case tr() left one behind.
    final activitiesPlanned = context
        .tr(
          'details.activitiesPlanned',
          params: {
            'n': '$totalActivities',
            'count': '$totalActivities',
          },
        )
        .replaceFirst(
          '{n}',
          '$totalActivities',
        );

    final items = <_DeckItem>[
      _DeckItem(
        Icons.local_activity_outlined,
        context.tr('details.activities'),
        activitiesPlanned,
        _showActivitiesSheet,
      ),
      _DeckItem(
        Icons.account_balance_wallet_outlined,
        context.tr('details.expenses'),
        context.tr('details.trackSpending'),
        _openExpenseTracker,
      ),
      _DeckItem(
        Icons.cloud_outlined,
        context.tr('details.weather'),
        context.tr('details.weatherForecast'),
        _openWeather,
      ),
    ];

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        _sectionEyebrow(
          context.tr('details.commandDeck'),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          shrinkWrap: true,
          physics:
              const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.0,
          children: items
              .map(
                (item) => _deckTile(item),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _deckTile(_DeckItem item) {
    final colors = context.triporaColors;

    return Material(
      color: colors.surface,
      borderRadius:
          BorderRadius.circular(14),
      child: InkWell(
        borderRadius:
            BorderRadius.circular(14),
        onTap: item.onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius:
                BorderRadius.circular(14),
            border: Border.all(
              color: colors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: colors.surfaceSecondary,
                  borderRadius:
                      BorderRadius.circular(9),
                ),
                child: Icon(
                  item.icon,
                  size: 17,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const Spacer(),
              Text(
                item.title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.subtitle,
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: colors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openWeather() {
    final tripId = _trip.id;

    if (tripId == null) {
      _showMessage(
        context.tr('details.weatherUnavailable'),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TripWeatherScreen(
          trip: _trip,
        ),
      ),
    );
  }

  void _openExpenseTracker() {
    final tripId = _trip.id;

    if (tripId == null) {
      _showMessage(
        context.tr('details.expensesUnavailable'),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExpenseTrackerScreen(
          trip: _trip,
        ),
      ),
    );
  }

  void _showActivitiesSheet() {
    final dayEntries =
        <MapEntry<int, List<Map<String, dynamic>>>>[];

    for (final rawDay in _trip.itinerary) {
      if (rawDay is! Map) continue;

      Map<String, dynamic> day;

      try {
        day = Map<String, dynamic>.from(rawDay);
      } catch (_) {
        continue;
      }

      final dayNumber =
          _getInt(day, 'day') ??
              (dayEntries.length + 1);

      final rawActivities =
          day['activities'];

      final activities =
          <Map<String, dynamic>>[];

      if (rawActivities is List) {
        for (final activity in rawActivities) {
          if (activity is Map) {
            try {
              activities.add(
                Map<String, dynamic>.from(
                  activity,
                ),
              );
            } catch (_) {}
          }
        }
      }

      if (activities.isNotEmpty) {
        dayEntries.add(
          MapEntry(
            dayNumber,
            activities,
          ),
        );
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (
            context,
            scrollController,
          ) {
            return Container(
              decoration:
                  BoxDecoration(
                color: context.triporaColors.surface,
                borderRadius:
                    const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 42,
                    height: 4,
                    decoration:
                        BoxDecoration(
                      color: context.triporaColors.borderStrong,
                      borderRadius:
                          BorderRadius.circular(99),
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(
                      20,
                      18,
                      20,
                      6,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.tr(
                              'details.allActivities',
                            ),
                            style:
                                TextStyle(
                              fontFamily:
                                  'Noto Serif',
                              fontSize: 22,
                              fontWeight:
                                  FontWeight.w600,
                              color: context.headingColor,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: context.tr(
                            'common.close',
                          ),
                          icon: const Icon(
                            Icons.close,
                          ),
                          onPressed: () =>
                              Navigator.pop(
                            context,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: dayEntries.isEmpty
                        ? Center(
                            child: Padding(
                              padding:
                                  const EdgeInsets.all(
                                24,
                              ),
                              child: Text(
                                context.tr(
                                  'details.noActivities',
                                ),
                                style: TextStyle(
                                  color: context
                                      .triporaColors
                                      .textMuted,
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller:
                                scrollController,
                            padding:
                                const EdgeInsets.fromLTRB(
                              20,
                              8,
                              20,
                              24,
                            ),
                            itemCount:
                                dayEntries.length,
                            itemBuilder:
                                (context, index) {
                              final entry =
                                  dayEntries[index];

                              return Padding(
                                padding:
                                    const EdgeInsets.only(
                                  bottom: 20,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      context.tr(
                                        'details.dayNumber',
                                        params: {
                                          'day':
                                              '${entry.key}',
                                          'n':
                                              '${entry.key}',
                                        },
                                      ),
                                      style:
                                          TextStyle(
                                        fontSize: 10,
                                        fontWeight:
                                            FontWeight.w700,
                                        letterSpacing:
                                            1.1,
                                        color: context
                                            .appStatus
                                            .info,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    ...entry.value.map(
                                      (activity) {
                                        final title =
                                            _getString(
                                          activity,
                                          'title',
                                        );

                                        final time =
                                            _getString(
                                          activity,
                                          'time',
                                        );

                                        final category =
                                            _getString(
                                          activity,
                                          'category',
                                        );

                                        return Container(
                                          margin:
                                              const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          padding:
                                              const EdgeInsets.all(
                                            12,
                                          ),
                                          decoration:
                                              BoxDecoration(
                                            color: context
                                                .triporaColors
                                                .backgroundColor,
                                            borderRadius:
                                                BorderRadius
                                                    .circular(
                                              12,
                                            ),
                                            border:
                                                Border.all(
                                              color: context
                                                  .triporaColors
                                                  .border,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                _getTimeIconData(
                                                  time,
                                                ),
                                                size: 16,
                                                color: context
                                                    .appStatus
                                                    .info,
                                              ),
                                              const SizedBox(
                                                width: 10,
                                              ),
                                              Expanded(
                                                child:
                                                    Text(
                                                  title.isEmpty
                                                      ? context.tr(
                                                          'details.activity',
                                                        )
                                                      : title,
                                                  style:
                                                      TextStyle(
                                                    fontSize:
                                                        13,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                    color:
                                                        context
                                                            .triporaColors
                                                            .textPrimary,
                                                  ),
                                                ),
                                              ),
                                              if (category
                                                  .isNotEmpty)
                                                Text(
                                                  category,
                                                  style:
                                                      TextStyle(
                                                    fontSize:
                                                        10,
                                                    fontWeight:
                                                        FontWeight.w700,
                                                    color:
                                                        context
                                                            .triporaColors
                                                            .textMuted,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEstimatedCost() {
    final cost = _trip.estimatedCost;

    if (cost == null || cost.isEmpty) {
      return const SizedBox.shrink();
    }

    final breakdown = cost['breakdown'];

    final currency =
        cost['currency']?.toString() ?? 'USD';

    final total =
        cost['estimatedTotal'] ??
            cost['estimated_total'] ??
            0;

    final prefs = AppPreferences.instance;

    if (breakdown is! Map) {
      return _sectionCard(
        child: _costHeader(
          currency,
          prefs.formatMoney(
            total,
            from: currency,
          ),
        ),
      );
    }

    final accommodation =
        prefs.formatMoney(
      breakdown['accommodation'] ?? 0,
      from: currency,
    );

    final food = prefs.formatMoney(
      breakdown['food'] ?? 0,
      from: currency,
    );

    final activities =
        prefs.formatMoney(
      breakdown['activities'] ?? 0,
      from: currency,
    );

    final transportation =
        prefs.formatMoney(
      breakdown['transportation'] ?? 0,
      from: currency,
    );

    return _sectionCard(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          _sectionEyebrow(
            context.tr('details.estimatedCost'),
          ),
          const SizedBox(height: 8),
          _costHeader(
            currency,
            prefs.formatMoney(
              total,
              from: currency,
            ),
          ),
          const SizedBox(height: 20),
          Divider(color: context.triporaColors.border),
          const SizedBox(height: 16),
          _buildCostRow(
            Icons.hotel_outlined,
            context.tr('it.accommodation'),
            accommodation,
          ),
          _buildCostRow(
            Icons.restaurant_outlined,
            context.tr('it.food'),
            food,
          ),
          _buildCostRow(
            Icons.local_activity_outlined,
            context.tr('it.activities'),
            activities,
          ),
          _buildCostRow(
            Icons.directions_car_outlined,
            context.tr('it.transportation'),
            transportation,
          ),
        ],
      ),
    );
  }

  Widget _costHeader(
    String currency,
    String formattedTotal,
  ) {
    return Row(
      crossAxisAlignment:
          CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            context.tr(
              'details.projectedTripSpend',
            ),
            style: TextStyle(
              fontSize: 14,
              color: context.triporaColors.textMuted,
            ),
          ),
        ),
        Text(
          formattedTotal,
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: context.headingColor,
          ),
        ),
      ],
    );
  }

  Widget _buildCostRow(
    IconData icon,
    String label,
    String value,
  ) {
    return Padding(
      padding:
          const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Icon(
            icon,
            size: 19,
            color: context.triporaColors.textMuted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: context.triporaColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.triporaColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInterests() {
    if (_trip.interests.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        _sectionEyebrow(
          context.tr('details.travelInterests'),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _trip.interests.map(
            (interest) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: context.triporaColors.surfaceSecondary,
                  borderRadius:
                      BorderRadius.circular(999),
                  border:
                      Border.all(color: context.triporaColors.border),
                ),
                child: Text(
                  _interestLabel(interest),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.headingColor,
                  ),
                ),
              );
            },
          ).toList(),
        ),
      ],
    );
  }

  Widget _buildItineraryHeader() {
    return Row(
      crossAxisAlignment:
          CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                context
                    .tr('details.yourItinerary')
                    .toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: context.triporaColors.textMuted,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                context.tr(
                  'details.dayByDayJourney',
                ),
                style: TextStyle(
                  fontFamily: 'Noto Serif',
                  fontSize: 27,
                  fontWeight: FontWeight.w600,
                  color: context.triporaColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        if (_trip.itinerary.isNotEmpty)
          Container(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: context.appStatus.info.withValues(
                alpha: 0.08,
              ),
              borderRadius:
                  BorderRadius.circular(999),
            ),
            child: Text(
              _trip.itinerary.length == 1
                  ? context.tr('details.dayCount')
                  : context.tr(
                      'details.dayCountMany',
                      params: {
                        'count':
                            '${_trip.itinerary.length}',
                        'n':
                            '${_trip.itinerary.length}',
                      },
                    ),
              style: TextStyle(
                color: context.appStatus.info,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyItinerary() {
    return _sectionCard(
      child: Column(
        children: [
          Icon(
            Icons.map_outlined,
            size: 32,
            color: context.triporaColors.textMuted,
          ),
          const SizedBox(height: 12),
          Text(
            context.tr(
              'details.noItinerary',
            ),
            style: const TextStyle(
              fontFamily: 'Noto Serif',
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            context.tr(
              'details.regenerateForPlan',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: context.triporaColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayCard(
    Map<String, dynamic> day,
  ) {
    final dayNumber = _getInt(day, 'day');
    final title = _getString(day, 'title');
    final date = _getString(day, 'date');
    final rawActivities = day['activities'];

    final List<Map<String, dynamic>> activities =
        [];

    if (rawActivities is List) {
      for (final activity in rawActivities) {
        if (activity is Map) {
          try {
            activities.add(
              Map<String, dynamic>.from(
                activity,
              ),
            );
          } catch (error) {
            appLog(
              'INVALID ACTIVITY DATA: $error',
            );
          }
        }
      }
    }

    return Container(
      margin:
          const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: context.triporaColors.surface,
        borderRadius:
            BorderRadius.circular(16),
        border: Border.all(
          color: context.triporaColors.border,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x071E1B4B),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding:
            const EdgeInsets.fromLTRB(
          18,
          20,
          18,
          8,
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
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius:
                        BorderRadius.circular(
                      12,
                    ),
                  ),
                  alignment:
                      Alignment.center,
                  child: Text(
                    dayNumber?.toString() ?? '?',
                    style:
                        TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontSize: 15,
                      fontWeight:
                          FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr(
                          'details.dayNumber',
                          params: {
                            'day':
                                '${dayNumber ?? ''}',
                            'n':
                                '${dayNumber ?? ''}',
                          },
                        ),
                        style:
                            TextStyle(
                          fontSize: 10,
                          fontWeight:
                              FontWeight.w700,
                          letterSpacing: 1.2,
                          color: context.appStatus.info,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (title.isNotEmpty)
                        Text(
                          title,
                          style:
                              TextStyle(
                            fontFamily:
                                'Noto Serif',
                            fontSize: 20,
                            fontWeight:
                                FontWeight.w600,
                            color: context.triporaColors.textPrimary,
                          ),
                        ),
                      if (date.isNotEmpty)
                        Padding(
                          padding:
                              const EdgeInsets.only(
                            top: 5,
                          ),
                          child: Text(
                            _formatItineraryDate(
                              date,
                            ),
                            style:
                                TextStyle(
                              fontSize: 12,
                              color: context.triporaColors.textMuted,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (activities.isEmpty)
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(
                  4,
                  0,
                  4,
                  14,
                ),
                child: Text(
                  context.tr(
                    'details.noActivitiesForDay',
                  ),
                  style:
                      TextStyle(
                    fontSize: 13,
                    color: context.triporaColors.textMuted,
                  ),
                ),
              )
            else
              _buildTimeline(activities),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeline(
    List<Map<String, dynamic>> activities,
  ) {
    return Column(
      children: List.generate(
        activities.length,
        (index) {
          final activity =
              activities[index];

          return _buildTimelineActivity(
            activity,
            isLast:
                index == activities.length - 1,
          );
        },
      ),
    );
  }

  Widget _buildTimelineActivity(
    Map<String, dynamic> activity, {
    required bool isLast,
  }) {
    final time =
        _getString(activity, 'time');

    final title =
        _getString(activity, 'title');

    final description =
        _getString(activity, 'description');

    final category =
        _getString(activity, 'category');

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: context.triporaColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: context.appStatus.info,
                      width: 2,
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: context.triporaColors.border,
                      margin:
                          const EdgeInsets.only(
                        top: 4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Container(
              margin:
                  const EdgeInsets.only(
                bottom: 18,
              ),
              padding:
                  const EdgeInsets.fromLTRB(
                14,
                13,
                14,
                14,
              ),
              decoration: BoxDecoration(
                color: context.triporaColors.backgroundColor,
                borderRadius:
                    BorderRadius.circular(
                  12,
                ),
                border: Border.all(
                  color: context.triporaColors.border,
                ),
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _getTimeIconData(time),
                        size: 17,
                        color: context.appStatus.info,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          time.isEmpty
                              ? context
                                  .tr(
                                    'details.activity',
                                  )
                                  .toUpperCase()
                              : time.toUpperCase(),
                          style:
                              TextStyle(
                            fontSize: 10,
                            fontWeight:
                                FontWeight.w700,
                            letterSpacing: 0.8,
                            color: context
                                .triporaColors.textMuted,
                          ),
                        ),
                      ),
                      if (category.isNotEmpty)
                        Container(
                          padding:
                              const EdgeInsets
                                  .symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration:
                              BoxDecoration(
                            color: context
                                .triporaColors.surface,
                            borderRadius:
                                BorderRadius
                                    .circular(
                              999,
                            ),
                            border:
                                Border.all(
                              color: context
                                  .triporaColors.border,
                            ),
                          ),
                          child: Text(
                            category,
                            style:
                                TextStyle(
                              fontSize: 9,
                              fontWeight:
                                  FontWeight.w700,
                              color:
                                  context.headingColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title.isEmpty
                        ? context.tr(
                            'details.activity',
                          )
                        : title,
                    style:
                        TextStyle(
                      fontFamily:
                          'Noto Serif',
                      fontSize: 17,
                      fontWeight:
                          FontWeight.w600,
                      color: context
                          .triporaColors.textPrimary,
                    ),
                  ),
                  if (description
                      .isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      description,
                      style:
                          TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: context
                            .triporaColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getTimeIconData(String time) {
    final lowerTime =
        time.toLowerCase();

    if (lowerTime.contains('morning')) {
      return Icons.wb_sunny_outlined;
    }

    if (lowerTime.contains('afternoon')) {
      return Icons.wb_sunny;
    }

    if (lowerTime.contains('evening')) {
      return Icons.nightlight_outlined;
    }

    return Icons.access_time;
  }

  String _formatItineraryDate(
    String dateString,
  ) {
    final parsed =
        DateTime.tryParse(dateString);

    if (parsed == null) {
      return dateString;
    }

    return _formatDate(parsed);
  }

  Widget _sectionCard({
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.triporaColors.surface,
        borderRadius:
            BorderRadius.circular(16),
        border: Border.all(
          color: context.triporaColors.border,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x071E1B4B),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _sectionEyebrow(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.3,
        color: context.triporaColors.textMuted,
      ),
    );
  }
}

class _DeckItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  _DeckItem(
    this.icon,
    this.title,
    this.subtitle,
    this.onTap,
  );
}