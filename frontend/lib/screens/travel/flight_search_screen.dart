import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/l10n/app_localizations.dart';
import '../../core/preferences/app_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../services/duffel_service.dart';

/// Flight search screen (live results, display only).
class FlightSearchScreen extends StatefulWidget {
  const FlightSearchScreen({super.key});

  @override
  State<FlightSearchScreen> createState() => _FlightSearchScreenState();
}

class _FlightSearchScreenState extends State<FlightSearchScreen> {
  final DuffelService _service = DuffelService();
  final _formKey = GlobalKey<FormState>();

  final _origin = TextEditingController();
  final _destination = TextEditingController();
  final _depart = TextEditingController();
  final _returnCtrl = TextEditingController();

  // These are canonical values used by the flight API.
  int _passengers = 1;
  String _cabin = 'economy';
  String _dateMode = 'date';

  bool _busy = false;
  bool _searched = false;
  String? _error;
  List<Map<String, dynamic>> _flights = [];
  String? _disclaimer;

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
  static const Color slate500 = Color(0xFF64748B);

  static const Color textSecondary = Color(0xFF47464F);

  static const Color blue = Color(0xFF3B82F6);
  static const Color emerald = Color(0xFF10B981);

  @override
  void dispose() {
    _origin.dispose();
    _destination.dispose();
    _depart.dispose();
    _returnCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  Future<void> _search() async {
    if (!_formKey.currentState!.validate()) return;

    HapticFeedback.lightImpact();

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final results = await _service.searchFlights(
        origin: _origin.text.trim().toUpperCase(),
        destination: _destination.text.trim().toUpperCase(),
        departDate: _depart.text.trim(),
        returnDate: _returnCtrl.text.trim(),
        passengers: _passengers,
        cabinClass: _cabin,
      );

      if (!mounted) return;

      final flights = (results['flights'] is List)
          ? (results['flights'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];

      setState(() {
        _flights = flights;
        _searched = true;
        _disclaimer = results['disclaimer']?.toString();
        _busy = false;
      });
    } catch (e) {
      _fail(
        e.toString().replaceFirst('Exception: ', '').trim(),
      );
    }
  }

  void _fail(String message) {
    if (!mounted) return;

    setState(() {
      _busy = false;
      _error = message;
    });
  }

  // ---------------------------------------------------------------------------
  // Main build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppPreferences.instance,
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: porcelain,
      appBar: _buildAppBar(),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;

          final isMobile = width < 768;
          final isTablet = width >= 768 && width < 1024;

          final horizontalPadding = isMobile
              ? 16.0
              : isTablet
                  ? 24.0
                  : 40.0;

          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: isMobile ? 24 : 36,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 1280,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildIntro(isMobile),

                      SizedBox(
                        height: isMobile ? 24 : 32,
                      ),

                      _buildForm(isMobile),

                      const SizedBox(height: 28),

                      if (_error != null)
                        _Banner(
                          text: _error!,
                          color: context.appStatus.error,
                        )
                      else if (_busy)
                        _buildLoading()
                      else if (_searched)
                        _buildResults(),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // App bar
  // ---------------------------------------------------------------------------

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: porcelain,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 20,
      title: Text(
        context.tr('flights.title'),
        style: GoogleFonts.manrope(
          color: midnight,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Intro
  // ---------------------------------------------------------------------------

  Widget _buildIntro(bool isMobile) {
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: slate100,
              borderRadius: BorderRadius.circular(999),
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
                    Icons.flight_takeoff_rounded,
                    size: 14,
                    color: blue,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    context.tr('flights.flightSearch').toUpperCase(),
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
            context.tr('flights.findNextFlight'),
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
            context.tr('flights.description'),
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
  // Search form
  // ---------------------------------------------------------------------------

  Widget _buildForm(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(
        isMobile ? 20 : 28,
      ),
      decoration: BoxDecoration(
        color: white,
        borderRadius: BorderRadius.circular(16),
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionLabel(
            context.tr('flights.route'),
          ),

          const SizedBox(height: 14),

          if (isMobile) ...[
            _buildTextField(
              controller: _origin,
              label: context.tr('flights.from'),
              hint: context.tr('flights.fromHint'),
              icon: Icons.flight_takeoff_rounded,
              validator: _locationValidator,
            ),

            const SizedBox(height: 14),

            _buildTextField(
              controller: _destination,
              label: context.tr('flights.to'),
              hint: context.tr('flights.toHint'),
              icon: Icons.location_on_outlined,
              validator: _locationValidator,
            ),
          ] else
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _origin,
                    label: context.tr('flights.from'),
                    hint: context.tr('flights.fromHint'),
                    icon: Icons.flight_takeoff_rounded,
                    validator: _locationValidator,
                  ),
                ),

                const SizedBox(width: 14),

                Expanded(
                  child: _buildTextField(
                    controller: _destination,
                    label: context.tr('flights.to'),
                    hint: context.tr('flights.toHint'),
                    icon: Icons.location_on_outlined,
                    validator: _locationValidator,
                  ),
                ),
              ],
            ),

          const SizedBox(height: 24),

          _sectionLabel(
            context.tr('flights.dates'),
          ),

          const SizedBox(height: 14),

          _buildDateModeSelector(),

          const SizedBox(height: 14),

          if (isMobile) ...[
            _buildDateField(
              controller: _depart,
              label: context.tr('flights.departDate'),
              icon: Icons.calendar_today_outlined,
              onTap: _pickDepart,
              validator: (v) =>
                  (v == null || v.trim().isEmpty)
                      ? context.tr('flights.required')
                      : null,
            ),

            const SizedBox(height: 14),

            _buildDateField(
              controller: _returnCtrl,
              label: context.tr('flights.returnDate'),
              icon: Icons.calendar_today_outlined,
              onTap: () => _pickDate(_returnCtrl),
            ),
          ] else
            Row(
              children: [
                Expanded(
                  child: _buildDateField(
                    controller: _depart,
                    label: context.tr('flights.departDate'),
                    icon: Icons.calendar_today_outlined,
                    onTap: _pickDepart,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty)
                            ? context.tr('flights.required')
                            : null,
                  ),
                ),

                const SizedBox(width: 14),

                Expanded(
                  child: _buildDateField(
                    controller: _returnCtrl,
                    label: context.tr('flights.returnDate'),
                    icon: Icons.calendar_today_outlined,
                    onTap: () => _pickDate(_returnCtrl),
                  ),
                ),
              ],
            ),

          const SizedBox(height: 24),

          _sectionLabel(
            context.tr('flights.travelDetails'),
          ),

          const SizedBox(height: 14),

          if (isMobile) ...[
            _buildPassengerDropdown(),
            const SizedBox(height: 14),
            _buildCabinDropdown(),
          ] else
            Row(
              children: [
                Expanded(
                  child: _buildPassengerDropdown(),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _buildCabinDropdown(),
                ),
              ],
            ),

          const SizedBox(height: 24),

          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _busy ? null : _search,
              icon: _busy
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: white,
                      ),
                    )
                  : const Icon(
                      Icons.search_rounded,
                      size: 18,
                    ),
              label: Text(
                _busy
                    ? context.tr('flights.searching')
                    : context.tr('flights.search'),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: midnight,
                foregroundColor: white,
                disabledBackgroundColor: slate300,
                disabledForegroundColor: white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Form components
  // ---------------------------------------------------------------------------

  Widget _sectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: slate500,
        fontSize: 9,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required String? Function(String?) validator,
  }) {
    return TextFormField(
      controller: controller,
      textCapitalization: TextCapitalization.words,
      decoration: _inputDecoration(
        label: label,
        hint: hint,
        icon: icon,
      ),
      validator: validator,
    );
  }

  Widget _buildDateField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      onTap: onTap,
      decoration: _inputDecoration(
        label: label,
        hint: null,
        icon: icon,
      ),
      validator: validator,
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required String? hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(
        icon,
        size: 19,
        color: slate500,
      ),
      filled: true,
      fillColor: porcelain,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 15,
      ),
      labelStyle: const TextStyle(
        color: slate500,
        fontSize: 13,
      ),
      hintStyle: const TextStyle(
        color: slate500,
        fontSize: 13,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(
          color: slate200,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(
          color: slate200,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(
          color: midnight,
          width: 1.4,
        ),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(8),
        ),
        borderSide: BorderSide(
          color: Color(0xFFBA1A1A),
        ),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(8),
        ),
        borderSide: BorderSide(
          color: Color(0xFFBA1A1A),
          width: 1.4,
        ),
      ),
    );
  }

  Widget _buildDateModeSelector() {
    return SegmentedButton<String>(
      segments: [
        ButtonSegment(
          value: 'date',
          label: Text(
            context.tr('flights.exactDate'),
          ),
          icon: const Icon(
            Icons.calendar_today_outlined,
            size: 16,
          ),
        ),
        ButtonSegment(
          value: 'month',
          label: Text(
            context.tr('flights.wholeMonth'),
          ),
          icon: const Icon(
            Icons.date_range_outlined,
            size: 16,
          ),
        ),
      ],
      selected: {_dateMode},
      onSelectionChanged: (selection) {
        setState(() {
          _dateMode = selection.first;
          _depart.clear();
        });
      },
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) {
            if (states.contains(WidgetState.selected)) {
              return white;
            }

            return midnight;
          },
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) {
            if (states.contains(WidgetState.selected)) {
              return midnight;
            }

            return white;
          },
        ),
        side: WidgetStateProperty.all(
          const BorderSide(
            color: slate300,
          ),
        ),
      ),
    );
  }

  Widget _buildPassengerDropdown() {
    return DropdownButtonFormField<int>(
      initialValue: _passengers,
      isExpanded: true,
      decoration: _inputDecoration(
        label: context.tr('flights.passengers'),
        hint: null,
        icon: Icons.groups_outlined,
      ),
      items: [
        for (var i = 1; i <= 9; i++)
          DropdownMenuItem(
            value: i,
            child: Text('$i'),
          ),
      ],
      onChanged: (v) {
        if (v != null) {
          setState(() => _passengers = v);
        }
      },
    );
  }

  Widget _buildCabinDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _cabin,
      isExpanded: true,
      decoration: _inputDecoration(
        label: context.tr('flights.cabin'),
        hint: null,
        icon: Icons.airline_seat_recline_extra,
      ),
      items: [
        DropdownMenuItem(
          value: 'economy',
          child: Text(
            context.tr('flights.economy'),
          ),
        ),
        DropdownMenuItem(
          value: 'premium_economy',
          child: Text(
            context.tr('flights.premiumEconomy'),
          ),
        ),
        DropdownMenuItem(
          value: 'business',
          child: Text(
            context.tr('flights.business'),
          ),
        ),
        DropdownMenuItem(
          value: 'first',
          child: Text(
            context.tr('flights.first'),
          ),
        ),
      ],
      onChanged: (v) {
        if (v != null) {
          setState(() => _cabin = v);
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Results
  // ---------------------------------------------------------------------------

  Widget _buildLoading() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: 32,
      ),
      decoration: BoxDecoration(
        color: white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: slate200,
        ),
      ),
      child: Column(
        children: [
          const CircularProgressIndicator(
            color: midnight,
            strokeWidth: 2.5,
          ),
          const SizedBox(height: 14),
          Text(
            context.tr('flights.searchingForFlights'),
            style: const TextStyle(
              color: slate500,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    final resultWord = _flights.length == 1
        ? context.tr('flights.result')
        : context.tr('flights.results');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context
                        .tr('flights.availableFlights')
                        .toUpperCase(),
                    style: const TextStyle(
                      color: slate500,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_flights.length} $resultWord',
                    style: GoogleFonts.notoSerif(
                      color: midnightDark,
                      fontSize: 27,
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        if (_flights.isEmpty)
          const _EmptyState()
        else
          ..._flights.map(
            (flight) => _FlightCard(flight),
          ),

        if (_disclaimer != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: slate100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: slate200,
              ),
            ),
            child: Text(
              _disclaimer!,
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                color: slate500,
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  String? _locationValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return context.tr('flights.locationRequired');
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Date pickers
  // ---------------------------------------------------------------------------

  Future<void> _pickDate(
    TextEditingController controller,
  ) async {
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: controller.text.isNotEmpty
          ? (DateTime.tryParse(controller.text) ?? now)
          : now,
      firstDate: now,
      lastDate: now.add(
        const Duration(days: 365),
      ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: midnight,
                  surface: white,
                ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      controller.text =
          '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _pickDepart() {
    if (_dateMode == 'month') {
      return _pickMonth(_depart);
    }

    return _pickDate(_depart);
  }

  Future<void> _pickMonth(
    TextEditingController controller,
  ) async {
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(
        now.year,
        now.month,
      ),
      lastDate: now.add(
        const Duration(days: 365),
      ),
      helpText: context.tr(
        'flights.selectTravelMonth',
      ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: midnight,
                  surface: white,
                ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      controller.text =
          '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}';
    }
  }
}

// =============================================================================
// Flight card
// =============================================================================

class _FlightCard extends StatelessWidget {
  final Map<String, dynamic> flight;

  const _FlightCard(this.flight);

  static const Color midnight = Color(0xFF1E1B4B);
  static const Color midnightDark = Color(0xFF070235);
  static const Color white = Color(0xFFFFFFFF);
  static const Color slate100 = Color(0xFFF1F5F9);
  static const Color slate200 = Color(0xFFE2E8F0);
  static const Color slate500 = Color(0xFF64748B);
  static const Color blue = Color(0xFF3B82F6);
  static const Color emerald = Color(0xFF10B981);

  @override
  Widget build(BuildContext context) {
    final price = flight['price'];

    final money = price is Map
        ? price
        : <String, dynamic>{};

    final amount = money['amount'] is num
        ? (money['amount'] as num).toDouble()
        : 0.0;

    // Currency code is API/data, not UI text.
    final currency = (money['currency'] ?? 'USD').toString();

    // Airline name is API/data and should not be translated.
    final airline = (flight['airline'] ?? '').toString();

    final segments = flight['segments'] is List
        ? (flight['segments'] as List)
            .whereType<Map>()
            .toList()
        : <Map>[];

    String originCode = '';
    String destCode = '';
    String depart = '';
    String arrive = '';
    int stops = 0;

    if (segments.isNotEmpty) {
      final first =
          Map<String, dynamic>.from(segments.first);

      final depAirport = first['departureAirport'];

      if (depAirport is Map) {
        originCode =
            (depAirport['code'] ?? '').toString();
      }

      depart =
          (first['departureTime'] ?? '').toString();

      final last =
          Map<String, dynamic>.from(segments.last);

      final arrAirport = last['arrivalAirport'];

      if (arrAirport is Map) {
        destCode =
            (arrAirport['code'] ?? '').toString();
      }

      arrive =
          (last['arrivalTime'] ?? '').toString();

      stops = first['stops'] is num
          ? (first['stops'] as num).toInt()
          : 0;
    }

    return Container(
      margin: const EdgeInsets.only(
        bottom: 16,
      ),
      decoration: BoxDecoration(
        color: white,
        borderRadius: BorderRadius.circular(16),
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
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: midnight,
                    borderRadius:
                        BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.flight_takeoff_rounded,
                    color: white,
                    size: 19,
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        context
                            .tr('flights.airline')
                            .toUpperCase(),
                        style: const TextStyle(
                          color: slate500,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        airline.isEmpty
                            ? context.tr(
                                'flights.flight',
                              )
                            : airline,
                        maxLines: 1,
                        overflow:
                            TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: midnightDark,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                Text(
                  AppPreferences.instance.formatMoney(
                    amount,
                    from: currency,
                  ),
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: midnight,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            const Divider(
              height: 1,
              color: slate200,
            ),

            const SizedBox(height: 20),

            Row(
              children: [
                _TimeColumn(
                  code: originCode,
                  time: depart,
                ),

                Expanded(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 16,
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding:
                              const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: stops == 0
                                ? const Color(
                                    0xFFEAF8F3,
                                  )
                                : slate100,
                            borderRadius:
                                BorderRadius.circular(
                              999,
                            ),
                          ),
                          child: Text(
                            stops == 0
                                ? context
                                    .tr('flights.direct')
                                    .toUpperCase()
                                : context.tr(
                                    'flights.stops',
                                    params: {
                                      'count':
                                          stops.toString(),
                                    },
                                  ).toUpperCase(),
                            style: TextStyle(
                              color: stops == 0
                                  ? emerald
                                  : slate500,
                              fontSize: 9,
                              fontWeight:
                                  FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        const Row(
                          children: [
                            Expanded(
                              child: Divider(
                                color: slate200,
                              ),
                            ),
                            SizedBox(width: 6),
                            Icon(
                              Icons.flight_rounded,
                              size: 15,
                              color: blue,
                            ),
                            SizedBox(width: 6),
                            Expanded(
                              child: Divider(
                                color: slate200,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                _TimeColumn(
                  code: destCode,
                  time: arrive,
                  alignEnd: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Time column
// =============================================================================

class _TimeColumn extends StatelessWidget {
  final String code;
  final String time;
  final bool alignEnd;

  const _TimeColumn({
    required this.code,
    required this.time,
    this.alignEnd = false,
  });

  static const Color midnightDark =
      Color(0xFF070235);

  static const Color slate500 =
      Color(0xFF64748B);

  @override
  Widget build(BuildContext context) {
    final label = time.isEmpty
        ? '\u2014'
        : time.replaceFirst(
            'T',
            ' ',
          );

    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          code.isEmpty ? '\u2014' : code,
          style: GoogleFonts.manrope(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: midnightDark,
          ),
        ),

        const SizedBox(height: 5),

        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: slate500,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Empty state
// =============================================================================

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  static const Color midnight =
      Color(0xFF1E1B4B);

  static const Color midnightDark =
      Color(0xFF070235);

  static const Color white =
      Color(0xFFFFFFFF);

  static const Color slate200 =
      Color(0xFFE2E8F0);

  static const Color slate500 =
      Color(0xFF64748B);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: slate200,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: midnight,
              borderRadius:
                  BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.search_off_rounded,
              size: 27,
              color: white,
            ),
          ),

          const SizedBox(height: 18),

          Text(
            context.tr('flights.noFlights'),
            style: GoogleFonts.notoSerif(
              fontSize: 23,
              fontWeight: FontWeight.w600,
              color: midnightDark,
            ),
          ),

          const SizedBox(height: 7),

          Text(
            context.tr('flights.noFlightsDescription'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: slate500,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Error banner
// =============================================================================

class _Banner extends StatelessWidget {
  final String text;
  final Color color;

  const _Banner({
    required this.text,
    required this.color,
  });

  static const Color white =
      Color(0xFFFFFFFF);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius:
                  BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.info_outline_rounded,
              color: color,
              size: 19,
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}