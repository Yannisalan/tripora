import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/duffel_service.dart';
import 'premium_gate.dart';

/// Premium hotel/stay search screen (live results, display only).
class StaySearchScreen extends StatefulWidget {
  const StaySearchScreen({super.key});

  @override
  State<StaySearchScreen> createState() => _StaySearchScreenState();
}

class _StaySearchScreenState extends State<StaySearchScreen> {
  final DuffelService _service = DuffelService();
  final _formKey = GlobalKey<FormState>();

  final _location = TextEditingController();
  final _checkIn = TextEditingController();
  final _checkOut = TextEditingController();

  int _guests = 2;
  int _rooms = 1;

  bool _busy = false;
  bool _searched = false;
  String? _error;
  List<Map<String, dynamic>> _stays = [];
  String? _disclaimer;

  @override
  void dispose() {
    _location.dispose();
    _checkIn.dispose();
    _checkOut.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final results = await _service.searchStays(
        location: _location.text.trim(),
        checkIn: _checkIn.text.trim(),
        checkOut: _checkOut.text.trim(),
        guests: _guests,
        rooms: _rooms,
      );
      if (!mounted) return;
      final stays = (results['stays'] is List)
          ? (results['stays'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      setState(() {
        _stays = stays;
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
      appBar: AppBar(title: const Text('Hotel Search')),
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
                    '${_stays.length} result(s)',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_stays.isEmpty)
                    const _EmptyState()
                  else
                    ..._stays.map(_StayCard.new),
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
              controller: _location,
              decoration: const InputDecoration(
                labelText: 'Location',
                hintText: 'Paris, France',
                prefixIcon: Icon(Icons.location_city_outlined),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a location' : null,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _checkIn,
                    readOnly: true,
                    onTap: () => _pickDate(_checkIn),
                    decoration: const InputDecoration(
                      labelText: 'Check-in',
                      prefixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _checkOut,
                    readOnly: true,
                    onTap: () => _pickDate(_checkOut),
                    decoration: const InputDecoration(
                      labelText: 'Check-out',
                      prefixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _guests,
                    decoration: const InputDecoration(
                      labelText: 'Guests',
                      prefixIcon: Icon(Icons.groups_outlined),
                    ),
                    items: [
                      for (var i = 1; i <= 10; i++)
                        DropdownMenuItem(value: i, child: Text('$i')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _guests = v);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _rooms,
                    decoration: const InputDecoration(
                      labelText: 'Rooms',
                      prefixIcon: Icon(Icons.bed_outlined),
                    ),
                    items: [
                      for (var i = 1; i <= 5; i++)
                        DropdownMenuItem(value: i, child: Text('$i')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _rooms = v);
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
                label: const Text('Search hotels'),
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

class _StayCard extends StatelessWidget {
  final Map<String, dynamic> stay;

  const _StayCard(this.stay);

  @override
  Widget build(BuildContext context) {
    final price = stay['price'];
    final money = (price is Map) ? price : <String, dynamic>{};
    final amount = (money['amount'] is num)
        ? (money['amount'] as num).toDouble()
        : 0.0;
    final currency = (money['currency'] ?? 'USD').toString();
    final name = (stay['name'] ?? '').toString();
    final city = (stay['city'] ?? '').toString();
    final country = (stay['country'] ?? '').toString();
    final place = [city, country].where((s) => s.isNotEmpty).join(', ');

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
                color: AppColors.secondary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.hotel_outlined,
                color: AppColors.secondary,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? 'Hotel' : name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (place.isNotEmpty)
                    Text(
                      place,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
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
            'No hotels found. Try adjusting your search.',
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
