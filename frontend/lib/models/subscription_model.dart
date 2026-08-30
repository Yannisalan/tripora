import 'package:flutter/foundation.dart';

/// Server-reported premium subscription status for the current user.
///
/// ``isPremium`` is authoritative (server-enforced); everything else is
/// metadata used to render the paywall with the correct regional price.
@immutable
class SubscriptionModel {
  final bool isPremium;
  final String tier;
  final String tierLabel;
  final double price;
  final String currency;
  final String period;
  final String? activeUntil;
  final String? store;

  const SubscriptionModel({
    required this.isPremium,
    required this.tier,
    required this.tierLabel,
    required this.price,
    required this.currency,
    required this.period,
    this.activeUntil,
    this.store,
  });

  factory SubscriptionModel.fromJson(Map<String, dynamic> json) {
    return SubscriptionModel(
      isPremium: (json['isPremium'] ?? false) == true,
      tier: (json['tier'] ?? 'tier_1').toString(),
      tierLabel: (json['tierLabel'] ?? 'Starter').toString(),
      price: (json['price'] is num)
          ? (json['price'] as num).toDouble()
          : 0,
      currency: (json['currency'] ?? 'USD').toString(),
      period: (json['period'] ?? 'monthly').toString(),
      activeUntil: json['activeUntil']?.toString(),
      store: json['store']?.toString(),
    );
  }

  /// Price rendered with its currency symbol (best-effort for common codes).
  String get priceLabel {
    const symbols = {
      'USD': r'$',
      'EUR': '€',
      'GBP': '£',
      'CAD': r'$',
      'AUD': r'$',
      'AED': 'AED ',
      'JPY': '¥',
      'CHF': 'CHF ',
    };
    final symbol = symbols[currency] ?? '$currency ';
    return '$symbol${price.toStringAsFixed(2)}';
  }

  @override
  String toString() =>
      'SubscriptionModel(premium: $isPremium, tier: $tier, price: $currency$price)';
}
