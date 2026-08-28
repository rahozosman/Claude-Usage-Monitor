import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_dimens.dart';
import '../app/theme/app_motion.dart';

/// macOS switch: 38×22 pill, green when on, white knob with a soft shadow.
class MacSwitch extends StatelessWidget {
  const MacSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.motion,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final AppMotion motion;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final on = value;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged(!value) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: AnimatedContainer(
            duration: motion.component,
            curve: motion.transition,
            width: 38,
            height: 22,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: on ? c.mark : c.fillStrong, // Claude terracotta when on, not green
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: on ? Colors.transparent : c.borderStrong, width: 0.5),
            ),
            child: AnimatedAlign(
              duration: motion.component,
              curve: motion.transition,
              alignment: on ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: <BoxShadow>[
                    BoxShadow(color: c.shadow.withValues(alpha: 0.28), blurRadius: 3, offset: const Offset(0, 1)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// macOS pop-up button (dropdown) with a check mark on the selected item.
class MacPopupButton<T> extends StatefulWidget {
  const MacPopupButton({
    super.key,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
    required this.motion,
    this.minWidth = 96,
  });

  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T?> onChanged;
  final AppMotion motion;
  final double minWidth;

  @override
  State<MacPopupButton<T>> createState() => _MacPopupButtonState<T>();
}

class _MacPopupButtonState<T> extends State<MacPopupButton<T>> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return PopupMenuButton<T>(
      tooltip: '',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 4),
      constraints: BoxConstraints(minWidth: widget.minWidth + 24),
      onSelected: widget.onChanged,
      itemBuilder: (context) => <PopupMenuEntry<T>>[
        for (final item in widget.items)
          PopupMenuItem<T>(
            value: item,
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 16,
                  child: item == widget.value
                      ? Icon(Icons.check_rounded, size: 13, color: c.textPrimary)
                      : null,
                ),
                const SizedBox(width: 2),
                Text(widget.labelOf(item), style: t.bodySmall?.copyWith(color: c.textPrimary, fontSize: 12.5)),
              ],
            ),
          ),
      ],
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: widget.motion.micro,
          height: AppDimens.controlHeight,
          constraints: BoxConstraints(minWidth: widget.minWidth),
          padding: const EdgeInsets.only(left: 9, right: 4),
          decoration: BoxDecoration(
            color: dark ? (_hover ? c.fillStrong : c.fill) : (_hover ? const Color(0xFFF7F7F7) : Colors.white),
            borderRadius: BorderRadius.circular(AppDimens.radiusSm),
            border: Border.all(color: c.borderStrong, width: 0.5),
            boxShadow: <BoxShadow>[
              BoxShadow(color: c.shadow.withValues(alpha: dark ? 0.25 : 0.08), blurRadius: 1.5, offset: const Offset(0, 0.5)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(widget.labelOf(widget.value), style: t.bodySmall?.copyWith(color: c.textPrimary, fontSize: 12.5)),
              const SizedBox(width: 6),
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(4)),
                child: const Icon(Icons.unfold_more_rounded, size: 12, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// macOS segmented control with a sliding selection.
class MacSegmentedControl<T> extends StatelessWidget {
  const MacSegmentedControl({
    super.key,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
    required this.motion,
    this.segmentWidth = 64,
  });

  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;
  final AppMotion motion;
  final double segmentWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final index = items.indexOf(value).clamp(0, items.length - 1);
    return Container(
      height: AppDimens.controlHeight,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: c.fill,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: c.border, width: 0.5),
      ),
      child: SizedBox(
        width: segmentWidth * items.length,
        child: Stack(
          children: <Widget>[
            AnimatedPositioned(
              duration: motion.component,
              curve: motion.transition,
              left: index * segmentWidth,
              top: 0,
              bottom: 0,
              width: segmentWidth,
              child: Container(
                decoration: BoxDecoration(
                  color: dark ? const Color(0xFF636366) : Colors.white,
                  borderRadius: BorderRadius.circular(5),
                  boxShadow: <BoxShadow>[
                    BoxShadow(color: c.shadow.withValues(alpha: 0.18), blurRadius: 2, offset: const Offset(0, 1)),
                  ],
                ),
              ),
            ),
            Row(
              children: <Widget>[
                for (final item in items)
                  SizedBox(
                    width: segmentWidth,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(item),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: motion.micro,
                            style: t.bodySmall!.copyWith(
                              fontSize: 12,
                              color: item == value ? c.textPrimary : c.textSecondary,
                              fontWeight: item == value ? FontWeight.w600 : FontWeight.w500,
                            ),
                            child: Text(labelOf(item)),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A rounded macOS-style toolbar/glyph button with hover capsule.
class MacGlyphButton extends StatefulWidget {
  const MacGlyphButton({
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
  State<MacGlyphButton> createState() => _MacGlyphButtonState();
}

class _MacGlyphButtonState extends State<MacGlyphButton> with SingleTickerProviderStateMixin {
  bool _hover = false;
  bool _down = false;
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    _syncSpin();
  }

  @override
  void didUpdateWidget(covariant MacGlyphButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSpin();
  }

  void _syncSpin() {
    if (widget.spinning && widget.motion.enabled) {
      if (!_spin.isAnimating) _spin.repeat();
    } else if (_spin.isAnimating) {
      _spin.animateTo(1, duration: const Duration(milliseconds: 300), curve: Curves.easeOut).then((_) {
        if (mounted && !widget.spinning) _spin.value = 0;
      });
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = widget.onTap != null;
    final iconColor = !enabled
        ? c.textTertiary
        : widget.danger && _hover
            ? c.statusCritical
            : (_hover ? c.textPrimary : c.textSecondary);
    final child = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _down = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.9 : 1,
          duration: widget.motion.micro,
          curve: widget.motion.enter,
          child: AnimatedContainer(
            duration: widget.motion.micro,
            curve: widget.motion.transition,
            width: 26,
            height: 24,
            decoration: BoxDecoration(
              color: _hover && enabled ? (_down ? c.fillStrong : c.fill) : Colors.transparent,
              borderRadius: BorderRadius.circular(AppDimens.radiusSm),
            ),
            child: Center(
              child: RotationTransition(
                turns: _spin,
                child: Icon(widget.icon, size: widget.size, color: iconColor),
              ),
            ),
          ),
        ),
      ),
    );
    if (widget.tooltip == null) return child;
    return Tooltip(message: widget.tooltip!, child: child);
  }
}
