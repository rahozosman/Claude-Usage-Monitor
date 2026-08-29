import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/app.dart';
import 'features/dashboard/usage_controller.dart';
import 'features/settings/settings_controller.dart';
import 'features/shell/shell_controller.dart';
import 'repositories/usage_repository.dart';
import 'services/anthropic_api_service.dart';
import 'services/claude_cli_service.dart';
import 'services/claude_session_watcher.dart';
import 'services/instance_service.dart';
import 'services/local_usage_service.dart';
import 'services/notification_service.dart';
import 'services/oauth_usage_service.dart';
import 'services/refresh_service.dart';
import 'services/settings_service.dart';
import 'services/startup_service.dart';
import 'services/statusline_bridge_service.dart';
import 'services/tray_service.dart';
import 'services/window_service.dart';

Future<void> main(List<String> args) async {
  // Never let an unexpected error take the whole utility down.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('Flutter error: ${details.exceptionAsString()}');
  };

  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // One copy only: a second launch wakes the running one and leaves.
      final instance = InstanceService();
      if (!await instance.acquire()) {
        await instance.wakeOther();
        exit(0);
      }

      final settingsService = SettingsService();
      await settingsService.init();

      final startup = StartupService();
      await startup.init();

      final settingsController = SettingsController(settingsService, startup);
      await settingsController.init();
      final settings = settingsController.settings;
      final startHidden = settings.launchMinimized;

      // "Open with Claude Code": keep the SessionStart hook (and its launcher
      // script, which embeds this exe path) in place while the setting is on.
      final bridge = StatusLineBridgeService();
      if (settings.launchWithClaude) unawaited(bridge.ensureLaunchHook());

      final cli = ClaudeCliService();
      final oauth = OAuthUsageService();
      final api = AnthropicApiService();
      final repository = UsageRepository(
        cli: cli,
        oauth: oauth,
        api: api,
        settingsService: settingsService,
        local: LocalUsageService(),
      );

      final notifications = NotificationService(settingsService);
      await notifications.init();

      final usage = UsageController(
        repository: repository,
        settings: settingsController,
        notifications: notifications,
        refreshService: RefreshService(),
      );

      late final ShellController shell;
      final window = WindowService(
        onCloseRequested: () => unawaited(shell.quit()),
        onAnchorChanged: (y) => unawaited(settingsController.update((s) => s.copyWith(anchorCenterY: y))),
        onFocusLost: () => shell.handleFocusLost(),
      );
      await window.init(
        alwaysOnTop: settings.alwaysOnTop,
        anchorCenterY: settings.anchorCenterY,
        startHidden: startHidden,
      );

      shell = ShellController(window: window, settings: settingsController, usage: usage);
      instance.watchMarkers(
        onWake: () => unawaited(shell.show()),
        onQuit: () => unawaited(shell.quit()),
      );
      if (startHidden) {
        await shell.hide();
      } else {
        usage.setTicking(true);
      }

      // Close when the last Claude Code session does, mirroring the
      // SessionStart hook that opened it. Quits the same way the tray's Quit
      // does, so the tray icon is removed rather than stranded.
      final sessions = ClaudeSessionWatcher(
        enabled: settings.quitWithClaude,
        onAllSessionsClosed: () => unawaited(shell.quit()),
      );
      settingsController.addListener(() => sessions.enabled = settingsController.settings.quitWithClaude);
      sessions.start();

      final tray = TrayService(
        onShow: () => unawaited(shell.show()),
        onHide: () => unawaited(shell.hide()),
        onToggle: () => unawaited(shell.toggleVisible()),
        onRefresh: () => unawaited(usage.refresh(probeApi: true, force: true)),
        onSettings: () => unawaited(shell.openSettings()),
        onToggleStartup: () => unawaited(settingsController.setStartWithWindows(!settingsController.startWithWindows)),
        onQuit: () => unawaited(shell.quit()),
      );
      await tray.init();
      shell.attachTray(tray);

      usage.start();

      runApp(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsController>.value(value: settingsController),
            ChangeNotifierProvider<UsageController>.value(value: usage),
            ChangeNotifierProvider<ShellController>.value(value: shell),
            Provider<StatusLineBridgeService>.value(value: bridge),
            Provider<NotificationService>.value(value: notifications),
          ],
          child: const ClaudeUsageMonitorApp(),
        ),
      );
    },
    (error, stack) {
      debugPrint('Uncaught: $error\n$stack');
    },
  );
}
