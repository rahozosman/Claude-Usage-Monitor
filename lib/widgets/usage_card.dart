import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_dimens.dart';
import '../app/theme/app_motion.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/format_utils.dart';
import '../core/utils/usage_math.dart';
import '../models/limit_window.dart';
import 'animated_number.dart';
import 'countdown.dart';
import 'glass_panel.dart';
import 'section_header.dart';
import 'usage_bar.dart';

/// Expanded-view card for one rolling window (5-hour, weekly, …).
class UsageCard extends StatelessWidget {
  const UsageCard({
    super.key,
    required this.window,
    required this.motion,
    required this.clock,
    required this.showPercentages,
    required this.showCountdown,
    this.opacity = 1,
  });

  final LimitWindow window;
  final AppMotion motion;
  final ValueListenable<DateTime> clock;
  final bool showPercentages;
  final bool showCountdown;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;

    return GlassPanel(
      elevated: true,
      opacity: opacity,
      radius: AppDimens.radiusMd,
      padding: const EdgeInsets.fromLTRB(AppDimens.s16, AppDimens.s14, AppDimens.s16, AppDimens.s14),
      child: ValueListenableBuilder<DateTime>(
        valueListenable: clock,
        builder: (context, now, _) {
          final reset = window.hasReset(now);
          final stale = window.isStale(now, AppConstants.staleAfter);
          final available = window.isAvailable;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SectionHeader(
                title: window.label,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (available && stale) _Chip(label: 'Stale', color: c.statusModerate),
                    if (available && stale) const SizedBox(width: AppDimens.s6),
                    if (available && reset)
                      _Chip(label: 'Reset', color: c.statusOffline)
                    else if (available)
                      _Chip(label: _statusLabel(window.status), color: c.forStatus(window.status))
                    else
                      _Chip(label: 'Unavailable', color: c.statusOffline),
                  ],
                ),
              ),
              const SizedBox(height: AppDimens.s10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  if (available && showPercentages)
                    AnimatedNumber(
                      value: reset ? null : window.usedPercentage,
                      motion: motion,
                      style: t.titleMedium?.copyWith(fontSize: 26, height: 1, fontWeight: FontWeight.w600),
                    )
                  else
                    Text(
                      available ? '' : '—',
                      style: t.titleMedium?.copyWith(fontSize: 26, height: 1, color: c.textTertiary),
                    ),
                  const SizedBox(width: AppDimens.s8),
                  if (available)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text('used', style: t.bodySmall),
                    ),
                  const Spacer(),
                  if (available && !reset && showCountdown)
                    Countdown(
                      resetsAt: window.resetsAt,
                      clock: clock,
                      prefix: 'Resets in ',
                      resetText: 'reset · awaiting data',
                      style: t.bodySmall?.copyWith(color: c.textSecondary, fontWeight: FontWeight.w500),
                    ),
                ],
              ),
              const SizedBox(height: AppDimens.s10),
              UsageBar(
                fraction: available && !reset ? UsageMath.fraction(window.usedPercentage) : null,
                status: reset ? UsageStatus.unknown : window.status,
                motion: motion,
                height: AppDimens.barThick,
                stale: stale,
              ),
              const SizedBox(height: AppDimens.s12),
              if (available) ..._details(context, now, reset, stale) else _unavailable(context),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _details(BuildContext context, DateTime now, bool reset, bool stale) {
    final c = context.colors;
    final rows = <(String, String)>[
      ('Used', reset ? LimitWindow.noActiveWindow(window.id) : FormatUtils.percent(window.usedPercentage)),
      ('Remaining', reset ? '—' : FormatUtils.percent(window.remainingPercentage)),
      ('Amount', window.used != null ? FormatUtils.integer(window.used) : 'Not provided by Claude'),
      ('Resets at', FormatUtils.absolute(window.resetsAt, now)),
      ('Updated', FormatUtils.relative(window.observedAt, now)),
      ('Source', window.source.label),
    ];
    return <Widget>[
      _DetailGrid(rows: rows, dim: stale),
      if (stale)
        Padding(
          padding: const EdgeInsets.only(top: AppDimens.s8),
          child: Text(
            'Last update is older than ${AppConstants.staleAfter.inMinutes} minutes — values may have changed.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.statusModerate),
          ),
        ),
    ];
  }

  Widget _unavailable(BuildContext context) {
    final c = context.colors;
    return Text(
      window.unavailableReason ?? 'Not provided by Claude',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.textSecondary),
    );
  }

  static String _statusLabel(UsageStatus s) {
    switch (s) {
      case UsageStatus.normal:
        return 'Normal';
      case UsageStatus.moderate:
        return 'Moderate';
      case UsageStatus.warning:
        return 'Warning';
      case UsageStatus.critical:
        return 'Critical';
      case UsageStatus.unknown:
        return 'Unknown';
    }
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, letterSpacing: 0.3),
      ),
    );
  }
}

/// Two-column label/value grid shared by the cards.
class _DetailGrid extends StatelessWidget {
  const _DetailGrid({required this.rows, this.dim = false});

  final List<(String, String)> rows;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Column(
      children: <Widget>[
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 92,
                  child: Text(label, style: t.bodySmall?.copyWith(color: c.textTertiary)),
                ),
                Expanded(
                  child: Text(
                    value,
                    style: t.bodySmall?.copyWith(
                      color: dim ? c.textSecondary : c.textPrimary,
                      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Public wrapper so other cards can reuse the grid.
class DetailGrid extends StatelessWidget {
  const DetailGrid({super.key, required this.rows, this.dim = false});

  final List<(String, String)> rows;
  final bool dim;

  @override
  Widget build(BuildContext context) => _DetailGrid(rows: rows, dim: dim);
}

/// Public chip for reuse.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => _Chip(label: label, color: color);
}
