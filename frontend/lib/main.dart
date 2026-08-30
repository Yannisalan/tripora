import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'routes/app_routes.dart';

void main() {
  runApp(const TriporaApp());
}

class TriporaApp extends StatelessWidget {
  const TriporaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      title: 'Tripora',

      theme: AppTheme.lightTheme,

      initialRoute: AppRoutes.home,

      routes: AppRoutes.routes,
    );
  }
}