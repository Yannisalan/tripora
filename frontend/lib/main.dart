import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../services/auth_service.dart';
import 'core/auth/auth_guard.dart';
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

  // Determine the initial screen without displaying a splash screen.
  var isLoggedIn = false;

  try {
    isLoggedIn = await AuthService().isLoggedIn();
  } catch (_) {
    isLoggedIn = false;
  }

  runApp(
    TriporaApp(initialRoute: isLoggedIn ? AppRoutes.home : AppRoutes.login),
  );
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
