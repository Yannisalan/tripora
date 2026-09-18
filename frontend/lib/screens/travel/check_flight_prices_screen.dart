import 'package:flutter/material.dart';

import '../../core/l10n/app_localizations.dart';
import '../../core/preferences/app_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../services/duffel_service.dart';

/// Lets any logged-in user check real flight prices for their trip.
///
/// Prefilled from the generated itinerary (origin/destination/date) and
/// backed by the Travelpayouts price endpoint.
class CheckFlightPricesScreen extends StatefulWidget {
  /// Optional prefill: `{origin, destination, departDate}` (IATA + ISO date).
  final Map<String, dynamic>? prefill;

  const CheckFlightPricesScreen({
    super.key,
    this.prefill,
  });

  @override
  State<CheckFlightPricesScreen> createState() =>
      _CheckFlightPricesScreenState();
}

class _CheckFlightPricesScreenState
    extends State<CheckFlightPricesScreen> {
  final DuffelService _service = DuffelService();
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _origin;
  late final TextEditingController _destination;
  late final TextEditingController _depart;

  bool _busy = false;
  bool _searched = false;
  String? _error;
  List<Map<String, dynamic>> _results = [];
  String? _disclaimer;

  @override
  void initState() {
    super.initState();

    final p = widget.prefill ?? const <String, dynamic>{};

    _origin = TextEditingController(
      text: (p['origin'] ?? '').toString(),
    );

    _destination = TextEditingController(
      text: (p['destination'] ?? '').toString(),
    );

    _depart = TextEditingController(
      text: (p['departDate'] ?? '').toString(),
    );
  }

  @override
  void dispose() {
    _origin.dispose();
    _destination.dispose();
    _depart.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  Future<void> _search() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final results = await _service.searchFlightPrices(
        origin: _origin.text.trim(),
        destination: _destination.text.trim(),
        departDate: _depart.text.trim(),
      );

      if (!mounted) return;

      final list = (results['results'] is List)
          ? (results['results'] as List)
              .whereType<Map>()
              .map(
                (e) => Map<String, dynamic>.from(e),
              )
              .toList()
          : <Map<String, dynamic>>[];

      setState(() {
        _results = list;
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
    final colors = context.triporaColors;

    return Scaffold(
      backgroundColor: colors.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          context.tr('flightPrices.title'),
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: colors.textPrimary,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 640,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.tr('flightPrices.description'),
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: colors.textSecondary,
                    ),
                  ),

                  const SizedBox(height: 18),

                  _buildForm(),

                  const SizedBox(height: 16),

                  if (_error != null)
                    _Banner(
                      text: _error!,
                      color: context.appStatus.error,
                    )
                  else if (_busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: 24,
                      ),
                      child: Center(
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_searched) ...[
                    Text(
                      _results.length == 1
                          ? context.tr(
                              'flightPrices.resultOne',
                            )
                          : context.tr(
                              'flightPrices.resultMany',
                              params: {
                                'count':
                                    _results.length.toString(),
                              },
                            ),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: colors.textPrimary,
                      ),
                    ),

                    const SizedBox(height: 12),

                    if (_results.isEmpty)
                      const _EmptyState()
                    else
                      ..._results.map(
                        _PriceCard.new,
                      ),

                    if (_disclaimer != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _disclaimer!,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Search form
  // ---------------------------------------------------------------------------

  Widget _buildForm() {
    final colors = context.triporaColors;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: colors.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _origin,
              textCapitalization:
                  TextCapitalization.words,
              decoration: InputDecoration(
                labelText: context.tr(
                  'flightPrices.from',
                ),
                hintText: context.tr(
                  'flightPrices.fromHint',
                ),
                prefixIcon: const Icon(
                  Icons.flight_takeoff,
                ),
              ),
              validator: _placeValidator(),
            ),

            const SizedBox(height: 14),

            TextFormField(
              controller: _destination,
              textCapitalization:
                  TextCapitalization.words,
              decoration: InputDecoration(
                labelText: context.tr(
                  'flightPrices.to',
                ),
                hintText: context.tr(
                  'flightPrices.toHint',
                ),
                prefixIcon: const Icon(
                  Icons.location_on_outlined,
                ),
              ),
              validator: _placeValidator(),
            ),

            const SizedBox(height: 14),

            TextFormField(
              controller: _depart,
              readOnly: true,
              onTap: _pickDate,
              decoration: InputDecoration(
                labelText: context.tr(
                  'flightPrices.departDate',
                ),
                prefixIcon: const Icon(
                  Icons.calendar_today_outlined,
                ),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty)
                      ? context.tr(
                          'flightPrices.required',
                        )
                      : null,
            ),

            const SizedBox(height: 18),

            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _busy ? null : _search,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.search,
                      ),
                label: Text(
                  _busy
                      ? context.tr(
                          'flightPrices.checking',
                        )
                      : context.tr(
                          'flightPrices.checkPrices',
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  String? Function(String?) _placeValidator() {
    return (v) {
      final value = (v ?? '').trim();

      if (value.isEmpty) {
        return context.tr(
          'flightPrices.locationRequired',
        );
      }

      return null;
    };
  }

  // ---------------------------------------------------------------------------
  // Date picker
  // ---------------------------------------------------------------------------

  Future<void> _pickDate() async {
    final now = DateTime.now();

    final initial =
        DateTime.tryParse(_depart.text) ?? now;

    final safeInitial =
        initial.isBefore(now) ? now : initial;

    final picked = await showDatePicker(
      context: context,
      initialDate: safeInitial,
      firstDate: now,
      lastDate: now.add(
        const Duration(days: 365),
      ),
    );

    if (picked != null) {
      _depart.text =
          '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
    }
  }
}

// =============================================================================
// Price card
// =============================================================================

class _PriceCard extends StatelessWidget {
  final Map<String, dynamic> result;

  const _PriceCard(this.result);

  @override
  Widget build(BuildContext context) {
    final colors = context.triporaColors;

    final price = result['price'];

    final money = price is Map
        ? price
        : <String, dynamic>{};

    final amount = money['amount'] is num
        ? (money['amount'] as num).toDouble()
        : 0.0;

    // Currency is API data.
    final currency =
        (money['currency'] ?? 'USD').toString();

    // Airline and flight number are API data.
    final airline =
        (result['airline'] ?? '').toString();

    final flightNumber =
        (result['flightNumber'] ?? '').toString();

    final depart =
        (result['departureTime'] ?? '').toString();

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(
        bottom: 12,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colors.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.flight,
              color: context.appStatus.info,
              size: 20,
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    airline.isEmpty
                        ? context.tr(
                            'flightPrices.flight',
                          )
                        : airline,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    [
                      if (flightNumber.isNotEmpty)
                        flightNumber
                      else
                        '${result['origin'] ?? ''} → '
                        '${result['destination'] ?? ''}',
                      if (depart.isNotEmpty)
                        depart.replaceFirst(
                          'T',
                          ' ',
                        ),
                    ].join('  •  '),
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),

            Text(
              AppPreferences.instance.formatMoney(
                amount,
                from: currency,
              ),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Theme.of(context)
                    .colorScheme
                    .primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Empty state
// =============================================================================

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = context.triporaColors;

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 24,
      ),
      child: Column(
        children: [
          Icon(
            Icons.search_off,
            size: 40,
            color: colors.textMuted,
          ),

          const SizedBox(height: 10),

          Text(
            context.tr('flightPrices.noPrices'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textMuted,
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

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: 0.1,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(
            alpha: 0.4,
          ),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
        ),
      ),
    );
  }
}