import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/auth/login_gate.dart';
import '../../core/auth/token_store.dart';
import '../../core/design/glass/glass_nav.dart';
import '../../core/design/glass/glass_tokens.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../widgets/theme_toggle.dart';
import '../../widgets/tripora_brand.dart';
import '../main_shell.dart';
import 'app_destinations.dart';

/// ---------------------------------------------------------------------
/// Tripora side navigation (medium rail + expanded sidebar)
///
/// Both are built from [appDestinations]. Order, top to bottom: brand
/// (sidebar only), the single primary "Plan a Trip" action, the
/// destinations, and the account area (with the Light/Dark switch merged
/// into it) pinned to the bottom.
/// ---------------------------------------------------------------------

/// Full 240 px sidebar for expanded widths (>= 1280).
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.currentIndex,
    required this.onSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return GlassSideNav(
      currentIndex: currentIndex,
      onSelected: onSelected,
      items: appNavItems(context),
      // Wordmark only (owner decision: no mark, badge or aura selector).
      header: const Padding(
        padding: EdgeInsets.fromLTRB(12, 6, 4, 4),
        child: TriporaWordmark(),
      ),
      primaryAction: const _PlanTripButton(),
      footer: const _AccountArea(),
    );
  }
}

/// 72 px icon-only rail for medium widths (768-1279).
class AppNavRail extends StatelessWidget {
  const AppNavRail({
    super.key,
    required this.currentIndex,
    required this.onSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return GlassNavRail(
      currentIndex: currentIndex,
      onSelected: onSelected,
      items: appNavItems(context),
      leading: const _PlanTripButton(iconOnly: true),
      trailing: const _AccountArea(compact: true),
    );
  }
}

// ---------------------------------------------------------------------------
// Primary action
// ---------------------------------------------------------------------------

class _PlanTripButton extends StatelessWidget {
  const _PlanTripButton({this.iconOnly = false});

  final bool iconOnly;

  void _open(BuildContext context) =>
      LoginGate.open(context, route: AppRoutes.planner);

  @override
  Widget build(BuildContext context) {
    final label = context.tr('nav.planTrip');
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(GlassRadius.xs),
    );

    if (iconOnly) {
      return Tooltip(
        message: label,
        child: IconButton.filled(
          onPressed: () => _open(context),
          style: IconButton.styleFrom(
            backgroundColor: context.brandFill,
            foregroundColor: context.onBrandFill,
            minimumSize: const Size(
              GlassNavMetrics.minTouchTarget,
              GlassNavMetrics.minTouchTarget,
            ),
            shape: shape,
          ),
          icon: Icon(Icons.add_rounded, size: 22, semanticLabel: label),
        ),
      );
    }

    return FilledButton.icon(
      onPressed: () => _open(context),
      style: FilledButton.styleFrom(
        backgroundColor: context.brandFill,
        foregroundColor: context.onBrandFill,
        elevation: 0,
        minimumSize: const Size(0, GlassNavMetrics.minTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: shape,
        textStyle: GoogleFonts.manrope(
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      icon: const Icon(Icons.add_rounded, size: 18),
      // Long translations (e.g. "Pianifica un Viaggio") wrap instead of
      // overflowing the fixed-width sidebar.
      label: Text(
        label,
        maxLines: 2,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Account area (existing account data only: name + email) + theme switch
// ---------------------------------------------------------------------------

class _AccountArea extends StatefulWidget {
  const _AccountArea({this.compact = false});

  /// Rail variant: avatar and theme switch stacked, no text.
  final bool compact;

  @override
  State<_AccountArea> createState() => _AccountAreaState();
}

class _AccountAreaState extends State<_AccountArea> {
  String? _name;
  String? _email;
  late int _lastTab = MainShell.currentIndex.value;

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

  void _onTabChanged() {
    final tab = MainShell.currentIndex.value;
    if (_lastTab == profileTabIndex && tab != profileTabIndex) _load();
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
      // Offline / signed out: show the guest state rather than stale data.
    }
    if (!mounted) return;
    setState(() {
      _name = (name == null || name.isEmpty) ? null : name;
      _email = (email == null || email.isEmpty) ? null : email;
    });
  }

  bool get _signedIn => _name != null || _email != null;

  void _open() {
    if (_signedIn) {
      MainShell.currentIndex.value = profileTabIndex;
    } else {
      Navigator.pushNamed(context, AppRoutes.login).then((_) => _load());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.triporaColors;
    final title = _name ?? _email ?? context.tr('nav.guest');
    final subtitle = _signedIn
        ? (_name != null ? (_email ?? '') : '')
        : context.tr('nav.guestSubtitle');
    final initial = title.isEmpty ? '?' : title.characters.first.toUpperCase();
    final avatar = _Avatar(signedIn: _signedIn, initial: initial);
    final radius = BorderRadius.circular(GlassRadius.xs);

    if (widget.compact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ThemeToggleButton(),
          const SizedBox(height: 4),
          Tooltip(
            message: title,
            child: Semantics(
              button: true,
              label: title,
              excludeSemantics: true,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: _open,
                  customBorder: const CircleBorder(),
                  child: SizedBox.square(
                    dimension: GlassNavMetrics.minTouchTarget,
                    child: Center(child: avatar),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Expanded(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: _open,
                borderRadius: radius,
                hoverColor: colors.textPrimary.withValues(alpha: 0.06),
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: GlassNavMetrics.minTouchTarget,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      avatar,
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
            ),
          ),
          const SizedBox(width: 2),
          // Light/Dark switch merged into the account area.
          const ThemeToggleButton(),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.signedIn, required this.initial});

  final bool signedIn;
  final String initial;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      // Solid deep crimson so the white initial is 5.41:1.
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.brandFill,
      ),
      child: signedIn
          ? Text(
              initial,
              style: TextStyle(
                color: context.onBrandFill,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            )
          : Icon(Icons.login_rounded, size: 18, color: context.onBrandFill),
    );
  }
}
