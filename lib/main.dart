import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/app.dart';
import 'core/services/app_paths.dart';
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

      // First launch: put the status-line bridge in place instead of making the
      // user find the button for it — without it the app has no subscription
      // numbers to show. Attempted once only; both writes to settings.json are
      // queued inside the service so they cannot clobber each other.
      if (!settings.bridgeAutoInstallDone) {
        unawaited(_installBridgeOnFirstRun(bridge, settingsController));
      }

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

/// Installs the status-line bridge the first time the app is opened.
///
/// The bridge is what feeds the official `rate_limits` block into the monitor,
/// so a fresh install has nothing to show until it is in place. It preserves
/// any status line the user already had (forwarding to it) and backs up
/// `settings.json` first, so this is safe to do unprompted.
///
/// The flag is only set once the install succeeds: if Claude Code is not on
/// this machine yet, or its settings file is temporarily unreadable, the next
/// launch tries again rather than giving up for good.
Future<void> _installBridgeOnFirstRun(StatusLineBridgeService bridge, SettingsController settings) async {
  try {
    // Nothing to attach to if Claude Code has never run here — don't create a
    // stray ~/.claude for an app that isn't installed.
    if (!await Directory(AppPaths.claudeConfigDir).exists()) return;
    await bridge.install();
    await settings.update((s) => s.copyWith(bridgeAutoInstallDone: true));
  } catch (e) {
    debugPrint('First-run bridge install failed: ${e.runtimeType}');
  }
}
