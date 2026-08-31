import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/duffel_service.dart';
import 'premium_gate.dart';

/// Premium flight search screen (live results, display only).
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

  int _passengers = 1;
  String _cabin = 'economy';

  bool _busy = false;
  bool _searched = false;
  String? _error;
  List<Map<String, dynamic>> _flights = [];
  String? _disclaimer;

  @override
  void dispose() {
    _origin.dispose();
    _destination.dispose();
    _depart.dispose();
    _returnCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (!_formKey.currentState!.validate()) return;
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
    } on PremiumRequiredException catch (e) {
      _fail(e.message);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Flight Search')),
      body: PremiumGate(
        builder: (_) => SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildForm(),
                const SizedBox(height: 16),
                if (_error != null)
                  _Banner(text: _error!, color: context.appStatus.error)
                else if (_busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_searched) ...[
                  Text(
                    '${_flights.length} result(s)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: context.triporaColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_flights.isEmpty)
                    const _EmptyState()
                  else
                    ..._flights.map(_FlightCard.new),
                  if (_disclaimer != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _disclaimer!,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: context.triporaColors.textMuted,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: context.triporaColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _origin,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'From (IATA)',
                      hintText: 'JFK',
                      prefixIcon: Icon(Icons.flight_takeoff),
                    ),
                    validator: _iataValidator('origin'),
                  ),
                ),
              ],
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
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _depart,
                    readOnly: true,
                    onTap: () => _pickDate(_depart),
                    decoration: const InputDecoration(
                      labelText: 'Depart date',
                      prefixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _returnCtrl,
                    readOnly: true,
                    onTap: () => _pickDate(_returnCtrl),
                    decoration: const InputDecoration(
                      labelText: 'Return (optional)',
                      prefixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _passengers,
                    decoration: const InputDecoration(
                      labelText: 'Passengers',
                      prefixIcon: Icon(Icons.groups_outlined),
                    ),
                    items: [
                      for (var i = 1; i <= 9; i++)
                        DropdownMenuItem(value: i, child: Text('$i')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _passengers = v);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _cabin,
                    decoration: const InputDecoration(
                      labelText: 'Cabin',
                      prefixIcon: Icon(Icons.airline_seat_recline_extra),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'economy', child: Text('Economy')),
                      DropdownMenuItem(
                        value: 'premium_economy',
                        child: Text('Premium economy'),
                      ),
                      DropdownMenuItem(value: 'business', child: Text('Business')),
                      DropdownMenuItem(value: 'first', child: Text('First')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _cabin = v);
                    },
                  ),
                ),
              ],
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
                label: const Text('Search flights'),
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

  Future<void> _pickDate(TextEditingController controller) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: controller.text.isNotEmpty
          ? (DateTime.tryParse(controller.text) ?? now)
          : now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      controller.text =
          '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
    }
  }
}

class _FlightCard extends StatelessWidget {
  final Map<String, dynamic> flight;

  const _FlightCard(this.flight);

  @override
  Widget build(BuildContext context) {
    final price = flight['price'];
    final money = (price is Map) ? price : <String, dynamic>{};
    final amount = (money['amount'] is num)
        ? (money['amount'] as num).toDouble()
        : 0.0;
    final currency = (money['currency'] ?? 'USD').toString();
    final airline = (flight['airline'] ?? '').toString();
    final segments = (flight['segments'] is List)
        ? (flight['segments'] as List).whereType<Map>().toList()
        : <Map>[];

    String originCode = '';
    String destCode = '';
    String depart = '';
    String arrive = '';
    int stops = 0;
    if (segments.isNotEmpty) {
      final first = Map<String, dynamic>.from(segments.first);
      final depAirport = first['departureAirport'];
      if (depAirport is Map) {
        originCode = (depAirport['code'] ?? '').toString();
      }
      depart = (first['departureTime'] ?? '').toString();
      final last = Map<String, dynamic>.from(segments.last);
      final arrAirport = last['arrivalAirport'];
      if (arrAirport is Map) {
        destCode = (arrAirport['code'] ?? '').toString();
      }
      arrive = (last['arrivalTime'] ?? '').toString();
      stops = (first['stops'] is num) ? (first['stops'] as num).toInt() : 0;
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.triporaColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ExcludeSemantics(
                  child: Icon(Icons.flight, color: context.appStatus.info, size: 20),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    airline.isEmpty ? 'Flight' : airline,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: context.triporaColors.textPrimary,
                    ),
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
            const SizedBox(height: 12),
            Row(
              children: [
                _TimeColumn(code: originCode, time: depart),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        stops == 0 ? 'Direct' : '$stops stop(s)',
                        style: TextStyle(
                          fontSize: 13,
                          color: context.triporaColors.textMuted,
                        ),
                      ),
                      const Divider(height: 20),
                    ],
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

class _TimeColumn extends StatelessWidget {
  final String code;
  final String time;
  final bool alignEnd;

  const _TimeColumn({
    required this.code,
    required this.time,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    final label = time.isEmpty ? '\u2014' : time.replaceFirst('T', ' ');
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          code,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: context.triporaColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: context.triporaColors.textMuted),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          ExcludeSemantics(
            child: Icon(Icons.search_off, size: 40, color: context.triporaColors.textMuted),
          ),
          const SizedBox(height: 10),
          Text(
            'No flights found. Try adjusting your search.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.triporaColors.textMuted),
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
