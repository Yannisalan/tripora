import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/duffel_service.dart';
import 'premium_gate.dart';

/// Premium car rental search screen (live results, display only).
class CarSearchScreen extends StatefulWidget {
  const CarSearchScreen({super.key});

  @override
  State<CarSearchScreen> createState() => _CarSearchScreenState();
}

class _CarSearchScreenState extends State<CarSearchScreen> {
  final DuffelService _service = DuffelService();
  final _formKey = GlobalKey<FormState>();

  final _pickup = TextEditingController();
  final _dropoff = TextEditingController();
  final _pickupDate = TextEditingController();
  final _pickupTime = TextEditingController();
  final _dropoffDate = TextEditingController();
  final _dropoffTime = TextEditingController();

  int _driverAge = 30;

  bool _busy = false;
  bool _searched = false;
  String? _error;
  List<Map<String, dynamic>> _cars = [];
  String? _disclaimer;

  @override
  void dispose() {
    _pickup.dispose();
    _dropoff.dispose();
    _pickupDate.dispose();
    _pickupTime.dispose();
    _dropoffDate.dispose();
    _dropoffTime.dispose();
    super.dispose();
  }

  String _isoDateTime(String date, String time) {
    final d = date.trim();
    final t = time.trim().isEmpty ? '10:00' : time.trim();
    return '${d}T${t.length == 4 ? '0$t' : t}:00';
  }
  Future<void> _search() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final results = await _service.searchCars(
        pickup: _pickup.text.trim(),
        dropoff: _dropoff.text.trim(),
        pickupDateTime: _isoDateTime(_pickupDate.text, _pickupTime.text),
        dropoffDateTime: _isoDateTime(_dropoffDate.text, _dropoffTime.text),
        driverAge: _driverAge,
      );
      if (!mounted) return;
      final cars = (results['cars'] is List)
          ? (results['cars'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      setState(() {
        _cars = cars;
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
      appBar: AppBar(title: const Text('Car Search')),
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
                  _Banner(text: _error!, color: Colors.red)
                else if (_busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_searched) ...[
                  Text(
                    '${_cars.length} result(s)',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_cars.isEmpty)
                    const _EmptyState()
                  else
                    ..._cars.map(_CarCard.new),
                  if (_disclaimer != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _disclaimer!,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: AppColors.textMuted,
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
        side: BorderSide(color: const Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _pickup,
              decoration: const InputDecoration(
                labelText: 'Pick-up (IATA or city)',
                hintText: 'LHR',
                prefixIcon: Icon(Icons.trip_origin),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _dropoff,
              decoration: const InputDecoration(
                labelText: 'Drop-off (IATA or city)',
                hintText: 'CDG',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            Text(
              'Pick-up',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _pickupDate,
                    readOnly: true,
                    onTap: () => _pickDate(_pickupDate),
                    decoration: const InputDecoration(
                      labelText: 'Date',
                      prefixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _pickupTime,
                    decoration: const InputDecoration(
                      labelText: 'Time (HH:MM)',
                      hintText: '10:00',
                      prefixIcon: Icon(Icons.schedule),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Drop-off',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _dropoffDate,
                    readOnly: true,
                    onTap: () => _pickDate(_dropoffDate),
                    decoration: const InputDecoration(
                      labelText: 'Date',
                      prefixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _dropoffTime,
                    decoration: const InputDecoration(
                      labelText: 'Time (HH:MM)',
                      hintText: '18:00',
                      prefixIcon: Icon(Icons.schedule),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<int>(
              initialValue: _driverAge,
              decoration: const InputDecoration(
                labelText: 'Driver age',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              items: [
                for (var age = 18; age <= 75; age += 5)
                  DropdownMenuItem(value: age, child: Text('$age')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _driverAge = v);
              },
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
                label: const Text('Search cars'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year, now.month, now.day),
      firstDate: DateTime(now.year, now.month, now.day),
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

class _CarCard extends StatelessWidget {
  final Map<String, dynamic> car;

  const _CarCard(this.car);

  @override
  Widget build(BuildContext context) {
    final price = car['price'];
    final money = (price is Map) ? price : <String, dynamic>{};
    final amount = (money['amount'] is num)
        ? (money['amount'] as num).toDouble()
        : 0.0;
    final currency = (money['currency'] ?? 'USD').toString();
    final name = (car['name'] ?? '').toString();
    final make = (car['make'] ?? '').toString();
    final carType = (car['carType'] ?? '').toString();
    final transmission = (car['transmission'] ?? '').toString();
    final details = [carType, transmission].where((s) => s.isNotEmpty).join(' · ');

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: const Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.tertiary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.directions_car_outlined,
                color: AppColors.tertiary,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? (make.isEmpty ? 'Car' : make) : name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      details,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    '$currency${amount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
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
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.search_off, size: 40, color: AppColors.textMuted),
          SizedBox(height: 10),
          Text(
            'No cars found. Try adjusting your search.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final String text;
  final MaterialColor color;

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
      child: Text(text, style: TextStyle(color: color.shade700)),
    );
  }
}
