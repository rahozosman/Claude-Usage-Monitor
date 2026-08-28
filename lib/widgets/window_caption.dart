import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_dimens.dart';
import '../app/theme/app_motion.dart';
import 'claude_mark.dart';

enum CaptionGlyph { minimize, close }

/// A Windows-style caption button: flat, arrow cursor, subtle fill on hover,
/// red with a white glyph for Close — exactly like a normal Windows window.
class CaptionButton extends StatefulWidget {
  const CaptionButton({
    super.key,
    required this.glyph,
    required this.onTap,
    required this.motion,
    this.tooltip,
    this.width = 46,
    this.height = AppDimens.titleBarHeight,
  });

  final CaptionGlyph glyph;
  final VoidCallback onTap;
  final AppMotion motion;
  final String? tooltip;
  final double width;
  final double height;

  @override
  State<CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<CaptionButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isClose = widget.glyph == CaptionGlyph.close;
    final Color bg;
    if (!_hover) {
      bg = Colors.transparent;
    } else if (isClose) {
      bg = c.trafficRed.withValues(alpha: _down ? 0.82 : 1);
    } else {
      bg = _down ? c.fillStrong : c.fill;
    }
    final fg = _hover && isClose ? Colors.white : (_hover ? c.textPrimary : c.textSecondary);

    final button = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _down = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: widget.motion.micro,
          curve: widget.motion.transition,
          width: widget.width,
          height: widget.height,
          color: bg,
          child: Center(
            child: CustomPaint(size: const Size(10, 10), painter: _CaptionGlyphPainter(widget.glyph, fg)),
          ),
        ),
      ),
    );
    if (widget.tooltip == null) return button;
    return Tooltip(message: widget.tooltip!, waitDuration: const Duration(milliseconds: 600), child: button);
  }
}

class _CaptionGlyphPainter extends CustomPainter {
  const _CaptionGlyphPainter(this.glyph, this.color);

  final CaptionGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.square
      ..isAntiAlias = true;
    switch (glyph) {
      case CaptionGlyph.minimize:
        final y = (size.height / 2).floorToDouble() + 0.5;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      case CaptionGlyph.close:
        canvas.drawLine(Offset.zero, Offset(size.width, size.height), paint);
        canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CaptionGlyphPainter old) => old.glyph != glyph || old.color != color;
}

/// Windows-style title bar: draggable, app mark + title on the left, page
/// actions on the right followed by the ─ and × caption buttons.
class WindowCaptionBar extends StatelessWidget {
  const WindowCaptionBar({
    super.key,
    required this.title,
    required this.motion,
    required this.onDragStart,
    required this.onMinimize,
    required this.onClose,
    this.actions = const <Widget>[],
    this.onDoubleTap,
    this.minimizeTooltip = 'Minimize',
    this.closeTooltip = 'Close',
  });

  final String title;
  final AppMotion motion;
  final VoidCallback onDragStart;
  final VoidCallback onMinimize;
  final VoidCallback onClose;
  final List<Widget> actions;
  final VoidCallback? onDoubleTap;
  final String minimizeTooltip;
  final String closeTooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => onDragStart(),
      onDoubleTap: onDoubleTap,
      child: SizedBox(
        height: AppDimens.titleBarHeight,
        child: Row(
          children: <Widget>[
            const SizedBox(width: AppDimens.s12),
            ClaudeMark(color: c.mark, size: 13),
            const SizedBox(width: AppDimens.s8),
            Expanded(
              child: Text(
                title,
                style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ...actions,
            const SizedBox(width: AppDimens.s6),
            CaptionButton(glyph: CaptionGlyph.minimize, onTap: onMinimize, motion: motion, tooltip: minimizeTooltip),
            CaptionButton(glyph: CaptionGlyph.close, onTap: onClose, motion: motion, tooltip: closeTooltip),
          ],
        ),
      ),
    );
  }
}
