import 'package:flutter/material.dart';

import '../app/theme/app_dimens.dart';
import '../app/theme/app_motion.dart';
import 'mac_controls.dart';

/// Small glyph button (macOS toolbar style). Kept as a thin alias so existing
/// call sites keep working; the look lives in [MacGlyphButton].
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.motion,
    this.tooltip,
    this.size = AppDimens.iconMd,
    this.spinning = false,
    this.danger = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final AppMotion motion;
  final String? tooltip;
  final double size;
  final bool spinning;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return MacGlyphButton(
      icon: icon,
      onTap: onTap,
      motion: motion,
      tooltip: tooltip,
      size: size,
      spinning: spinning,
      danger: danger,
    );
  }
}
