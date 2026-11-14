import 'package:flutter/material.dart';

import '../core/design/glass/glass_tokens.dart';
import '../core/l10n/app_localizations.dart';
import '../core/preferences/active_aura.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/destination_accents.dart';
import '../data/destinations.dart';
import '../models/destination_model.dart';

/// Compact "Active Aura" destination selector (Tripora 2.0).
///
/// Shows the destination picked as the user's aura with its accent dot and
/// opens a menu of the app's real destinations. The choice is a local
/// presentation preference ([ActiveAura]); nothing is sent to the backend.
class ActiveAuraSelector extends StatelessWidget {
  const ActiveAuraSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.triporaColors;

    return ListenableBuilder(
      listenable: ActiveAura.instance,
      builder: (context, _) {
        final selected = ActiveAura.instance.destination;
        final accent = DestinationAccents.of(context, selected);
        final value = selected?.fullName ?? context.tr('nav.chooseAura');

        return Material(
          type: MaterialType.transparency,
          child: PopupMenuButton<_AuraChoice>(
            tooltip: context.tr('nav.activeAura'),
            position: PopupMenuPosition.under,
            constraints: const BoxConstraints(minWidth: 220, maxHeight: 420),
            onSelected: (choice) =>
                ActiveAura.instance.select(choice.destination),
            itemBuilder: (context) => [
              if (selected != null)
                PopupMenuItem<_AuraChoice>(
                  value: const _AuraChoice(null),
                  child: Text(context.tr('nav.clearAura')),
                ),
              for (final d in destinations)
                PopupMenuItem<_AuraChoice>(
                  value: _AuraChoice(d),
                  child: Row(
                    children: [
                      _Dot(color: DestinationAccents.of(context, d)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          d.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (d.city == selected?.city)
                        Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                    ],
                  ),
                ),
            ],
            child: Container(
              constraints: const BoxConstraints(
                minHeight: GlassNavMetrics.minTouchTarget,
              ),
              padding: const EdgeInsets.fromLTRB(12, 9, 10, 10),
              decoration: BoxDecoration(
                color: colors.surfaceSecondary.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(GlassRadius.sm),
                border: Border.all(color: colors.borderStrong),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.tr('nav.activeAura').toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                      _Dot(color: accent),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: colors.textSecondary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Menu value; a dedicated type (null destination = clear the selection).
class _AuraChoice {
  const _AuraChoice(this.destination);

  final DestinationModel? destination;
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6),
        ],
      ),
    );
  }
}
