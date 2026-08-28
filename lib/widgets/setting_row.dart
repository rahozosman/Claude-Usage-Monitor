import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_dimens.dart';
import '../app/theme/app_motion.dart';
import 'mac_controls.dart';

/// One System-Settings-style row: title, optional subtitle, trailing control.
class SettingRow extends StatefulWidget {
  const SettingRow({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  State<SettingRow> createState() => _SettingRowState();
}

class _SettingRowState extends State<SettingRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.s8, horizontal: AppDimens.s12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  widget.title,
                  style: t.bodyMedium?.copyWith(color: widget.enabled ? c.textPrimary : c.textTertiary),
                ),
                if (widget.subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 1.5),
                    child: Text(widget.subtitle!, style: t.bodySmall?.copyWith(color: c.textTertiary, fontSize: 11)),
                  ),
              ],
            ),
          ),
          if (widget.trailing != null) ...<Widget>[const SizedBox(width: AppDimens.s12), widget.trailing!],
        ],
      ),
    );
    if (widget.onTap == null) return row;
    return MouseRegion(
      cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? widget.onTap : null,
        child: ColoredBox(color: _hover && widget.enabled ? c.fill : Colors.transparent, child: row),
      ),
    );
  }
}

/// Compact pop-up button used inside [SettingRow.trailing] (macOS style).
class SettingDropdown<T> extends StatelessWidget {
  const SettingDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
    this.motion = AppMotion.on,
  });

  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T?> onChanged;
  final AppMotion motion;

  @override
  Widget build(BuildContext context) {
    return MacPopupButton<T>(
      value: value,
      items: items,
      labelOf: labelOf,
      onChanged: onChanged,
      motion: motion,
    );
  }
}
