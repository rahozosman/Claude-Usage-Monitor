import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_dimens.dart';

/// macOS-style surface: translucent fill, hairline border, top sheen, soft
/// layered shadow. `elevated` renders the inset grouped-card style.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.opacity = 1,
    this.radius = AppDimens.radiusLg,
    this.padding = EdgeInsets.zero,
    this.elevated = false,
    this.hover = false,
    this.borderRadius,
  });

  final Widget child;
  final double opacity;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool elevated;
  final bool hover;

  /// Overrides [radius] when the corners are not uniform (the edge-docked
  /// states round only their left side).
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shape = borderRadius ?? BorderRadius.circular(radius);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = elevated ? c.surfaceElevated : c.surface;
    final fill = hover ? Color.alphaBlend(c.fill, base) : base;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill.withValues(alpha: elevated ? (0.55 + 0.45 * opacity) : opacity),
        borderRadius: shape,
        border: Border.all(color: elevated ? c.border : c.borderStrong, width: 0.6),
        boxShadow: elevated
            ? <BoxShadow>[
                BoxShadow(
                  color: c.shadow.withValues(alpha: dark ? 0.16 : 0.05),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ]
            : <BoxShadow>[
                BoxShadow(
                  color: c.shadow.withValues(alpha: dark ? 0.45 : 0.22),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(
                  color: c.shadow.withValues(alpha: dark ? 0.30 : 0.10),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: Stack(
          children: <Widget>[
            // Vibrancy sheen: a faint vertical gradient like a macOS material.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        c.highlight.withValues(alpha: dark ? 0.06 : 0.35),
                        c.highlight.withValues(alpha: 0),
                      ],
                      stops: const <double>[0, 0.6],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: IgnorePointer(
                child: Container(height: 0.8, color: c.highlight.withValues(alpha: dark ? 0.16 : 0.9)),
              ),
            ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}
