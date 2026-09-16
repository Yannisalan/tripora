import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/routes/app_routes.dart';

void main() {
  test('free-only: no premium or gated travel routes are registered', () {
    final routes = AppRoutes.routes;
    // No premium paywall, subscription hub, or gated stays/cars routes.
    expect(routes.containsKey('/premium'), isFalse);
    expect(routes.containsKey('/travel'), isFalse);
    expect(routes.containsKey('/travel/stays'), isFalse);
    expect(routes.containsKey('/travel/cars'), isFalse);
    // Core app routes remain.
    expect(routes.containsKey(AppRoutes.home), isTrue);
    expect(routes.containsKey(AppRoutes.profile), isTrue);
    expect(routes.containsKey(AppRoutes.travelFlights), isTrue);
  });
}