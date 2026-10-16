import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/auth/login_gate.dart';
import '../core/design/glass/glass_background.dart';
import '../core/design/glass/glass_nav.dart';
import '../core/design/glass/glass_surface.dart';
import '../core/design/glass/glass_tokens.dart';
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

                  // Let the floating glass bottom bar sit over the ambient
                  // background so it can refract it. The web layout keeps a
                  // solid header, so body extension is not needed there.
                  extendBody: !showWebHeader,
                  backgroundColor: Colors.transparent,

                  // Only the compact web layout uses a drawer.
                  drawer: (showWebHeader && isCompactWeb)
                      ? _TriporaWebDrawer(
                          currentIndex: currentIndex,
                          onSelected: selectTab,
                        )
                      : null,

                  body: GlassBackground(
                    intensity: 0.9,
                    child: Column(
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
    final items = _navItems(context);

    return GlassSurface(
      variant: GlassVariant.bar,
      borderRadius: BorderRadius.zero,
      padding: EdgeInsets.zero,
      elevation: 0.6,
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
        LoginGate.open(
          context,
          route: AppRoutes.planner,
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
    return GlassSurface(
      variant: GlassVariant.bar,
      borderRadius: BorderRadius.zero,
      padding: EdgeInsets.zero,
      elevation: 0.6,
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
                    LoginGate.open(
                      context,
                      route: AppRoutes.planner,
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
      backgroundColor: Colors.transparent,
      child: GlassSurface(
        variant: GlassVariant.sheet,
        borderRadius: const BorderRadius.horizontal(
          right: Radius.circular(GlassRadius.xl),
        ),
        padding: EdgeInsets.zero,
        elevation: 0,
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
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Native app bottom navigation
//
// Delegates to the shared Liquid Glass bottom bar. The bar is a floating,
// capsule-shaped glass surface that refracts the ambient background behind
// it (see GlassBottomNav / GlassSurface).
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
    final items = _navItems(context);

    return GlassBottomNav(
      currentIndex: currentIndex,
      onSelected: onSelected,
      items: [
        for (final item in items)
          GlassNavItem(
            icon: item.icon,
            selectedIcon: item.selectedIcon,
            label: item.label,
          ),
      ],
    );
  }
}

