import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/weather_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-flight dedupe + cache behaviour for [WeatherService].
///
/// [WeatherService.baseUrl] is a compile-time constant, so the backend call is
/// intercepted with [HttpOverrides] and every real HTTP request is counted to
/// assert how often the (mocked) Open-Meteo-backed endpoint is hit.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecordingOverrides overrides;

  // A fresh trip id per test: WeatherService._cache is process-global, so a
  // warm entry from an earlier test would hide the request we want to assert on.
  var nextTripId = 100;

  setUp(() {
    SharedPreferences.setMockInitialValues({'access_token': 'test-token'});
    overrides = RecordingOverrides();
    HttpOverrides.global = overrides;
  });

  tearDown(() {
    HttpOverrides.global = null;
  });

  test('concurrent calls for the same trip share one backend request',
      () async {
    final tripId = nextTripId++;
    final first = WeatherService.fetchWeather(tripId);
    final second = WeatherService.fetchWeather(tripId);

    final result1 = await first;
    final result2 = await second;

    expect(overrides.requestCount, 1);
    expect(result1['available'], true);
    expect(result2['available'], true);
  });

  test('fresh calls within the 30-minute TTL are served from cache', () async {
    final tripId = nextTripId++;
    await WeatherService.fetchWeather(tripId);
    expect(overrides.requestCount, 1);

    await WeatherService.fetchWeather(tripId);
    expect(overrides.requestCount, 1, reason: 'cache hit must not hit backend');
  });

  test('force refresh bypasses the cache', () async {
    final tripId = nextTripId++;
    await WeatherService.fetchWeather(tripId);
    expect(overrides.requestCount, 1);

    await WeatherService.fetchWeather(tripId, force: true);
    expect(overrides.requestCount, 2, reason: 'force must refetch');
  });

  test('parses the stale field from a 429-stale response', () async {
    overrides.responseBody = jsonEncode({
      'success': true,
      'available': true,
      'stale': true,
      'cached': false,
      'forecast': [
        {
          'date': '2026-09-24',
          'label': 'Mainly clear',
          'icon': 'mostly_clear',
          'tempMax': 25.0,
        }
      ],
    });

    final result = await WeatherService.fetchWeather(nextTripId++);

    expect(overrides.requestCount, 1);
    expect(result['available'], true);
    expect(result['stale'], true);
    expect(result['forecast'], isA<List>());
  });

  test('an in-flight failure is not cached and can be retried', () async {
    final tripId = nextTripId++;
    overrides.statusCode = 500;
    await expectLater(
      WeatherService.fetchWeather(tripId),
      throwsA(isA<Exception>()),
    );

    overrides.statusCode = 200;
    final result = await WeatherService.fetchWeather(tripId);
    expect(result['available'], true);
    expect(overrides.requestCount, 2);
  });
}

/// Counts every [HttpClient.openUrl] call and returns canned responses.
class RecordingOverrides extends HttpOverrides {
  int requestCount = 0;
  int statusCode = 200;
  String responseBody =
      '{"success":true,"available":true,"cached":false,"forecast":[]}';

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _FakeHttpClient(this);
}

class _FakeHttpClient implements HttpClient {
  final RecordingOverrides owner;

  _FakeHttpClient(this.owner);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    owner.requestCount++;
    return _FakeHttpRequest(this, url);
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);

  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);

  @override
  Future<HttpClientRequest> putUrl(Uri url) => openUrl('PUT', url);

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => openUrl('DELETE', url);

  @override
  Future<HttpClientRequest> headUrl(Uri url) => openUrl('HEAD', url);

  @override
  Future<HttpClientRequest> patchUrl(Uri url) => openUrl('PATCH', url);

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) {
    return openUrl(method, Uri(scheme: 'http', host: host, port: port, path: path));
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpRequest implements HttpClientRequest {
  final _FakeHttpClient client;
  final Uri url;

  _FakeHttpRequest(this.client, this.url);

  late final _FakeHttpHeaders _headers = _FakeHttpHeaders();

  @override
  HttpHeaders get headers => _headers;

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  bool persistentConnection = true;

  @override
  int contentLength = -1;

  @override
  Future<HttpClientResponse> close() async => _FakeHttpResponse(
        statusCode: client.owner.statusCode,
        body: client.owner.responseBody,
      );

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    // Drain any request body (none for a GET) without doing anything with it.
    return stream.listen(null).asFuture<void>(null);
  }

  @override
  void add(List<int> data) {}

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> _values = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name] = [value.toString()];
  }

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    _values.putIfAbsent(name, () => []).add(value.toString());
  }

  @override
  List<String>? operator [](String name) => _values[name];

  @override
  String? value(String name) => _values[name]?.firstOrNull;

  @override
  void forEach(void Function(String name, List<String> values) action) {
    _values.forEach(action);
  }

  @override
  void clear() => _values.clear();

  @override
  void remove(String name, Object value) => _values.remove(name);

  @override
  void removeAll(String name) => _values.remove(name);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpResponse implements HttpClientResponse {
  _FakeHttpResponse({required this.statusCode, required this.body});

  @override
  final int statusCode;
  final String body;

  @override
  int get contentLength =>
      body.isEmpty ? 0 : utf8.encode(body).length;

  @override
  bool get isRedirect => false;

  @override
  bool get persistentConnection => false;

  @override
  String get reasonPhrase => statusCode == 200 ? 'OK' : 'Error';

  @override
  HttpHeaders get headers => _FakeHttpHeaders();

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([utf8.encode(body)])
        .listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #redirects) return const <RedirectInfo>[];
    return null;
  }
}
