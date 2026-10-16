import 'package:flutter/material.dart';

import 'glass_surface.dart';
import 'glass_tokens.dart';

/// ---------------------------------------------------------------------
/// Glass button
///
/// Three variants that match the Liquid Glass idiom:
///  - [GlassButtonVariant.primary]  : accent gradient capsule (filled).
///  - [GlassButtonVariant.secondary]: translucent glass capsule.
///  - [GlassButtonVariant.ghost]    : borderless, low-emphasis action.
/// ---------------------------------------------------------------------

enum GlassButtonVariant { primary, secondary, ghost }

class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    this.label,
    this.child,
    this.icon,
    this.onPressed,
    this.variant = GlassButtonVariant.primary,
    this.expand = false,
    this.loading = false,
    this.minHeight = 52,
    this.padding = const EdgeInsets.symmetric(horizontal: 22),
  }) : assert(
          label != null || child != null,
          'GlassButton needs a label or a child',
        );

  final String? label;
  final Widget? child;
  final IconData? icon;
  final VoidCallback? onPressed;
  final GlassButtonVariant variant;
  final bool expand;
  final bool loading;
  final double minHeight;
  final EdgeInsetsGeometry padding;

  bool get _enabled => onPressed != null && !loading;

  @override
  Widget build(BuildContext context) {
    switch (variant) {
      case GlassButtonVariant.primary:
        return _primary(context);
      case GlassButtonVariant.secondary:
        return _secondary(context);
      case GlassButtonVariant.ghost:
        return _ghost(context);
    }
  }

  Widget _content(BuildContext context, Color foreground) {
    final children = <Widget>[];

    if (loading) {
      children.add(
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            valueColor: AlwaysStoppedAnimation(foreground),
          ),
        ),
      );
    } else if (icon != null) {
      children.add(Icon(icon, size: 20, color: foreground));
    }

    final text = child ??
        Text(
          label ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
            color: foreground,
          ),
        );

    if (children.isEmpty) {
      return text;
    }

    return Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        children.first,
        const SizedBox(width: 8),
        Flexible(child: text),
      ],
    );
  }

  Widget _primary(BuildContext context) {
    final opacity = _enabled ? 1.0 : 0.5;

    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(GlassRadius.pill),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          GlassAccents.sky.withValues(alpha: opacity),
          GlassAccents.indigo.withValues(alpha: opacity),
        ],
      ),
      boxShadow: _enabled
          ? [
              BoxShadow(
                color: GlassAccents.indigo.withValues(alpha: 0.32),
                blurRadius: 20,
                offset: const Offset(0, 8),
                spreadRadius: -4,
              ),
            ]
          : null,
    );

    return _wrap(
      Material(
        color: Colors.transparent,
        child: Ink(
          decoration: decoration,
          child: InkWell(
            onTap: _enabled ? onPressed : null,
            customBorder: const StadiumBorder(),
            child: Container(
              padding: padding,
              constraints: BoxConstraints(minHeight: minHeight),
              alignment: Alignment.center,
              child: _content(context, Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  Widget _secondary(BuildContext context) {
    return _wrap(
      GlassSurface(
        variant: GlassVariant.pill,
        onTap: _enabled ? onPressed : null,
        tintStrength: 0.7,
        padding: padding,
        constraints: BoxConstraints(minHeight: minHeight),
        child: Opacity(
          opacity: _enabled ? 1 : 0.5,
          child: _content(context, context.triporaGlassText),
        ),
      ),
    );
  }

  Widget _ghost(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return _wrap(
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(GlassRadius.pill),
          child: Container(
            padding: padding,
            constraints: BoxConstraints(minHeight: minHeight),
            alignment: Alignment.center,
            child: Opacity(
              opacity: _enabled ? 1 : 0.5,
              child: _content(context, scheme.primary),
            ),
          ),
        ),
      ),
    );
  }

  Widget _wrap(Widget button) {
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Convenience accessor for the theme's primary text color on glass.
extension on BuildContext {
  Color get triporaGlassText =>
      Theme.of(this).colorScheme.onSurface;
}
