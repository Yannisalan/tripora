import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/l10n/app_localizations.dart';
import '../core/preferences/app_preferences.dart';
import '../core/theme/app_theme.dart';
import '../screens/explore/explore_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/travel/flight_search_screen.dart';
import '../screens/trips/trips_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  static final ValueNotifier<int> currentIndex = ValueNotifier<int>(0);

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  // Built per-render (not const) so a language/currency/theme change —
  // which rebuilds MainShell through the ListenableBuilder below — also
  // rebuilds the tab contents instead of serving stale instances.
  List<Widget> _buildPages() {
    return [
      HomeScreen(),
      ExploreScreen(),
      FlightSearchScreen(),
      TripsScreen(),
      ProfileScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // Re-render the shell (nav labels, every tab) whenever preferences
    // change so translated labels and per-currency UI stay in sync.
    return ListenableBuilder(
      listenable: AppPreferences.instance,
      builder: (context, _) {
        return ValueListenableBuilder<int>(
          valueListenable: MainShell.currentIndex,
          builder: (context, currentIndex, _) {
            return Scaffold(
              body: IndexedStack(
                index: currentIndex,
                children: _buildPages(),
              ),
              bottomNavigationBar: _TriporaBottomNav(
                currentIndex: currentIndex,
                onSelected: (index) {
                  MainShell.currentIndex.value = index;
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _TriporaBottomNav extends StatelessWidget {
  const _TriporaBottomNav({
    required this.currentIndex,
    required this.onSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.triporaColors;

    final items = [
      _NavItem(
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
        label: context.tr('nav.home'),
      ),
      _NavItem(
        icon: Icons.explore_outlined,
        selectedIcon: Icons.explore,
        label: context.tr('nav.explore'),
      ),
      _NavItem(
        icon: Icons.flight_takeoff_outlined,
        selectedIcon: Icons.flight_takeoff,
        label: context.tr('nav.flights'),
      ),
      _NavItem(
        icon: Icons.card_travel_outlined,
        selectedIcon: Icons.card_travel,
        label: context.tr('nav.trips'),
      ),
      _NavItem(
        icon: Icons.person_outline,
        selectedIcon: Icons.person,
        label: context.tr('nav.profile'),
      ),
    ];

    return SizedBox(
      height: 64 + MediaQuery.of(context).padding.bottom,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned.fill(
            child: Container(
              color: Colors.transparent,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom,
            child: Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      blurRadius: 24,
                      spreadRadius: 0,
                      offset: const Offset(0, -4),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(
                    color: colors.border.withValues(alpha: 0.5),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      Expanded(
                        child: _TriporaNavItem(
                          item: items[i],
                          selected: i == currentIndex,
                          onTap: () => onSelected(i),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TriporaNavItem extends StatelessWidget {
  const _TriporaNavItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.triporaColors;

    final activeColor = AppColors.primary;
    final inactiveColor = colors.textMuted;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(
            vertical: 9,
            horizontal: 4,
          ),
          decoration: BoxDecoration(
            color: selected
                ? activeColor.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            border: selected
                ? Border.all(
              color: activeColor.withValues(alpha: 0.10),
              width: 0.8,
            )
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, animation) {
                  return ScaleTransition(
                    scale: Tween<double>(
                      begin: 0.88,
                      end: 1,
                    ).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutBack,
                      ),
                    ),
                    child: FadeTransition(
                      opacity: animation,
                      child: child,
                    ),
                  );
                },
                child: Icon(
                  selected ? item.selectedIcon : item.icon,
                  key: ValueKey(selected),
                  size: 23,
                  color: selected ? activeColor : inactiveColor,
                ),
              ),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: selected ? activeColor : inactiveColor,
                  fontWeight:
                  selected ? FontWeight.w700 : FontWeight.w600,
                ),
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}