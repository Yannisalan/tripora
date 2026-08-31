import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../models/subscription_model.dart';
import '../../routes/app_routes.dart';
import '../../services/subscription_service.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/shimmer_loader.dart';

/// Paywall / subscription management screen.
///
/// Shows the user's region-priced premium tier, lists the premium features
/// (flight-price checks and daily weather forecast), and offers an upgrade
/// entry point. Store purchases are gated on real product ids being
/// configured; until then a clearly-labelled development activation path is
/// shown so the flow can be exercised end-to-end.
class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  final SubscriptionService _service = SubscriptionService();

  SubscriptionModel? _subscription;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _message;

  bool get _storeIapConfigured =>
      AppConfig.premiumMonthlyProductId.isNotEmpty ||
      AppConfig.premiumYearlyProductId.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await _service.getStatus();
      if (!mounted) return;
      setState(() {
        _subscription = status;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '').trim();
      });
    }
  }

  Future<void> _activateDev() async {
    setState(() {
      _busy = true;
      _message = null;
      _error = null;
    });
    try {
      final status = await _service.activateDev(days: 3);
      if (!mounted) return;
      setState(() {
        _subscription = status;
        _busy = false;
        _message = 'Premium activated (development/testing).';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '').trim();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tripora Premium')),
      body: _loading
          ? const PremiumScreenShimmer()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null)
                    _Banner(text: _error!, color: context.appStatus.error)
                  else if (_message != null)
                    _Banner(text: _message!, color: context.appStatus.success),
                  const SizedBox(height: 8),
                  _buildHeroCard(),
                  const SizedBox(height: 20),
                  _buildFeatureList(),
                  const SizedBox(height: 20),
                  _buildActionCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildHeroCard() {
    final sub = _subscription;
    final premium = sub?.isPremium ?? false;
    final price = sub != null ? sub.priceLabel : '\u2014';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: context.triporaColors.border),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const ExcludeSemantics(
                    child: Icon(
                      Icons.workspace_premium,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    premium ? 'You are Premium' : 'Upgrade to Premium',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              premium
                  ? 'Ship-shape \u2014 you have full access.'
                  : 'Unlock $price/month in your region',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.95),
                fontSize: 16,
                height: 1.4,
              ),
            ),
            if (sub != null && premium)
              const SizedBox(height: 12),
            if (sub != null && premium && sub.activeUntil != null)
              Text(
                'Active until ${sub.activeUntil!.split('T').first}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 13,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureList() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: context.triporaColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Everything in your region, plus:',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: context.triporaColors.textPrimary,
              ),
            ),
            const SizedBox(height: 14),
            const _FeatureRow(
              icon: Icons.flight_takeoff,
              title: 'Flight price checks',
              subtitle: 'See estimated airfare for your routes before booking.',
            ),
            const SizedBox(height: 14),
            const _FeatureRow(
              icon: Icons.wb_sunny_outlined,
              title: 'Day-to-day weather forecast',
              subtitle: 'Daily outlook for your destination through your trip.',
            ),
            const SizedBox(height: 14),
            const _FeatureRow(
              icon: Icons.travel_explore,
              title: 'Live travel search',
              subtitle: 'Search flights, hotels and rental cars in real time.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard() {
    final premium = _subscription?.isPremium ?? false;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: context.triporaColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (premium) ...[
              OutlinedButton.icon(
                onPressed: _busy ? null : _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh status'),
              ),
              const SizedBox(height: 12),
              GradientButton(
                onPressed: () {
                  Navigator.pushNamed(context, AppRoutes.travel);
                },
                height: 52,
                icon: const Icon(Icons.travel_explore),
                label: const Text('Open Premium Travel'),
              ),
            ] else ...[
              if (!_storeIapConfigured) ...[
                Text(
                  'In-app purchases aren\'t configured yet in this build.',
                  style: TextStyle(color: context.triporaColors.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 12),
                GradientButton(
                  onPressed: _busy ? null : _activateDev,
                  height: 52,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.flash_on),
                  label: const Text('Try premium (development)'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(10),
          ),
          child: ExcludeSemantics(
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: context.triporaColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: context.triporaColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
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
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(text, style: TextStyle(color: color)),
    );
  }
}
