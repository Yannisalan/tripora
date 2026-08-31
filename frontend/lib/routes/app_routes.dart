import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../core/utils/logger.dart';
import '../screens/home/home_screen.dart';
import '../screens/explore/explore_screen.dart';
import '../screens/planner/planner_screen.dart';
import '../screens/itinerary/itinerary_screen.dart';
import '../screens/trips/trips_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/premium/premium_screen.dart';
import '../screens/travel/premium_travel_screen.dart';
import '../screens/travel/flight_search_screen.dart';
import '../screens/travel/stay_search_screen.dart';
import '../screens/travel/car_search_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/legal/legal_screen.dart';
import '../screens/legal/legal_content.dart';

class AppRoutes {
  AppRoutes._();

  // ============================================================
  // ROUTE NAMES
  // ============================================================

  static const String home = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String terms = '/terms';
  static const String privacy = '/privacy';
  static const String explore = '/explore';
  static const String planner = '/planner';
  static const String itinerary = '/itinerary';
  static const String trips = '/trips';
  static const String profile = '/profile';
  static const String premium = '/premium';
  static const String travel = '/travel';
  static const String travelFlights = '/travel/flights';
  static const String travelStays = '/travel/stays';
  static const String travelCars = '/travel/cars';

  // ============================================================
  // ROUTES
  // ============================================================

  static Map<String, WidgetBuilder> get routes {
    final result = <String, WidgetBuilder>{
      // ========================================================
      // HOME
      // ========================================================
      home: (_) => const HomeScreen(),

      // ========================================================
      // LOGIN
      // ========================================================
      login: (_) => const LoginScreen(),

      // ========================================================
      // REGISTER
      // ========================================================
      register: (_) => const RegisterScreen(),

      // ========================================================
      // LEGAL (TERMS & PRIVACY)
      // ========================================================
      terms: (_) => const LegalScreen(
            title: TermsContent.title,
            sections: TermsContent.sections,
          ),
      privacy: (_) => const LegalScreen(
            title: PrivacyContent.title,
            sections: PrivacyContent.sections,
          ),

      // ========================================================
      // EXPLORE
      // ========================================================
      explore: (_) => const ExploreScreen(),

      // ========================================================
      // PLANNER
      // ========================================================
      planner: (context) {
        final arguments = ModalRoute.of(context)?.settings.arguments;

        String? destination;

        if (arguments is String) {
          destination = arguments;
        }

        return PlannerScreen(initialDestination: destination);
      },

      // ========================================================
      // ITINERARY
      // ========================================================
      itinerary: (context) {
        final arguments = ModalRoute.of(context)?.settings.arguments;

        return _buildItineraryRoute(arguments);
      },

      // ========================================================
      // MY TRIPS
      // ========================================================
      trips: (_) => const TripsScreen(),

      // ========================================================
      // PROFILE
      // ========================================================
      profile: (_) => const ProfileScreen(),
    };

    // ============================================================
    // PREMIUM + PREMIUM TRAVEL (FREEMIUM)
    // ============================================================
    //
    // v1 ships free-only: these routes are registered only when the
    // `PREMIUM_ENABLED` build flag is set (see AppConfig.premiumEnabled). With
    // the flag off there is no way to navigate to the paywall or the
    // premium travel search, so the app exposes no premium surface.
    // ------------------------------------------------------------
    if (AppConfig.premiumEnabled) {
      result[premium] = (_) => const PremiumScreen();
      result[travel] = (_) => const PremiumTravelScreen();
      result[travelFlights] = (_) => const FlightSearchScreen();
      result[travelStays] = (_) => const StaySearchScreen();
      result[travelCars] = (_) => const CarSearchScreen();
    }

    return result;
  }

  // ============================================================
  // BUILD ITINERARY ROUTE
  // ============================================================

  static Widget _buildItineraryRoute(dynamic arguments) {
    // ----------------------------------------------------------
    // STEP 1
    //
    // The PlannerScreen currently sends:
    //
    // Navigator.pushNamed(
    //   context,
    //   '/itinerary',
    //   arguments: tripMap,
    // );
    //
    // Therefore tripMap itself is the argument.
    //
    // We ALSO support this format:
    //
    // {
    //   "trip": {...},
    //   "itinerary": [...],
    //   "estimatedCost": {...}
    // }
    //
    // ----------------------------------------------------------

    if (arguments == null) {
      return const _InvalidTripScreen(reason: 'No trip data was provided.');
    }

    if (arguments is! Map) {
      return const _InvalidTripScreen(
        reason: 'The trip data is not a valid object.',
      );
    }

    final argumentsMap = Map<String, dynamic>.from(arguments);

    // ----------------------------------------------------------
    // STEP 2
    //
    // Determine where the actual trip object is.
    //
    // If arguments contains "trip" and it is a Map:
    //     use arguments["trip"]
    //
    // Otherwise:
    //     arguments itself IS the trip.
    // ----------------------------------------------------------

    Map<String, dynamic> trip;

    final nestedTrip = argumentsMap['trip'];

    if (nestedTrip is Map) {
      trip = Map<String, dynamic>.from(nestedTrip);
    } else {
      trip = argumentsMap;
    }

    // ----------------------------------------------------------
    // DEBUG
    // ----------------------------------------------------------

    appLog('');
    appLog('================================================');
    appLog('TRIPORA - ITINERARY ROUTE');
    appLog('================================================');
    appLog('ARGUMENTS TYPE: ${arguments.runtimeType}');
    appLog('TRIP TYPE: ${trip.runtimeType}');
    appLog('TRIP ID: ${trip['id']}');
    appLog('DESTINATION: ${trip['destination']}');
    appLog('START DATE: ${trip['startDate']}');
    appLog('END DATE: ${trip['endDate']}');
    appLog('TRAVELERS: ${trip['travelers']}');
    appLog('BUDGET: ${trip['budget']}');
    appLog('TRAVEL STYLE: ${trip['travelStyle']}');
    appLog('INTERESTS: ${trip['interests']}');
    appLog(
      'ESTIMATED COST TYPE: '
      '${trip['estimatedCost']?.runtimeType}',
    );
    appLog(
      'ITINERARY TYPE: '
      '${trip['itinerary']?.runtimeType}',
    );
    appLog('================================================');

    // ==========================================================
    // DESTINATION
    // ==========================================================

    final destination = _readString(trip['destination']);

    if (destination == null || destination.isEmpty) {
      return const _InvalidTripScreen(
        reason: 'The destination is missing from the trip.',
      );
    }

    // ==========================================================
    // START DATE
    // ==========================================================

    final startDate = _readDate(trip['startDate']);

    if (startDate == null) {
      return const _InvalidTripScreen(
        reason: 'The start date is missing or invalid.',
      );
    }

    // ==========================================================
    // END DATE
    // ==========================================================

    final endDate = _readDate(trip['endDate']);

    if (endDate == null) {
      return const _InvalidTripScreen(
        reason: 'The end date is missing or invalid.',
      );
    }

    // ----------------------------------------------------------
    // Make sure dates are logical.
    // ----------------------------------------------------------

    if (endDate.isBefore(startDate)) {
      return const _InvalidTripScreen(
        reason: 'The end date is before the start date.',
      );
    }

    // ==========================================================
    // BUDGET
    // ==========================================================

    final budget = _readString(trip['budget']);

    if (budget == null || budget.isEmpty) {
      return const _InvalidTripScreen(reason: 'The trip budget is missing.');
    }

    // ==========================================================
    // TRAVEL STYLE
    // ==========================================================

    final travelStyle = _readString(trip['travelStyle']);

    if (travelStyle == null || travelStyle.isEmpty) {
      return const _InvalidTripScreen(reason: 'The travel style is missing.');
    }

    // ==========================================================
    // ESTIMATED COST
    // ==========================================================

    Map<String, dynamic>? estimatedCost;

    // First, look inside the trip.
    final tripCost = trip['estimatedCost'];

    if (tripCost is Map) {
      estimatedCost = Map<String, dynamic>.from(tripCost);
    }

    // If it wasn't inside the trip, look at the
    // outer arguments.
    if (estimatedCost == null) {
      final outerCost = argumentsMap['estimatedCost'];

      if (outerCost is Map) {
        estimatedCost = Map<String, dynamic>.from(outerCost);
      }
    }

    // ==========================================================
    // ITINERARY
    // ==========================================================

    dynamic itineraryData;

    // ----------------------------------------------------------
    // FIRST:
    //
    // Read itinerary directly from the trip.
    //
    // This is the format your current generated trip uses.
    // ----------------------------------------------------------

    itineraryData = trip['itinerary'];

    // ----------------------------------------------------------
    // SECOND:
    //
    // If there is no itinerary inside the trip,
    // check the outer arguments.
    // ----------------------------------------------------------

    itineraryData ??= argumentsMap['itinerary'];

    // ----------------------------------------------------------
    // Convert itinerary safely.
    // ----------------------------------------------------------

    final generatedItinerary = _readItinerary(itineraryData);

    // ==========================================================
    // ITINERARY DEBUG
    // ==========================================================

    appLog('');
    appLog('================================================');
    appLog('ITINERARY DATA');
    appLog('================================================');
    appLog('TYPE: ${itineraryData.runtimeType}');
    appLog('NUMBER OF DAYS: ${generatedItinerary.length}');

    for (int i = 0; i < generatedItinerary.length; i++) {
      final day = generatedItinerary[i];

      final activities = day['activities'];

      appLog('DAY ${i + 1}');

      appLog('  day: ${day['day']}');

      appLog('  date: ${day['date']}');

      appLog('  title: ${day['title']}');

      appLog(
        '  activities type: '
        '${activities.runtimeType}',
      );

      appLog(
        '  activities count: '
        '${activities is List ? activities.length : 0}',
      );
    }

    appLog('================================================');
    appLog('');

    // ==========================================================
    // IMPORTANT
    //
    // DO NOT reject the itinerary here just because its length
    // is unexpected.
    //
    // The backend is responsible for generating it.
    // The ItineraryScreen is responsible for displaying it.
    //
    // This prevents a valid saved trip from being incorrectly
    // rejected by the Flutter route.
    // ==========================================================

    return ItineraryScreen(tripData: argumentsMap);
  }

  // ============================================================
  // READ STRING
  // ============================================================

  static String? _readString(dynamic value) {
    if (value == null) {
      return null;
    }

    final result = value.toString().trim();

    if (result.isEmpty) {
      return null;
    }

    return result;
  }

  // ============================================================
  // READ DATE
  // ============================================================

  static DateTime? _readDate(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is DateTime) {
      return value;
    }

    final stringValue = value.toString().trim();

    if (stringValue.isEmpty) {
      return null;
    }

    return DateTime.tryParse(stringValue);
  }

  // ============================================================
  // READ ITINERARY
  // ============================================================

  static List<Map<String, dynamic>> _readItinerary(dynamic value) {
    final result = <Map<String, dynamic>>[];

    if (value == null) {
      return result;
    }

    if (value is! List) {
      return result;
    }

    for (final item in value) {
      if (item is Map) {
        result.add(Map<String, dynamic>.from(item));
      }
    }

    return result;
  }
}

// ================================================================
// INVALID TRIP SCREEN
// ================================================================

class _InvalidTripScreen extends StatelessWidget {
  final String reason;

  const _InvalidTripScreen({this.reason = 'Invalid trip data.'});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),

      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Tripora',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF111827),
          ),
        ),
      ),

      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 500),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 52,
                  color: Colors.redAccent,
                ),

                const SizedBox(height: 18),

                const Text(
                  'Invalid Trip Data',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                ),

                const SizedBox(height: 12),

                Text(
                  reason,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: Color(0xFF6B7280),
                  ),
                ),

                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Go Back',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
