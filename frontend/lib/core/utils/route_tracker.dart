import 'package:flutter/material.dart';

import '../../services/activity_service.dart';

/// A [NavigatorObserver] that reports screen visits to the analytics backend.
///
/// Each pushed route that has a name reports that name (e.g. ``/planner``) to
/// the page-view beacon. Reports are fire-and-forget and throttled inside
/// [ActivityService], so navigation is never slowed or blocked by analytics.
class RouteTrackingObserver extends NavigatorObserver {
  RouteTrackingObserver({ActivityService? activity})
      : _activity = activity ?? ActivityService();

  final ActivityService _activity;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    final name = route.settings.name;
    if (name != null && name.isNotEmpty) {
      _activity.trackPageView(name);
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    final name = newRoute?.settings.name;
    if (name != null && name.isNotEmpty) {
      _activity.trackPageView(name);
    }
  }
}
