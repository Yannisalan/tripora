import 'package:flutter/material.dart';

import '../core/design/glass/glass_tokens.dart';
import '../core/theme/app_theme.dart';

/// Network destination photo with one consistent loading behaviour:
///
/// - the dark placeholder shows until the first frame is decoded,
/// - the photo then fades in briefly (instant under reduced motion, and
///   instant for images already in the cache),
/// - a failed load keeps a calm placeholder with an icon instead of an
///   error.
///
/// `cacheWidth` decodes to a small texture so long lists never exhaust
/// WebGL texture memory on iOS Safari.
class DestinationImage extends StatelessWidget {
  const DestinationImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.cacheWidth = 900,
    this.placeholder,
    this.showErrorIcon = true,
  });

  final String url;
  final BoxFit fit;
  final Alignment alignment;
  final int? cacheWidth;

  /// Shown while loading and on error. Defaults to the dark surface.
  final Widget? placeholder;

  final bool showErrorIcon;

  static const Duration _fade = Duration(milliseconds: 280);

  @override
  Widget build(BuildContext context) {
    final colors = context.triporaColors;
    final base = placeholder ?? ColoredBox(color: colors.surfaceSecondary);

    return Image.network(
      url,
      fit: fit,
      alignment: alignment,
      cacheWidth: cacheWidth,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return Stack(
          fit: StackFit.expand,
          children: [
            base,
            AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: GlassMotion.resolve(context, _fade),
              curve: Curves.easeOut,
              child: child,
            ),
          ],
        );
      },
      errorBuilder: (context, error, stackTrace) {
        if (!showErrorIcon) return base;
        return Stack(
          fit: StackFit.expand,
          children: [
            base,
            Center(
              child: Icon(
                Icons.image_not_supported_outlined,
                size: 32,
                color: colors.textMuted,
              ),
            ),
          ],
        );
      },
    );
  }
}
