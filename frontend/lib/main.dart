import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../services/auth_service.dart';
import 'core/auth/auth_guard.dart';
import 'core/auth/login_gate.dart';
import '../services/notification_service.dart';
import 'core/preferences/app_preferences.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/route_tracker.dart';
import 'routes/app_routes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details, forceReport: true);
  };

  final prefs = AppPreferences.instance;

  await prefs.load();
  unawaited(prefs.ensureRates());

  await NotificationService.instance.init();

  // Guest-first: the app always opens on Home. The stored session is only
  // read so the UI can decide what to show — never to force a login wall.
  var isLoggedIn = false;

  try {
    isLoggedIn = await AuthService().isLoggedIn();
  } catch (_) {
    isLoggedIn = false;
  }

  // Deep link / page refresh: if a guest lands directly on a protected route
  // (e.g. /planner, /trips, /profile), route them through Login and remember
  // the destination so they continue there after signing in.
  var initialRoute = AppRoutes.home;

  if (!isLoggedIn) {
    final requested = PlatformDispatcher.instance.defaultRouteName;

    if (LoginGate.isProtected(requested)) {
      LoginGate.setReturnTo(requested);
      initialRoute = AppRoutes.login;
    }
  }

  runApp(TriporaApp(initialRoute: initialRoute));
}

class TriporaApp extends StatefulWidget {
  const TriporaApp({
    super.key,
    this.themeMode,
    this.initialRoute = AppRoutes.home,
  });

  /// Allows an external settings screen to control light/dark/system.
  /// When null the app follows the system brightness.
  final ThemeMode? themeMode;

  final String initialRoute;

  @override
  State<TriporaApp> createState() => _TriporaAppState();
}

class _TriporaAppState extends State<TriporaApp> {
  final RouteTrackingObserver _routeTracker = RouteTrackingObserver();

  @override
  Widget build(BuildContext context) {
    // Rebuild the whole tree (locale, delegates) the instant the language
    // or currency preference changes.
    return ListenableBuilder(
      listenable: AppPreferences.instance,
      builder: (context, _) {
        final resolvedThemeMode =
            widget.themeMode ?? AppPreferences.instance.themeMode;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Tripora',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: resolvedThemeMode,
          initialRoute: widget.initialRoute,
          routes: AppRoutes.routes,
          navigatorObservers: [_routeTracker],
          navigatorKey: AuthGuard.navigatorKey,
          locale: AppPreferences.instance.locale,
          supportedLocales: AppPreferences.validLanguages
              .map((code) => Locale(code))
              .toList(),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        );
      },
    );
  }
}
