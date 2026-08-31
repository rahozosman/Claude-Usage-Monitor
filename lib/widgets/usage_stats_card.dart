import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_dimens.dart';
import '../app/theme/app_motion.dart';
import '../core/utils/format_utils.dart';
import '../models/session_usage.dart';
import '../models/usage_stats.dart';
import 'activity_heatmap.dart';
import 'animated_number.dart';
import 'glass_panel.dart';
import 'mac_controls.dart';
import 'section_header.dart';
import 'usage_card.dart';

/// "How you use it": the shape of the account's history — days, streaks,
/// sessions and tokens — read from Claude Code's own stats cache, which is
/// what its `/usage` Overview tab is drawn from.
///
/// The percentages above say how much is gone, the activity card says what
/// spent it, and this says how the two came about over time.
class UsageStatsCard extends StatefulWidget {
  const UsageStatsCard({
    super.key,
    required this.stats,
    required this.local,
    required this.motion,
    required this.clock,
    this.opacity = 1,
  });

  final UsageStats? stats;

  /// This PC's transcript scan — the only source with a per-day input/output/
  /// cache split, which the stats cache keeps for all time only.
  final LocalUsageReport? local;
  final AppMotion motion;
  final ValueListenable<DateTime> clock;
  final double opacity;

  @override
  State<UsageStatsCard> createState() => _UsageStatsCardState();
}

class _UsageStatsCardState extends State<UsageStatsCard> {
  StatsRange _range = StatsRange.allTime;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final stats = widget.stats;

    return GlassPanel(
      elevated: true,
      opacity: widget.opacity,
      radius: AppDimens.radiusMd,
      padding: const EdgeInsets.fromLTRB(AppDimens.s16, AppDimens.s14, AppDimens.s16, AppDimens.s14),
      child: ValueListenableBuilder<DateTime>(
        valueListenable: widget.clock,
        builder: (context, now, _) {
          final range = stats == null ? null : RangeStats.compute(stats: stats, range: _range, now: now);
          final split = _split(now);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SectionHeader(
                title: 'How you use it · ${_range.label.toLowerCase()}',
                trailing: StatusChip(label: 'Claude Code · /usage', color: c.textTertiary),
              ),
              const SizedBox(height: AppDimens.s10),
              if (stats == null || range == null)
                Text(
                  'Claude Code has not written a stats cache this app can read yet — open Claude Code and '
                  'run /usage once, and this fills in from ~/.claude/stats-cache.json.',
                  style: t.bodySmall?.copyWith(color: c.textSecondary),
                )
              else ...<Widget>[
                Row(
                  children: <Widget>[
                    MacSegmentedControl<StatsRange>(
                      value: _range,
                      items: StatsRange.values,
                      labelOf: (r) => r.label,
                      motion: widget.motion,
                      segmentWidth: 62,
                      onChanged: (r) => setState(() => _range = r),
                    ),
                    const Spacer(),
                    const HeatmapLegend(),
                  ],
                ),
                const SizedBox(height: AppDimens.s12),
                ActivityHeatmap(
                  days: range.days,
                  from: range.from,
                  to: range.to,
                  busiest: range.busiestMessages,
                ),
                const SizedBox(height: AppDimens.s14),
                _Hero(range: range, motion: widget.motion),
                const SizedBox(height: AppDimens.s12),
                _Tiles(stats: stats, range: range, now: now),
                const SizedBox(height: AppDimens.s12),
                _Split(totals: split, basis: _splitBasis(stats, split, range), motion: widget.motion),
                if (stats.hourCounts.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppDimens.s12),
                  _WhenYouWork(hours: stats.hourCounts),
                ],
                const SizedBox(height: AppDimens.s10),
                Container(height: 1, color: c.border),
                const SizedBox(height: AppDimens.s8),
                Text(_provenance(stats, now), style: t.bodySmall?.copyWith(color: c.textTertiary, fontSize: 11)),
              ],
            ],
          );
        },
      ),
    );
  }

  /// The input/output/cache split for the chosen range, or null when no single
  /// source can give it honestly.
  ModelTotals? _split(DateTime now) {
    final stats = widget.stats;
    if (stats == null) return null;
    switch (_range) {
      case StatsRange.allTime:
        return stats.hasSplit ? stats.allTimeTotals : null;
      case StatsRange.last7:
        final rollups = widget.local?.dayRollups ?? const <DayRollup>[];
        if (rollups.isEmpty) return null;
        final from = DateTime(now.year, now.month, now.day - 6);
        var sum = const ModelTotals();
        for (final day in rollups) {
          if (!day.date.isBefore(from)) sum = sum + day.totals;
        }
        return sum.isEmpty ? null : sum;
      case StatsRange.last30:
        // Claude Code stores the split for all time only, and this PC's
        // transcripts reach back 7 days. Nothing here can be interpolated
        // into a 30-day answer, so the card says so instead of inventing one.
        return null;
    }
  }

  String _splitBasis(UsageStats stats, ModelTotals? split, RangeStats range) {
    // Whatever the source, the split covers a definite set of tokens. Where
    // that is fewer than the range holds, the card says so rather than letting
    // the bar imply it accounts for everything.
    final covered = split?.total ?? 0;
    final missing = range.totalTokens - covered;
    final short = covered > 0 && missing > range.totalTokens * 0.02;
    switch (_range) {
      case StatsRange.allTime:
        final through = stats.lastComputedDate;
        return 'All time · Claude Code’s own totals'
            '${through == null ? '' : ', counted through ${DateFormat('d MMM').format(through)}'}'
            '${short ? ' — the ${FormatUtils.compact(missing)} tokens counted here since are not in this split yet.' : '.'}';
      case StatsRange.last7:
        return 'Last 7 days · counted from this PC’s transcripts'
            '${short ? ' — ${FormatUtils.compact(covered)} of the ${FormatUtils.compact(range.totalTokens)} tokens in '
                  'this range; the rest is in transcripts older than the 7-day scan.' : '.'}';
      case StatsRange.last30:
        return 'Claude Code keeps this split for all time only, and this PC’s transcripts reach back 7 days — '
            'so there is no honest 30-day answer to give.';
    }
  }

  String _provenance(UsageStats stats, DateTime now) {
    final parts = <String>[
      'Read from Claude Code’s own stats cache — the same numbers as its /usage → Overview. '
          'This PC and this account only.',
      'Cache updated ${FormatUtils.relative(stats.observedAt, now)}.',
    ];
    final topped = stats.toppedUpFrom;
    if (topped != null) {
      parts.add(
        '${DateFormat('d MMM').format(topped)} onwards counted here from the same transcripts, '
        'because Claude Code had not finished counting them — which is what /usage does too.',
      );
    }
    if (!stats.versionUnderstood) {
      parts.add('The cache is format v${stats.version}; anything unrecognised in it was left out rather than guessed.');
    }
    return parts.join(' ');
  }
}

/// The two figures worth reading from across the room.
class _Hero extends StatelessWidget {
  const _Hero({required this.range, required this.motion});

  final RangeStats range;
  final AppMotion motion;

  @override
  Widget build(BuildContext context) {
    final tokens = _scale(range.totalTokens);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Figure(
          label: 'Total tokens',
          value: tokens.$1,
          suffix: tokens.$2,
          decimals: tokens.$3,
          sub: '${FormatUtils.integer(range.messages)} messages',
          motion: motion,
        ),
        const SizedBox(width: AppDimens.s24),
        _Figure(
          label: 'Sessions',
          value: range.sessions.toDouble(),
          suffix: '',
          decimals: 0,
          sub: '${FormatUtils.integer(range.toolCalls)} tool calls',
          motion: motion,
        ),
      ],
    );
  }

  /// Split into the number and its unit so [AnimatedNumber] can tween the
  /// number itself; the unit only changes when the scale does.
  static (double, String, int) _scale(int value) {
    final v = value.toDouble();
    if (v.abs() >= 1e9) return (v / 1e9, 'B', 2);
    if (v.abs() >= 1e6) return (v / 1e6, 'M', 2);
    if (v.abs() >= 1e3) return (v / 1e3, 'k', 1);
    return (v, '', 0);
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    required this.suffix,
    required this.decimals,
    required this.sub,
    required this.motion,
  });

  final String label;
  final double value;
  final String suffix;
  final int decimals;
  final String sub;
  final AppMotion motion;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: t.labelMedium),
        const SizedBox(height: 2),
        AnimatedNumber(
          value: value,
          motion: motion,
          suffix: suffix,
          decimals: decimals,
          style: t.titleMedium?.copyWith(fontSize: 24, height: 1.1, fontWeight: FontWeight.w600),
        ),
        Text(sub, style: t.bodySmall?.copyWith(color: c.textTertiary)),
      ],
    );
  }
}

/// Six compact facts, two rows of three.
class _Tiles extends StatelessWidget {
  const _Tiles({required this.stats, required this.range, required this.now});

  final UsageStats stats;
  final RangeStats range;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final favorite = range.favoriteModel;
    final longest = stats.longestSession;
    final busiest = range.mostActiveDay;

    final tiles = <Widget>[
      _Tile(
        label: 'Favourite model',
        value: favorite == null ? '—' : FormatUtils.modelShortName(favorite.$1),
        sub: favorite == null ? 'no tokens in range' : '${(favorite.$2 * 100).toStringAsFixed(0)}% of the tokens',
      ),
      _Tile(
        label: 'Longest session',
        value: longest == null ? '—' : FormatUtils.durationLong(longest.duration),
        sub: longest?.at == null
            ? 'not recorded'
            : '${FormatUtils.absolute(longest!.at, now)}${range.longestSessionInRange ? '' : ' · all time'}',
      ),
      _Tile(
        label: 'Active days',
        value: '${range.activeDays}/${range.spanDays}',
        sub: range.spanDays == 0 ? '' : '${(range.activeDays / range.spanDays * 100).round()}% of the days',
        fraction: range.spanDays == 0 ? null : range.activeDays / range.spanDays,
      ),
      _Tile(
        label: 'Longest streak',
        value: '${range.longestStreak} day${range.longestStreak == 1 ? '' : 's'}',
        sub: 'back to back',
      ),
      _Tile(
        label: 'Current streak',
        value: '${range.currentStreak} day${range.currentStreak == 1 ? '' : 's'}',
        sub: range.currentStreak == 0 ? 'nothing yet today' : 'and counting',
      ),
      _Tile(
        label: 'Most active day',
        value: busiest == null ? '—' : DateFormat('d MMM').format(busiest.date),
        sub: busiest == null ? 'no activity in range' : '${FormatUtils.integer(busiest.messages)} messages',
      ),
    ];

    return Column(
      children: <Widget>[
        for (var row = 0; row < 2; row++)
          Padding(
            padding: EdgeInsets.only(top: row == 0 ? 0 : AppDimens.s10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (var column = 0; column < 3; column++) ...<Widget>[
                  if (column > 0) const SizedBox(width: AppDimens.s10),
                  Expanded(child: tiles[row * 3 + column]),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, required this.sub, this.fraction});

  final String label;
  final String value;
  final String sub;

  /// Draws a hairline meter under the value (used by "Active days").
  final double? fraction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label.toUpperCase(), style: t.labelSmall?.copyWith(color: c.textTertiary, letterSpacing: 0.6)),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.bodyMedium?.copyWith(
            color: c.textPrimary,
            fontWeight: FontWeight.w600,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        if (fraction != null) ...<Widget>[
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 3,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(child: ColoredBox(color: c.track)),
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: fraction!.clamp(0.0, 1.0),
                      child: ColoredBox(color: c.accent),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 2),
        Text(sub, style: t.bodySmall?.copyWith(color: c.textTertiary, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

/// Where the tokens actually went: one stacked bar and its four exact numbers.
class _Split extends StatelessWidget {
  const _Split({required this.totals, required this.basis, required this.motion});

  final ModelTotals? totals;
  final String basis;
  final AppMotion motion;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final split = totals;

    if (split == null || split.total == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Input · output · cache', style: t.labelMedium),
          const SizedBox(height: 3),
          Text(basis, style: t.bodySmall?.copyWith(color: c.textTertiary, fontSize: 11)),
        ],
      );
    }

    // One colour stepped down by rank, like the model shares above: these are
    // four parts of one measure, not four different states.
    final parts = <(String, int, double)>[
      ('Cache read', split.cacheRead, 1),
      ('Cache write', split.cacheWrite, 0.72),
      ('Output', split.output, 0.5),
      ('Input', split.input, 0.32),
    ];
    final total = split.total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('Input · output · cache', style: t.labelMedium),
            const Spacer(),
            Text(
              FormatUtils.compact(total),
              style: t.bodySmall?.copyWith(
                color: c.textSecondary,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.s6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 8,
            child: Row(
              children: <Widget>[
                for (final (_, value, shade) in parts)
                  if (value > 0)
                    Expanded(
                      flex: value,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0, end: 1),
                        duration: motion.value,
                        curve: motion.settle,
                        builder: (context, v, child) => Opacity(opacity: v, child: child),
                        child: ColoredBox(color: c.accent.withValues(alpha: shade)),
                      ),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppDimens.s8),
        Row(
          children: <Widget>[
            for (var i = 0; i < parts.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: AppDimens.s8),
              Expanded(
                child: _SplitLegend(
                  label: parts[i].$1,
                  value: parts[i].$2,
                  share: total == 0 ? 0 : parts[i].$2 / total,
                  shade: parts[i].$3,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppDimens.s6),
        Text(basis, style: t.bodySmall?.copyWith(color: c.textTertiary, fontSize: 11)),
      ],
    );
  }
}

class _SplitLegend extends StatelessWidget {
  const _SplitLegend({required this.label, required this.value, required this.share, required this.shade});

  final String label;
  final int value;
  final double share;
  final double shade;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: c.accent.withValues(alpha: shade),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: AppDimens.s4),
            Expanded(
              child: Text(
                label,
                style: t.bodySmall?.copyWith(color: c.textSecondary, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 1),
        Text(
          '${FormatUtils.compact(value)} · ${(share * 100).toStringAsFixed(share < 0.1 ? 1 : 0)}%',
          style: t.bodySmall?.copyWith(
            color: c.textPrimary,
            fontSize: 11,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// The hour-of-day histogram Claude Code keeps but never shows.
class _WhenYouWork extends StatelessWidget {
  const _WhenYouWork({required this.hours});

  /// Hour (0-23) → sessions started in it, all time.
  final Map<int, int> hours;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    var peak = 0;
    var peakHour = 0;
    var counted = 0;
    hours.forEach((hour, count) {
      counted += count;
      if (count > peak) {
        peak = count;
        peakHour = hour;
      }
    });
    if (peak == 0) return const SizedBox.shrink();

    String hourLabel(int hour) => '${hour.toString().padLeft(2, '0')}:00';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('When you work', style: t.labelMedium),
            const Spacer(),
            Text(
              'busiest at ${hourLabel(peakHour)}',
              style: t.bodySmall?.copyWith(color: c.textSecondary, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.s6),
        SizedBox(
          height: 26,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              for (var hour = 0; hour < 24; hour++) ...<Widget>[
                if (hour > 0) const SizedBox(width: 2),
                Expanded(
                  child: Tooltip(
                    message:
                        '${hourLabel(hour)} — ${hours[hour] ?? 0} session${(hours[hour] ?? 0) == 1 ? '' : 's'} started',
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        height: (26 * ((hours[hour] ?? 0) / peak)).clamp(2.0, 26.0),
                        decoration: BoxDecoration(
                          color: (hours[hour] ?? 0) == 0
                              ? c.track
                              : c.accent.withValues(alpha: 0.35 + 0.65 * ((hours[hour] ?? 0) / peak)),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 3),
        Row(
          children: <Widget>[
            for (final label in <String>['00', '06', '12', '18', '23'])
              Expanded(
                child: Text(
                  label,
                  textAlign: label == '00'
                      ? TextAlign.left
                      : (label == '23' ? TextAlign.right : TextAlign.center),
                  style: t.bodySmall?.copyWith(color: c.textTertiary, fontSize: 9),
                ),
              ),
          ],
        ),
        Text(
          'Sessions by the hour they started — Claude Code’s own tally of $counted, all time. It keeps this '
          'histogram, but its /usage screen never shows it.',
          style: t.bodySmall?.copyWith(color: c.textTertiary, fontSize: 11),
        ),
      ],
    );
  }
}
