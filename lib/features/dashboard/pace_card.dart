import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimens.dart';
import '../../core/utils/format_utils.dart';
import '../../core/utils/usage_math.dart';
import '../../models/limit_window.dart';
import '../../models/usage_series.dart';
import '../../models/usage_snapshot.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/section_header.dart';
import '../../widgets/sparkline.dart';
import '../../widgets/usage_card.dart';
import 'usage_controller.dart';

/// How fast the quota is going, from what Claude actually reported.
///
/// The gauges answer "what percent am I at". They cannot answer the question
/// that decides anything — *do I start this now, or wait for the reset?* —
/// because a percentage has no direction. A rate does.
///
/// Everything here is arithmetic over recorded observations of Claude's own
/// percentages. Nothing is inferred from local token counts: transcript
/// totals do not map to Anthropic's rate-limit maths, and a pace built on
/// them would be a guess wearing a number's clothes. Where the readings are
/// too thin to say anything, this says that instead of saying it weakly.
class PaceCard extends StatelessWidget {
  const PaceCard({super.key, required this.snapshot, this.opacity = 1});

  final UsageSnapshot snapshot;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final usage = context.watch<UsageController>();
    final history = usage.history;
    final now = DateTime.now();

    final segment = history.seriesFor(LimitWindow.fiveHourId)?.current;
    final rate = segment?.rate(now);

    return GlassPanel(
      elevated: true,
      opacity: opacity,
      radius: AppDimens.radiusLg,
      padding: const EdgeInsets.fromLTRB(AppDimens.s16, AppDimens.s14, AppDimens.s16, AppDimens.s14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: 'How fast you\'re using it',
            trailing: rate == null
                ? StatusChip(label: 'Measuring', color: c.textTertiary)
                : StatusChip(
                    label: '${rate.perHour >= 0 ? '+' : ''}${rate.perHour.toStringAsFixed(0)}%/h',
                    color: rate.climbing ? c.forStatus(_paceStatus(rate, segment)) : c.textSecondary,
                  ),
          ),
          const SizedBox(height: AppDimens.s10),
          if (segment == null || segment.readings.length < 2)
            Text(
              'Not enough readings yet. The pace appears once a few status lines have arrived in the current '
              '5-hour window — usually a couple of Claude Code responses.',
              style: t.bodySmall?.copyWith(color: c.textSecondary),
            )
          else ...<Widget>[
            _Window(segment: segment, now: now),
            const SizedBox(height: AppDimens.s10),
            Text(_basis(segment, rate), style: t.bodySmall?.copyWith(color: c.textSecondary)),
            const SizedBox(height: AppDimens.s4),
            _Projection(segment: segment, rate: rate, now: now),
          ],
          const SizedBox(height: AppDimens.s14),
          _Week(weekly: snapshot.weekly, now: now),
          if (history.dailyPeaks.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppDimens.s14),
            _Days(peaks: history.dailyPeaks),
          ],
          const SizedBox(height: AppDimens.s10),
          Text(
            'Measured from the percentages Claude reported to this machine, and only while the app was running — '
            'gaps are drawn as gaps. A projection is the pace of the readings shown, not a promise.',
            style: t.bodySmall?.copyWith(color: c.textTertiary, fontSize: 11),
          ),
        ],
      ),
    );
  }

  /// Colours the pace by how close it is to costing you the window, not by
  /// the current percentage — that is what the gauge above is for.
  UsageStatus _paceStatus(UsageRate rate, UsageSegment? segment) {
    final reaches = rate.reaches(100);
    final resetsAt = segment?.resetsAt;
    if (reaches == null) return UsageStatus.normal;
    if (resetsAt == null) return UsageStatus.moderate;
    return reaches.isBefore(resetsAt) ? UsageStatus.critical : UsageStatus.normal;
  }

  String _basis(UsageSegment segment, UsageRate? rate) {
    if (rate == null) {
      final n = segment.readings.length;
      return 'No recent pace — the last reading is older than ten minutes, or there are too few of them in the '
          'last ninety ($n in this window so far).';
    }
    final direction = rate.climbing
        ? '+${rate.perHour.toStringAsFixed(0)}% per hour'
        : rate.perHour < -0.01
        ? 'falling'
        : 'holding steady';
    final mixed = segment.mixedSources ? ', from two sources' : '';
    return '$direction over the last ${FormatUtils.duration(rate.span)} '
        '(${rate.readings} reading${rate.readings == 1 ? '' : 's'}$mixed).';
  }
}

/// The current window: its observed curve, and where the reset falls.
class _Window extends StatelessWidget {
  const _Window({required this.segment, required this.now});

  final UsageSegment segment;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final resetsAt = segment.resetsAt;
    final length = UsageSeries.nominalLength(segment.readings.first.windowId);
    // Anchored on Claude's reset instant so the line's position across the
    // chart is how far through the window you are. The window's own length is
    // only used to find where it started.
    final from = resetsAt != null && length != null ? resetsAt.subtract(length) : segment.startedAt;
    final to = resetsAt ?? (segment.endedAt.isAfter(now) ? segment.endedAt : now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Sparkline(
          runs: <List<SparkPoint>>[
            for (final run in segment.runs())
              <SparkPoint>[for (final reading in run) SparkPoint(reading.observedAt, reading.percentage)],
          ],
          from: from.isAfter(segment.startedAt) ? segment.startedAt : from,
          to: to,
          color: c.accent,
          capColor: c.separator,
        ),
        const SizedBox(height: AppDimens.s4),
        Row(
          children: <Widget>[
            Text(
              'now ${FormatUtils.percent(segment.lastPercentage)} · peak ${FormatUtils.percent(segment.peakPercentage)}',
              style: t.bodySmall?.copyWith(color: c.textTertiary, fontSize: 11),
            ),
            const Spacer(),
            Text(
              resetsAt == null ? 'no reset time' : 'resets ${FormatUtils.absolute(resetsAt, now)}',
              style: t.bodySmall?.copyWith(color: c.textTertiary, fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }
}

/// The one sentence the card exists to produce.
class _Projection extends StatelessWidget {
  const _Projection({required this.segment, required this.rate, required this.now});

  final UsageSegment segment;
  final UsageRate? rate;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final resetsAt = segment.resetsAt;

    String text;
    Color color = c.textPrimary;
    if (rate == null) {
      text = 'No projection while the pace is unknown.';
      color = c.textTertiary;
    } else if (!rate!.climbing) {
      text = resetsAt == null
          ? 'Not climbing, so nothing to run out of at this pace.'
          : 'Not climbing — at this pace the window resets ${FormatUtils.absolute(resetsAt, now)} untouched.';
      color = c.textSecondary;
    } else {
      final reaches = rate!.reaches(100);
      if (reaches == null) {
        text = 'Already at the cap.';
        color = c.statusCritical;
      } else if (resetsAt != null && !reaches.isBefore(resetsAt)) {
        text = 'At this pace you stay under the cap — the window resets ${FormatUtils.absolute(resetsAt, now)} first.';
        color = c.textSecondary;
      } else {
        text = resetsAt == null
            ? 'At this pace you reach 100% around ${FormatUtils.absolute(reaches, now)}.'
            : 'At this pace you reach 100% around ${FormatUtils.absolute(reaches, now)}, before the window resets '
                  '${FormatUtils.absolute(resetsAt, now)}.';
        color = c.statusWarning;
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('→ ', style: t.bodySmall?.copyWith(color: color)),
        Expanded(child: Text(text, style: t.bodySmall?.copyWith(color: color))),
      ],
    );
  }
}

/// Used against elapsed, which is the only comparison the weekly number
/// supports without inventing anything.
class _Week extends StatelessWidget {
  const _Week({required this.weekly, required this.now});

  final LimitWindow weekly;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final used = weekly.usedPercentage;
    final resetsAt = weekly.resetsAt;
    final length = UsageSeries.nominalLength(weekly.id) ?? const Duration(days: 7);

    if (used == null || resetsAt == null) {
      return Text(
        'Weekly pace needs the weekly limit, which has not arrived yet.',
        style: t.bodySmall?.copyWith(color: c.textTertiary),
      );
    }

    final remaining = resetsAt.difference(now);
    final elapsed = (1 - remaining.inSeconds / length.inSeconds).clamp(0.0, 1.0) * 100;
    final gap = used - elapsed;
    final verdict = gap > 5
        ? 'ahead of the week'
        : gap < -5
        ? 'behind the week'
        : 'on pace';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('Week', style: t.bodySmall?.copyWith(color: c.textSecondary, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(
              verdict,
              style: t.bodySmall?.copyWith(color: gap > 5 ? c.statusWarning : c.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.s6),
        _Bar(label: 'used', fraction: used / 100, color: c.forStatus(weekly.status), value: FormatUtils.percent(used)),
        const SizedBox(height: AppDimens.s4),
        _Bar(label: 'elapsed', fraction: elapsed / 100, color: c.textTertiary, value: FormatUtils.percent(elapsed)),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.fraction, required this.color, required this.value});

  final String label;
  final double fraction;
  final Color color;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Row(
      children: <Widget>[
        SizedBox(
          width: 52,
          child: Text(label, style: t.bodySmall?.copyWith(color: c.textTertiary, fontSize: 11)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppDimens.barThin),
            child: Container(
              height: AppDimens.barThin,
              color: c.track,
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: fraction.clamp(0.0, 1.0),
                child: Container(color: color),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppDimens.s8),
        SizedBox(
          width: 38,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: t.bodySmall?.copyWith(color: c.textSecondary, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

/// The highest 5-hour reading on each of the last seven days.
///
/// A day the app never ran has no bar rather than a zero one: nothing was
/// observed, which is not the same as nothing was used.
class _Days extends StatelessWidget {
  const _Days({required this.peaks});

  final List<DailyPeak> peaks;

  static const List<String> _weekdays = <String>['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final highest = peaks.reduce((a, b) => a.peak >= b.peak ? a : b);
    final capped = peaks.where((p) => p.hitCap).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('Last 7 days', style: t.bodySmall?.copyWith(color: c.textSecondary, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(
              capped == 0
                  ? 'peak ${FormatUtils.percent(highest.peak)}'
                  : 'peak ${FormatUtils.percent(highest.peak)} · hit the cap $capped×',
              style: t.bodySmall?.copyWith(color: capped == 0 ? c.textTertiary : c.statusWarning, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.s6),
        SizedBox(
          height: 34,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              for (final peak in peaks) ...<Widget>[
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      Container(
                        height: (2 + (peak.peak.clamp(0.0, 100.0) / 100) * 22),
                        decoration: BoxDecoration(
                          color: peak.hitCap ? c.statusCritical : c.accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _weekdays[peak.day.weekday - 1],
                        style: t.bodySmall?.copyWith(color: c.textTertiary, fontSize: 9),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppDimens.s4),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
