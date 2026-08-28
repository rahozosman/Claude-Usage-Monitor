import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../features/settings/settings_controller.dart';
import '../features/shell/app_shell.dart';
import 'theme/app_theme.dart';

class ClaudeUsageMonitorApp extends StatelessWidget {
  const ClaudeUsageMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.select<SettingsController, ThemeMode>((s) => s.settings.themeMode);
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      color: Colors.transparent,
      home: const AppShell(),
    );
  }
}
