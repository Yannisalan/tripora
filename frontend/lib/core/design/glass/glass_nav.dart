import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'glass_surface.dart';
import 'glass_tokens.dart';

/// ---------------------------------------------------------------------
/// Glass navigation
///
/// A floating, capsule-shaped bottom bar built on [GlassSurface]. Kept
/// generic (via [GlassNavItem]) so screens decide their own items and the
/// shell only wires up index + callback - no business logic lives here.
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

class GlassBottomNav extends StatelessWidget {
  const GlassBottomNav({
    super.key,
    required this.currentIndex,
    required this.onSelected,
    required this.items,
    this.horizontalMargin = 16,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;
  final List<GlassNavItem> items;
  final double horizontalMargin;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalMargin),
        child: GlassSurface(
          variant: GlassVariant.bar,
          borderRadius: BorderRadius.circular(GlassRadius.pill),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          elevation: 1.2,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _GlassNavItemView(
                    item: items[i],
                    selected: i == currentIndex,
                    onTap: () => onSelected(i),
                  ),
                ),
            ],
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
  });

  final GlassNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = context.triporaColors;
    final glass = context.glass;

    final active = scheme.primary;
    final inactive = colors.textMuted;

    final duration = GlassMotion.resolve(context, GlassMotion.base);

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GlassRadius.pill),
        child: AnimatedContainer(
          duration: duration,
          curve: GlassMotion.standard,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: selected
                ? active.withValues(alpha: glass.isDark ? 0.14 : 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(GlassRadius.pill),
            border: selected
                ? Border.all(
                    color: active.withValues(
                      alpha: glass.isDark ? 0.16 : 0.30,
                    ),
                    width: glass.isDark ? 0.8 : 1.0,
                  )
                : null,
            // Light mode gets a soft lift so the selected chip reads as a
            // raised, lit glass pill over the translucent bar.
            boxShadow: selected && !glass.isDark
                ? [
                    BoxShadow(
                      color: active.withValues(alpha: 0.20),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: GlassMotion.resolve(context, GlassMotion.fast),
                transitionBuilder: (child, animation) {
                  return ScaleTransition(
                    scale: Tween<double>(begin: 0.86, end: 1).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: GlassMotion.emphasized,
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
                  color: selected ? active : inactive,
                ),
              ),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: duration,
                curve: GlassMotion.standard,
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                      color: selected ? active : inactive,
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
