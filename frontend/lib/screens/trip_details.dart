import 'package:flutter/material.dart';
import '../../core/config/app_config.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/preferences/app_preferences.dart';
import '../../core/utils/logger.dart';
import '../../core/theme/app_theme.dart';
import '../../models/trip_model.dart';
import '../../services/trip_service.dart';
import '../../widgets/shimmer_loader.dart';
import 'expenses/expense_tracker_screen.dart';
import 'vault/vault_screen.dart';

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

  static const Color _midnight = Color(0xFF1E1B4B);
  static const Color _midnightDark = Color(0xFF070235);
  static const Color _blue = Color(0xFF3B82F6);
  static const Color _amber = Color(0xFFF59E0B);
  static const Color _emerald = Color(0xFF10B981);
  static const Color _surface = Color(0xFFF8FAFC);
  static const Color _white = Colors.white;
  static const Color _border = Color(0xFFE2E8F0);
  static const Color _slate100 = Color(0xFFF1F5F9);
  static const Color _slate200 = Color(0xFFE2E8F0);
  static const Color _slate300 = Color(0xFFCBD5E1);
  static const Color _slate400 = Color(0xFF94A3B8);
  static const Color _slate500 = Color(0xFF64748B);
  static const Color _slate600 = Color(0xFF475569);
  static const Color _text = Color(0xFF191C1E);

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: _surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 8,
        title: const Text(
          'Trip Details',
          style: TextStyle(
            fontFamily: 'Noto Serif',
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: _midnight,
          ),
        ),
        actions: [
          if (!_isLoading && _errorMessage == null)
            IconButton(
              tooltip: 'Edit trip',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _isSaving || _isRegenerating
                  ? null
                  : _showEditTripSheet,
            ),
          if (!_isLoading && _errorMessage == null)
            IconButton(
              tooltip: 'Regenerate itinerary',
              icon: const Icon(Icons.auto_awesome_outlined),
              color: _blue,
              onPressed: _isSaving || _isRegenerating
                  ? null
                  : _regenerateItinerary,
            ),
          if (!_isLoading && _errorMessage == null)
            IconButton(
              tooltip: 'Refresh',
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
    if (_isLoading && _trip.destination.isEmpty) {
      return const TripDetailsShimmer();
    }

    if (_errorMessage != null && _trip.destination.isEmpty) {
      return _buildErrorState();
    }

    return Stack(
      children: [
        RefreshIndicator(
          color: _midnight,
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
                      constraints: BoxConstraints(maxWidth: maxWidth),
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
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              minHeight: 2,
              color: _blue,
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
                    color: _white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _border),
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
                          color: _blue.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(14),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: _blue,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _isRegenerating
                            ? 'Regenerating itinerary'
                            : 'Saving trip',
                        style: const TextStyle(
                          fontFamily: 'Noto Serif',
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: _midnight,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _isRegenerating
                            ? 'Tripora is creating a fresh AI travel plan.'
                            : 'Updating your saved journey.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: _slate500,
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
        return AlertDialog(
          backgroundColor: _white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Regenerate Itinerary?',
            style: TextStyle(
              fontFamily: 'Noto Serif',
              fontWeight: FontWeight.w600,
              color: _text,
            ),
          ),
          content: const Text(
            'Tripora will replace the current day-by-day itinerary with a fresh AI plan.',
            style: TextStyle(fontSize: 14, height: 1.5, color: _slate600),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _blue,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.auto_awesome_outlined, size: 18),
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

      final message = _extractErrorMessage(error);

      setState(() {
        _isRegenerating = false;
        _errorMessage = message;
      });

      _showMessage(message, isError: true);
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
      backgroundColor: Colors.transparent,
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

            return Container(
              decoration: const BoxDecoration(
                color: _white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                              color: _slate300,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),

                        const SizedBox(height: 22),

                        const Text(
                          'Edit your journey',
                          style: TextStyle(
                            fontFamily: 'Noto Serif',
                            fontSize: 26,
                            fontWeight: FontWeight.w600,
                            color: _midnight,
                          ),
                        ),

                        const SizedBox(height: 6),

                        const Text(
                          'Update the details Tripora uses to shape your itinerary.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: _slate500,
                          ),
                        ),

                        const SizedBox(height: 22),

                        _sheetLabel('DESTINATION'),

                        const SizedBox(height: 7),

                        TextField(
                          controller: destinationController,
                          decoration: _inputDecoration(
                            'Where are you going?',
                            Icons.location_on_outlined,
                          ),
                        ),

                        const SizedBox(height: 18),

                        _sheetLabel('DATES'),

                        const SizedBox(height: 7),

                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => pickDate(isStartDate: true),
                                icon: const Icon(
                                  Icons.calendar_month_outlined,
                                  size: 18,
                                ),
                                label: Text(_formatDate(startDate)),
                                style: _outlinedButtonStyle(),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => pickDate(isStartDate: false),
                                icon: const Icon(
                                  Icons.event_outlined,
                                  size: 18,
                                ),
                                label: Text(_formatDate(endDate)),
                                style: _outlinedButtonStyle(),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 18),

                        _sheetLabel('TRAVELERS'),

                        const SizedBox(height: 7),

                        Container(
                          height: 52,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: _surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _border),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.people_outline,
                                color: _slate500,
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Travelers',
                                  style: TextStyle(fontSize: 14, color: _text),
                                ),
                              ),
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
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
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
                        ),

                        const SizedBox(height: 18),

                        _sheetLabel('BUDGET'),

                        const SizedBox(height: 7),

                        DropdownButtonFormField<String>(
                          initialValue: budget,
                          decoration: _inputDecoration(
                            'Budget',
                            Icons.account_balance_wallet_outlined,
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

                        const SizedBox(height: 18),

                        _sheetLabel('TRAVEL STYLE'),

                        const SizedBox(height: 9),

                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: ['Relaxed', 'Balanced', 'Packed'].map((
                              style,
                              ) {
                            final selected = travelStyle == style;

                            return ChoiceChip(
                              label: Text(style),
                              selected: selected,
                              onSelected: (_) {
                                setSheetState(() {
                                  travelStyle = style;
                                });
                              },
                              selectedColor: _midnight,
                              backgroundColor: _slate100,
                              labelStyle: TextStyle(
                                color: selected ? Colors.white : _midnight,
                                fontWeight: FontWeight.w600,
                              ),
                              side: BorderSide(
                                color: selected ? _midnight : _border,
                              ),
                            );
                          }).toList(),
                        ),

                        const SizedBox(height: 18),

                        _sheetLabel('INTERESTS'),

                        const SizedBox(height: 9),

                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _availableInterests.map((interest) {
                            final selected = selectedInterests.contains(
                              interest,
                            );

                            return FilterChip(
                              label: Text(interest),
                              selected: selected,
                              onSelected: (value) {
                                setSheetState(() {
                                  if (value) {
                                    selectedInterests.add(interest);
                                  } else {
                                    selectedInterests.remove(interest);
                                  }
                                });
                              },
                              selectedColor: _blue,
                              backgroundColor: _slate100,
                              labelStyle: TextStyle(
                                color: selected ? Colors.white : _midnight,
                                fontWeight: FontWeight.w600,
                              ),
                              checkmarkColor: Colors.white,
                              side: BorderSide(
                                color: selected ? _blue : _border,
                              ),
                            );
                          }).toList(),
                        ),

                        const SizedBox(height: 24),

                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: FilledButton.icon(
                            onPressed: submit,
                            icon: const Icon(Icons.save_outlined, size: 19),
                            label: const Text(
                              'Save Changes',
                              style: TextStyle(fontWeight: FontWeight.w600),
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

      _showMessage('Trip updated.');
    } catch (error) {
      if (!mounted) return;

      final message = _extractErrorMessage(error);

      setState(() {
        _isSaving = false;
        _errorMessage = message;
      });

      _showMessage(message, isError: true);
    }
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: _slate500),
      filled: true,
      fillColor: _white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _midnight, width: 1.5),
      ),
    );
  }

  ButtonStyle _outlinedButtonStyle() {
    return OutlinedButton.styleFrom(
      foregroundColor: _midnight,
      minimumSize: const Size(0, 52),
      side: const BorderSide(color: _border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    );
  }

  Widget _sheetLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: _slate500,
      ),
    );
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
              : statusColors?.success ?? _emerald,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: context.appStatus.error.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.error_outline,
                  size: 36,
                  color: context.appStatus.error,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Unable to load trip details',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Noto Serif',
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  color: _text,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _errorMessage ?? 'Something went wrong.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: _slate500,
                ),
              ),
              const SizedBox(height: 26),
              FilledButton.icon(
                onPressed: _loadTripDetails,
                icon: const Icon(Icons.refresh_outlined),
                label: const Text('Try Again'),
                style: FilledButton.styleFrom(
                  backgroundColor: _midnight,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(140, 48),
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
        color: _amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _amber.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_outlined, color: _amber, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Could not refresh: $_errorMessage. '
                  'Showing cached data.',
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
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 30),
      decoration: const BoxDecoration(color: _midnightDark),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth > 1100
              ? 1100.0
              : double.infinity;

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _blue.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: _blue.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 13,
                              color: Color(0xFF93C5FD),
                            ),
                            SizedBox(width: 6),
                            Text(
                              'AI TRAVEL PLAN',
                              style: TextStyle(
                                color: Color(0xFFBFDBFE),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
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
                        _trip.numberOfDays == 1 ? 'DAY' : 'DAYS',
                      ),
                      _heroMetric(
                        '${_trip.travelers}',
                        _trip.travelers == 1 ? 'TRAVELER' : 'TRAVELERS',
                      ),
                      _heroMetric(
                        _trip.budget.isEmpty ? '—' : _trip.budget.toUpperCase(),
                        'BUDGET',
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

  /// Status pill computed from the trip's real start/end dates —
  /// mirrors the "Upcoming in 12 Days" style badge from the mockup.
  Widget _buildStatusPill() {
    final now = DateTime.now();
    String label;
    IconData icon;
    Color color;

    if (now.isBefore(_trip.startDate)) {
      final daysUntil = _trip.startDate.difference(now).inDays;
      label = daysUntil <= 0 ? 'Starting today' : 'Upcoming in $daysUntil days';
      icon = Icons.event_outlined;
      color = _blue;
    } else if (now.isAfter(_trip.endDate)) {
      label = 'Trip completed';
      icon = Icons.check_circle_outline;
      color = _slate400;
    } else {
      label = 'Trip in progress';
      icon = Icons.flight_takeoff_rounded;
      color = _emerald;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
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

  Widget _heroMetric(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionEyebrow('TRIP OVERVIEW'),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 650 ? 4 : 2;

              final items = [
                _overviewItem(
                  Icons.calendar_month_outlined,
                  'Duration',
                  '${_trip.numberOfDays} days',
                ),
                _overviewItem(
                  Icons.people_outline,
                  'Travelers',
                  '${_trip.travelers}',
                ),
                _overviewItem(
                  Icons.account_balance_wallet_outlined,
                  'Budget',
                  _trip.budget.isNotEmpty ? _trip.budget : 'Not specified',
                ),
                _overviewItem(
                  Icons.explore_outlined,
                  'Style',
                  _trip.travelStyle.isNotEmpty
                      ? _trip.travelStyle
                      : 'Not specified',
                ),
              ];

              return GridView.count(
                crossAxisCount: columns,
                crossAxisSpacing: 16,
                mainAxisSpacing: 18,
                childAspectRatio: columns == 4 ? 2.8 : 3.4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: items,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _overviewItem(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: _slate100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 19, color: _midnight),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: _slate500,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _text,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Row of three stat tiles (Budget / Plan Complete / Duration) —
  /// mirrors the mockup's Budget/Weather/Plan row using only real data
  /// (there's no weather source wired up yet, so that tile is omitted
  /// rather than faked).
  Widget _buildStatsRow() {
    final activitiesCount = _trip.itinerary.fold<int>(0, (sum, day) {
      if (day is! Map) return sum;
      final acts = day['activities'];
      return sum + (acts is List ? acts.length : 0);
    });

    final expectedActivities = _trip.numberOfDays * 3; // rough baseline
    final planPercent = expectedActivities == 0
        ? 0.0
        : (activitiesCount / expectedActivities).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 500;

        final tiles = [
          _statTile(
            label: context.tr('details.budget'),
            value: _trip.budget.isEmpty ? '—' : _trip.budget,
            icon: Icons.account_balance_wallet_outlined,
          ),
          _statTile(
            label: context.tr('details.planComplete'),
            value: '${(planPercent * 100).round()}%',
            icon: Icons.map_outlined,
            progress: planPercent,
          ),
          _statTile(
            label: context.tr('details.duration'),
            value:
                '${_trip.numberOfDays} ${_trip.numberOfDays == 1 ? 'day' : 'days'}',
            icon: Icons.schedule_outlined,
          ),
        ];

        if (isNarrow) {
          return Column(
            children: tiles
                .map(
                  (t) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: t,
              ),
            )
                .toList(),
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: tiles
              .map(
                (t) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: t,
              ),
            ),
          )
              .toList(),
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: _slate500),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: _slate500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _midnight,
            ),
          ),
          if (progress != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: _slate100,
                color: _blue,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// "Command deck" grid. Activities, Expenses, and Vault route
  /// to real functionality already in this screen/app. Hotels and Packing
  /// tiles are intentionally absent from the deck — hotels shipping remains
  /// gated behind [AppConfig.hotelFeatureEnabled] and packing was removed
  /// entirely.
  Widget _buildCommandDeck() {
    final totalActivities = _trip.itinerary.fold<int>(0, (sum, day) {
      if (day is! Map) return sum;
      final acts = day['activities'];
      return sum + (acts is List ? acts.length : 0);
    });

    final items = <_DeckItem>[
      _DeckItem(
        Icons.local_activity_outlined,
        context.tr('details.activities'),
        context.tr('details.activitiesPlanned')
            .replaceFirst('{n}', '$totalActivities'),
        _showActivitiesSheet,
      ),
      _DeckItem(
        Icons.account_balance_wallet_outlined,
        context.tr('details.expenses'),
        context.tr('details.trackSpending'),
        _openExpenseTracker,
      ),
      _DeckItem(
        Icons.folder_outlined,
        context.tr('details.vault'),
        context.tr('details.tripDocuments'),
            _openVault,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionEyebrow(context.tr('details.commandDeck')),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.0,
          children: items.map((item) => _deckTile(item)).toList(),
        ),
      ],
    );
  }

  Widget _deckTile(_DeckItem item) {
    return Material(
      color: _white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: item.onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _slate100,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(item.icon, size: 17, color: _midnight),
              ),
              const Spacer(),
              Text(
                item.title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: _slate500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens the trip's document Vault (board passes, confirmations, ...).
  void _openVault() {
    final tripId = _trip.id;

    if (tripId == null) {
      _showMessage('This trip cannot open its vault yet.');
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VaultScreen(
          tripId: tripId,
          tripDestination: _trip.destination,
        ),
      ),
    );
  }

  /// Opens the trip's expense tracker.
  void _openExpenseTracker() {
    final tripId = _trip.id;

    if (tripId == null) {
      _showMessage('This trip cannot track expenses yet.');
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExpenseTrackerScreen(trip: _trip),
      ),
    );
  }

  /// Bottom sheet listing every activity across all itinerary days,
  /// grouped by day, using the trip's real itinerary data.
  void _showActivitiesSheet() {
    final dayEntries = <MapEntry<int, List<Map<String, dynamic>>>>[];

    for (final rawDay in _trip.itinerary) {
      if (rawDay is! Map) continue;

      Map<String, dynamic> day;
      try {
        day = Map<String, dynamic>.from(rawDay);
      } catch (_) {
        continue;
      }

      final dayNumber = _getInt(day, 'day') ?? (dayEntries.length + 1);
      final rawActivities = day['activities'];
      final activities = <Map<String, dynamic>>[];

      if (rawActivities is List) {
        for (final activity in rawActivities) {
          if (activity is Map) {
            try {
              activities.add(Map<String, dynamic>.from(activity));
            } catch (_) {}
          }
        }
      }

      if (activities.isNotEmpty) {
        dayEntries.add(MapEntry(dayNumber, activities));
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
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: _white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _slate300,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'All Activities',
                            style: TextStyle(
                              fontFamily: 'Noto Serif',
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              color: _midnight,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: dayEntries.isEmpty
                        ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No activities available yet.',
                          style: TextStyle(color: _slate500),
                        ),
                      ),
                    )
                        : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      itemCount: dayEntries.length,
                      itemBuilder: (context, index) {
                        final entry = dayEntries[index];

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [
                              Text(
                                'DAY ${entry.key}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.1,
                                  color: _blue,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...entry.value.map((activity) {
                                final title = _getString(
                                  activity,
                                  'title',
                                );
                                final time = _getString(
                                  activity,
                                  'time',
                                );
                                final category = _getString(
                                  activity,
                                  'category',
                                );

                                return Container(
                                  margin: const EdgeInsets.only(
                                    bottom: 8,
                                  ),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: _surface,
                                    borderRadius:
                                    BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _border,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        _getTimeIconData(time),
                                        size: 16,
                                        color: _blue,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          title.isEmpty
                                              ? 'Activity'
                                              : title,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight:
                                            FontWeight.w600,
                                            color: _text,
                                          ),
                                        ),
                                      ),
                                      if (category.isNotEmpty)
                                        Text(
                                          category,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight:
                                            FontWeight.w700,
                                            color: _slate500,
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              }),
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
    final currency = cost['currency']?.toString() ?? 'USD';
    final total = cost['estimatedTotal'] ?? cost['estimated_total'] ?? 0;

    final prefs = AppPreferences.instance;

    if (breakdown is! Map) {
      return _sectionCard(
        child: _costHeader(currency, prefs.formatMoney(total, from: currency)),
      );
    }

    final accommodation =
        prefs.formatMoney(breakdown['accommodation'] ?? 0, from: currency);
    final food =
        prefs.formatMoney(breakdown['food'] ?? 0, from: currency);
    final activities =
        prefs.formatMoney(breakdown['activities'] ?? 0, from: currency);
    final transportation =
        prefs.formatMoney(breakdown['transportation'] ?? 0, from: currency);

    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionEyebrow(context.tr('details.estimatedCost')),
          const SizedBox(height: 8),
          _costHeader(
            currency,
            prefs.formatMoney(total, from: currency),
          ),
          const SizedBox(height: 20),
          const Divider(color: _border),
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

  Widget _costHeader(String currency, String formattedTotal) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            context.tr('details.projectedTripSpend'),
            style: const TextStyle(fontSize: 14, color: _slate500),
          ),
        ),
        Text(
          formattedTotal,
          style: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: _midnight,
          ),
        ),
      ],
    );
  }

  Widget _buildCostRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Icon(icon, size: 19, color: _slate500),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, color: _slate600),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _text,
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionEyebrow('TRAVEL INTERESTS'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _trip.interests.map((interest) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _slate100,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _border),
              ),
              child: Text(
                interest,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _midnight,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildItineraryHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'YOUR ITINERARY',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: _slate500,
                ),
              ),
              SizedBox(height: 5),
              Text(
                'A day-by-day journey',
                style: TextStyle(
                  fontFamily: 'Noto Serif',
                  fontSize: 27,
                  fontWeight: FontWeight.w600,
                  color: _text,
                ),
              ),
            ],
          ),
        ),
        if (_trip.itinerary.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${_trip.itinerary.length} '
                  '${_trip.itinerary.length == 1 ? 'DAY' : 'DAYS'}',
              style: const TextStyle(
                color: _blue,
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
          const Icon(Icons.map_outlined, size: 32, color: _slate400),
          const SizedBox(height: 12),
          const Text(
            'No itinerary available.',
            style: TextStyle(
              fontFamily: 'Noto Serif',
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Regenerate the itinerary to create a fresh AI travel plan.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: _slate500),
          ),
        ],
      ),
    );
  }

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

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x071E1B4B),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _midnight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    dayNumber?.toString() ?? '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DAY ${dayNumber ?? ''}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: _blue,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (title.isNotEmpty)
                        Text(
                          title,
                          style: const TextStyle(
                            fontFamily: 'Noto Serif',
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: _text,
                          ),
                        ),
                      if (date.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            _formatItineraryDate(date),
                            style: const TextStyle(
                              fontSize: 12,
                              color: _slate500,
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
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
                child: Text(
                  'No activities available for this day.',
                  style: const TextStyle(fontSize: 13, color: _slate500),
                ),
              )
            else
              _buildTimeline(activities),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeline(List<Map<String, dynamic>> activities) {
    return Column(
      children: List.generate(activities.length, (index) {
        final activity = activities[index];

        return _buildTimelineActivity(
          activity,
          isLast: index == activities.length - 1,
        );
      }),
    );
  }

  Widget _buildTimelineActivity(
      Map<String, dynamic> activity, {
        required bool isLast,
      }) {
    final time = _getString(activity, 'time');
    final title = _getString(activity, 'title');
    final description = _getString(activity, 'description');
    final category = _getString(activity, 'category');

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _white,
                    shape: BoxShape.circle,
                    border: Border.all(color: _blue, width: 2),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: _slate200,
                      margin: const EdgeInsets.only(top: 4),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 4),

          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 18),
              padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_getTimeIconData(time), size: 17, color: _blue),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          time.isEmpty ? 'ACTIVITY' : time.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: _slate500,
                          ),
                        ),
                      ),
                      if (category.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: _border),
                          ),
                          child: Text(
                            category,
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: _midnight,
                            ),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  Text(
                    title.isEmpty ? 'Activity' : title,
                    style: const TextStyle(
                      fontFamily: 'Noto Serif',
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: _text,
                    ),
                  ),

                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: _slate600,
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
    final lowerTime = time.toLowerCase();

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

  String _formatItineraryDate(String dateString) {
    final parsed = DateTime.tryParse(dateString);

    if (parsed == null) {
      return dateString;
    }

    return _formatDate(parsed);
  }

  Widget _sectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
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
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.3,
        color: _slate500,
      ),
    );
  }
}

/// Simple data holder for a tile in the "Trip Command Deck" grid.
class _DeckItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  _DeckItem(this.icon, this.title, this.subtitle, this.onTap);
}