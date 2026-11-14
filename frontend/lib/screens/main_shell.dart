import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/auth/login_gate.dart';
import '../core/design/glass/glass_background.dart';
import '../core/design/glass/glass_nav.dart';
import '../core/design/glass/glass_tokens.dart';
import '../core/l10n/app_localizations.dart';
import '../core/auth/token_store.dart';
import '../core/preferences/active_aura.dart';
import '../core/preferences/app_preferences.dart';
import '../core/theme/app_theme.dart';
import '../routes/app_routes.dart';
import '../services/auth_service.dart';
import '../widgets/theme_toggle.dart';
import '../widgets/tripora_brand.dart';
import '../screens/explore/explore_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/travel/flight_search_screen.dart';
import '../screens/trips/trips_screen.dart';

/// Root shell with the five primary destinations.
///
/// Navigation placement is decided by available width only (see
/// [TriporaBreakpoints]), never by platform:
///
/// - compact / medium (< 1024): floating Liquid Glass bottom bar
/// - expanded (>= 1024):        floating Liquid Glass left sidebar
///
/// Exactly one of the two is built at any time. The pages live in one
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
  bool? _pagesForSidebar;

  void _onPreferencesChanged() => _pages = null;

  List<Widget> _pagesFor({required bool sidebar}) {
    if (_pages == null || _pagesForSidebar != sidebar) {
      _pages = _buildPages(sidebar: sidebar);
      _pagesForSidebar = sidebar;
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
  List<Widget> _buildPages({required bool sidebar}) {
    return [
      // With the sidebar, the brand and the Plan a Trip CTA live in the
      // sidebar, so Home hides its own app bar to avoid duplicating them.
      HomeScreen(showAppBar: !sidebar),
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
                final sidebar = TriporaBreakpoints.usesSidebar(
                  constraints.maxWidth,
                );

                Widget pages = KeyedSubtree(
                  key: _pagesKey,
                  child: IndexedStack(
                    index: currentIndex,
                    children: _pagesFor(sidebar: sidebar),
                  ),
                );

                if (sidebar) {
                  // The sidebar already consumes the left safe-area inset.
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
                        if (sidebar)
                          _TriporaSideNav(
                            currentIndex: currentIndex,
                            onSelected: _selectTab,
                          ),
                        Expanded(child: pages),
                      ],
                    ),
                  ),

                  bottomNavigationBar: sidebar
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
// Shared navigation items
//
// The five destinations, their order, labels and icons are shared by the
// bottom bar and the sidebar so both always present the same navigation.
// ---------------------------------------------------------------------------

List<GlassNavItem> _navItems(BuildContext context) {
  return [
    GlassNavItem(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      label: context.tr('nav.home'),
    ),
    GlassNavItem(
      icon: Icons.explore_outlined,
      selectedIcon: Icons.explore,
      label: context.tr('nav.explore'),
    ),
    GlassNavItem(
      icon: Icons.flight_takeoff_outlined,
      selectedIcon: Icons.flight_takeoff,
      label: context.tr('nav.flights'),
    ),
    GlassNavItem(
      icon: Icons.card_travel_outlined,
      selectedIcon: Icons.card_travel,
      label: context.tr('nav.trips'),
    ),
    GlassNavItem(
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
      label: context.tr('nav.profile'),
    ),
  ];
}

// ---------------------------------------------------------------------------
// Tripora brand
// ---------------------------------------------------------------------------

class _TriporaSidebarHeader extends StatelessWidget {
  const _TriporaSidebarHeader();

  @override
  Widget build(BuildContext context) {
    // Wordmark only (no Active Aura selector, mark, badge or subtitle).
    // The Active Aura is still chosen from the Home destination cards.
    return const Padding(
      padding: EdgeInsets.fromLTRB(12, 10, 4, 12),
      child: TriporaWordmark(),
    );
  }
}

// ---------------------------------------------------------------------------
// Plan Trip CTA (sidebar footer)
// ---------------------------------------------------------------------------

class _TriporaPlanTripCta extends StatelessWidget {
  const _TriporaPlanTripCta();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Secondary action (owner decision, Phase 4 review): keeps the Planner
    // one click away without competing with the active navigation item or
    // the Home hero. Crimson text is the mode's AA variant (scheme.primary);
    // the outline is the exact brand crimson at reduced strength (3:1+).
    return OutlinedButton.icon(
      onPressed: () {
        LoginGate.open(context, route: AppRoutes.planner);
      },
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, GlassNavMetrics.minTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        foregroundColor: scheme.primary,
        backgroundColor: Colors.transparent,
        side: BorderSide(
          color: TriporaBrand.crimson.withValues(alpha: 0.75),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GlassRadius.sm),
        ),
        textStyle: GoogleFonts.manrope(
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      icon: const Icon(Icons.add_rounded, size: 18),
      // Long translations (e.g. "Pianifica un Viaggio") wrap instead of
      // overflowing the fixed-width sidebar.
      label: Text(
        context.tr('nav.planTrip'),
        maxLines: 2,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Expanded layout: left sidebar
// ---------------------------------------------------------------------------

class _TriporaSideNav extends StatelessWidget {
  const _TriporaSideNav({required this.currentIndex, required this.onSelected});

  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return GlassSideNav(
      currentIndex: currentIndex,
      onSelected: onSelected,
      items: _navItems(context),
      header: const _TriporaSidebarHeader(),
      footer: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _TriporaPlanTripCta(),
          SizedBox(height: 10),
          ThemeToggleRow(),
          SizedBox(height: 8),
          _SidebarProfileCard(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sidebar footer: profile card (existing account data only: name + email)
// ---------------------------------------------------------------------------

class _SidebarProfileCard extends StatefulWidget {
  const _SidebarProfileCard();

  @override
  State<_SidebarProfileCard> createState() => _SidebarProfileCardState();
}

class _SidebarProfileCardState extends State<_SidebarProfileCard> {
  String? _name;
  String? _email;

  @override
  void initState() {
    super.initState();
    _load();
    // Re-read after leaving the Profile tab, where the name/email can change.
    MainShell.currentIndex.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    MainShell.currentIndex.removeListener(_onTabChanged);
    super.dispose();
  }

  int _lastTab = MainShell.currentIndex.value;

  void _onTabChanged() {
    final tab = MainShell.currentIndex.value;
    if (_lastTab == 4 && tab != 4) _load();
    _lastTab = tab;
  }

  Future<void> _load() async {
    String? name;
    String? email;
    try {
      if (await TokenStore.instance.hasSession()) {
        final response = await AuthService().getCurrentUser();
        final user = response['user'] as Map<String, dynamic>;
        name = (user['name'] ?? '').toString().trim();
        email = (user['email'] ?? '').toString().trim();
      }
    } catch (_) {
      // Offline / signed out: show the guest card rather than stale data.
    }
    if (!mounted) return;
    setState(() {
      _name = (name == null || name.isEmpty) ? null : name;
      _email = (email == null || email.isEmpty) ? null : email;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.triporaColors;
    final signedIn = _name != null || _email != null;
    final title = _name ?? _email ?? context.tr('nav.guest');
    final subtitle = signedIn
        ? (_name != null ? (_email ?? '') : '')
        : context.tr('nav.guestSubtitle');
    final initial = title.isEmpty ? '?' : title.characters.first.toUpperCase();

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(GlassRadius.sm),
        onTap: () {
          if (signedIn) {
            MainShell.currentIndex.value = 4;
          } else {
            Navigator.pushNamed(context, AppRoutes.login).then((_) => _load());
          }
        },
        child: Container(
          constraints: const BoxConstraints(
            minHeight: GlassNavMetrics.minTouchTarget,
          ),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colors.surfaceSecondary.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(GlassRadius.sm),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                // Solid deep crimson so the white initial is 5.41:1.
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: TriporaBrand.crimsonDeep,
                ),
                child: signedIn
                    ? Text(
                        initial,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    : const Icon(
                        Icons.login_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                  ],
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
// Compact / medium layout: floating bottom bar
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
      items: _navItems(context),
    );
  }
}
