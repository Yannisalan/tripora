import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../routes/app_routes.dart';
import '../../services/subscription_service.dart';
import '../../widgets/gradient_button.dart';

/// Wraps a premium-only travel screen and enforces the upgrade flow.
///
/// On load it fetches the user's subscription status from the backend (the
/// authoritative source). While loading it shows a spinner; if the user is not
/// premium it renders a paywall prompt that routes to the Premium screen. Once
/// premium, it shows [child] and optionally re-checks after a rebuild.
class PremiumGate extends StatefulWidget {
  /// The premium-only content to show once verified.
  final Widget Function(BuildContext context) builder;

  const PremiumGate({super.key, required this.builder});

  @override
  State<PremiumGate> createState() => _PremiumGateState();
}

class _PremiumGateState extends State<PremiumGate> {
  final SubscriptionService _service = SubscriptionService();

  bool _loading = true;
  bool _premium = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _loading = true);
    try {
      final status = await _service.getStatus();
      if (!mounted) return;
      setState(() {
        _premium = status.isPremium;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _premium = false;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_premium) {
      return widget.builder(context);
    }
    return _Paywall(onRetry: _check);
  }
}

class _Paywall extends StatelessWidget {
  final VoidCallback onRetry;

  const _Paywall({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Column(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      color: Colors.white,
                      size: 48,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Premium Travel',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Live flight, hotel and car search is part of '
                      'Tripora Premium.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: context.triporaColors.border),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Upgrade to unlock',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: context.triporaColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Search flights, hotels and rental cars from '
                        'your region\'s premium price with live results.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: context.triporaColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              GradientButton(
                height: 52,
                label: const Text('View Premium'),
                onPressed: () {
                  Navigator.pushNamed(context, AppRoutes.premium);
                },
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
