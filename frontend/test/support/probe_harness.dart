// Shared harness for the responsive probes: a sample trip, an in-memory
// fake backend (no request leaves the test process), app pumping, and an
// error collector that records every layout error with the source line
// Flutter blames.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/core/auth/token_store.dart';
import 'package:frontend/main.dart';
import 'package:frontend/models/trip_model.dart';
import 'package:frontend/screens/auth/forgot_password_screen.dart';
import 'package:frontend/screens/auth/login_screen.dart';
import 'package:frontend/screens/auth/register_screen.dart';
import 'package:frontend/screens/auth/verify_email_screen.dart';
import 'package:frontend/screens/expenses/expense_tracker_screen.dart';
import 'package:frontend/screens/itinerary/itinerary_screen.dart';
import 'package:frontend/screens/main_shell.dart';
import 'package:frontend/screens/planner/planner_screen.dart';
import 'package:frontend/screens/travel/check_flight_prices_screen.dart';
import 'package:frontend/screens/trip_details.dart';
import 'package:frontend/screens/weather/trip_weather_screen.dart';

const probeWidths = <double>[
  320,
  360,
  390,
  430,
  600,
  768,
  1024,
  1280,
  1440,
  1920,
];
const probeLanguages = ['en', 'es', 'fr', 'de', 'it', 'pt'];

final sampleTripJson = <String, dynamic>{
  'id': 42,
  'destination': 'Rio de Janeiro, Brazil',
  'startDate': '2027-03-10',
  'endDate': '2027-03-14',
  'travelers': 3,
  'budget': 'medium',
  'budgetAmount': 2400,
  'travelStyle': 'balanced',
  'interests': ['culture', 'food', 'nature', 'nightlife'],
  'estimatedCost': {
    'total': 2350,
    'currency': 'EUR',
    'accommodation': 900,
    'food': 600,
    'transport': 350,
    'activities': 500,
  },
  'itinerary': [
    for (var d = 1; d <= 4; d++)
      {
        'day': d,
        'title': 'Day $d: Copacabana, Santa Teresa and the historic centre',
        'activities': [
          {
            'time': '09:00',
            'title': 'Sunrise walk along Copacabana and Ipanema promenade',
            'description':
                'A long description of the activity that should wrap across '
                'several lines on narrow phones without clipping.',
          },
          {
            'time': '14:30',
            'title': 'Christ the Redeemer',
            'description': 'Cog train up Corcovado.',
          },
        ],
      },
  ],
};

TripModel sampleTrip() => TripModel.fromJson(sampleTripJson);

/// In-memory stand-in for the backend so loaded states (trip lists,
/// expenses, weather, profile) are laid out, not just error states. No
/// request ever leaves the test process.
http.Client fakeBackend() {
  http.Response json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  return MockClient((request) async {
    final path = request.url.path;
    if (request.method == 'GET' && path == '/api/trips') {
      return json({
        'success': true,
        'trips': [
          sampleTripJson,
          {
            ...sampleTripJson,
            'id': 43,
            'destination': 'Saint-Jean-de-Luz, Pyrénées-Atlantiques, France',
            'startDate': '2025-06-01',
            'endDate': '2025-06-12',
          },
          {...sampleTripJson, 'id': 44, 'destination': 'Kyoto, Japan'},
        ],
      });
    }
    final single = RegExp(r'^/api/trips/(\d+)$').firstMatch(path);
    if (request.method == 'GET' && single != null) {
      return json({
        'success': true,
        'trip': {...sampleTripJson, 'id': int.parse(single.group(1)!)},
      });
    }
    if (request.method == 'GET' && path.endsWith('/expenses')) {
      return json({
        'budgetAmount': 2400,
        'budgetCurrency': 'EUR',
        'expenses': [
          for (var i = 0; i < 6; i++)
            {
              'id': i + 1,
              'tripId': 42,
              'amount': 1234.56 * (i + 1),
              'currency': 'EUR',
              'category': [
                'food',
                'transport',
                'accommodation',
                'activities',
                'shopping',
                'other',
              ][i],
              'description':
                  'Dinner at a very long-named seafood restaurant in Leblon $i',
              'date': '2027-03-1${i % 5}',
              'paymentMethod': 'card',
              'createdAt': '2027-03-10T10:00:00Z',
            },
        ],
      });
    }
    if (request.method == 'GET' && path.endsWith('/weather')) {
      return json({
        'available': true,
        'location': {'name': 'Rio de Janeiro', 'country': 'Brazil'},
        'dates': {'forecastStart': '2027-03-10', 'forecastEnd': '2027-03-14'},
        'forecast': [
          for (var d = 10; d <= 14; d++)
            {
              'date': '2027-03-$d',
              'icon': 'rain',
              'label': 'Moderate rain showers with thunderstorms',
              'tempMax': 31.5,
              'tempMin': 22.1,
              'precipitationProbability': 80,
            },
        ],
      });
    }
    if (request.method == 'GET' && path == '/api/auth/me') {
      return json({
        'success': true,
        'user': {
          'id': 7,
          'name': 'Maximiliana Rodrigues-Fernandes de Albuquerque',
          'email': 'maximiliana.rodrigues-fernandes@example-domain.com',
          'emailVerified': true,
        },
      });
    }
    return json({'success': false, 'message': 'Not found'}, 404);
  });
}

const probeTabs = {
  0: 'home',
  1: 'explore',
  2: 'flights',
  3: 'trips',
  4: 'profile',
};

class ProbeErrors {
  final List<String> items = [];

  /// Full diagnostic text of the first error at each source location.
  static final Map<String, String> firstDetails = {};

  static final _blame = RegExp(r'(lib/[\w/]+\.dart):(\d+)');

  void add(FlutterErrorDetails d, String where) {
    final text = d.toString();
    final m = _blame.firstMatch(text);
    final firstLine = d.exceptionAsString().split('\n').first;
    final loc = m == null ? '?' : '${m.group(1)}:${m.group(2)}';
    firstDetails.putIfAbsent(loc, () => text);
    items.add('$where | $firstLine | $loc');
  }
}

Future<void> pumpShell(
  WidgetTester tester,
  Size size, {
  ThemeMode? themeMode,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  SharedPreferences.setMockInitialValues({'access_token': 'test-token'});
  // A signed-in, in-memory session so protected screens (My Trips,
  // Profile) render their loaded states against the fake backend.
  await TokenStore.instance.saveSession(
    accessToken: 'test-token',
    refreshToken: 'test-refresh',
  );
  MainShell.currentIndex.value = 0;
  await tester.pumpWidget(TriporaApp(themeMode: themeMode));
  await tester.pump(const Duration(milliseconds: 1500));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Runs [body] while recording every Flutter error instead of failing on
/// the first; restores the handler afterwards.
Future<List<String>> collectErrors(
  WidgetTester tester,
  Future<void> Function(ProbeErrors) body,
) async {
  final errors = ProbeErrors();
  final previous = FlutterError.onError;
  var where = '';
  FlutterError.onError = (d) => errors.add(d, where);
  try {
    await http.runWithClient(() => body(errors), fakeBackend);
  } finally {
    FlutterError.onError = previous;
  }
  return errors.items;
}

void drainErrors(WidgetTester tester, ProbeErrors errors, String where) {
  // Tag errors recorded since the previous drain with [where].
  for (var i = 0; i < errors.items.length; i++) {
    if (errors.items[i].startsWith(' | ')) {
      errors.items[i] = '$where${errors.items[i]}';
    }
  }
  final e = tester.takeException();
  if (e != null) errors.items.add('$where | exception: $e');
}

/// Screens pushed over the shell, by name.
final Map<String, WidgetBuilder> probeScreens = {
  'planner': (_) => const PlannerScreen(),
  'itinerary': (_) => ItineraryScreen(tripData: {'trip': sampleTripJson}),
  'tripDetails': (_) => TripDetailsScreen(trip: sampleTrip()),
  'expenses': (_) => ExpenseTrackerScreen(trip: sampleTrip()),
  'weather': (_) => TripWeatherScreen(trip: sampleTrip()),
  'checkFlights': (_) => const CheckFlightPricesScreen(),
  'login': (_) => const LoginScreen(),
  'register': (_) => const RegisterScreen(),
  'forgotPassword': (_) => const ForgotPasswordScreen(),
  'verifyEmail': (_) =>
      const VerifyEmailScreen(email: 'very.long.address@example-domain.com'),
};
