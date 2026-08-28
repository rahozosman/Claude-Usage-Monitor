import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_dimens.dart';
import '../app/theme/app_motion.dart';
import 'app_button.dart';
import 'setting_row.dart';

/// Settings row for the shared devices folder: shows the folder in use,
/// lets the user type another one (empty = back to the OneDrive default)
/// and open it in Explorer.
class FolderEditor extends StatefulWidget {
  const FolderEditor({
    super.key,
    required this.current,
    required this.resolved,
    required this.motion,
    required this.onSave,
    this.onOpen,
  });

  /// The user's custom path (null = automatic).
  final String? current;

  /// The folder actually in use right now (null = none available).
  final String? resolved;
  final AppMotion motion;
  final Future<void> Function(String? path) onSave;
  final VoidCallback? onOpen;

  @override
  State<FolderEditor> createState() => _FolderEditorState();
}

class _FolderEditorState extends State<FolderEditor> {
  late final TextEditingController _controller = TextEditingController(text: widget.current ?? '');
  bool _busy = false;

  @override
  void didUpdateWidget(covariant FolderEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.current != widget.current && _controller.text != (widget.current ?? '')) {
      _controller.text = widget.current ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final text = _controller.text.trim();
      await widget.onSave(text.isEmpty ? null : text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SettingRow(
          title: 'Shared devices folder',
          subtitle: widget.resolved == null
              ? 'OneDrive was not found on this PC. Enter any folder that syncs between your devices.'
              : '${widget.resolved}${widget.current == null ? '  (OneDrive, automatic)' : ''}',
          trailing: widget.onOpen == null
              ? null
              : AppButton(label: 'Open', motion: widget.motion, onTap: widget.onOpen),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppDimens.s10, 0, AppDimens.s10, AppDimens.s10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: t.bodySmall?.copyWith(color: c.textPrimary),
                  decoration: const InputDecoration(hintText: 'Leave empty to use OneDrive automatically'),
                  onSubmitted: (_) => _save(),
                ),
              ),
              const SizedBox(width: AppDimens.s8),
              AppButton(
                label: 'Save',
                motion: widget.motion,
                style: AppButtonStyle.primary,
                loading: _busy,
                onTap: _save,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
