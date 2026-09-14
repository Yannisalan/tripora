import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../screens/explore/explore_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/travel/flight_search_screen.dart';
import '../screens/trips/trips_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  /// Shared across the app so screens nested inside the shell (Home,
  /// Explore, etc.) can switch tabs without pushing a new route — pushing
  /// would render the target screen outside this shell, hiding the bottom
  /// nav bar.
  static final ValueNotifier<int> currentIndex = ValueNotifier<int>(0);

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const List<Widget> _pages = [
    HomeScreen(),
    ExploreScreen(),
    FlightSearchScreen(),
    TripsScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: MainShell.currentIndex,
      builder: (context, currentIndex, _) {
        return Scaffold(
          body: IndexedStack(index: currentIndex, children: _pages),
          bottomNavigationBar: NavigationBar(
            selectedIndex: currentIndex,
            onDestinationSelected: (index) {
              MainShell.currentIndex.value = index;
            },
            backgroundColor: AppColors.surface,
            indicatorColor: AppColors.primary.withValues(alpha: 0.14),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.explore_outlined),
                selectedIcon: Icon(Icons.explore),
                label: 'Explore',
              ),
              NavigationDestination(
                icon: Icon(Icons.flight_takeoff_outlined),
                selectedIcon: Icon(Icons.flight_takeoff),
                label: 'Flights',
              ),
              NavigationDestination(
                icon: Icon(Icons.card_travel_outlined),
                selectedIcon: Icon(Icons.card_travel),
                label: 'My Trips',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
          ),
        );
      },
    );
  }
}