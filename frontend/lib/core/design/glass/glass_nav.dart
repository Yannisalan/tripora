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
/// - [GlassBottomNav]: floating capsule bar (compact + medium widths).
/// - [GlassSideNav]: floating vertical sidebar (expanded widths).
///
/// Kept generic (via [GlassNavItem]) so screens decide their own items and
/// the shell only wires up index + callback - no business logic lives here.
/// Both share the same selected-state styling ([_selectedDecoration]) so a
/// destination looks the same wherever it is rendered.
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

/// Small crimson dot marking the active destination (Tripora 2.0).
class _ActiveDot extends StatelessWidget {
  const _ActiveDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: const BoxDecoration(
        color: TriporaBrand.crimson,
        shape: BoxShape.circle,
      ),
    );
  }
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
// Sidebar
// ---------------------------------------------------------------------------

/// Floating vertical glass sidebar used at expanded widths.
///
/// [header] sits above the destinations (the brand), [footer] below them
/// (the primary call to action). The column scrolls when the window is
/// too short to fit everything, so it never overflows.
class GlassSideNav extends StatelessWidget {
  const GlassSideNav({
    super.key,
    required this.currentIndex,
    required this.onSelected,
    required this.items,
    this.header,
    this.footer,
    this.width = GlassNavMetrics.sidebarWidth,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;
  final List<GlassNavItem> items;
  final Widget? header;
  final Widget? footer;
  final double width;

  @override
  Widget build(BuildContext context) {
    final isDark = context.glass.isDark;
    final colors = context.triporaColors;

    // Tripora 2.0: a compact panel docked to the window edge (not a
    // floating card), separated from the content by a hairline.
    return SizedBox(
      width: width,
      child: GlassSurface(
        variant: GlassVariant.bar,
        borderRadius: BorderRadius.zero,
        padding: EdgeInsets.zero,
        elevation: 0,
        showBorder: false,
        showHighlight: false,
        tintStrength: isDark ? 0.55 : 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: colors.border)),
          ),
          child: SafeArea(
            right: false,
            child: CustomScrollView(
              primary: false,
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 18, 12, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (header != null) ...[
                          header!,
                          const SizedBox(height: 18),
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
                        if (footer != null) ...[
                          const SizedBox(height: 18),
                          footer!,
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
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

    // Icon: brand crimson in light, bright AA variant in dark (see the
    // bottom bar). Label: the mode's AA crimson text (scheme.primary).
    final active = context.glass.isDark ? scheme.primary : TriporaBrand.crimson;
    final activeLabel = scheme.primary;
    final inactive = colors.textSecondary;
    final color = selected ? active : inactive;

    final duration = GlassMotion.resolve(context, GlassMotion.base);
    final radius = BorderRadius.circular(GlassRadius.sm);

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
          hoverColor: active.withValues(alpha: 0.08),
          focusColor: active.withValues(alpha: 0.20),
          highlightColor: active.withValues(alpha: 0.10),
          child: AnimatedContainer(
            duration: duration,
            curve: GlassMotion.standard,
            constraints: const BoxConstraints(
              minHeight: GlassNavMetrics.minTouchTarget,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: _selectedDecoration(
              context,
              selected,
              radius: GlassRadius.sm,
            ),
            child: Row(
              children: [
                _NavIcon(
                  item: item,
                  selected: selected,
                  color: color,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AnimatedDefaultTextStyle(
                    duration: duration,
                    curve: GlassMotion.standard,
                    style: Theme.of(context).textTheme.labelLarge!.copyWith(
                      fontSize: 14,
                      color: selected ? activeLabel : inactive,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 8),
                  const _ActiveDot(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
