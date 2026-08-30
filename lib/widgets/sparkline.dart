import 'package:flutter/material.dart';

/// One observed value at one moment. The widget takes no model types so it
/// stays a drawing, not a reading of the data.
class SparkPoint {
  const SparkPoint(this.at, this.value);

  final DateTime at;

  /// Percentage, 0-100.
  final double value;
}

/// The observed percentages of one usage window, drawn against real time.
///
/// [runs] are stretches of readings taken close together. They are drawn as
/// separate lines on purpose: joining across the hours the app was closed
/// would draw a straight line through values nobody measured, which is the
/// picture inventing data the app refuses to invent anywhere else.
///
/// The x-axis is [from]..[to] — normally the window opening to the reset
/// instant Claude gave — so how far the line has got across is literally how
/// far through the window you are. The y-axis is a fixed 0-100, so two
/// windows can be compared by eye.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.runs,
    required this.from,
    required this.to,
    required this.color,
    required this.capColor,
    this.height = 46,
  });

  final List<List<SparkPoint>> runs;
  final DateTime from;
  final DateTime to;
  final Color color;

  /// The 100% guide line.
  final Color capColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparkPainter(runs: runs, from: from, to: to, color: color, capColor: capColor),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  const _SparkPainter({
    required this.runs,
    required this.from,
    required this.to,
    required this.color,
    required this.capColor,
  });

  final List<List<SparkPoint>> runs;
  final DateTime from;
  final DateTime to;
  final Color color;
  final Color capColor;

  @override
  void paint(Canvas canvas, Size size) {
    final totalMs = to.difference(from).inMilliseconds;
    if (totalMs <= 0 || size.width <= 0 || size.height <= 0) return;

    double dx(DateTime at) =>
        (at.difference(from).inMilliseconds / totalMs).clamp(0.0, 1.0) * size.width;
    double dy(double value) => size.height - (value.clamp(0.0, 100.0) / 100) * size.height;

    // The cap, so a line's distance from it is readable without axis labels.
    canvas.drawLine(
      Offset(0, dy(100) + 0.5),
      Offset(size.width, dy(100) + 0.5),
      Paint()
        ..color = capColor
        ..strokeWidth = 1,
    );

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    for (final run in runs) {
      if (run.isEmpty) continue;
      // A lone reading has no line to draw, but it was still observed.
      if (run.length == 1) {
        canvas.drawCircle(Offset(dx(run.first.at), dy(run.first.value)), 1.8, Paint()..color = color);
        continue;
      }
      final path = Path()..moveTo(dx(run.first.at), dy(run.first.value));
      for (final point in run.skip(1)) {
        path.lineTo(dx(point.at), dy(point.value));
      }
      canvas.drawPath(
        Path.from(path)
          ..lineTo(dx(run.last.at), size.height)
          ..lineTo(dx(run.first.at), size.height)
          ..close(),
        fill,
      );
      canvas.drawPath(path, stroke);
    }

    for (var i = runs.length - 1; i >= 0; i--) {
      if (runs[i].isEmpty) continue;
      final last = runs[i].last;
      canvas.drawCircle(Offset(dx(last.at), dy(last.value)), 2.6, Paint()..color = color);
      break;
    }
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.from != from || old.to != to || old.color != color || old.capColor != capColor || old.runs != runs;
}
