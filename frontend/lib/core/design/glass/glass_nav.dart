import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'glass_surface.dart';
import 'glass_tokens.dart';

/// ---------------------------------------------------------------------
/// Glass navigation
///
/// Two presentations of the same destinations, both built on
/// [GlassSurface]:
///
/// - [GlassBottomNav]: floating capsule bar (compact widths).
/// - [GlassNavRail]: icon-only rail (medium widths).
/// - [GlassSideNav]: docked full sidebar (expanded widths).
///
/// Kept generic (via [GlassNavItem]) so screens decide their own items and
/// the shell only wires up index + callback - no business logic lives here.
/// The bottom bar keeps its pill selection ([_selectedDecoration]); the rail
/// and the sidebar share a tinted fill with a left accent bar
/// ([_SideNavSelection]).
/// ---------------------------------------------------------------------

class GlassNavItem {
  const GlassNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Selected-chip decoration shared by the bottom bar and the sidebar.
///
/// Tripora 2.0: a subtle crimson wash with a crimson hairline and a faint
/// crimson glow (restrained, no bloom). [radius] lets the sidebar use a
/// rounded rectangle while the bottom bar keeps its pill.
BoxDecoration _selectedDecoration(
  BuildContext context,
  bool selected, {
  double radius = GlassRadius.pill,
}) {
  const crimson = TriporaBrand.crimson;
  final isDark = context.glass.isDark;

  return BoxDecoration(
    // Kept faint so the crimson label/icon on it still reach AA.
    color: selected
        ? crimson.withValues(alpha: isDark ? 0.07 : 0.05)
        : Colors.transparent,
    borderRadius: BorderRadius.circular(radius),
    border: selected
        ? Border.all(
            color: crimson.withValues(alpha: isDark ? 0.55 : 0.45),
            width: 1.0,
          )
        : null,
    boxShadow: selected
        ? [
            BoxShadow(
              color: crimson.withValues(alpha: isDark ? 0.18 : 0.14),
              blurRadius: 14,
              spreadRadius: -4,
            ),
          ]
        : null,
  );
}

/// Icon that swaps between outlined and filled with the glass motion.
class _NavIcon extends StatelessWidget {
  const _NavIcon({
    required this.item,
    required this.selected,
    required this.color,
    this.size = 23,
  });

  final GlassNavItem item;
  final bool selected;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: GlassMotion.resolve(context, GlassMotion.fast),
      transitionBuilder: (child, animation) {
        return ScaleTransition(
          scale: Tween<double>(begin: 0.86, end: 1).animate(
            CurvedAnimation(parent: animation, curve: GlassMotion.emphasized),
          ),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: Icon(
        selected ? item.selectedIcon : item.icon,
        key: ValueKey(selected),
        size: size,
        color: color,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom bar
// ---------------------------------------------------------------------------

class GlassBottomNav extends StatelessWidget {
  const GlassBottomNav({
    super.key,
    required this.currentIndex,
    required this.onSelected,
    required this.items,
    this.horizontalMargin = 16,
    this.maxWidth = GlassNavMetrics.bottomBarMaxWidth,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;
  final List<GlassNavItem> items;
  final double horizontalMargin;

  /// The capsule never grows wider than this; on wider windows it is
  /// centered instead of stretching across the screen.
  final double maxWidth;

  /// Below this window width the bar trims its side margin and inner
  /// padding so five labels keep enough room (320-390 px phones).
  static const double _tightWidth = 400;

  @override
  Widget build(BuildContext context) {
    final tight = MediaQuery.sizeOf(context).width < _tightWidth;

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tight ? horizontalMargin * 0.625 : horizontalMargin,
        ),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: GlassSurface(
              variant: GlassVariant.bar,
              borderRadius: BorderRadius.circular(GlassRadius.pill),
              padding: EdgeInsets.symmetric(
                horizontal: tight ? 4 : 8,
                vertical: 8,
              ),
              elevation: 1.2,
              // Equal-height items: a label that wraps to two lines (long
              // translations on narrow phones) never misaligns the icons.
              // Measured here, outside IntrinsicHeight (LayoutBuilder cannot
              // report intrinsic sizes): the width each label gets.
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final labelWidth =
                      constraints.maxWidth / items.length -
                      _GlassNavItemView.chromeFor(tight: tight);
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < items.length; i++)
                          Expanded(
                            child: _GlassNavItemView(
                              item: items[i],
                              selected: i == currentIndex,
                              onTap: () => onSelected(i),
                              labelWidth: labelWidth,
                              tight: tight,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassNavItemView extends StatelessWidget {
  const _GlassNavItemView({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.labelWidth,
    required this.tight,
  });

  final GlassNavItem item;
  final bool selected;
  final VoidCallback onTap;
  final double labelWidth;
  final bool tight;

  static double _margin({required bool tight}) => tight ? 1 : 2;
  static double _padding({required bool tight}) => tight ? 1 : 4;

  /// Horizontal margin + padding around the label, both sides.
  static double chromeFor({required bool tight}) =>
      2 * (_margin(tight: tight) + _padding(tight: tight));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = context.triporaColors;

    // Icon: brand crimson in light (graphic, >= 3:1); the bright AA
    // variant in dark, where #F01D54 drops below 3:1 on the lit glass.
    // Label: the AA crimson text variant for the mode (scheme.primary).
    final active = context.glass.isDark ? scheme.primary : TriporaBrand.crimson;
    // Dark: the floating bar's lit glass leaves crimson text just under
    // 4.5:1, so the label uses primary text; icon, chip and dot carry the
    // crimson cue.
    final activeLabel = context.glass.isDark
        ? colors.textPrimary
        : scheme.primary;
    // Same inactive tone as the sidebar (AA on the bar).
    final inactive = colors.textSecondary;

    final duration = GlassMotion.resolve(context, GlassMotion.base);

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GlassRadius.pill),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: GlassNavMetrics.minTouchTarget,
            minWidth: GlassNavMetrics.minTouchTarget,
          ),
          child: AnimatedContainer(
            duration: duration,
            curve: GlassMotion.standard,
            margin: EdgeInsets.symmetric(horizontal: _margin(tight: tight)),
            padding: EdgeInsets.symmetric(
              vertical: 8,
              horizontal: _padding(tight: tight),
            ),
            decoration: _selectedDecoration(context, selected),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _NavIcon(
                  item: item,
                  selected: selected,
                  color: selected ? active : inactive,
                ),
                const SizedBox(height: 4),
                AnimatedDefaultTextStyle(
                  duration: duration,
                  curve: GlassMotion.standard,
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    color: selected ? activeLabel : inactive,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                  child: _NavLabel(item.label, maxWidth: labelWidth),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom-bar label that is never cut off or broken mid-word.
///
/// A label that fits stays on one line. A longer multi-word label splits at
/// its most balanced space onto two lines ("Meine / Reisen"). Every line is
/// a single-line text in a scale-down [FittedBox], so a word that is still
/// too wide for the slot (e.g. "Entdecken" at 320 px) shrinks slightly
/// instead of overflowing - decided at layout time with the font that is
/// actually loaded, so a late web-font swap cannot break it.
class _NavLabel extends StatelessWidget {
  const _NavLabel(this.label, {required this.maxWidth});

  final String label;
  final double maxWidth;

  double _width(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// The label as one line, or two lines split at the most balanced space.
  List<String> _lines(BuildContext context, TextStyle style) {
    final words = label.split(' ');
    if (words.length == 1 || _width(context, label, style) <= maxWidth) {
      return [label];
    }
    var best = [label];
    var bestWidest = double.infinity;
    for (var i = 1; i < words.length; i++) {
      final first = words.sublist(0, i).join(' ');
      final second = words.sublist(i).join(' ');
      final widest = [
        _width(context, first, style),
        _width(context, second, style),
      ].reduce((a, b) => a > b ? a : b);
      if (widest < bestWidest) {
        bestWidest = widest;
        best = [first, second];
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final line in _lines(context, style))
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              line,
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}


// ---------------------------------------------------------------------------
// Side navigation (rail + sidebar)
//
// Shared by the medium rail and the expanded sidebar: a quiet, translucent
// panel docked to the window edge (no hard slab), separated from the
// content by a low-opacity hairline, with an optional light blur.
// ---------------------------------------------------------------------------

/// Translucent docked panel behind the rail and the sidebar.
class _SideNavPanel extends StatelessWidget {
  const _SideNavPanel({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = context.glass.isDark;
    final colors = context.triporaColors;

    return SizedBox(
      width: width,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              // ~2% white over navy. Light mode needs a little more veil
              // to read as a panel over the pale ambient background.
              color: Colors.white.withValues(alpha: isDark ? 0.02 : 0.35),
              border: Border(
                right: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : colors.border.withValues(alpha: 0.7),
                ),
              ),
            ),
            child: SafeArea(right: false, child: child),
          ),
        ),
      ),
    );
  }
}

/// Selection styling shared by rail and sidebar items: a soft crimson fill
/// and a 3 px crimson accent bar on the leading edge. No outline, no dot.
class _SideNavSelection {
  _SideNavSelection._();

  static const double fillAlpha = 0.12;
  static const double barWidth = 3;

  static BoxDecoration decoration(bool selected, BorderRadius radius) {
    return BoxDecoration(
      color: selected
          ? TriporaBrand.crimson.withValues(alpha: fillAlpha)
          : Colors.transparent,
      borderRadius: radius,
    );
  }

  /// Hover wash: ~6% of the foreground (white on navy).
  static Color hover(BuildContext context) =>
      context.triporaColors.textPrimary.withValues(alpha: 0.06);
}

/// The 3 px leading accent bar, animated in/out with the selection.
class _SideNavAccentBar extends StatelessWidget {
  const _SideNavAccentBar({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      top: 10,
      bottom: 10,
      child: AnimatedOpacity(
        opacity: selected ? 1 : 0,
        duration: GlassMotion.resolve(context, GlassMotion.fast),
        child: Container(
          width: _SideNavSelection.barWidth,
          decoration: BoxDecoration(
            color: TriporaBrand.crimson,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

/// Docked full sidebar used at expanded widths.
///
/// Order, top to bottom: [header] (brand), [primaryAction] (the single
/// primary CTA), the destinations, then [footer] (account area) pinned to
/// the bottom. The column scrolls when the window is too short.
class GlassSideNav extends StatelessWidget {
  const GlassSideNav({
    super.key,
    required this.currentIndex,
    required this.onSelected,
    required this.items,
    this.header,
    this.primaryAction,
    this.footer,
    this.width = GlassNavMetrics.sidebarWidth,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;
  final List<GlassNavItem> items;
  final Widget? header;
  final Widget? primaryAction;
  final Widget? footer;
  final double width;

  @override
  Widget build(BuildContext context) {
    return _SideNavPanel(
      width: width,
      child: CustomScrollView(
        primary: false,
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 20, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (header != null) ...[header!, const SizedBox(height: 16)],
                  if (primaryAction != null) ...[
                    primaryAction!,
                    const SizedBox(height: 16),
                  ],
                  for (var i = 0; i < items.length; i++) ...[
                    _GlassSideNavItemView(
                      item: items[i],
                      selected: i == currentIndex,
                      onTap: () => onSelected(i),
                    ),
                    if (i != items.length - 1) const SizedBox(height: 4),
                  ],
                  const Spacer(),
                  if (footer != null) ...[const SizedBox(height: 16), footer!],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassSideNavItemView extends StatelessWidget {
  const _GlassSideNavItemView({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final GlassNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = context.triporaColors;

    // Icon: the mode's AA crimson (scheme.primary). Label: primary text on
    // the 12% wash, so it stays well above 4.5:1 in both modes.
    final iconColor = selected ? scheme.primary : colors.textSecondary;
    final labelColor = selected ? colors.textPrimary : colors.textSecondary;

    final duration = GlassMotion.resolve(context, GlassMotion.base);
    final radius = BorderRadius.circular(GlassRadius.xs);

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          hoverColor: _SideNavSelection.hover(context),
          focusColor: scheme.primary.withValues(alpha: 0.20),
          highlightColor: scheme.primary.withValues(alpha: 0.10),
          child: Stack(
            children: [
              AnimatedContainer(
                duration: duration,
                curve: GlassMotion.standard,
                constraints: const BoxConstraints(
                  minHeight: GlassNavMetrics.minTouchTarget,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: _SideNavSelection.decoration(selected, radius),
                child: Row(
                  children: [
                    _NavIcon(
                      item: item,
                      selected: selected,
                      color: iconColor,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AnimatedDefaultTextStyle(
                        duration: duration,
                        curve: GlassMotion.standard,
                        style: Theme.of(context).textTheme.labelLarge!.copyWith(
                          fontSize: 14,
                          color: labelColor,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                        child: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _SideNavAccentBar(selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

/// Icon-only navigation rail used at medium widths.
///
/// Same destinations and selection styling as [GlassSideNav]; every item
/// carries a [Tooltip] and a [Semantics] label because the text is hidden.
/// [leading] sits above the destinations (the primary action), [trailing]
/// is pinned to the bottom (account + theme).
class GlassNavRail extends StatelessWidget {
  const GlassNavRail({
    super.key,
    required this.currentIndex,
    required this.onSelected,
    required this.items,
    this.leading,
    this.trailing,
    this.width = GlassNavMetrics.railWidth,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;
  final List<GlassNavItem> items;
  final Widget? leading;
  final Widget? trailing;
  final double width;

  @override
  Widget build(BuildContext context) {
    return _SideNavPanel(
      width: width,
      child: CustomScrollView(
        primary: false,
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 20, 8, 14),
              child: Column(
                children: [
                  if (leading != null) ...[leading!, const SizedBox(height: 16)],
                  for (var i = 0; i < items.length; i++) ...[
                    _GlassNavRailItemView(
                      item: items[i],
                      selected: i == currentIndex,
                      onTap: () => onSelected(i),
                    ),
                    if (i != items.length - 1) const SizedBox(height: 4),
                  ],
                  const Spacer(),
                  if (trailing != null) ...[
                    const SizedBox(height: 16),
                    trailing!,
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassNavRailItemView extends StatelessWidget {
  const _GlassNavRailItemView({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final GlassNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = context.triporaColors;
    final radius = BorderRadius.circular(GlassRadius.xs);

    return Tooltip(
      message: item.label,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 300),
      child: Semantics(
        button: true,
        selected: selected,
        label: item.label,
        excludeSemantics: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            hoverColor: _SideNavSelection.hover(context),
            focusColor: scheme.primary.withValues(alpha: 0.20),
            highlightColor: scheme.primary.withValues(alpha: 0.10),
            child: Stack(
              children: [
                AnimatedContainer(
                  duration: GlassMotion.resolve(context, GlassMotion.base),
                  curve: GlassMotion.standard,
                  width: double.infinity,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: _SideNavSelection.decoration(selected, radius),
                  child: _NavIcon(
                    item: item,
                    selected: selected,
                    color: selected ? scheme.primary : colors.textSecondary,
                    size: 22,
                  ),
                ),
                _SideNavAccentBar(selected: selected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
