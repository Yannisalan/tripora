import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/duffel_service.dart';

/// Lets any logged-in user check real flight prices for their trip.
///
/// Prefilled from the generated itinerary (origin/destination/date) and
/// backed by the Travelpayouts price endpoint. No premium paywall here.
class CheckFlightPricesScreen extends StatefulWidget {
  /// Optional prefill: `{origin, destination, departDate}` (IATA + ISO date).
  final Map<String, dynamic>? prefill;

  const CheckFlightPricesScreen({super.key, this.prefill});

  @override
  State<CheckFlightPricesScreen> createState() =>
      _CheckFlightPricesScreenState();
}

class _CheckFlightPricesScreenState extends State<CheckFlightPricesScreen> {
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
    _origin = TextEditingController(text: (p['origin'] ?? '').toString());
    _destination = TextEditingController(
      text: (p['destination'] ?? '').toString(),
    );
    _depart = TextEditingController(text: (p['departDate'] ?? '').toString());
  }

  @override
  void dispose() {
    _origin.dispose();
    _destination.dispose();
    _depart.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final results = await _service.searchFlightPrices(
        origin: _origin.text.trim().toUpperCase(),
        destination: _destination.text.trim().toUpperCase(),
        departDate: _depart.text.trim(),
      );
      if (!mounted) return;
      final list = (results['results'] is List)
          ? (results['results'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : <Map<String, dynamic>>[];
      setState(() {
        _results = list;
        _searched = true;
        _disclaimer = results['disclaimer']?.toString();
        _busy = false;
      });
    } catch (e) {
      _fail(e.toString().replaceFirst('Exception: ', '').trim());
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.triporaColors;
    return Scaffold(
      backgroundColor: colors.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Check Flight Prices',
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
            constraints: const BoxConstraints(maxWidth: 640),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Real-time prices from airline partners. Display only '
                    '- we don\u2019t book flights.',
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
                    _Banner(text: _error!, color: context.appStatus.error)
                  else if (_busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_searched) ...[
                    Text(
                      '${_results.length} price(s)',
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
                      ..._results.map(_PriceCard.new),
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

  Widget _buildForm() {
    final colors = context.triporaColors;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _origin,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'From (IATA)',
                hintText: 'JFK',
                prefixIcon: Icon(Icons.flight_takeoff),
              ),
              validator: _iataValidator('origin'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _destination,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'To (IATA)',
                hintText: 'LHR',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
              validator: _iataValidator('destination'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _depart,
              readOnly: true,
              onTap: () => _pickDate(),
              decoration: const InputDecoration(
                labelText: 'Depart date',
                prefixIcon: Icon(Icons.calendar_today_outlined),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
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
                    : const Icon(Icons.search),
                label: const Text('Check prices'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? Function(String?) _iataValidator(String field) {
    return (v) {
      final value = (v ?? '').trim().toUpperCase();
      if (value.length != 3 || !RegExp(r'^[A-Z]{3}$').hasMatch(value)) {
        return 'Enter a 3-letter IATA code';
      }
      return null;
    };
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(_depart.text) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      _depart.text =
          '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
    }
  }
}

class _PriceCard extends StatelessWidget {
  final Map<String, dynamic> result;

  const _PriceCard(this.result);

  @override
  Widget build(BuildContext context) {
    final colors = context.triporaColors;
    final price = result['price'];
    final money = (price is Map) ? price : <String, dynamic>{};
    final amount = (money['amount'] is num)
        ? (money['amount'] as num).toDouble()
        : 0.0;
    final currency = (money['currency'] ?? 'USD').toString();
    final airline = (result['airline'] ?? '').toString();
    final flightNumber = (result['flightNumber'] ?? '').toString();
    final depart = (result['departureTime'] ?? '').toString();

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.flight, color: context.appStatus.info, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    airline.isEmpty ? 'Flight' : airline,
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
                        '${result['origin'] ?? ''} \u2192 ${result['destination'] ?? ''}',
                      if (depart.isNotEmpty) depart.replaceFirst('T', ' '),
                    ].join('  \u2022  '),
                    style: TextStyle(fontSize: 12, color: colors.textMuted),
                  ),
                ],
              ),
            ),
            Text(
              '$currency${amount.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = context.triporaColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.search_off, size: 40, color: colors.textMuted),
          const SizedBox(height: 10),
          Text(
            'No prices found. Try adjusting your search.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final String text;
  final Color color;

  const _Banner({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(text, style: TextStyle(color: color)),
    );
  }
}
