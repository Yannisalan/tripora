import 'package:flutter/material.dart';

import '../core/design/glass/glass_background.dart';
import '../core/design/glass/glass_nav.dart';
import '../core/design/glass/glass_tokens.dart';
import '../core/preferences/active_aura.dart';
import '../core/preferences/app_preferences.dart';
import '../screens/explore/explore_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/travel/flight_search_screen.dart';
import '../screens/trips/trips_screen.dart';
import 'shell/app_destinations.dart';
import 'shell/app_side_navigation.dart';

/// Root shell with the five primary destinations.
///
/// Navigation placement is decided by available width only (see
/// [TriporaBreakpoints]), never by platform:
///
/// - compact  (< 768):     floating Liquid Glass bottom bar
/// - medium   (768-1279):  72 px icon-only rail ([AppNavRail])
/// - expanded (>= 1280):   240 px sidebar ([AppSidebar])
///
/// Exactly one of the three is built at any time, all from the shared
/// [appDestinations] list. The pages live in one
/// [IndexedStack] under a [GlobalKey], so crossing a breakpoint keeps every
/// page's State (scroll positions, form values, loaded data) alive.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  static final ValueNotifier<int> currentIndex = ValueNotifier<int>(0);

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  /// Keeps the page stack (and every page's State) across layout changes.
  final GlobalKey _pagesKey = GlobalKey(debugLabel: 'MainShell.pages');

  /// The five page widgets, built once and reused: identical widget
  /// instances let a tab switch only re-lay-out the IndexedStack instead of
  /// rebuilding all five pages. Rebuilt when the layout crosses the
  /// sidebar breakpoint or a preference (language, currency) changes;
  /// theme changes still reach every page through Theme.of.
  List<Widget>? _pages;
  bool? _pagesForSideNav;

  void _onPreferencesChanged() => _pages = null;

  List<Widget> _pagesFor({required bool sideNav}) {
    if (_pages == null || _pagesForSideNav != sideNav) {
      _pages = _buildPages(sideNav: sideNav);
      _pagesForSideNav = sideNav;
    }
    return _pages!;
  }

  @override
  void initState() {
    super.initState();
    // Restore the locally stored Active Aura (no-op once loaded).
    ActiveAura.instance.load();
    AppPreferences.instance.addListener(_onPreferencesChanged);
  }

  @override
  void dispose() {
    AppPreferences.instance.removeListener(_onPreferencesChanged);
    super.dispose();
  }

  // Pages are rebuilt when preferences change so translated UI
  // and currency-dependent UI remain synchronized.
  List<Widget> _buildPages({required bool sideNav}) {
    return [
      // With the rail or sidebar, the Plan a Trip CTA and the theme switch
      // live in the side navigation, so Home hides its own app bar to
      // avoid duplicating them.
      HomeScreen(showAppBar: !sideNav),
      const ExploreScreen(),
      const FlightSearchScreen(),
      const TripsScreen(),
      const ProfileScreen(),
    ];
  }

  void _selectTab(int index) {
    MainShell.currentIndex.value = index;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppPreferences.instance,
      builder: (context, _) {
        return ValueListenableBuilder<int>(
          valueListenable: MainShell.currentIndex,
          builder: (context, currentIndex, _) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final mode = TriporaBreakpoints.navFor(constraints.maxWidth);
                final sideNav = mode != TriporaNavMode.bottomBar;

                Widget pages = KeyedSubtree(
                  key: _pagesKey,
                  child: IndexedStack(
                    index: currentIndex,
                    children: _pagesFor(sideNav: sideNav),
                  ),
                );

                if (sideNav) {
                  // The rail / sidebar already consumes the left inset.
                  pages = MediaQuery.removePadding(
                    context: context,
                    removeLeft: true,
                    child: pages,
                  );
                }

                return Scaffold(
                  // Let the floating glass bottom bar sit over the ambient
                  // background so it can refract it. This also makes the
                  // body's bottom padding equal the bar's height, which
                  // pages use for content clearance
                  // (GlassNavMetrics.bottomClearance).
                  extendBody: true,
                  backgroundColor: Colors.transparent,

                  body: GlassBackground(
                    intensity: 0.9,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (mode == TriporaNavMode.sidebar)
                          AppSidebar(
                            currentIndex: currentIndex,
                            onSelected: _selectTab,
                          )
                        else if (mode == TriporaNavMode.rail)
                          AppNavRail(
                            currentIndex: currentIndex,
                            onSelected: _selectTab,
                          ),
                        Expanded(child: pages),
                      ],
                    ),
                  ),

                  bottomNavigationBar: sideNav
                      ? null
                      : _TriporaBottomNav(
                          currentIndex: currentIndex,
                          onSelected: _selectTab,
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
// Compact layout: floating bottom bar
//
// Delegates to the shared Liquid Glass bottom bar. The bar is a floating,
// capsule-shaped glass surface that refracts the ambient background behind
// it (see GlassBottomNav / GlassSurface).
//
// While the on-screen keyboard is open the bar collapses, so it can never
// sit on top of a focused text field; the body's bottom padding shrinks
// with it, and the bar returns when the keyboard closes.
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
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      return const SizedBox.shrink();
    }

    return GlassBottomNav(
      currentIndex: currentIndex,
      onSelected: onSelected,
      items: appNavItems(context),
    );
  }
}
