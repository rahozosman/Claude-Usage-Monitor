import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/motion_scope.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimens.dart';
import '../../app/theme/app_motion.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/format_utils.dart';
import '../../core/utils/usage_math.dart';
import '../../models/limit_window.dart';
import '../../widgets/claude_mark.dart';
import '../../widgets/status_indicator.dart';
import '../../widgets/usage_bar.dart';
import '../settings/settings_controller.dart';
import '../shell/shell_controller.dart';
import 'usage_controller.dart';

/// STATE 2 — the compact limits panel: only 5 hours, 1 week and API.
///
/// Reads the existing [UsageController] snapshot; it starts no requests of its
/// own. Clicking anywhere on it (header included) transitions to Home.
class LimitsPanel extends StatelessWidget {
  const LimitsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final usage = context.watch<UsageController>();
    final settings = context.watch<SettingsController>().settings;
    final shell = context.read<ShellController>();
    final motion = context.motion;
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final snap = usage.snapshot;

    final api = snap.api;
    final apiPercent = api?.headlineUsedPercentage;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: shell.showHome,
        child: SizedBox(
          width: AppConstants.limitsWidth,
          height: AppConstants.limitsHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppDimens.s16, AppDimens.s12, AppDimens.s14, AppDimens.s14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _Entrance(
                  index: 0,
                  motion: motion,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) => shell.startDragging(),
                    onTap: shell.showHome,
                    child: Row(
                      children: <Widget>[
                        ClaudeMark(color: c.mark, size: 11),
                        const SizedBox(width: AppDimens.s8),
                        Text('Claude Usage', style: t.titleMedium),
                        const Spacer(),
                        StatusIndicator(status: snap.connection, motion: motion, size: 6),
                        const SizedBox(width: AppDimens.s8),
                        Tooltip(
                          message: 'Open the full window',
                          child: Icon(Icons.chevron_right_rounded, size: 15, color: c.textTertiary),
                        ),
                      ],
                    ),
                  ),
                ),
                _Entrance(
                  index: 1,
                  motion: motion,
                  child: _LimitRow(
                    label: '5 HOURS',
                    window: snap.fiveHour,
                    clock: usage.clock,
                    motion: motion,
                    showCountdown: settings.showCountdown,
                  ),
                ),
                _Entrance(
                  index: 2,
                  motion: motion,
                  child: _LimitRow(
                    label: '1 WEEK',
                    window: snap.weekly,
                    clock: usage.clock,
                    motion: motion,
                    showCountdown: settings.showCountdown,
                  ),
                ),
                _Entrance(
                  index: 3,
                  motion: motion,
                  child: _ApiRow(percent: apiPercent, configured: usage.apiConfigured, motion: motion),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One subscription window: name, percentage, bar, then remaining + reset.
class _LimitRow extends StatelessWidget {
  const _LimitRow({
    required this.label,
    required this.window,
    required this.clock,
    required this.motion,
    required this.showCountdown,
  });

  final String label;
  final LimitWindow window;
  final ValueListenable<DateTime> clock;
  final AppMotion motion;
  final bool showCountdown;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime>(
      valueListenable: clock,
      builder: (context, now, _) {
        final closed = window.isClosed(now);
        final live = window.isActive(now);
        final stale = window.isStale(now, AppConstants.staleAfter);
        final meta = !window.isAvailable
            ? (window.unavailableReason ?? 'Not provided by Claude')
            : closed
            // The row's own label already names the span, so the short form
            // here — the card carries the full sentence.
            ? 'closed ${FormatUtils.relative(window.knownResetsAt, now)}'
            : <String>[
                '${FormatUtils.percent(window.remainingPercentage)} left',
                if (showCountdown && window.knownResetsAt != null)
                  'resets in ${FormatUtils.countdown(window.untilReset(now))}',
                if (stale) 'stale',
              ].join(' · ');

        return _Section(
          label: label,
          // A closed figure is kept, but greyed: `stale` is what dims the
          // number and `unknown` is what drains the colour out of the bar.
          percent: window.isAvailable ? window.usedPercentage : null,
          fraction: window.isAvailable ? UsageMath.fraction(window.usedPercentage) : null,
          status: live ? window.status : UsageStatus.unknown,
          meta: meta,
          motion: motion,
          stale: stale || closed,
        );
      },
    );
  }
}

/// The API limiter — headroom on the tightest per-minute limit, no reset line.
class _ApiRow extends StatelessWidget {
  const _ApiRow({required this.percent, required this.configured, required this.motion});

  final double? percent;
  final bool configured;
  final AppMotion motion;

  @override
  Widget build(BuildContext context) {
    final meta = !configured
        ? 'Add an API key in Settings'
        : percent == null
        ? 'Waiting for the first probe'
        : '${FormatUtils.percent(UsageMath.remainingPercentage(percent))} left of the tightest limit';
    return _Section(
      label: 'API',
      percent: percent,
      fraction: percent == null ? null : UsageMath.fraction(percent),
      status: UsageMath.statusFor(percent),
      meta: meta,
      motion: motion,
      stale: false,
    );
  }
}

/// Shared three-line block: name + value, bar, meta.
class _Section extends StatelessWidget {
  const _Section({
    required this.label,
    required this.percent,
    required this.fraction,
    required this.status,
    required this.meta,
    required this.motion,
    required this.stale,
  });

  final String label;
  final double? percent;
  final double? fraction;
  final UsageStatus status;
  final String meta;
  final AppMotion motion;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Text(label, style: t.labelSmall?.copyWith(letterSpacing: 0.6)),
            const Spacer(),
            if (percent == null)
              Text('—', style: t.titleMedium?.copyWith(fontSize: 15, color: c.textTertiary))
            else
              TweenAnimationBuilder<double>(
                tween: Tween<double>(end: percent),
                duration: motion.value,
                curve: motion.settle,
                builder: (context, v, _) => Text(
                  '${v.toStringAsFixed(0)}%',
                  style: t.titleMedium?.copyWith(
                    fontSize: 15,
                    color: stale ? c.textSecondary : c.textPrimary,
                    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppDimens.s6),
        UsageBar(fraction: fraction, status: status, motion: motion, height: 5, stale: stale),
        const SizedBox(height: AppDimens.s6),
        Text(
          meta,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.bodySmall?.copyWith(fontSize: 10.5, color: c.textTertiary),
        ),
      ],
    );
  }
}

/// Small staggered fade/slide as the panel opens.
class _Entrance extends StatelessWidget {
  const _Entrance({required this.index, required this.motion, required this.child});

  final int index;
  final AppMotion motion;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!motion.enabled) return child;
    final start = (0.12 * index).clamp(0.0, 0.5);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: motion.component,
      curve: Interval(start, 1, curve: motion.enter),
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset((1 - v) * 10, 0), child: child),
      ),
      child: child,
    );
  }
}
