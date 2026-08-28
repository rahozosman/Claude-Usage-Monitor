import 'package:flutter/material.dart';

/// The GitHub mark, drawn from the official logo outline.
///
/// Painted rather than shipped as an asset or pulled from an icon-font package:
/// one glyph is not worth a dependency, and a path scales cleanly at the small
/// sizes this app uses. Coordinates are the 16×16 logo normalised to 0–1.
class GitHubMark extends StatelessWidget {
  const GitHubMark({super.key, required this.color, this.size = 14});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.square(size), painter: _GitHubPainter(color));
  }
}

class _GitHubPainter extends CustomPainter {
  _GitHubPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final path = Path()
      ..moveTo(0.5 * s, 0 * s)
      ..cubicTo(0.2238 * s, 0 * s, 0 * s, 0.2238 * s, 0 * s, 0.5 * s)
      ..cubicTo(0 * s, 0.7212 * s, 0.1431 * s, 0.9081 * s, 0.3419 * s, 0.9744 * s)
      ..cubicTo(0.3669 * s, 0.9788 * s, 0.3762 * s, 0.9637 * s, 0.3762 * s, 0.9506 * s)
      ..cubicTo(0.3762 * s, 0.9387 * s, 0.3756 * s, 0.8994 * s, 0.3756 * s, 0.8575 * s)
      ..cubicTo(0.25 * s, 0.8806 * s, 0.2175 * s, 0.8269 * s, 0.2075 * s, 0.7987 * s)
      ..cubicTo(0.2019 * s, 0.7844 * s, 0.1775 * s, 0.74 * s, 0.1562 * s, 0.7281 * s)
      ..cubicTo(0.1387 * s, 0.7187 * s, 0.1137 * s, 0.6956 * s, 0.1556 * s, 0.695 * s)
      ..cubicTo(0.195 * s, 0.6944 * s, 0.2231 * s, 0.7312 * s, 0.2325 * s, 0.7462 * s)
      ..cubicTo(0.2775 * s, 0.8219 * s, 0.3494 * s, 0.8006 * s, 0.3781 * s, 0.7875 * s)
      ..cubicTo(0.3825 * s, 0.755 * s, 0.3956 * s, 0.7331 * s, 0.41 * s, 0.7206 * s)
      ..cubicTo(0.2988 * s, 0.7081 * s, 0.1825 * s, 0.665 * s, 0.1825 * s, 0.4737 * s)
      ..cubicTo(0.1825 * s, 0.4194 * s, 0.2019 * s, 0.3744 * s, 0.2338 * s, 0.3394 * s)
      ..cubicTo(0.2288 * s, 0.3269 * s, 0.2113 * s, 0.2756 * s, 0.2388 * s, 0.2069 * s)
      ..cubicTo(0.2388 * s, 0.2069 * s, 0.2806 * s, 0.1937 * s, 0.3763 * s, 0.2581 * s)
      ..cubicTo(0.4163 * s, 0.2469 * s, 0.4588 * s, 0.2412 * s, 0.5012 * s, 0.2412 * s)
      ..cubicTo(0.5437 * s, 0.2412 * s, 0.5862 * s, 0.2469 * s, 0.6262 * s, 0.2582 * s)
      ..cubicTo(0.6594 * s, 0.1932 * s, 0.7637 * s, 0.2069 * s, 0.7637 * s, 0.2069 * s)
      ..cubicTo(0.7912 * s, 0.2757 * s, 0.7737 * s, 0.3269 * s, 0.7687 * s, 0.3394 * s)
      ..cubicTo(0.8006 * s, 0.3744 * s, 0.82 * s, 0.4188 * s, 0.82 * s, 0.4738 * s)
      ..cubicTo(0.82 * s, 0.6657 * s, 0.7031 * s, 0.7082 * s, 0.5919 * s, 0.7207 * s)
      ..cubicTo(0.61 * s, 0.7363 * s, 0.6256 * s, 0.7663 * s, 0.6256 * s, 0.8132 * s)
      ..cubicTo(0.6256 * s, 0.8801 * s, 0.625 * s, 0.9338 * s, 0.625 * s, 0.9507 * s)
      ..cubicTo(0.625 * s, 0.9638 * s, 0.6344 * s, 0.9794 * s, 0.6594 * s, 0.9744 * s)
      ..cubicTo(0.8629 * s, 0.9057 * s, 1 * s, 0.7148 * s, 1 * s, 0.5 * s)
      ..cubicTo(1 * s, 0.2238 * s, 0.7762 * s, 0 * s, 0.5 * s, 0 * s)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _GitHubPainter old) => old.color != color;
}
