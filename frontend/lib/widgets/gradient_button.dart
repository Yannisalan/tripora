import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// A gradient-filled button (blue → violet → sky) with a [FilledButton]-like
/// API. It wraps the gradient in a [Material] + [Ink] so the brand gradient
/// fills the whole button and the tap ripple renders on top.
class GradientButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget? icon;
  final Widget? label;
  final Widget? child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final bool gradientStrong;
  final double? height;

  const GradientButton({
    super.key,
    this.onPressed,
    this.icon,
    this.label,
    this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
    this.gradientStrong = false,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final gradient = gradientStrong
        ? AppColors.brandStrongGradient
        : AppColors.brandGradient;
    final enabled = onPressed != null;

    final content = child ??
        (icon != null || label != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ?icon,
                  if (icon != null && label != null) const SizedBox(width: 8),
                  ?label,
                ],
              )
            : const SizedBox.shrink());

    return Material(
      color: Colors.transparent,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: enabled
              ? gradient
              : const LinearGradient(colors: [Color(0xFFB7C6DC)]),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: borderRadius,
          splashColor: Colors.white.withValues(alpha: 0.25),
          highlightColor: Colors.white.withValues(alpha: 0.12),
          child: Container(
            height: height,
            padding: padding,
            alignment: Alignment.center,
            child: DefaultTextStyle(
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}
