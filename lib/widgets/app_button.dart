import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_dimens.dart';
import '../app/theme/app_motion.dart';

enum AppButtonStyle { primary, secondary, danger }

/// macOS push button: 22 pt, 6 pt radius, hairline border, subtle gradient;
/// primary is the blue "default" button.
class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.motion,
    this.style = AppButtonStyle.secondary,
    this.loading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onTap;
  final AppMotion motion;
  final AppButtonStyle style;
  final bool loading;
  final IconData? icon;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final enabled = widget.onTap != null && !widget.loading;

    List<Color> gradient;
    Color fg;
    Color border;
    switch (widget.style) {
      case AppButtonStyle.primary:
        final top = Color.lerp(c.accent, Colors.white, _down ? 0 : 0.12)!;
        final bottom = Color.lerp(c.accent, Colors.black, _down ? 0.2 : 0.06)!;
        gradient = enabled ? <Color>[top, bottom] : <Color>[c.accent.withValues(alpha: 0.45), c.accent.withValues(alpha: 0.45)];
        fg = Colors.white;
        border = Color.lerp(c.accent, Colors.black, 0.25)!.withValues(alpha: 0.6);
      case AppButtonStyle.danger:
        gradient = <Color>[
          _hover && enabled ? c.statusCritical.withValues(alpha: 0.16) : c.fill,
          _hover && enabled ? c.statusCritical.withValues(alpha: 0.10) : c.fill.withValues(alpha: 0.6),
        ];
        fg = enabled ? c.statusCritical : c.textTertiary;
        border = c.borderStrong;
      case AppButtonStyle.secondary:
        if (dark) {
          gradient = <Color>[
            _down ? c.fill : (_hover ? c.fillStrong : c.fillStrong.withValues(alpha: 0.9)),
            _down ? c.fill : c.fill,
          ];
        } else {
          gradient = <Color>[
            _down ? const Color(0xFFEDEDED) : Colors.white,
            _down ? const Color(0xFFE6E6E6) : const Color(0xFFF7F7F7),
          ];
        }
        fg = enabled ? c.textPrimary : c.textTertiary;
        border = c.borderStrong;
    }

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _down = false;
      }),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: widget.motion.micro,
          curve: widget.motion.transition,
          height: AppDimens.controlHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppDimens.s12),
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: gradient),
            borderRadius: BorderRadius.circular(AppDimens.radiusSm),
            border: Border.all(color: border, width: 0.5),
            boxShadow: <BoxShadow>[
              BoxShadow(color: c.shadow.withValues(alpha: dark ? 0.3 : 0.08), blurRadius: 1.5, offset: const Offset(0, 0.5)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (widget.loading)
                SizedBox(width: 11, height: 11, child: CircularProgressIndicator(strokeWidth: 1.5, color: fg))
              else if (widget.icon != null)
                Icon(widget.icon, size: AppDimens.iconSm, color: fg),
              if (widget.loading || widget.icon != null) const SizedBox(width: AppDimens.s6),
              Text(
                widget.label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: fg, fontSize: 12.5, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
