import 'package:flutter/material.dart';

import '../../routes/app_routes.dart';
import '../../screens/main_shell.dart';
import '../../services/auth_service.dart';

/// A small, reusable "require login, then continue" gate.
///
/// Every place that needs a signed-in user — opening the Planner ("Start
/// planning" / "Plan a Trip"), the guarded My Trips and Profile tabs, or a
/// protected deep link — goes through this helper instead of pushing Login
/// directly. When there is no session the user is sent to Login and the
/// intended destination is remembered, so a successful login lands them
/// exactly where they were heading (rather than always on Home).
///
/// This reuses the app's single source of truth for auth state
/// ([AuthService] / the `access_token` preference); it never changes how
/// tokens are stored or validated.
class LoginGate {
  LoginGate._();

  /// Routes that require a signed-in user.
  static const Set<String> _protectedRoutes = {
    AppRoutes.planner,
    AppRoutes.trips,
    AppRoutes.profile,
    AppRoutes.itinerary,
  };

  /// Shell tab indices for the guarded tabs (see `MainShell._buildPages`).
  static const int tripsTab = 3;
  static const int profileTab = 4;

  /// Guarded routes that map onto a shell tab (My Trips / Profile), so we can
  /// return the user to the same tab instead of a standalone screen.
  static const Map<String, int> _routeTabs = {
    AppRoutes.trips: tripsTab,
    AppRoutes.profile: profileTab,
  };

  static String? _route;
  static Object? _arguments;
  static int? _tabIndex;

  /// Whether [route] must not be shown to a guest.
  static bool isProtected(String? route) =>
      route != null && _protectedRoutes.contains(route);

  /// Remembers where to continue after login.
  ///
  /// Used for deep links / refreshes, where the target route cannot be handed
  /// to the navigator through [open].
  static void setReturnTo(String route, {Object? arguments}) {
    _route = route;
    _arguments = arguments;
    _tabIndex = _routeTabs[route];
  }

  /// Forgets any remembered destination.
  static void clear() {
    _route = null;
    _arguments = null;
    _tabIndex = null;
  }

  /// Opens [route], requiring a signed-in user first.
  ///
  /// - signed in -> pushes [route] immediately (unchanged behaviour).
  /// - guest      -> opens Login and remembers [route] for after login.
  static Future<void> open(
    BuildContext context, {
    required String route,
    Object? arguments,
  }) async {
    var signedIn = false;

    try {
      signedIn = await AuthService().isLoggedIn();
    } catch (_) {
      signedIn = false;
    }

    if (!context.mounted) return;

    if (signedIn) {
      Navigator.pushNamed(context, route, arguments: arguments);
      return;
    }

    setReturnTo(route, arguments: arguments);
    Navigator.pushNamed(context, AppRoutes.login);
  }

  /// Switches to a guarded shell tab (My Trips / Profile), requiring a
  /// signed-in user first. Guests are returned to the same tab after login.
  static Future<void> openTab(
    BuildContext context, {
    required int tabIndex,
  }) async {
    var signedIn = false;

    try {
      signedIn = await AuthService().isLoggedIn();
    } catch (_) {
      signedIn = false;
    }

    if (!context.mounted) return;

    if (signedIn) {
      MainShell.currentIndex.value = tabIndex;
      return;
    }

    _route = null;
    _arguments = null;
    _tabIndex = tabIndex;
    Navigator.pushNamed(context, AppRoutes.login);
  }

  /// Applies the remembered destination after a successful login.
  static void apply(BuildContext context) {
    final tab = _tabIndex;
    final route = _route;
    final arguments = _arguments;

    clear();

    // Always re-root on the shell so the navigation chrome and ambient
    // background are present, then continue to the destination.
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.home,
      (route) => false,
    );

    if (tab != null) {
      MainShell.currentIndex.value = tab;
      return;
    }

    if (route != null) {
      Navigator.pushNamed(context, route, arguments: arguments);
    }
  }
}
