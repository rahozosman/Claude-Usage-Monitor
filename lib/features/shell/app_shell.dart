import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../settings/settings_controller.dart';
import 'edge_shell.dart';
import 'shell_controller.dart';

/// Root of the window. The window itself is docked to the right edge and only
/// as big as the current state needs; everything visual lives in [EdgeShell].
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = context.read<SettingsController>().settings;
      if (!settings.compactMode) context.read<ShellController>().showHome();
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Material(
      type: MaterialType.transparency,
      // Transparent room for the glass shadow. The right side stays flush so
      // the widget reads as attached to the screen edge.
      child: Padding(
        padding: EdgeInsets.only(
          left: AppConstants.shadowPad,
          top: AppConstants.shadowPad,
          bottom: AppConstants.shadowPad,
        ),
        child: EdgeShell(),
      ),
    );
  }
}
