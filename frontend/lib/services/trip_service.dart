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

/// Thrown when the backend reports the AI is busy (HTTP 503 `ai_busy`) or
/// the generate request exceeded the client timeout. The planner turns this
/// into a friendly, localized "the AI is busy" message instead of a raw
/// technical error.
class AiBusyException implements Exception {
  const AiBusyException([this.message = 'The AI is busy right now.']);

  final String message;

  @override
  String toString() => message;
}

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

  /// True when the last fetch could not reach the backend and fell back to
  /// the locally saved trip data. Read by the trips list / trip details
  /// screens to show an offline banner and force read-only mode.
  static bool isOffline = false;

  static const String _tripsCacheKey = 'tripora.offline_trips_v1';
  static const String _tripCacheKeyPrefix = 'tripora.offline_trip_';

  /// Max time to wait for the backend's generate-trip call. That endpoint
  /// runs the full AI itinerary generation inline, so this is generous
  /// enough to not kill a legitimate slow generation, yet bounded so the
  /// planner's non-dismissible generation overlay can never hang forever
  /// waiting on a dead connection.
  static const Duration generateRequestTimeout = Duration(seconds: 60);

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
  // OFFLINE CACHE
  // ============================================================
  //
  // Trip data the user last saw is saved locally so the trips list and
  // trip details stay viewable (read-only) when the backend is
  // unreachable. Only genuine network failures fall back to this cache —
  // real HTTP errors (404/401/500) rethrow as before so a deleted or
  // unauthorized trip is never shown from a stale copy.

  /// Serializes trips the same way the details screen expects
  /// (`toDetailMap()` carries id + itinerary + estimatedCost), then
  /// round-trips them through [TripModel.fromJson] so dates, interests,
  /// and nested lists survive JSON exactly as the backend sends them.
  String _serializeTrips(List<TripModel> trips) {
    return jsonEncode(
      trips.map((trip) => trip.toDetailMap()).toList(),
    );
  }

  Future<void> _saveTripsCache(List<TripModel> trips) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tripsCacheKey, _serializeTrips(trips));

      // Mirror each trip into its single-trip cache slot so a fresh trip
      // details view works offline even when only the list was fetched.
      for (final trip in trips) {
        if (trip.id != null) {
          await prefs.setString(
            '$_tripCacheKeyPrefix${trip.id}',
            jsonEncode(trip.toDetailMap()),
          );
        }
      }
    } catch (e) {
      _debugLog('TripService: failed to save trips cache: $e');
    }
  }

  Future<List<TripModel>> _readTripsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_tripsCacheKey);

      if (raw == null || raw.isEmpty) {
        return [];
      }

      final decoded = jsonDecode(raw);

      if (decoded is! List) {
        return [];
      }

      final trips = <TripModel>[];

      for (final item in decoded) {
        if (item is! Map) continue;

        try {
          trips.add(
            TripModel.fromJson(
              Map<String, dynamic>.from(item),
            ),
          );
        } catch (e) {
          _debugLog('TripService: skipped invalid cached trip: $e');
        }
      }

      return trips;
    } catch (e) {
      _debugLog('TripService: failed to read trips cache: $e');
      return [];
    }
  }

  Future<TripModel?> _readTripCache(int tripId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_tripCacheKeyPrefix$tripId');

      if (raw == null || raw.isEmpty) {
        return null;
      }

      final decoded = jsonDecode(raw);

      if (decoded is! Map) {
        return null;
      }

      return TripModel.fromJson(Map<String, dynamic>.from(decoded));
    } catch (e) {
      _debugLog('TripService: failed to read trip cache: $e');
      return null;
    }
  }

  /// Distinguishes "the backend could not be reached" from real HTTP
  /// responses. Web-safe: type names are matched from the error string so
  /// no dart:io import is needed.
  bool _isNetworkError(Object error) {
    final message = error.toString();

    return error is http.ClientException ||
        error is TimeoutException ||
        message.contains('SocketException') ||
        message.contains('HandshakeException') ||
        message.contains('Failed host lookup') ||
        message.contains('Connection reset') ||
        message.contains('Connection refused') ||
        message.toLowerCase().contains('unable to reach host');
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

    final http.Response response;

    try {
      response = await http
          .post(
            Uri.parse('$baseUrl/api/trips/generate'),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(generateRequestTimeout);
    } on TimeoutException {
      _debugLog(
        'TripService: generateTrip timed out after '
        '${generateRequestTimeout.inSeconds}s',
      );
      throw const AiBusyException();
    }

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
    // AI BUSY
    // ----------------------------------------------------------

    if (response.statusCode == 503 &&
        decoded is Map &&
        decoded['error'] == 'ai_busy') {
      throw const AiBusyException();
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

    // This endpoint returns a raw decoded map rather than a TripModel
    // (unlike updateTrip/regenerateItinerary/getTrip below), so parse
    // the created trip here and resync its reminders right away —
    // otherwise a trip created from the planner would carry no
    // notifications until the next getTrips()/getTrip() lands.
    if (decoded is Map && decoded['success'] == true) {
      final trip = decoded['trip'];

      if (trip is Map) {
        unawaited(
          _scheduleReminders(
            TripModel.fromJson(
              Map<String, dynamic>.from(trip),
            ),
          ),
        );
      }
    }

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

    // A server write confirmed we are online — freshen the local cache so
    // an offline view later shows this latest version.
    isOffline = false;
    unawaited(_saveTripCache(parsed));

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

    isOffline = false;
    unawaited(_saveTripCache(parsed));

    return parsed;
  }

  // ============================================================
  // SWAP A SINGLE TRIP ITINERARY ACTIVITY
  // POST /api/trips/<tripId>/swap-activity
  // ============================================================

  Future<TripModel> swapActivity({
    required int tripId,
    required int day,
    required String time,
  }) async {
    final headers = await _headers();

    final response = await http.post(
      Uri.parse('$baseUrl/api/trips/$tripId/swap-activity'),
      headers: headers,
      body: jsonEncode({'day': day, 'time': time}),
    );

    final decoded = _decodeResponse(response);

    _debugLog('====================================');
    _debugLog('POST /api/trips/$tripId/swap-activity');
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
          decoded['message']?.toString() ?? 'Failed to swap activity.',
        );
      }

      throw Exception('Failed to swap activity.');
    }

    if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
      throw Exception('Failed to swap activity.');
    }

    final updatedTrip = decoded['trip'];

    if (updatedTrip is! Map) {
      throw Exception('Backend response does not contain a valid trip.');
    }

    final parsed = TripModel.fromJson(Map<String, dynamic>.from(updatedTrip));

    // Itinerary content changed but dates are unlikely to — rescheduling
    // is still cheap (cancel + re-add 3 local notifications) and keeps
    // this correct even if a swap ever touches dates later.
    unawaited(_scheduleReminders(parsed));

    isOffline = false;
    unawaited(_saveTripCache(parsed));

    return parsed;
  }

  // ============================================================
  // GET ALL USER TRIPS
  // GET /api/trips
  // ============================================================

  Future<List<TripModel>> getTrips() async {
    List<TripModel> trips;

    try {
      trips = await _fetchTripsFromNetwork();
    } catch (error) {
      // Only fall back to saved data when the backend itself could not
      // be reached. A real HTTP response (401 session, 404/500, validation)
      // is rethrown so screens never render a stale trip as if it were live.
      if (!_isNetworkError(error)) {
        rethrow;
      }

      final cached = await _readTripsCache();

      if (cached.isNotEmpty) {
        isOffline = true;
        return cached;
      }

      rethrow;
    }

    isOffline = false;

    // Save the fresh list before returning so the next offline launch has
    // the latest version of every trip.
    unawaited(_saveTripsCache(trips));

    return trips;
  }

  Future<List<TripModel>> _fetchTripsFromNetwork() async {
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
    TripModel trip;

    try {
      trip = await _fetchTripFromNetwork(tripId);
    } catch (error) {
      if (!_isNetworkError(error)) {
        rethrow;
      }

      final cached = await _readTripCache(tripId);

      if (cached != null) {
        isOffline = true;
        return cached;
      }

      rethrow;
    }

    isOffline = false;

    unawaited(_saveTripCache(trip));

    return trip;
  }

  Future<TripModel> _fetchTripFromNetwork(int tripId) async {
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
  // OFFLINE CACHE
  // ============================================================

  /// Saves a single freshly fetched trip into its dedicated cache slot and
  /// merges it into the cached trips list so both views stay consistent.
  Future<void> _saveTripCache(TripModel trip) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString(
        '$_tripCacheKeyPrefix${trip.id}',
        jsonEncode(trip.toDetailMap()),
      );

      final cached = await _readTripsCache();
      final upserted = <TripModel>[];
      var replaced = false;

      for (final item in cached) {
        if (item.id != null && item.id == trip.id) {
          upserted.add(trip);
          replaced = true;
        } else {
          upserted.add(item);
        }
      }

      if (!replaced) {
        upserted.add(trip);
      }

      await prefs.setString(
        _tripsCacheKey,
        _serializeTrips(upserted),
      );
    } catch (e) {
      _debugLog('TripService: failed to save trip cache: $e');
    }
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

    // Drop the deleted trip from the offline cache so a later offline
    // launch doesn't resurrect it.
    isOffline = false;

    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.remove('$_tripCacheKeyPrefix$tripId');

      final cached = await _readTripsCache();
      final remaining =
          cached.where((item) => item.id != tripId).toList();

      await prefs.setString(
        _tripsCacheKey,
        _serializeTrips(remaining),
      );
    } catch (e) {
      _debugLog('TripService: failed to prune deleted trip from cache: $e');
    }
  }
}