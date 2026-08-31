import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_dimens.dart';
import '../app/theme/app_motion.dart';
import '../core/utils/format_utils.dart';
import '../models/session_usage.dart';
import 'glass_panel.dart';
import 'section_header.dart';
import 'usage_card.dart';

/// "Today, hour by hour": how much of each hour of today was spent working,
/// and what came out of it.
///
/// The gauges above say how much of the window is gone; the activity card
/// below says which sessions spent it. Neither says *when*, which is the one
/// thing that tells a steady afternoon apart from twenty minutes that emptied
/// half the window.
///
/// Output tokens only. Input and cache are the same conversation re-sent on
/// every turn, so they grow with how long a chat has run rather than with what
/// the hour produced — on an hourly scale they drown the signal. Every figure
/// is a real count from Claude Code's transcripts on this PC.
class HourlyActivityCard extends StatefulWidget {
  const HourlyActivityCard({
    super.key,
    required this.report,
    required this.scanning,
    required this.motion,
    required this.clock,
    this.opacity = 1,
  });

  final LocalUsageReport? report;
  final bool scanning;
  final AppMotion motion;
  final ValueListenable<DateTime> clock;
  final double opacity;

  @override
  State<HourlyActivityCard> createState() => _HourlyActivityCardState();
}

class _HourlyActivityCardState extends State<HourlyActivityCard> {
  /// The hour the user clicked, or null while nothing is focused.
  int? _selected;

  void _select(int hour) => setState(() => _selected = _selected == hour ? null : hour);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final r = widget.report;
    // The list is either empty or all 24 hours; a half-built day would put the
    // columns under the wrong labels.
    final hours = r == null || r.todayHours.length != 24 ? null : r.todayHours;
    final selected = hours == null || _selected == null ? null : hours[_selected!];

    return GlassPanel(
      elevated: true,
      opacity: widget.opacity,
      radius: AppDimens.radiusMd,
      padding: const EdgeInsets.fromLTRB(AppDimens.s16, AppDimens.s14, AppDimens.s16, AppDimens.s14),
      child: ValueListenableBuilder<DateTime>(
        valueListenable: widget.clock,
        builder: (context, now, _) {
          final current = r?.hourAt(now);
          final busiest = r?.busiestHour;
          final panel = selected == null
              ? const SizedBox(width: double.infinity)
              : _HourFocus(
                  hour: selected,
                  isNow: selected.hour == now.hour,
                  isFuture: selected.hour > now.hour,
                  onClose: () => setState(() => _selected = null),
                );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SectionHeader(
                title: 'Today · hour by hour',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (r != null && r.activeHourCount > 0) ...<Widget>[
                      StatusChip(
                        label: '${r.activeHourCount} active hour${r.activeHourCount == 1 ? '' : 's'}',
                        color: c.textTertiary,
                      ),
                      const SizedBox(width: AppDimens.s6),
                    ],
                    StatusChip(label: 'Output · this PC', color: c.textTertiary),
                  ],
                ),
              ),
              const SizedBox(height: AppDimens.s10),
              if (hours == null)
                Text(
                  widget.scanning
                      ? 'Scanning local Claude Code sessions…'
                      : 'No local Claude Code sessions found.',
                  style: t.bodySmall?.copyWith(color: c.textSecondary),
                )
              else ...<Widget>[
                Row(
                  children: <Widget>[
                    _Stat(
                      label: 'This hour',
                      value: FormatUtils.compact(current?.outputTokens ?? 0),
                      sub: current == null
                          ? '—'
                          : '${current.sessions} session${current.sessions == 1 ? '' : 's'} · '
                                '${current.activeMinutes} min',
                    ),
                    const SizedBox(width: AppDimens.s16),
                    _Stat(
                      label: 'Output today',
                      value: FormatUtils.compact(r!.todayOutputTotal),
                      sub: '${r.todaySessionCount} session${r.todaySessionCount == 1 ? '' : 's'}',
                    ),
                    const SizedBox(width: AppDimens.s16),
                    _Stat(
                      label: 'Busiest hour',
                      value: busiest?.label ?? '—',
                      sub: busiest == null
                          ? 'nothing yet today'
                          : '${FormatUtils.compact(busiest.outputTokens)} output',
                    ),
                  ],
                ),
                const SizedBox(height: AppDimens.s12),
                _HourChart(
                  hours: hours,
                  now: now,
                  motion: widget.motion,
                  selected: _selected,
                  onSelect: _select,
                ),
                // The clicked hour, in full. Animated so the card grows into it
                // rather than jumping the cards below down the page — but only
                // when there is motion to animate with: AnimatedSize on a zero
                // duration re-dirties itself mid-layout and throws.
                if (widget.motion.enabled)
                  AnimatedSize(
                    duration: widget.motion.component,
                    curve: widget.motion.transition,
                    alignment: Alignment.topCenter,
                    child: panel,
                  )
                else
                  panel,
                const SizedBox(height: AppDimens.s8),
                Text(
                  'Bar height is how many of that hour\'s 60 minutes carried a response — a bar filling its slot '
                  'is an hour worked end to end — and the taller a bar is the bolder it is drawn. The strip '
                  'underneath is how many sessions were in flight. Token figures are output only: what Claude '
                  'generated, counted from its transcripts on this PC. Click an hour for its exact figures.',
                  style: t.bodySmall?.copyWith(color: c.textTertiary, fontSize: 11),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// One headline figure with its unit underneath — the same shape the activity
/// card uses, so the two read as one family.
class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.sub});

  final String label;
  final String value;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: t.labelMedium),
          const SizedBox(height: 2),
          Text(
            value,
            style: t.titleMedium?.copyWith(
              fontSize: 20,
              height: 1.1,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          Text(
            sub,
            style: t.bodySmall?.copyWith(color: c.textTertiary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// The 24 columns: minutes-worked bar on top, session strip under it, hour
/// ticks below.
class _HourChart extends StatelessWidget {
  const _HourChart({
    required this.hours,
    required this.now,
    required this.motion,
    required this.selected,
    required this.onSelect,
  });

  final List<HourActivity> hours;
  final DateTime now;
  final AppMotion motion;
  final int? selected;
  final ValueChanged<int> onSelect;

  static const double barHeight = 58;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    // The bars are drawn against a fixed 60 minutes, so only the session strip
    // needs a peak to scale against.
    var peakSessions = 0;
    for (final h in hours) {
      if (h.sessions > peakSessions) peakSessions = h.sessions;
    }
    // The tick nearest the hour running now, so it can be picked out.
    final nowTick = now.hour - now.hour % 3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            for (final h in hours)
              Expanded(
                child: _HourColumn(
                  hour: h,
                  peakSessions: peakSessions,
                  isNow: h.hour == now.hour,
                  isFuture: h.hour > now.hour,
                  isSelected: h.hour == selected,
                  motion: motion,
                  onTap: () => onSelect(h.hour),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppDimens.s4),
        Row(
          children: <Widget>[
            for (var h = 0; h < 24; h++)
              Expanded(
                // Every third hour, so the ticks never collide at 560 px wide.
                child: h % 3 != 0
                    ? const SizedBox.shrink()
                    : Text(
                        h.toString().padLeft(2, '0'),
                        textAlign: TextAlign.center,
                        style: t.bodySmall?.copyWith(
                          color: h == nowTick ? c.textSecondary : c.textTertiary,
                          fontSize: 9,
                          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                        ),
                      ),
              ),
          ],
        ),
        const SizedBox(height: AppDimens.s6),
        Row(
          children: <Widget>[
            _Key(color: c.accent, label: 'minutes worked · full height = the whole hour'),
            const SizedBox(width: AppDimens.s10),
            _Key(color: c.connected, label: 'sessions'),
          ],
        ),
      ],
    );
  }
}

class _HourColumn extends StatelessWidget {
  const _HourColumn({
    required this.hour,
    required this.peakSessions,
    required this.isNow,
    required this.isFuture,
    required this.isSelected,
    required this.motion,
    required this.onTap,
  });

  final HourActivity hour;
  final int peakSessions;
  final bool isNow;
  final bool isFuture;
  final bool isSelected;
  final AppMotion motion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // An hour that has not arrived yet is drawn quieter than one that arrived
    // and stayed empty: "nothing happened" and "not yet" are different facts.
    final track = c.track.withValues(alpha: isFuture ? 0.25 : 0.5);
    // Height is the minutes worked, out of the whole 60 — so a bar that fills
    // its slot means an hour worked end to end, on any day. Every bar is the
    // full width of its column; only the height and the colour carry meaning.
    final share = hour.minuteShare;
    // Colour follows the height, so a tall bar is also a bold one and the busy
    // hours of the day carry at a glance without reading the axis.
    final weight = 0.35 + 0.65 * share;
    final barColor = c.accent.withValues(alpha: isNow || isSelected ? 1.0 : weight);
    final sessionColor = hour.sessions <= 0
        ? track
        : c.connected.withValues(alpha: peakSessions <= 0 ? 1 : 0.35 + 0.65 * (hour.sessions / peakSessions));

    return Tooltip(
      message: _tooltip(),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          // Opaque, so the empty space above a short bar is clickable too —
          // the target is the hour, not the ink.
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  height: _HourChart.barHeight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: isSelected ? c.accent.withValues(alpha: 0.16) : track,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        TweenAnimationBuilder<double>(
                          tween: Tween<double>(end: share),
                          duration: motion.value,
                          curve: motion.settle,
                          builder: (context, v, _) => SizedBox(
                            // A single worked minute still gets a visible
                            // sliver: rounding it away would read as an hour
                            // that did nothing at all.
                            height: hour.activeMinutes <= 0
                                ? 0
                                : (_HourChart.barHeight * v).clamp(2.0, _HourChart.barHeight),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: barColor,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Container(
                  height: 4,
                  decoration: BoxDecoration(color: sessionColor, borderRadius: BorderRadius.circular(1.5)),
                ),
                const SizedBox(height: 3),
                // Says which hour is running now, and which one is focused.
                Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? c.accent
                        : isNow
                        ? c.accent.withValues(alpha: 0.55)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _tooltip() {
    if (isFuture) return '${hour.range}\nLater today';
    if (!hour.isActive) return '${hour.range}\nNothing generated in this hour';
    return '${hour.range}${isNow ? ' · running now' : ''}\n'
        '${hour.activeMinutes} of 60 min worked · '
        '${FormatUtils.compact(hour.outputTokens)} output · '
        '${hour.sessions} session${hour.sessions == 1 ? '' : 's'}\n'
        'Click for the full figures';
  }
}

/// The clicked hour, in full — the numbers the chart can only imply.
class _HourFocus extends StatelessWidget {
  const _HourFocus({required this.hour, required this.isNow, required this.isFuture, required this.onClose});

  final HourActivity hour;
  final bool isNow;
  final bool isFuture;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final rows = <(String, String)>[
      ('Sessions', '${hour.sessions}'),
      ('Output tokens', FormatUtils.integer(hour.outputTokens)),
      ('Minutes worked', '${hour.activeMinutes} of 60'),
      ('Responses', FormatUtils.integer(hour.responses)),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: AppDimens.s10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppDimens.s12),
        decoration: BoxDecoration(
          color: c.accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppDimens.radiusMd),
          border: Border.all(color: c.accent.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    hour.range,
                    style: t.bodyMedium?.copyWith(color: c.textPrimary, fontWeight: FontWeight.w600),
                  ),
                ),
                if (isNow)
                  Padding(
                    padding: const EdgeInsets.only(right: AppDimens.s6),
                    child: StatusChip(label: 'Running now', color: c.connected),
                  ),
                _CloseHour(onTap: onClose),
              ],
            ),
            const SizedBox(height: AppDimens.s8),
            if (isFuture)
              Text(
                'This hour has not started yet.',
                style: t.bodySmall?.copyWith(color: c.textSecondary),
              )
            else if (!hour.isActive)
              Text(
                'Nothing generated in this hour — no session spoke in it.',
                style: t.bodySmall?.copyWith(color: c.textSecondary),
              )
            else ...<Widget>[
              DetailGrid(rows: rows),
              const SizedBox(height: AppDimens.s6),
              Text(
                hour.activeMinutes >= 45
                    ? 'Worked through: ${hour.activeMinutes} of the 60 minutes carried a response.'
                    : 'Bursty: the work landed in ${hour.activeMinutes} minute'
                          '${hour.activeMinutes == 1 ? '' : 's'} of the hour.',
                style: t.bodySmall?.copyWith(color: c.textTertiary, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The × on the focus panel.
class _CloseHour extends StatelessWidget {
  const _CloseHour({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Tooltip(
          message: 'Close',
          child: Icon(Icons.close_rounded, size: AppDimens.iconSm, color: c.textTertiary),
        ),
      ),
    );
  }
}

/// The two-swatch key under the chart: orange is what was generated, green is
/// how many pieces of work produced it.
class _Key extends StatelessWidget {
  const _Key({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: AppDimens.s4),
          Flexible(
            child: Text(
              label,
              style: t.bodySmall?.copyWith(color: c.textTertiary, fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
