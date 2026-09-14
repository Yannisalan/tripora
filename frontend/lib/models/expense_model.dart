/// Client-side model for a trip expense.
///
/// Mirrors `backend/models/expense.py`. Shares the same category and
/// currency vocabularies so drop-down options always match what the API
/// accepts.
class ExpenseModel {
  final int? id;
  final int? tripId;
  final double amount;
  final String currency;
  final String category;
  final String description;
  final DateTime date;
  final String paymentMethod;
  final DateTime? createdAt;

  const ExpenseModel({
    this.id,
    this.tripId,
    required this.amount,
    required this.currency,
    required this.category,
    this.description = '',
    required this.date,
    this.paymentMethod = 'other',
    this.createdAt,
  });

  ExpenseModel copyWith({
    double? amount,
    String? currency,
    String? category,
    String? description,
    DateTime? date,
    String? paymentMethod,
  }) {
    return ExpenseModel(
      id: id,
      tripId: tripId,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      category: category ?? this.category,
      description: description ?? this.description,
      date: date ?? this.date,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      createdAt: createdAt,
    );
  }

  factory ExpenseModel.fromJson(Map<String, dynamic> json) {
    final dynamic rawAmount = json['amount'];

    return ExpenseModel(
      id: json['id'] is int
          ? json['id']
          : int.tryParse('${json['id'] ?? ''}'),
      tripId: json['tripId'] is int
          ? json['tripId']
          : int.tryParse('${json['tripId'] ?? ''}'),
      amount: rawAmount is num ? rawAmount.toDouble() : 0.0,
      currency: json['currency']?.toString() ?? 'USD',
      category: json['category']?.toString() ?? 'other',
      description: json['description']?.toString() ?? '',
      date: DateTime.tryParse(
            json['date']?.toString() ?? '',
          ) ??
          DateTime.now(),
      paymentMethod: json['paymentMethod']?.toString() ?? 'other',
      createdAt: DateTime.tryParse(
        json['createdAt']?.toString() ?? '',
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'amount': amount,
      'currency': currency,
      'category': category,
      'description': description,
      'date': date.toIso8601String().split('T').first,
      'paymentMethod': paymentMethod,
    };
  }
}

// ============================================================
// SHARED VOCABULARY (kept in sync with the backend)
// ============================================================

const List<String> expenseCategories = [
  'transport',
  'accommodation',
  'food',
  'activities',
  'shopping',
  'health',
  'other',
];

const List<String> paymentMethods = [
  'cash',
  'card',
  'mobile',
  'other',
];

const List<String> validCurrencies = [
  'USD',
  'EUR',
  'GBP',
  'JPY',
  'CNY',
  'INR',
  'CAD',
  'AUD',
  'CHF',
  'SEK',
  'NOK',
  'DKK',
  'SGD',
  'HKD',
  'NZD',
  'KRW',
  'BRL',
  'MXN',
  'ZAR',
  'AED',
  'SAR',
  'TRY',
];

/// Display label for an expense category.
String expenseCategoryLabel(String category) {
  switch (category.toLowerCase()) {
    case 'transport':
      return 'Transport';
    case 'accommodation':
      return 'Accommodation';
    case 'food':
      return 'Food & Drink';
    case 'activities':
      return 'Activities';
    case 'shopping':
      return 'Shopping';
    case 'health':
      return 'Health';
    default:
      return 'Other';
  }
}

/// Display label for a payment method.
String paymentMethodLabel(String method) {
  switch (method.toLowerCase()) {
    case 'cash':
      return 'Cash';
    case 'card':
      return 'Card';
    case 'mobile':
      return 'Mobile';
    default:
      return 'Other';
  }
}