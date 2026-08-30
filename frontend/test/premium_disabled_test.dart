import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/config/app_config.dart';
import 'package:frontend/routes/app_routes.dart';

void main() {
  test('v1 free-only: premium routes are not registered by default', () {
    expect(AppConfig.premiumEnabled, isFalse);
    final routes = AppRoutes.routes;
    expect(routes.containsKey(AppRoutes.premium), isFalse);
    expect(routes.containsKey(AppRoutes.travel), isFalse);
    expect(routes.containsKey(AppRoutes.travelFlights), isFalse);
    expect(routes.containsKey(AppRoutes.travelStays), isFalse);
    expect(routes.containsKey(AppRoutes.travelCars), isFalse);
    // Core app routes remain.
    expect(routes.containsKey(AppRoutes.home), isTrue);
    expect(routes.containsKey(AppRoutes.profile), isTrue);
  });
}
