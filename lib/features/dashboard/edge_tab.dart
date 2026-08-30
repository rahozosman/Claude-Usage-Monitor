import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/motion_scope.dart';
import '../../app/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/format_utils.dart';
import '../../core/utils/usage_math.dart';
import '../../models/limit_window.dart';
import '../../widgets/claude_mark.dart';
import '../shell/shell_controller.dart';
import 'usage_controller.dart';

/// STATE 1 — the tiny vertical glass tab stuck to the right edge.
///
/// Deliberately almost invisible: the Claude mark and one hair-thin level
/// showing the tightest subscription window. No text, no cards, no numbers.
/// Click opens the limits panel; dragging moves it up and down the edge.
class EdgeTab extends StatefulWidget {
  const EdgeTab({super.key});

  @override
  State<EdgeTab> createState() => _EdgeTabState();
}

class _EdgeTabState extends State<EdgeTab> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final usage = context.watch<UsageController>();
    final shell = context.read<ShellController>();
    final motion = context.motion;
    final c = context.colors;
    final snap = usage.snapshot;

    return ValueListenableBuilder<DateTime>(
      valueListenable: usage.clock,
      builder: (context, now, _) {
        // The tightest of the two subscription windows drives the sliver.
        // A closed window is skipped: its last figure is history, and the
        // sliver would otherwise sit at a level nothing is measuring.
        LimitWindow? worst;
        for (final w in <LimitWindow>[snap.fiveHour, snap.weekly]) {
          if (!w.isActive(now)) continue;
          if (worst == null || (w.usedPercentage ?? 0) > (worst.usedPercentage ?? 0)) worst = w;
        }
        final status = worst == null ? UsageStatus.unknown : worst.status;
        final level = worst?.usedPercentage;

        String share(LimitWindow w, String of) =>
            w.isActive(now) ? '${FormatUtils.percent(w.usedPercentage)} of $of' : LimitWindow.noActiveWindow(w.id);
        final tooltip = worst == null
            ? 'Claude usage — click to open'
            : '${share(snap.fiveHour, '5 hours')} · ${share(snap.weekly, 'the week')}\nClick to open';

        return Tooltip(
          message: tooltip,
          waitDuration: const Duration(milliseconds: 500),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() {
              _hover = false;
              _down = false;
            }),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => setState(() => _down = true),
              onTapUp: (_) => setState(() => _down = false),
              onTapCancel: () => setState(() => _down = false),
              onTap: shell.showLimits,
              onPanStart: (_) => shell.startDragging(),
              child: AnimatedScale(
                // Grows from the edge it is attached to, never away from it.
                alignment: Alignment.centerRight,
                scale: _down ? 0.94 : (_hover ? 1.05 : 1),
                duration: motion.micro,
                curve: motion.enter,
                child: SizedBox(
                  width: AppConstants.edgeTabWidth,
                  height: AppConstants.edgeTabHeight,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      AnimatedOpacity(
                        duration: motion.micro,
                        opacity: _hover ? 1 : 0.82,
                        child: ClaudeMark(color: c.mark, size: 11),
                      ),
                      const SizedBox(height: 9),
                      _Level(fraction: UsageMath.fraction(level), known: level != null, status: status),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A 3 px vertical level that fills from the bottom.
class _Level extends StatelessWidget {
  const _Level({required this.fraction, required this.known, required this.status});

  final double fraction;
  final bool known;
  final UsageStatus status;

  static const double _height = 26;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final motion = context.motion;
    final color = c.forStatus(status);
    return SizedBox(
      width: 3,
      height: _height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Stack(
          children: <Widget>[
            Positioned.fill(child: ColoredBox(color: c.track)),
            if (known)
              TweenAnimationBuilder<double>(
                tween: Tween<double>(end: fraction),
                duration: motion.value,
                curve: motion.settle,
                builder: (context, v, _) => Align(
                  alignment: Alignment.bottomCenter,
                  // The explicit width matters: a ColoredBox with no child takes
                  // constraints.smallest, so without it the level is zero wide
                  // and the sliver looks permanently empty.
                  child: SizedBox(
                    width: double.infinity,
                    height: (_height * v).clamp(1.5, _height),
                    child: ColoredBox(color: color),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
