import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_motion.dart';
import '../core/utils/usage_math.dart';

/// macOS-style level indicator: recessed track, tinted fill with a soft top
/// highlight, animated to the new value. `fraction == null` renders an empty,
/// dimmed track (unknown value).
class UsageBar extends StatelessWidget {
  const UsageBar({
    super.key,
    required this.fraction,
    required this.status,
    required this.motion,
    this.height = 6,
    this.stale = false,
  });

  final double? fraction;
  final UsageStatus status;
  final AppMotion motion;
  final double height;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = c.forStatus(status).withValues(alpha: stale ? 0.5 : 1);
    final target = (fraction ?? 0).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: fraction == null ? c.track.withValues(alpha: 0.5) : c.track,
                  border: Border.all(color: c.shadow.withValues(alpha: dark ? 0.25 : 0.06), width: 0.5),
                  borderRadius: BorderRadius.circular(height),
                ),
              ),
            ),
            // Positioned.fill is load-bearing: as a plain Stack child this gets
            // loose constraints, and a DecoratedBox with no child collapses to
            // constraints.smallest — a zero-height fill. The bar then renders as
            // an empty track no matter what the value is.
            if (fraction != null)
              Positioned.fill(
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: target),
                  duration: motion.value,
                  curve: motion.settle,
                  builder: (context, value, _) => FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: value,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Color.lerp(color, Colors.white, 0.18)!,
                            color,
                            Color.lerp(color, Colors.black, 0.08)!,
                          ],
                          stops: const <double>[0, 0.55, 1],
                        ),
                        borderRadius: BorderRadius.circular(height),
                        boxShadow: status == UsageStatus.critical && !stale
                            ? <BoxShadow>[BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 6)]
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
