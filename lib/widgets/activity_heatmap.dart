import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../app/theme/app_colors.dart';
import '../app/theme/app_dimens.dart';
import '../core/utils/format_utils.dart';
import '../models/usage_stats.dart';

/// The contribution grid: one cell per calendar day between [from] and [to],
/// shaded by how many messages that day carried.
///
/// A history shorter than five weeks is drawn as a single row of days instead
/// of a 7×N grid — two lonely columns in a 482 px card read as broken, and the
/// empty year the terminal draws says nothing at all.
class ActivityHeatmap extends StatefulWidget {
  const ActivityHeatmap({super.key, required this.days, required this.from, required this.to, this.busiest = 0});

  /// Only the days Claude Code recorded; the gaps between them are the days
  /// nothing happened.
  final List<DayActivity> days;

  /// Inclusive local-midnight bounds.
  final DateTime from;
  final DateTime to;

  /// Messages on the busiest day in range — the top of the shading scale.
  final int busiest;

  /// Below this many days the grid becomes a single row.
  static const int stripThreshold = 35;

  @override
  State<ActivityHeatmap> createState() => _ActivityHeatmapState();
}

class _ActivityHeatmapState extends State<ActivityHeatmap> {
  DayActivity? _hovered;
  Offset _hoverAt = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final byDay = <String, DayActivity>{for (final d in widget.days) DayActivity.key(d.date): d};
    final label = t.bodySmall?.copyWith(color: c.textTertiary, fontSize: 9) ?? const TextStyle(fontSize: 9);

    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = _Geometry(from: widget.from, to: widget.to, width: constraints.maxWidth);
        return MouseRegion(
          onHover: (event) {
            final day = geometry.dateAt(event.localPosition);
            final found = day == null ? null : byDay[DayActivity.key(day)];
            // A day with nothing in it is still a day; showing "no activity"
            // beats a tooltip that flickers in and out across the grid.
            final resolved =
                found ??
                (day == null
                    ? null
                    : DayActivity(
                        date: day,
                        messages: 0,
                        sessions: 0,
                        toolCalls: 0,
                        tokensByModel: const <String, int>{},
                      ));
            if (resolved?.date != _hovered?.date) setState(() => _hovered = resolved);
            _hoverAt = event.localPosition;
          },
          onExit: (_) => setState(() => _hovered = null),
          child: SizedBox(
            height: geometry.height,
            width: double.infinity,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned.fill(
                  child: CustomPaint(
                    painter: _HeatmapPainter(
                      geometry: geometry,
                      byDay: byDay,
                      busiest: widget.busiest,
                      accent: c.accent,
                      empty: c.track,
                      today: c.accent,
                      labelStyle: label,
                    ),
                  ),
                ),
                if (_hovered != null)
                  Positioned(
                    left: (_hoverAt.dx - 90).clamp(0.0, (constraints.maxWidth - 180).clamp(0.0, double.infinity)),
                    top: _hoverAt.dy > geometry.height / 2 ? null : _hoverAt.dy + 14,
                    bottom: _hoverAt.dy > geometry.height / 2 ? geometry.height - _hoverAt.dy + 14 : null,
                    child: IgnorePointer(child: _Tooltip(day: _hovered!)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Where every day sits, shared by the painter and the hit test.
class _Geometry {
  _Geometry({required this.from, required this.to, required double width}) {
    final span = _daysBetween(from, to) + 1;
    strip = span <= ActivityHeatmap.stripThreshold;
    rows = strip ? 1 : 7;
    // The grid starts on the Monday of the first week, so a column is a week.
    start = strip ? from : _shift(from, -(from.weekday - DateTime.monday));
    columns = strip ? span : ((_daysBetween(start, to) + 1) / 7).ceil();
    gutter = strip ? 0 : 22;
    final available = width - gutter;
    final maxCell = strip ? 16.0 : 13.0;
    final raw = columns <= 0 ? maxCell : (available + gap) / columns - gap;
    cell = raw.clamp(4.0, maxCell);
  }

  final DateTime from;
  final DateTime to;
  late final bool strip;
  late final DateTime start;
  late final int columns;
  late final int rows;

  /// Room on the left for the Mon/Wed/Fri labels (grid only).
  late final double gutter;
  late final double cell;

  static const double gap = 2;

  /// The month (or date) labels sit above the cells.
  static const double labelHeight = 13;

  double get height => labelHeight + rows * (cell + gap) - gap;

  double get gridWidth => gutter + columns * (cell + gap) - gap;

  Rect? rectFor(DateTime day) {
    final index = _daysBetween(start, day);
    if (index < 0) return null;
    final column = strip ? index : index ~/ 7;
    final row = strip ? 0 : index % 7;
    if (column >= columns) return null;
    return Rect.fromLTWH(
      gutter + column * (cell + gap),
      labelHeight + row * (cell + gap),
      cell,
      cell,
    );
  }

  DateTime? dateAt(Offset position) {
    final x = position.dx - gutter;
    final y = position.dy - labelHeight;
    if (x < 0 || y < 0) return null;
    final column = x ~/ (cell + gap);
    final row = y ~/ (cell + gap);
    if (column < 0 || column >= columns || row < 0 || row >= rows) return null;
    final day = _shift(start, strip ? column.toInt() : column.toInt() * 7 + row.toInt());
    if (day.isBefore(from) || day.isAfter(to)) return null;
    return day;
  }

  /// Day arithmetic through UTC so a daylight-saving change cannot turn a day
  /// into 23 hours and lose a column.
  static int _daysBetween(DateTime a, DateTime b) =>
      DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

  static DateTime _shift(DateTime day, int by) => DateTime(day.year, day.month, day.day + by);
}

class _HeatmapPainter extends CustomPainter {
  const _HeatmapPainter({
    required this.geometry,
    required this.byDay,
    required this.busiest,
    required this.accent,
    required this.empty,
    required this.today,
    required this.labelStyle,
  });

  final _Geometry geometry;
  final Map<String, DayActivity> byDay;
  final int busiest;
  final Color accent;
  final Color empty;
  final Color today;
  final TextStyle labelStyle;

  /// Four steps, so a quiet day and a heavy one are told apart at a glance.
  static const List<double> _steps = <double>[0.30, 0.52, 0.76, 1];

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(geometry.cell >= 8 ? 2.5 : 1.5);
    final now = DateTime.now();
    final todayKey = DayActivity.key(DateTime(now.year, now.month, now.day));

    var cursor = geometry.from;
    while (!cursor.isAfter(geometry.to)) {
      final rect = geometry.rectFor(cursor);
      if (rect != null) {
        final day = byDay[DayActivity.key(cursor)];
        final level = _level(day?.messages ?? 0);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, radius),
          Paint()..color = level == 0 ? empty : accent.withValues(alpha: _steps[level - 1]),
        );
        if (DayActivity.key(cursor) == todayKey) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect.inflate(1.4), Radius.circular(radius.x + 1.4)),
            Paint()
              ..color = today
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1,
          );
        }
      }
      cursor = _Geometry._shift(cursor, 1);
    }

    if (geometry.strip) {
      _paintStripLabels(canvas);
    } else {
      _paintWeekdayLabels(canvas);
      _paintMonthLabels(canvas);
    }
  }

  int _level(int messages) {
    if (messages <= 0) return 0;
    if (busiest <= 0) return 4;
    final share = messages / busiest;
    if (share <= 0.25) return 1;
    if (share <= 0.5) return 2;
    if (share <= 0.75) return 3;
    return 4;
  }

  void _paintStripLabels(Canvas canvas) {
    final format = DateFormat('d MMM');
    var cursor = geometry.from;
    while (!cursor.isAfter(geometry.to)) {
      // One tick per week, plus the first day, so the row stays readable.
      final isWeekStart = cursor.weekday == DateTime.monday;
      if (isWeekStart || cursor == geometry.from) {
        final rect = geometry.rectFor(cursor);
        if (rect != null) _text(canvas, format.format(cursor), Offset(rect.left, 0));
      }
      cursor = _Geometry._shift(cursor, 1);
    }
  }

  void _paintWeekdayLabels(Canvas canvas) {
    const labels = <int, String>{DateTime.monday: 'Mon', DateTime.wednesday: 'Wed', DateTime.friday: 'Fri'};
    labels.forEach((weekday, text) {
      final row = weekday - DateTime.monday;
      _text(canvas, text, Offset(0, _Geometry.labelHeight + row * (geometry.cell + _Geometry.gap) - 1));
    });
  }

  void _paintMonthLabels(Canvas canvas) {
    final format = DateFormat('MMM');
    var lastMonth = -1;
    var lastX = -100.0;
    var cursor = geometry.start;
    while (!cursor.isAfter(geometry.to)) {
      if (cursor.month != lastMonth) {
        final rect = geometry.rectFor(cursor);
        // Only where the month's first drawn week begins, and never so close
        // to the previous label that the two collide.
        if (rect != null && rect.left - lastX > 20) {
          _text(canvas, format.format(cursor), Offset(rect.left, 0));
          lastX = rect.left;
        }
        lastMonth = cursor.month;
      }
      cursor = _Geometry._shift(cursor, 7);
    }
  }

  void _text(Canvas canvas, String value, Offset at) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_HeatmapPainter old) =>
      old.byDay != byDay ||
      old.busiest != busiest ||
      old.accent != accent ||
      old.empty != empty ||
      old.geometry.cell != geometry.cell ||
      old.geometry.from != geometry.from ||
      old.geometry.to != geometry.to;
}

/// What one day actually held, in the same words as the card.
class _Tooltip extends StatelessWidget {
  const _Tooltip({required this.day});

  final DayActivity day;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final date = DateFormat('EEE d MMM').format(day.date);
    final detail = day.isActive
        ? '${FormatUtils.integer(day.messages)} messages · '
              '${day.sessions} session${day.sessions == 1 ? '' : 's'} · '
              '${FormatUtils.compact(day.tokens)} tokens'
        : 'No Claude Code activity';

    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.s8, vertical: AppDimens.s6),
      decoration: BoxDecoration(
        color: c.surfaceElevated,
        borderRadius: BorderRadius.circular(AppDimens.radiusSm),
        border: Border.all(color: c.borderStrong, width: 0.6),
        boxShadow: <BoxShadow>[
          BoxShadow(color: c.shadow.withValues(alpha: 0.28), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(date, style: t.bodySmall?.copyWith(color: c.textPrimary, fontWeight: FontWeight.w600)),
          Text(detail, style: t.bodySmall?.copyWith(color: c.textSecondary, fontSize: 11)),
          if (day.fromTranscripts)
            Text(
              'Counted here — Claude Code has not finished counting this day.',
              style: t.bodySmall?.copyWith(color: c.textTertiary, fontSize: 10),
            ),
        ],
      ),
    );
  }
}

/// The `Less ▢▨▩■ More` key under the grid.
class HeatmapLegend extends StatelessWidget {
  const HeatmapLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final style = t.bodySmall?.copyWith(color: c.textTertiary, fontSize: 10);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text('Less', style: style),
        const SizedBox(width: AppDimens.s4),
        for (final alpha in <double?>[null, ..._HeatmapPainter._steps])
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: alpha == null ? c.track : c.accent.withValues(alpha: alpha),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        const SizedBox(width: AppDimens.s4),
        Text('More', style: style),
      ],
    );
  }
}
