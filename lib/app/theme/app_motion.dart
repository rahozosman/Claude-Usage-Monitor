import 'package:flutter/animation.dart';

/// Central motion tokens with macOS-style easing: quick to start, long soft
/// settle, never linear. When animations are disabled every duration is zero.
class AppMotion {
  const AppMotion({required this.enabled});

  final bool enabled;

  static const AppMotion on = AppMotion(enabled: true);
  static const AppMotion off = AppMotion(enabled: false);

  Duration _d(int ms) => enabled ? Duration(milliseconds: ms) : Duration.zero;

  /// Hover tint, press, glyph swap.
  Duration get micro => _d(160);

  /// Panel/page swap, switch toggle, popover.
  Duration get component => _d(320);

  /// Bars and numbers settling to a new value.
  Duration get value => _d(560);

  /// Dashboard entrance, large reveals.
  Duration get large => _d(640);

  /// Breathing status glow.
  Duration get ambient => _d(2600);

  /// macOS "ease out" — fast start, long gentle landing.
  Curve get enter => const Cubic(0.22, 1, 0.36, 1);

  /// Exit — accelerate away.
  Curve get exit => const Cubic(0.4, 0, 1, 1);

  /// Symmetric ease for state changes (switches, segmented controls).
  Curve get transition => const Cubic(0.45, 0, 0.15, 1);

  /// Values settling (progress bars, counters).
  Curve get settle => const Cubic(0.16, 1, 0.3, 1);

  /// A touch of overshoot for pops (window reveal).
  Curve get spring => const Cubic(0.34, 1.28, 0.64, 1);
}
