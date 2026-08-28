import 'package:flutter/material.dart';

import '../app/theme/app_motion.dart';

/// Tweens between numeric values and renders them with tabular figures so
/// the text never jitters horizontally. Null renders as an em dash.
class AnimatedNumber extends StatelessWidget {
  const AnimatedNumber({
    super.key,
    required this.value,
    required this.motion,
    this.style,
    this.suffix = '%',
    this.decimals = 0,
  });

  final double? value;
  final AppMotion motion;
  final TextStyle? style;
  final String suffix;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    final base = (style ?? DefaultTextStyle.of(context).style).copyWith(
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
    if (value == null) return Text('—', style: base);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value),
      duration: motion.value,
      curve: motion.settle,
      builder: (context, v, _) => Text('${v.toStringAsFixed(decimals)}$suffix', style: base),
    );
  }
}
