import 'dart:convert';

class TripModel {
  final int? id;

  final String destination;
  final DateTime startDate;
  final DateTime endDate;

  final int travelers;

  final String budget;
  final String travelStyle;

  final List<String> interests;

  final List<dynamic> itinerary;

  final Map<String, dynamic>? estimatedCost;

  final DateTime? createdAt;

  const TripModel({
    this.id,
    required this.destination,
    required this.startDate,
    required this.endDate,
    required this.travelers,
    required this.budget,
    required this.travelStyle,
    required this.interests,
    this.itinerary = const [],
    this.estimatedCost,
    this.createdAt,
  });

  // ============================================================
  // NUMBER OF DAYS
  // ============================================================

  int get numberOfDays {
    final start = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
    );

    final end = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
    );

    return end.difference(start).inDays + 1;
  }

  // ============================================================
  // FORMAT DATE FOR API
  // ============================================================

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  // ============================================================
  // CONVERT TO JSON
  // ============================================================

  Map<String, dynamic> toJson() {
    return {
      'destination': destination,
      'startDate': _formatDate(startDate),
      'endDate': _formatDate(endDate),
      'travelers': travelers,
      'budget': budget,
      'travelStyle': travelStyle,
      'interests': interests,
    };
  }

  // ============================================================
  // CONVERT TO DETAIL MAP (for ItineraryScreen / routes)
  // ============================================================

  Map<String, dynamic> toDetailMap() {
    return {
      'id': id,
      'destination': destination,
      'startDate': _formatDate(startDate),
      'endDate': _formatDate(endDate),
      'travelers': travelers,
      'budget': budget,
      'travelStyle': travelStyle,
      'interests': interests,
      'itinerary': itinerary,
      'estimatedCost': estimatedCost,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  // ============================================================
  // PARSE HELPERS
  // ============================================================

  static List<String> _parseInterests(dynamic rawInterests) {
    if (rawInterests is List) {
      return rawInterests
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList();
    }

    if (rawInterests is String && rawInterests.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawInterests);

        if (decoded is List) {
          return decoded
              .map((item) => item.toString())
              .where((item) => item.isNotEmpty)
              .toList();
        }
      } catch (_) {
        return [rawInterests];
      }
    }

    return [];
  }

  static List<dynamic> _parseItinerary(dynamic rawItinerary) {
    if (rawItinerary is List) {
      return List<dynamic>.from(rawItinerary);
    }

    if (rawItinerary is String && rawItinerary.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawItinerary);

        if (decoded is List) {
          return List<dynamic>.from(decoded);
        }
      } catch (_) {
        return [];
      }
    }

    return [];
  }

  static Map<String, dynamic>? _parseEstimatedCost(
    dynamic rawEstimatedCost,
  ) {
    if (rawEstimatedCost is! Map) {
      return null;
    }

    final cost = Map<String, dynamic>.from(rawEstimatedCost);

    if (cost['estimatedTotal'] == null &&
        cost['estimated_total'] != null) {
      cost['estimatedTotal'] = cost['estimated_total'];
    }

    final breakdown = cost['breakdown'];

    if (breakdown is Map) {
      cost['breakdown'] = Map<String, dynamic>.from(breakdown);
    }

    return cost;
  }

  // ============================================================
  // CREATE FROM JSON
  // ============================================================

  factory TripModel.fromJson(Map<String, dynamic> json) {
    // ----------------------------------------------------------
    // ID
    // ----------------------------------------------------------

    final dynamic rawId =
        json['id'] ?? json['tripId'];

    final int? parsedId = rawId is int
        ? rawId
        : int.tryParse(
            rawId?.toString() ?? '',
          );

    // ----------------------------------------------------------
    // DESTINATION
    // ----------------------------------------------------------

    final String parsedDestination =
        json['destination']?.toString() ?? '';

    // ----------------------------------------------------------
    // DATES
    // ----------------------------------------------------------

    final dynamic rawStartDate =
        json['startDate'] ?? json['start_date'];

    final dynamic rawEndDate =
        json['endDate'] ?? json['end_date'];

    final DateTime parsedStartDate =
        DateTime.tryParse(
              rawStartDate?.toString() ?? '',
            ) ??
            DateTime.now();

    final DateTime parsedEndDate =
        DateTime.tryParse(
              rawEndDate?.toString() ?? '',
            ) ??
            parsedStartDate;

    // ----------------------------------------------------------
    // TRAVELERS
    // ----------------------------------------------------------

    final dynamic rawTravelers =
        json['travelers'];

    final int parsedTravelers =
        rawTravelers is int
            ? rawTravelers
            : int.tryParse(
                  rawTravelers?.toString() ?? '',
                ) ??
                1;

    // ----------------------------------------------------------
    // BUDGET
    // ----------------------------------------------------------

    final String parsedBudget =
        json['budget']?.toString() ?? '';

    // ----------------------------------------------------------
    // TRAVEL STYLE
    // ----------------------------------------------------------

    final String parsedTravelStyle =
        json['travelStyle']?.toString() ??
        json['travel_style']?.toString() ??
        '';

    // ----------------------------------------------------------
    // INTERESTS
    // ----------------------------------------------------------

    final dynamic rawInterests =
        json['interests'];

    final List<String> parsedInterests =
        _parseInterests(rawInterests);

    // ----------------------------------------------------------
    // ITINERARY
    // ----------------------------------------------------------

    final dynamic rawItinerary =
        json['itinerary'];

    final List<dynamic> parsedItinerary =
        _parseItinerary(rawItinerary);

    // ----------------------------------------------------------
    // ESTIMATED COST
    // ----------------------------------------------------------

    final dynamic rawEstimatedCost =
        json['estimatedCost'] ??
        json['estimated_cost'];

    final Map<String, dynamic>? parsedEstimatedCost =
        _parseEstimatedCost(rawEstimatedCost);

    // ----------------------------------------------------------
    // CREATED AT
    // ----------------------------------------------------------

    final dynamic rawCreatedAt =
        json['createdAt'] ??
        json['created_at'];

    final DateTime? parsedCreatedAt =
        rawCreatedAt != null
            ? DateTime.tryParse(
                rawCreatedAt.toString(),
              )
            : null;

    // ----------------------------------------------------------
    // RETURN MODEL
    // ----------------------------------------------------------

    return TripModel(
      id: parsedId,
      destination: parsedDestination,
      startDate: parsedStartDate,
      endDate: parsedEndDate,
      travelers: parsedTravelers,
      budget: parsedBudget,
      travelStyle: parsedTravelStyle,
      interests: parsedInterests,
      itinerary: parsedItinerary,
      estimatedCost: parsedEstimatedCost,
      createdAt: parsedCreatedAt,
    );
  }
}
