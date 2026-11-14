import 'package:flutter/material.dart';

import '../core/design/glass/glass_tokens.dart';
import '../core/l10n/app_localizations.dart';
import '../core/preferences/app_preferences.dart';
import '../core/theme/app_theme.dart';

/// Direct Light/Dark switching on top of the existing [AppPreferences]
/// theme setting (no second theme system).
///
/// The toggle flips the theme that is ON SCREEN: it reads the effective
/// brightness (which already resolves System to the OS setting) and stores
/// the opposite explicit mode. One tap therefore always changes the theme,
/// whatever the current setting. System mode itself is still available in
/// Profile > Appearance.
///
/// The change is local only: AppPreferences persists it on the device
/// (SharedPreferences), the app root rebuilds from it, and nothing is sent
/// to the backend, so it works the same for guests and signed-in users and
/// leaves navigation state untouched.
class ThemeToggle {
  ThemeToggle._();

  /// Whether the theme currently on screen is dark.
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Future<void> toggle(BuildContext context) => AppPreferences.instance
      .setThemeMode(isDark(context) ? ThemeMode.light : ThemeMode.dark);
}

/// Sidebar row: the active theme's icon and name plus a switch (on = dark).
/// The whole row is one toggle target.
class ThemeToggleRow extends StatelessWidget {
  const ThemeToggleRow({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.triporaColors;
    final dark = ThemeToggle.isDark(context);
    final label = context.tr(dark ? 'profile.dark' : 'profile.light');

    return MergeSemantics(
      child: Semantics(
        label: context.tr('nav.themeSwitchHint'),
        toggled: dark,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => ThemeToggle.toggle(context),
            borderRadius: BorderRadius.circular(GlassRadius.sm),
            child: Container(
              constraints: const BoxConstraints(
                minHeight: GlassNavMetrics.minTouchTarget,
              ),
              padding: const EdgeInsets.only(left: 12, right: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(GlassRadius.sm),
                border: Border.all(color: colors.borderStrong),
              ),
              child: Row(
                children: [
                  Icon(
                    dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                    size: 18,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  ExcludeSemantics(
                    child: Switch(
                      value: dark,
                      onChanged: (_) => ThemeToggle.toggle(context),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact layouts (no sidebar): an icon button showing the theme it
/// switches TO (sun in dark mode, moon in light mode).
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = ThemeToggle.isDark(context);

    return IconButton(
      tooltip: context.tr(dark ? 'nav.switchToLight' : 'nav.switchToDark'),
      onPressed: () => ThemeToggle.toggle(context),
      constraints: const BoxConstraints(
        minWidth: GlassNavMetrics.minTouchTarget,
        minHeight: GlassNavMetrics.minTouchTarget,
      ),
      icon: Icon(
        dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        color: context.headingColor,
      ),
    );
  }
}
