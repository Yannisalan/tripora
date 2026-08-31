import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'gradient_button.dart';

class DestinationCard extends StatelessWidget {
  final String imageUrl;
  final String city;
  final String country;
  final String description;
  final String? footer;
  final List<String>? tags;
  final double? width;
  final double? height;
  final VoidCallback? onTap;
  final VoidCallback? onPlan;

  const DestinationCard({
    super.key,
    required this.imageUrl,
    required this.city,
    required this.country,
    required this.description,
    this.footer,
    this.tags,
    this.width,
    this.height,
    this.onTap,
    this.onPlan,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: _buildCard(context, accent),
    );
  }

  Widget _buildCard(BuildContext context, Color accent) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Container(
        width: width ?? 300,
        height: height,
        decoration: BoxDecoration(
          color: context.triporaColors.surface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(color: context.triporaColors.surface),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // =====================================================
                // IMAGE WITH OVERLAY
                // =====================================================
                SizedBox(
                  height: 200,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) {
                            return child;
                          }

                          return Container(
                            color: context.triporaColors.border,
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: context.triporaColors.border,
                            child: Center(
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                size: 40,
                                color: context.triporaColors.textMuted,
                              ),
                            ),
                          );
                        },
                      ),
                      // Gradient overlay for legibility
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.55),
                            ],
                            stops: const [0.45, 1.0],
                          ),
                        ),
                      ),
                      // Top-left trip length badge
                      if (footer != null && footer!.isNotEmpty)
                        Positioned(
                          top: 14,
                          left: 14,
                          child: _Badge(
                            icon: Icons.calendar_month_outlined,
                            text: footer!,
                            background: Colors.black.withValues(alpha: 0.35),
                            foreground: Colors.white,
                          ),
                        ),
                      // Bottom-left labels over the image
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 14,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              city,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                ExcludeSemantics(
                                  child: const Icon(
                                    Icons.location_on_outlined,
                                    size: 15,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    country,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // =====================================================
                // BODY
                // =====================================================
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: context.triporaColors.textMuted,
                        ),
                      ),
                      if (tags != null && tags!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: tags!.take(3).map((tag) {
                            return _Badge(
                              icon: Icons.tag,
                              text: tag,
                              background: accent.withValues(alpha: 0.10),
                              foreground: accent,
                              iconSize: 13,
                            );
                          }).toList(),
                        ),
                      ],
                      if (onPlan != null) ...[
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: GradientButton(
                            onPressed: onPlan,
                            height: 44,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            borderRadius: const BorderRadius.all(
                              Radius.circular(12),
                            ),
                            icon: const Icon(
                              Icons.add_location_alt_outlined,
                              size: 18,
                            ),
                            label: const Text(
                              'Plan This Trip',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
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

class _Badge extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color background;
  final Color foreground;
  final double iconSize;

  const _Badge({
    required this.text,
    required this.icon,
    required this.background,
    required this.foreground,
    this.iconSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: foreground),
          const SizedBox(width: 5),
          Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}
