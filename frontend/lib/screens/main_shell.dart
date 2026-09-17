import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/l10n/app_localizations.dart';
import '../core/preferences/app_preferences.dart';
import '../core/theme/app_theme.dart';
import '../routes/app_routes.dart';
import '../screens/explore/explore_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/travel/flight_search_screen.dart';
import '../screens/trips/trips_screen.dart';

/// Width (CSS pixels) at which the web top header switches from the
/// compact (icon + drawer) layout to the full labeled layout.
///
/// This only affects which WEB header is shown.
/// It does not affect whether the header is shown at all.
///
/// - Web build -> top header
/// - Native app -> bottom navigation
const double _webHeaderCompactBreakpoint = 960;

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  static final ValueNotifier<int> currentIndex =
      ValueNotifier<int>(0);

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey =
      GlobalKey<ScaffoldState>();

  // Pages are rebuilt when preferences change so translated UI
  // and currency-dependent UI remain synchronized.
  List<Widget> _buildPages({bool webChrome = false}) {
    return [
      HomeScreen(showAppBar: !webChrome),
      const ExploreScreen(),
      const FlightSearchScreen(),
      const TripsScreen(),
      const ProfileScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // Platform decides top-vs-bottom navigation.
    //
    // Web:
    //   phone/tablet/laptop browser -> top header
    //
    // Native:
    //   Android/iOS -> bottom navigation
    const bool showWebHeader = kIsWeb;

    return ListenableBuilder(
      listenable: AppPreferences.instance,
      builder: (context, _) {
        return ValueListenableBuilder<int>(
          valueListenable: MainShell.currentIndex,
          builder: (context, currentIndex, _) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final isCompactWeb =
                    constraints.maxWidth <
                    _webHeaderCompactBreakpoint;

                void selectTab(int index) {
                  MainShell.currentIndex.value = index;

                  // Close the web drawer after selecting an item.
                  if (_scaffoldKey.currentState?.isDrawerOpen ??
                      false) {
                    Navigator.of(context).pop();
                  }
                }

                return Scaffold(
                  key: _scaffoldKey,

                  // Only the compact web layout uses a drawer.
                  drawer: (showWebHeader && isCompactWeb)
                      ? _TriporaWebDrawer(
                          currentIndex: currentIndex,
                          onSelected: selectTab,
                        )
                      : null,

                  body: Column(
                    children: [
                      if (showWebHeader)
                        isCompactWeb
                            ? _TriporaCompactWebHeader(
                                onMenuTap: () {
                                  _scaffoldKey.currentState
                                      ?.openDrawer();
                                },
                              )
                            : _TriporaWebHeader(
                                currentIndex: currentIndex,
                                onSelected: selectTab,
                              ),

                      Expanded(
                        child: IndexedStack(
                          index: currentIndex,
                          children: _buildPages(
                            webChrome: showWebHeader,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Native app navigation only.
                  bottomNavigationBar: showWebHeader
                      ? null
                      : _TriporaBottomNav(
                          currentIndex: currentIndex,
                          onSelected: selectTab,
                        ),
                );
              },
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Shared navigation items
// ---------------------------------------------------------------------------

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

List<_NavItem> _navItems(BuildContext context) {
  return [
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
}

// ---------------------------------------------------------------------------
// Website top navigation - full
// ---------------------------------------------------------------------------

class _TriporaWebHeader extends StatelessWidget {
  const _TriporaWebHeader({
    required this.currentIndex,
    required this.onSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;

  static const double _maxContentWidth = 1280;

  @override
  Widget build(BuildContext context) {
    final colors = context.triporaColors;
    final items = _navItems(context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(
            color: colors.border,
            width: 0.8,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding =
                constraints.maxWidth < 1200
                    ? 24.0
                    : 40.0;

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: _maxContentWidth,
                ),
                child: SizedBox(
                  height: 68,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                    ),
                    child: Row(
                      children: [
                        const _TriporaBrand(),

                        SizedBox(
                          width: horizontalPadding,
                        ),

                        Expanded(
                          child: Row(
                            children: [
                              for (var i = 0;
                                  i < items.length;
                                  i++) ...[
                                Expanded(
                                  child: _TriporaWebNavItem(
                                    item: items[i],
                                    selected:
                                        i == currentIndex,
                                    onTap: () =>
                                        onSelected(i),
                                  ),
                                ),

                                if (i != items.length - 1)
                                  const SizedBox(width: 4),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(width: 8),

                        const _TriporaPlanTripCta(),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tripora brand
// ---------------------------------------------------------------------------

class _TriporaBrand extends StatelessWidget {
  const _TriporaBrand();

  @override
  Widget build(BuildContext context) {
    final colors = context.triporaColors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Tripora',
          style: GoogleFonts.manrope(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: colors.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Website full navigation item
// ---------------------------------------------------------------------------

class _TriporaWebNavItem extends StatelessWidget {
  const _TriporaWebNavItem({
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
    final scheme = Theme.of(context).colorScheme;

    final color =
        selected ? scheme.primary : colors.textSecondary;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                  fontSize: 15,
                  fontWeight: selected
                      ? FontWeight.w700
                      : FontWeight.w600,
                  color: color,
                ),
              ),

              const SizedBox(height: 5),

              AnimatedContainer(
                duration:
                    const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                width: selected ? 20 : 0,
                height: 3,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius:
                      BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Plan Trip CTA
// ---------------------------------------------------------------------------

class _TriporaPlanTripCta extends StatelessWidget {
  const _TriporaPlanTripCta();

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: () {
        Navigator.pushNamed(
          context,
          AppRoutes.planner,
        );
      },
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(
          horizontal: 18,
        ),
        textStyle: GoogleFonts.manrope(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      icon: const Icon(
        Icons.add_rounded,
        size: 18,
      ),
      label: Text(
        context.tr('nav.planTrip'),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Website compact navigation
//
// Used on narrow browser windows.
//
// IMPORTANT:
// This is still WEB navigation.
// It does NOT become the native bottom navigation.
// ---------------------------------------------------------------------------

class _TriporaCompactWebHeader extends StatelessWidget {
  const _TriporaCompactWebHeader({
    required this.onMenuTap,
  });

  final VoidCallback onMenuTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.triporaColors;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(
            color: colors.border,
            width: 0.8,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: onMenuTap,
                  icon: const Icon(
                    Icons.menu_rounded,
                  ),
                  tooltip:
                      MaterialLocalizations.of(context)
                          .openAppDrawerTooltip,
                ),

                const SizedBox(width: 4),

                const _TriporaBrand(),

                const Spacer(),

                IconButton(
                  onPressed: () {
                    Navigator.pushNamed(
                      context,
                      AppRoutes.planner,
                    );
                  },
                  icon: const Icon(
                    Icons.add_rounded,
                  ),
                  tooltip:
                      context.tr('nav.planTrip'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Website compact drawer
// ---------------------------------------------------------------------------

class _TriporaWebDrawer extends StatelessWidget {
  const _TriporaWebDrawer({
    required this.currentIndex,
    required this.onSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final items = _navItems(context);
    final colors = context.triporaColors;
    final scheme = Theme.of(context).colorScheme;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                8,
              ),
              child: _TriporaBrand(),
            ),

            Divider(
              color: colors.border,
              height: 1,
            ),

            for (var i = 0; i < items.length; i++)
              ListTile(
                leading: Icon(
                  i == currentIndex
                      ? items[i].selectedIcon
                      : items[i].icon,
                  color: i == currentIndex
                      ? scheme.primary
                      : colors.textSecondary,
                ),
                title: Text(
                  items[i].label,
                  style: GoogleFonts.manrope(
                    fontWeight: i == currentIndex
                        ? FontWeight.w700
                        : FontWeight.w600,
                    color: i == currentIndex
                        ? scheme.primary
                        : colors.textPrimary,
                  ),
                ),
                selected: i == currentIndex,
                onTap: () => onSelected(i),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Native app bottom navigation
// ---------------------------------------------------------------------------

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
    final items = _navItems(context);

    return SizedBox(
      height:
          64 + MediaQuery.of(context).padding.bottom,
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
            bottom:
                MediaQuery.of(context).padding.bottom,
            child: Center(
              child: Container(
                margin:
                    const EdgeInsets.symmetric(
                  horizontal: 16,
                ),
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color:
                      colors.surface.withValues(
                    alpha: 0.92,
                  ),
                  borderRadius:
                      BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color:
                          AppColors.primary.withValues(
                        alpha: 0.12,
                      ),
                      blurRadius: 24,
                      spreadRadius: 0,
                      offset:
                          const Offset(0, -4),
                    ),
                    BoxShadow(
                      color:
                          Colors.black.withValues(
                        alpha: 0.08,
                      ),
                      blurRadius: 12,
                      offset:
                          const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(
                    color:
                        colors.border.withValues(
                      alpha: 0.5,
                    ),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  children: [
                    for (var i = 0;
                        i < items.length;
                        i++)
                      Expanded(
                        child: _TriporaNavItem(
                          item: items[i],
                          selected:
                              i == currentIndex,
                          onTap: () =>
                              onSelected(i),
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

// ---------------------------------------------------------------------------
// Native navigation item
// ---------------------------------------------------------------------------

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
        borderRadius:
            BorderRadius.circular(22),
        child: AnimatedContainer(
          duration:
              const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          margin:
              const EdgeInsets.symmetric(
            horizontal: 2,
          ),
          padding:
              const EdgeInsets.symmetric(
            vertical: 9,
            horizontal: 4,
          ),
          decoration: BoxDecoration(
            color: selected
                ? activeColor.withValues(
                    alpha: 0.12,
                  )
                : Colors.transparent,
            borderRadius:
                BorderRadius.circular(22),
            border: selected
                ? Border.all(
                    color:
                        activeColor.withValues(
                      alpha: 0.10,
                    ),
                    width: 0.8,
                  )
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration:
                    const Duration(milliseconds: 180),
                transitionBuilder:
                    (child, animation) {
                  return ScaleTransition(
                    scale: Tween<double>(
                      begin: 0.88,
                      end: 1,
                    ).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve:
                            Curves.easeOutBack,
                      ),
                    ),
                    child: FadeTransition(
                      opacity: animation,
                      child: child,
                    ),
                  );
                },
                child: Icon(
                  selected
                      ? item.selectedIcon
                      : item.icon,
                  key: ValueKey(selected),
                  size: 23,
                  color: selected
                      ? activeColor
                      : inactiveColor,
                ),
              ),

              const SizedBox(height: 4),

              AnimatedDefaultTextStyle(
                duration:
                    const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall!
                    .copyWith(
                      color: selected
                          ? activeColor
                          : inactiveColor,
                      fontWeight: selected
                          ? FontWeight.w700
                          : FontWeight.w600,
                    ),
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}