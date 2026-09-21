import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/auth/auth_guard.dart';
import '../services/notification_service.dart';
import 'core/preferences/app_preferences.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/route_tracker.dart';
import 'routes/app_routes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Temporary diagnostic: always print the full stack for every exception so
  // the "Null check operator used on a null value" source line is visible.
  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details, forceReport: true);
  };

  final prefs = AppPreferences.instance;

  // Restore the saved language/currency, then kick off a best-effort
  // refresh of the conversion table in the background.
  await prefs.load();
  unawaited(prefs.ensureRates());

  await NotificationService.instance.init();
  runApp(const TriporaApp());
}

class TriporaApp extends StatefulWidget {
  const TriporaApp({super.key, this.themeMode});

  /// Allows an external settings screen to control light/dark/system.
  /// When null the app follows the system brightness.
  final ThemeMode? themeMode;

  @override
  State<TriporaApp> createState() => _TriporaAppState();
}

class _TriporaAppState extends State<TriporaApp> {
  final RouteTrackingObserver _routeTracker = RouteTrackingObserver();

  @override
  void initState() {
    super.initState();
    // Ask for notification permission right after the first frame renders.
    // Doing this before runApp() (e.g. in main()) risks failing silently on
    // Android, since the plugin needs a live Activity attached first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.instance.requestPermission();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild the whole tree (locale, delegates) the instant the language
    // or currency preference changes.
    return ListenableBuilder(
      listenable: AppPreferences.instance,
      builder: (context, _) {
        final resolvedThemeMode = widget.themeMode ?? AppPreferences.instance.themeMode;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Tripora',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: resolvedThemeMode,
          initialRoute: AppRoutes.home,
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