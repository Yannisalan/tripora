import 'package:flutter/material.dart';

import '../../core/design/glass/glass_nav.dart';
import '../../core/l10n/app_localizations.dart';
import '../../routes/app_routes.dart';

/// One primary destination of the app shell.
///
/// The single list below is the only definition of the five tabs. The
/// bottom bar, the rail and the sidebar are all built from it, so their
/// order, icons and labels cannot drift apart.
class AppDestination {
  const AppDestination({
    required this.icon,
    required this.selectedIcon,
    required this.labelKey,
    required this.route,
  });

  final IconData icon;
  final IconData selectedIcon;

  /// Localization key of the visible label.
  final String labelKey;

  /// The standalone route that shows the same screen outside the shell.
  final String route;
}

/// The five primary destinations, in display order. The index in this list
/// is the tab index stored in `MainShell.currentIndex`.
const List<AppDestination> appDestinations = [
  AppDestination(
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    labelKey: 'nav.home',
    route: AppRoutes.home,
  ),
  AppDestination(
    icon: Icons.explore_outlined,
    selectedIcon: Icons.explore,
    labelKey: 'nav.explore',
    route: AppRoutes.explore,
  ),
  AppDestination(
    icon: Icons.flight_takeoff_outlined,
    selectedIcon: Icons.flight_takeoff,
    labelKey: 'nav.flights',
    route: AppRoutes.travelFlights,
  ),
  AppDestination(
    icon: Icons.card_travel_outlined,
    selectedIcon: Icons.card_travel,
    labelKey: 'nav.trips',
    route: AppRoutes.trips,
  ),
  AppDestination(
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
    labelKey: 'nav.profile',
    route: AppRoutes.profile,
  ),
];

/// Tab index of the Profile destination.
final int profileTabIndex = appDestinations.indexWhere(
  (d) => d.route == AppRoutes.profile,
);

/// [appDestinations] as localized nav items for the glass navigation
/// widgets.
List<GlassNavItem> appNavItems(BuildContext context) => [
  for (final d in appDestinations)
    GlassNavItem(
      icon: d.icon,
      selectedIcon: d.selectedIcon,
      label: context.tr(d.labelKey),
    ),
];
