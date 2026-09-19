import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/auth/auth_guard.dart';
import '../core/config/app_config.dart';
import '../trip_reminder.dart';
import '../core/preferences/app_preferences.dart';
import '../models/trip_model.dart';

/// Adapts TripModel to the TripLike interface TripReminderScheduler
/// expects. If your TripModel's field names differ from `destination`,
/// `startDate`, or `endDate`, update the getters below — nothing else
/// needs to change.
class _TripModelReminderAdapter implements TripLike {
  _TripModelReminderAdapter(this._trip);

  final TripModel _trip;

  @override
  String get id => _trip.id!.toString();

  @override
  String get destination => _trip.destination;

  @override
  DateTime get startDate => _trip.startDate;

  @override
  DateTime get endDate => _trip.endDate;
}

class TripService {
  static const String baseUrl = AppConfig.apiBaseUrl;

  void _debugLog(String message) {
    assert(() {
      debugPrint(message);
      return true;
    }());
  }

  /// Schedules trip reminders for a freshly fetched/updated TripModel.
  /// Wrapped in try/catch so a notification-scheduling failure (e.g.
  /// permission denied, platform channel error) never breaks the
  /// underlying trip fetch/update/delete flow.
  Future<void> _scheduleReminders(TripModel trip) async {
    if (trip.id == null) {
      // No server-assigned id yet — nothing stable to key reminders on.
      // This shouldn't happen for trips returned by update/regenerate/get,
      // since those always come back from the backend with an id, but
      // guarding here avoids silently scheduling under a bogus "null" key.
      _debugLog('TripService: skipped scheduling, trip has no id yet');
      return;
    }

    try {
      await TripReminderScheduler.scheduleForTrip(
        _TripModelReminderAdapter(trip),
      );
    } catch (e) {
      _debugLog('TripService: failed to schedule reminders for trip: $e');
    }
  }

  Future<void> _cancelReminders(int tripId) async {
    try {
      await TripReminderScheduler.cancelForTripId(tripId.toString());
    } catch (e) {
      _debugLog('TripService: failed to cancel reminders for trip: $e');
    }
  }

  // ============================================================
  // GET AUTH TOKEN
  // ============================================================

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString('access_token');
  }

  // ============================================================
  // AUTHORIZATION HEADERS
  // ============================================================

  Future<Map<String, String>> _headers() async {
    final token = await _getToken();

    if (token == null || token.isEmpty) {
      // No token at all simply means "not signed in". Do NOT force a
      // redirect to /login here — that made the app bounce straight to
      // the login page on launch. Instead surface a clean "not logged
      // in" error so screens can render their guest state (e.g. the
      // home screen's "Sign in to see your saved trips" card). Expired
      // sessions are handled separately by the 401 branch in each call.
      throw Exception('You are not logged in.');
    }

    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // ============================================================
  // DECODE RESPONSE
  // ============================================================

  dynamic _decodeResponse(http.Response response) {
    if (response.body.isEmpty) {
      return null;
    }

    try {
      return jsonDecode(response.body);
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // GENERATE TRIP
  // POST /api/trips/generate
  // ============================================================

  Future<Map<String, dynamic>> generateTrip(TripModel trip) async {
    final headers = await _headers();

    final body = Map<String, dynamic>.from(trip.toJson())
      ..['preferredLanguage'] = AppPreferences.instance.language
      ..['preferredCurrency'] = AppPreferences.instance.currency;

    final response = await http.post(
      Uri.parse('$baseUrl/api/trips/generate'),
      headers: headers,
      body: jsonEncode(body),
    );

    final decoded = _decodeResponse(response);

    _debugLog('====================================');
    _debugLog('POST /api/trips/generate');
    _debugLog('STATUS: ${response.statusCode}');
    _debugLog('BODY:');
    _debugLog(response.body);
    _debugLog('====================================');

    // ----------------------------------------------------------
    // UNAUTHORIZED
    // ----------------------------------------------------------

    if (response.statusCode == 401) {
      await AuthGuard.handleUnauthorized();
      throw Exception('Your session has expired. Please log in again.');
    }

    // ----------------------------------------------------------
    // SERVER ERROR
    // ----------------------------------------------------------

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (decoded is Map) {
        throw Exception(
          decoded['message']?.toString() ?? 'Failed to generate trip.',
        );
      }

      throw Exception('Failed to generate trip.');
    }

    // NOTE: this endpoint returns a raw decoded map rather than a
    // TripModel (unlike updateTrip/regenerateItinerary/getTrip below),
    // so reminders aren't scheduled here. Once the caller that invokes
    // generateTrip() parses the response into a TripModel and saves it,
    // have that call site call TripReminderScheduler.scheduleForTrip()
    // (via the _TripModelReminderAdapter pattern above) or, simpler,
    // route the newly created trip through updateTrip()/getTrip() so
    // scheduling happens automatically.
    return decoded;
  }

  // ============================================================
  // UPDATE USER TRIP
  // PATCH /api/trips/<tripId>
  // ============================================================

  Future<TripModel> updateTrip({
    required int tripId,
    required TripModel trip,
  }) async {
    final headers = await _headers();

    final response = await http.patch(
      Uri.parse('$baseUrl/api/trips/$tripId'),
      headers: headers,
      body: jsonEncode(trip.toJson()),
    );

    final decoded = _decodeResponse(response);

    _debugLog('====================================');
    _debugLog('PATCH /api/trips/$tripId');
    _debugLog('STATUS: ${response.statusCode}');
    _debugLog('BODY:');
    _debugLog(response.body);
    _debugLog('====================================');

    if (response.statusCode == 401) {
      await AuthGuard.handleUnauthorized();
      throw Exception('Your session has expired. Please log in again.');
    }

    if (response.statusCode == 404) {
      throw Exception('Trip not found.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (decoded is Map) {
        throw Exception(
          decoded['message']?.toString() ?? 'Failed to update trip.',
        );
      }

      throw Exception('Failed to update trip.');
    }

    if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
      throw Exception('Failed to update trip.');
    }

    final updatedTrip = decoded['trip'];

    if (updatedTrip is! Map) {
      throw Exception('Backend response does not contain a valid trip.');
    }

    final parsed = TripModel.fromJson(Map<String, dynamic>.from(updatedTrip));

    // Dates may have changed (or the trip may have just been confirmed),
    // so reschedule reminders against the latest start/end dates.
    unawaited(_scheduleReminders(parsed));

    return parsed;
  }

  // ============================================================
  // REGENERATE USER TRIP ITINERARY
  // POST /api/trips/<tripId>/regenerate
  // ============================================================

  Future<TripModel> regenerateItinerary(int tripId) async {
    final headers = await _headers();

    final response = await http.post(
      Uri.parse('$baseUrl/api/trips/$tripId/regenerate'),
      headers: headers,
    );

    final decoded = _decodeResponse(response);

    _debugLog('====================================');
    _debugLog('POST /api/trips/$tripId/regenerate');
    _debugLog('STATUS: ${response.statusCode}');
    _debugLog('BODY:');
    _debugLog(response.body);
    _debugLog('====================================');

    if (response.statusCode == 401) {
      await AuthGuard.handleUnauthorized();
      throw Exception('Your session has expired. Please log in again.');
    }

    if (response.statusCode == 404) {
      throw Exception('Trip not found.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (decoded is Map) {
        throw Exception(
          decoded['message']?.toString() ?? 'Failed to regenerate itinerary.',
        );
      }

      throw Exception('Failed to regenerate itinerary.');
    }

    if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
      throw Exception('Failed to regenerate itinerary.');
    }

    final updatedTrip = decoded['trip'];

    if (updatedTrip is! Map) {
      throw Exception('Backend response does not contain a valid trip.');
    }

    final parsed = TripModel.fromJson(Map<String, dynamic>.from(updatedTrip));

    // Itinerary content changed but dates are unlikely to — rescheduling
    // is still cheap (cancel + re-add 3 local notifications) and keeps
    // this correct even if regeneration ever touches dates later.
    unawaited(_scheduleReminders(parsed));

    return parsed;
  }

  // ============================================================
  // GET ALL USER TRIPS
  // GET /api/trips
  // ============================================================

  Future<List<TripModel>> getTrips() async {
    final headers = await _headers();

    final response = await http.get(
      Uri.parse('$baseUrl/api/trips'),
      headers: headers,
    );

    _debugLog('====================================');
    _debugLog('GET /api/trips');
    _debugLog('STATUS: ${response.statusCode}');
    _debugLog('BODY:');
    _debugLog(response.body);
    _debugLog('====================================');

    final decoded = _decodeResponse(response);

    // ----------------------------------------------------------
    // UNAUTHORIZED
    // ----------------------------------------------------------

    if (response.statusCode == 401) {
      await AuthGuard.handleUnauthorized();
      throw Exception('Your session has expired. Please log in again.');
    }

    // ----------------------------------------------------------
    // SERVER ERROR
    // ----------------------------------------------------------

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (decoded is Map) {
        throw Exception(
          decoded['message']?.toString() ?? 'Failed to fetch trips.',
        );
      }

      throw Exception('Failed to fetch trips.');
    }

    // ----------------------------------------------------------
    // VALIDATE RESPONSE
    // ----------------------------------------------------------

    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid response from Tripora backend.');
    }

    if (decoded['success'] != true) {
      throw Exception(
        decoded['message']?.toString() ?? 'Failed to fetch trips.',
      );
    }

    final trips = decoded['trips'];

    if (trips is! List) {
      throw Exception('Backend response does not contain a valid trips list.');
    }

    // ----------------------------------------------------------
    // CONVERT TRIPS
    // ----------------------------------------------------------

    final parsedTrips = trips.map((trip) {
      if (trip is! Map) {
        throw Exception('Invalid trip data received from backend.');
      }

      final tripMap = Map<String, dynamic>.from(trip);

      _debugLog('------------------------------------');
      _debugLog('TRIP ID: ${tripMap['id']}');
      _debugLog('DESTINATION: ${tripMap['destination']}');
      _debugLog(
        'ITINERARY TYPE: '
            '${tripMap['itinerary']?.runtimeType}',
      );
      _debugLog(
        'ITINERARY LENGTH: '
            '${tripMap['itinerary'] is List ? (tripMap['itinerary'] as List).length : 0}',
      );
      _debugLog('ITINERARY: ${tripMap['itinerary']}');
      _debugLog('------------------------------------');

      return TripModel.fromJson(tripMap);
    }).toList();

    // Resync local reminders against the source of truth from the
    // backend. scheduleForTrip() cancels-then-reschedules per trip, so
    // this stays correct even after a reinstall or a fresh login on a
    // new device — and it's all local, no network cost, so looping
    // over a typical trip list is cheap.
    for (final trip in parsedTrips) {
      unawaited(_scheduleReminders(trip));
    }

    return parsedTrips;
  }

  // ============================================================
  // GET SINGLE USER TRIP
  // GET /api/trips/<tripId>
  // ============================================================

  Future<TripModel> getTrip(int tripId) async {
    final headers = await _headers();

    final response = await http.get(
      Uri.parse('$baseUrl/api/trips/$tripId'),
      headers: headers,
    );

    _debugLog('====================================');
    _debugLog('GET /api/trips/$tripId');
    _debugLog('STATUS: ${response.statusCode}');
    _debugLog('BODY:');
    _debugLog(response.body);
    _debugLog('====================================');

    final decoded = _decodeResponse(response);

    // ----------------------------------------------------------
    // UNAUTHORIZED
    // ----------------------------------------------------------

    if (response.statusCode == 401) {
      await AuthGuard.handleUnauthorized();
      throw Exception('Your session has expired. Please log in again.');
    }

    // ----------------------------------------------------------
    // NOT FOUND
    // ----------------------------------------------------------

    if (response.statusCode == 404) {
      throw Exception('Trip not found.');
    }

    // ----------------------------------------------------------
    // SERVER ERROR
    // ----------------------------------------------------------

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (decoded is Map) {
        throw Exception(
          decoded['message']?.toString() ?? 'Failed to fetch trip.',
        );
      }

      throw Exception('Failed to fetch trip.');
    }

    // ----------------------------------------------------------
    // VALIDATE RESPONSE
    // ----------------------------------------------------------

    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid response from Tripora backend.');
    }

    if (decoded['success'] != true) {
      throw Exception(
        decoded['message']?.toString() ?? 'Failed to fetch trip.',
      );
    }

    // ----------------------------------------------------------
    // GET TRIP
    // ----------------------------------------------------------

    final trip = decoded['trip'];

    if (trip is! Map) {
      throw Exception('Backend response does not contain a valid trip.');
    }

    final tripMap = Map<String, dynamic>.from(trip);

    _debugLog('====================================');
    _debugLog('SINGLE TRIP');
    _debugLog('TRIP ID: ${tripMap['id']}');
    _debugLog('DESTINATION: ${tripMap['destination']}');
    _debugLog(
      'ITINERARY TYPE: '
          '${tripMap['itinerary']?.runtimeType}',
    );
    _debugLog(
      'ITINERARY LENGTH: '
          '${tripMap['itinerary'] is List ? (tripMap['itinerary'] as List).length : 0}',
    );
    _debugLog('====================================');

    final parsed = TripModel.fromJson(tripMap);

    unawaited(_scheduleReminders(parsed));

    return parsed;
  }

  // ============================================================
  // DELETE USER TRIP
  // DELETE /api/trips/<tripId>
  // ============================================================

  Future<void> deleteTrip(int tripId) async {
    final headers = await _headers();

    final response = await http.delete(
      Uri.parse('$baseUrl/api/trips/$tripId'),
      headers: headers,
    );

    final decoded = _decodeResponse(response);

    _debugLog('====================================');
    _debugLog('DELETE /api/trips/$tripId');
    _debugLog('STATUS: ${response.statusCode}');
    _debugLog('BODY:');
    _debugLog(response.body);
    _debugLog('====================================');

    // ----------------------------------------------------------
    // UNAUTHORIZED
    // ----------------------------------------------------------

    if (response.statusCode == 401) {
      await AuthGuard.handleUnauthorized();
      throw Exception('Your session has expired. Please log in again.');
    }

    // ----------------------------------------------------------
    // NOT FOUND
    // ----------------------------------------------------------

    if (response.statusCode == 404) {
      throw Exception('Trip not found.');
    }

    // ----------------------------------------------------------
    // SERVER ERROR
    // ----------------------------------------------------------

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (decoded is Map) {
        throw Exception(
          decoded['message']?.toString() ?? 'Failed to delete trip.',
        );
      }

      throw Exception('Failed to delete trip.');
    }

    // ----------------------------------------------------------
    // VALIDATE RESPONSE
    // ----------------------------------------------------------

    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid response from Tripora backend.');
    }

    if (decoded['success'] != true) {
      throw Exception(
        decoded['message']?.toString() ?? 'Failed to delete trip.',
      );
    }

    // Trip is confirmed deleted server-side — clear its local reminders
    // so the user doesn't get notified about a trip they removed.
    await _cancelReminders(tripId);
  }
}