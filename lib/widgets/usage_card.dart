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
          // Closed is its own state, not a flavour of unavailable: the figure
          // is real and recent, it just stopped being live when the block
          // ended. Shown dimmed throughout so it can never read as current.
          final closed = available && reset;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SectionHeader(
                title: window.label,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // "Stale" means the feed is late. A closed window is not
                    // late — it is finished — so Closed stands on its own.
                    if (available && stale && !closed) _Chip(label: 'Stale', color: c.statusModerate),
                    if (available && stale && !closed) const SizedBox(width: AppDimens.s6),
                    if (closed)
                      _Chip(label: 'Closed', color: c.statusOffline)
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
                      value: window.usedPercentage,
                      motion: motion,
                      style: t.titleMedium?.copyWith(
                        fontSize: 26,
                        height: 1,
                        fontWeight: FontWeight.w600,
                        color: closed ? c.textTertiary : null,
                      ),
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
                      child: Text(closed ? 'used before it closed' : 'used', style: t.bodySmall),
                    ),
                  const Spacer(),
                  if (closed)
                    Text(
                      'closed ${FormatUtils.relative(window.knownResetsAt, now)}',
                      style: t.bodySmall?.copyWith(color: c.textTertiary, fontWeight: FontWeight.w500),
                    )
                  else if (available && showCountdown && window.knownResetsAt != null)
                    Countdown(
                      resetsAt: window.knownResetsAt,
                      clock: clock,
                      prefix: 'Resets in ',
                      resetText: 'reset · awaiting data',
                      style: t.bodySmall?.copyWith(color: c.textSecondary, fontWeight: FontWeight.w500),
                    ),
                ],
              ),
              const SizedBox(height: AppDimens.s10),
              UsageBar(
                fraction: available ? UsageMath.fraction(window.usedPercentage) : null,
                // Grey, not the status colour: a closed 95% is not a warning
                // about anything happening now.
                status: closed ? UsageStatus.unknown : window.status,
                motion: motion,
                height: AppDimens.barThick,
                stale: stale || closed,
              ),
              const SizedBox(height: AppDimens.s12),
              if (available) ..._details(context, now, closed, stale) else _unavailable(context),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _details(BuildContext context, DateTime now, bool closed, bool stale) {
    final c = context.colors;
    final rows = <(String, String)>[
      ('Used', FormatUtils.percent(window.usedPercentage)),
      // Remaining is a live quantity. There is nothing left to spend in a
      // block that is over, so the row goes rather than reading "92%".
      if (!closed) ('Remaining', FormatUtils.percent(window.remainingPercentage)),
      ('Amount', window.used != null ? FormatUtils.integer(window.used) : 'Not provided by Claude'),
      // Not window.resetsAt: an uncredible one prints as "—" rather than
      // as a reset time in the past, which is what it literally is.
      (closed ? 'Closed at' : 'Resets at', FormatUtils.absolute(window.knownResetsAt, now)),
      ('Updated', FormatUtils.relative(window.observedAt, now)),
      ('Source', window.source.label),
    ];
    return <Widget>[
      _DetailGrid(rows: rows, dim: stale || closed),
      if (closed)
        Padding(
          padding: const EdgeInsets.only(top: AppDimens.s8),
          child: Text(
            '${LimitWindow.closedWindow(window.id, FormatUtils.percent(window.usedPercentage), FormatUtils.relative(window.knownResetsAt, now))}. '
            'A new one opens on your next message to Claude.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.textTertiary),
          ),
        ),
      // Staleness is about the feed, closure about the window: a closed one is
      // not late, so the warning would be noise on top of the line above.
      if (stale && !closed)
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
