import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'core/utils/route_tracker.dart';
import 'routes/app_routes.dart';

void main() {
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
  Widget build(BuildContext context) {
    final themeMode = widget.themeMode ?? ThemeMode.light;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tripora',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      initialRoute: AppRoutes.home,
      routes: AppRoutes.routes,
      navigatorObservers: [_routeTracker],
    );
  }
}
