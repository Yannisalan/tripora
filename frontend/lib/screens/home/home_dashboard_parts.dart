import 'package:flutter/material.dart';

import '../../core/design/glass/glass_tokens.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/destination_accents.dart';
import '../../models/destination_model.dart';

/// ---------------------------------------------------------------------
/// AI command center (Tripora 2.0 Home)
///
/// Honest by construction: the only AI-backed (Groq) flow in the app is the
/// Planner (POST /api/trips/generate, behind the AI consent dialog). There
/// is no free-text command endpoint, so "running" a command opens the
/// Planner with the typed destination prefilled. Nothing is generated or
/// sent until the user reviews and submits the Planner form. The chips
/// only open screens that already exist.
/// ---------------------------------------------------------------------

class AiCommandChip {
  const AiCommandChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

class AiCommandBar extends StatelessWidget {
  const AiCommandBar({
    super.key,
    required this.controller,
    required this.compact,
    required this.auraCity,
    required this.onRun,
    required this.chips,
  });

  final TextEditingController controller;
  final bool compact;
  final String? auraCity;
  final ValueChanged<String> onRun;
  final List<AiCommandChip> chips;

  @override
  Widget build(BuildContext context) {
    final colors = context.triporaColors;
    final glass = context.glass;
    final hint = auraCity == null
        ? context.tr('home.aiCommandHint')
        : context.tr('home.aiCommandHintAura', params: {'city': auraCity!});
    final runLabel = context.tr('home.aiRun');

    void run() => onRun(controller.text.trim());

    final radius = BorderRadius.circular(GlassRadius.md);
    OutlineInputBorder outline(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: color, width: width),
        );

    final runButton = compact
        ? IconButton.filled(
            tooltip: runLabel,
            onPressed: run,
            style: IconButton.styleFrom(
              backgroundColor: TriporaBrand.crimsonDeep,
              foregroundColor: Colors.white,
              minimumSize: const Size(44, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(GlassRadius.xs),
              ),
            ),
            icon: const Icon(Icons.arrow_forward_rounded, size: 20),
          )
        : FilledButton.icon(
            onPressed: run,
            icon: const Icon(Icons.arrow_forward_rounded, size: 17),
            label: Text(runLabel),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(GlassRadius.xs),
              ),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: glass.shadows(lift: 0.6),
          ),
          child: TextField(
            controller: controller,
            onSubmitted: (_) => run(),
            textInputAction: TextInputAction.go,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: hint,
              // Phones: two lines so the hint is readable, not cut at
              // "Where to next? Type a…".
              hintMaxLines: compact ? 2 : 1,
              semanticCounterText: '',
              labelText: null,
              hintStyle: TextStyle(color: colors.textMuted, fontSize: 14),
              filled: true,
              fillColor: colors.surface.withValues(
                alpha: glass.isDark ? 0.72 : 0.86,
              ),
              constraints: const BoxConstraints(minHeight: 64),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 20,
              ),
              prefixIcon: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
                child: Semantics(
                  label: context.tr('home.aiCommandLabel'),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(GlassRadius.xs),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          TriporaBrand.crimson,
                          TriporaBrand.crimsonDeep,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: TriporaBrand.crimson.withValues(alpha: 0.35),
                          blurRadius: 12,
                          spreadRadius: -3,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 62),
              suffixIcon: Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 10, 10),
                child: runButton,
              ),
              border: outline(context.inputBorder),
              enabledBorder: outline(context.inputBorder),
              focusedBorder: outline(Theme.of(context).colorScheme.primary, 2),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Each chip carries 4 px of invisible tap area above and below, so
        // the run spacing drops from 8 to 0 to keep the same visual gap.
        Wrap(
          spacing: 8,
          runSpacing: 0,
          children: [for (final chip in chips) _CommandChip(chip: chip)],
        ),
        const SizedBox(height: 4),
        Text(
          context.tr('home.aiCommandNote'),
          style: TextStyle(color: colors.textMuted, fontSize: 12, height: 1.35),
        ),
      ],
    );
  }
}

class _CommandChip extends StatelessWidget {
  const _CommandChip({required this.chip});

  final AiCommandChip chip;

  @override
  Widget build(BuildContext context) {
    final colors = context.triporaColors;

    // Visually the same 40 px pill; the tap target is 48 px tall
    // (4 px transparent margin above and below, inside the InkWell).
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: chip.onTap,
        borderRadius: BorderRadius.circular(GlassRadius.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: colors.surfaceSecondary.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(GlassRadius.pill),
            border: Border.all(color: colors.borderStrong),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(chip.icon, size: 15, color: TriporaBrand.crimson),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  chip.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
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

/// ---------------------------------------------------------------------
/// Destination accent aura cards (horizontal strip)
///
/// Built from the app's real destination data. Each card shows the
/// destination, its country, the existing suggested trip length and its
/// accent (from [DestinationAccents]). Currency is not shown: the
/// destination data has no currency field.
/// ---------------------------------------------------------------------

class AccentAuraStrip extends StatelessWidget {
  const AccentAuraStrip({
    super.key,
    required this.destinations,
    required this.selectedCity,
    required this.onSelected,
    this.grid = false,
  });

  final List<DestinationModel> destinations;
  final String? selectedCity;
  final ValueChanged<DestinationModel> onSelected;

  /// False: one horizontally scrolling row (phones). True: a responsive
  /// grid whose cards all share one height (medium and expanded).
  final bool grid;

  /// Card height in both presentations.
  static const double _cardHeight = 112;

  /// Widest a grid card may grow before another column is added.
  static const double _maxCardWidth = 260;

  Widget _card(DestinationModel d) => _AuraCard(
    destination: d,
    selected: d.city == selectedCity,
    onTap: () => onSelected(d),
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.triporaColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('home.accentAuras').toUpperCase(),
          style: TextStyle(
            color: colors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.3,
          ),
        ),
        const SizedBox(height: 12),
        if (grid)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: _maxCardWidth,
              mainAxisExtent: _cardHeight,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
            ),
            itemCount: destinations.length,
            itemBuilder: (context, i) => _card(destinations[i]),
          )
        else
          SizedBox(
            height: _cardHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              clipBehavior: Clip.none,
              itemCount: destinations.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) =>
                  SizedBox(width: 228, child: _card(destinations[i])),
            ),
          ),
      ],
    );
  }
}

class _AuraCard extends StatelessWidget {
  const _AuraCard({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final DestinationModel destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.triporaColors;
    final isDark = context.glass.isDark;
    final accent = DestinationAccents.of(context, destination);
    final radius = BorderRadius.circular(GlassRadius.sm);
    final duration = GlassMotion.resolve(context, GlassMotion.base);

    final base = colors.surface.withValues(alpha: isDark ? 0.78 : 0.9);

    return Semantics(
      button: true,
      selected: selected,
      label: '${destination.fullName}, ${destination.tripLength}',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: AnimatedContainer(
            duration: duration,
            curve: GlassMotion.standard,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: radius,
              color: selected
                  ? Color.alphaBlend(
                      accent.withValues(alpha: isDark ? 0.12 : 0.08),
                      base,
                    )
                  : base,
              border: Border.all(
                color: selected ? accent : colors.border,
                width: selected ? 1.4 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: isDark ? 0.28 : 0.2),
                        blurRadius: 18,
                        spreadRadius: -6,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.5),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        destination.tripLength.toUpperCase(),
                        maxLines: 1,
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    if (selected) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.check_circle_rounded, size: 16, color: accent),
                    ],
                  ],
                ),
                const Spacer(),
                Text(
                  destination.city,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  destination.country,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
