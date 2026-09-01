import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../core/theme/app_theme.dart';
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

import '../screens/admin/admin_login_screen.dart';
import '../screens/admin/admin_screen.dart';

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
  // ADMIN
  // ============================================================

  static const String adminLogin = '/admin/login';
  static const String adminDashboard = '/admin';

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
      // AUTH
      // ========================================================

      login: (_) => const LoginScreen(),

      register: (_) => const RegisterScreen(),

      // ========================================================
      // LEGAL
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
        final arguments =
            ModalRoute.of(context)?.settings.arguments;

        String? destination;

        if (arguments is String) {
          destination = arguments;
        }

        return PlannerScreen(
          initialDestination: destination,
        );
      },

      // ========================================================
      // ITINERARY
      // ========================================================

      itinerary: (context) {
        final arguments =
            ModalRoute.of(context)?.settings.arguments;

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

      // ========================================================
      // ADMIN
      // ========================================================

      adminLogin: (_) => const AdminLoginScreen(),

      adminDashboard: (_) => const AdminScreen(),
    };

    // ============================================================
    // PREMIUM + PREMIUM TRAVEL
    // ============================================================

    if (AppConfig.premiumEnabled) {
      result[premium] = (_) => const PremiumScreen();

      result[travel] = (_) => const PremiumTravelScreen();

      result[travelFlights] =
          (_) => const FlightSearchScreen();

      result[travelStays] =
          (_) => const StaySearchScreen();

      result[travelCars] =
          (_) => const CarSearchScreen();
    }

    return result;
  }

  // ============================================================
  // BUILD ITINERARY ROUTE
  // ============================================================

  static Widget _buildItineraryRoute(dynamic arguments) {
    if (arguments == null) {
      return const _InvalidTripScreen(
        reason: 'No trip data was provided.',
      );
    }

    if (arguments is! Map) {
      return const _InvalidTripScreen(
        reason: 'The trip data is not a valid object.',
      );
    }

    final argumentsMap =
        Map<String, dynamic>.from(arguments);

    Map<String, dynamic> trip;

    final nestedTrip = argumentsMap['trip'];

    if (nestedTrip is Map) {
      trip = Map<String, dynamic>.from(nestedTrip);
    } else {
      trip = argumentsMap;
    }

    // ==========================================================
    // DEBUG
    // ==========================================================

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

    final destination =
        _readString(trip['destination']);

    if (destination == null || destination.isEmpty) {
      return const _InvalidTripScreen(
        reason: 'The destination is missing from the trip.',
      );
    }

    // ==========================================================
    // START DATE
    // ==========================================================

    final startDate =
        _readDate(trip['startDate']);

    if (startDate == null) {
      return const _InvalidTripScreen(
        reason: 'The start date is missing or invalid.',
      );
    }

    // ==========================================================
    // END DATE
    // ==========================================================

    final endDate =
        _readDate(trip['endDate']);

    if (endDate == null) {
      return const _InvalidTripScreen(
        reason: 'The end date is missing or invalid.',
      );
    }

    if (endDate.isBefore(startDate)) {
      return const _InvalidTripScreen(
        reason: 'The end date is before the start date.',
      );
    }

    // ==========================================================
    // BUDGET
    // ==========================================================

    final budget =
        _readString(trip['budget']);

    if (budget == null || budget.isEmpty) {
      return const _InvalidTripScreen(
        reason: 'The trip budget is missing.',
      );
    }

    // ==========================================================
    // TRAVEL STYLE
    // ==========================================================

    final travelStyle =
        _readString(trip['travelStyle']);

    if (travelStyle == null || travelStyle.isEmpty) {
      return const _InvalidTripScreen(
        reason: 'The travel style is missing.',
      );
    }

    // ==========================================================
    // ESTIMATED COST
    // ==========================================================

    Map<String, dynamic>? estimatedCost;

    final tripCost = trip['estimatedCost'];

    if (tripCost is Map) {
      estimatedCost =
          Map<String, dynamic>.from(tripCost);
    }

    if (estimatedCost == null) {
      final outerCost =
          argumentsMap['estimatedCost'];

      if (outerCost is Map) {
        estimatedCost =
            Map<String, dynamic>.from(outerCost);
      }
    }

    // ==========================================================
    // ITINERARY
    // ==========================================================

    dynamic itineraryData =
        trip['itinerary'];

    itineraryData ??=
        argumentsMap['itinerary'];

    final generatedItinerary =
        _readItinerary(itineraryData);

    // ==========================================================
    // ITINERARY DEBUG
    // ==========================================================

    appLog('');
    appLog('================================================');
    appLog('ITINERARY DATA');
    appLog('================================================');
    appLog('TYPE: ${itineraryData.runtimeType}');
    appLog(
      'NUMBER OF DAYS: ${generatedItinerary.length}',
    );

    for (int i = 0;
        i < generatedItinerary.length;
        i++) {

      final day =
          generatedItinerary[i];

      final activities =
          day['activities'];

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
    // RETURN ITINERARY
    // ==========================================================

    return ItineraryScreen(
      tripData: argumentsMap,
    );
  }

  // ============================================================
  // READ STRING
  // ============================================================

  static String? _readString(dynamic value) {
    if (value == null) {
      return null;
    }

    final result =
        value.toString().trim();

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

    final stringValue =
        value.toString().trim();

    if (stringValue.isEmpty) {
      return null;
    }

    return DateTime.tryParse(stringValue);
  }

  // ============================================================
  // READ ITINERARY
  // ============================================================

  static List<Map<String, dynamic>> _readItinerary(
      dynamic value) {

    final result =
        <Map<String, dynamic>>[];

    if (value == null) {
      return result;
    }

    if (value is! List) {
      return result;
    }

    for (final item in value) {
      if (item is Map) {
        result.add(
          Map<String, dynamic>.from(item),
        );
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

  const _InvalidTripScreen({
    this.reason = 'Invalid trip data.',
  });

  @override
  Widget build(BuildContext context) {
    final colors =
        context.triporaColors;

    return Scaffold(
      backgroundColor:
          colors.backgroundColor,

      appBar: AppBar(
        backgroundColor:
            Colors.transparent,
        elevation: 0,
        surfaceTintColor:
            Colors.transparent,
        title: Text(
          'Tripora',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: colors.textPrimary,
          ),
        ),
      ),

      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            width: double.infinity,
            constraints:
                const BoxConstraints(
              maxWidth: 500,
            ),
            padding:
                const EdgeInsets.all(28),
            decoration:
                BoxDecoration(
              color: colors.surface,
              borderRadius:
                  BorderRadius.circular(20),
              border: Border.all(
                color: colors.border,
              ),
            ),
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              children: [

                const Icon(
                  Icons.error_outline,
                  size: 52,
                  color: Colors.redAccent,
                ),

                const SizedBox(height: 18),

                const Text(
                  'Invalid Trip Data',
                  textAlign:
                      TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight:
                        FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 12),

                Text(
                  reason,
                  textAlign:
                      TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color:
                        colors.textSecondary,
                  ),
                ),

                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child:
                      ElevatedButton(
                    onPressed: () {
                      Navigator.pop(
                        context,
                      );
                    },
                    style:
                        ElevatedButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(
                        vertical: 15,
                      ),
                      shape:
                          RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(
                          12,
                        ),
                      ),
                    ),
                    child:
                        const Text(
                      'Go Back',
                      style:
                          TextStyle(
                        fontWeight:
                            FontWeight.w700,
                      ),
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
