import 'dart:io';

import 'package:path/path.dart' as p;

import '../constants/app_constants.dart';

/// Resolves the on-disk locations the app reads from or writes to.
class AppPaths {
  AppPaths._();

  static String get home =>
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? Directory.current.path;

  /// Claude Code config dir. Honors CLAUDE_CONFIG_DIR like Claude Code does.
  static String get claudeConfigDir => Platform.environment['CLAUDE_CONFIG_DIR'] ?? p.join(home, '.claude');

  static String get claudeSettingsFile => p.join(claudeConfigDir, 'settings.json');
  static String get claudeCredentialsFile => p.join(claudeConfigDir, '.credentials.json');

  static String get localAppData => Platform.environment['LOCALAPPDATA'] ?? p.join(home, 'AppData', 'Local');

  /// Where this app keeps its own files, in the place each OS expects:
  /// `%LOCALAPPDATA%\ClaudeUsageMonitor` on Windows,
  /// `~/Library/Application Support/ClaudeUsageMonitor` on macOS.
  static String get appDataDir => Platform.isMacOS
      ? p.join(home, 'Library', 'Application Support', AppConstants.localFolderName)
      : p.join(localAppData, AppConstants.localFolderName);
  static String get statusLineFile => p.join(appDataDir, AppConstants.statusLineFileName);
  static String get statusLineLimitsFile => p.join(appDataDir, AppConstants.statusLineLimitsFileName);
  static String get bridgeDir => p.join(appDataDir, AppConstants.bridgeFolderName);
  static String get bridgeScript => p.join(bridgeDir, AppConstants.bridgeScriptName);
  static String get bridgeConfig => p.join(bridgeDir, AppConstants.bridgeConfigName);
  static String get bridgeForward => p.join(bridgeDir, AppConstants.bridgeForwardName);
  static String get launchHookScript => p.join(appDataDir, AppConstants.launchHookScriptName);
  /// This machine's stable sync identity (see DeviceSyncService).
  /// Appended record of every percentage Claude reported (see
  /// UsageHistoryService). One JSON object per line.
  static String get historyFile => p.join(appDataDir, 'history.jsonl');
  static String get deviceIdFile => p.join(appDataDir, 'device-id');
  static String get backupsDir => p.join(appDataDir, 'backups');
  static String get instanceLockFile => p.join(appDataDir, 'instance.lock');
  static String get wakeFile => p.join(appDataDir, 'wake');
  static String get quitFile => p.join(appDataDir, 'quit');

  /// Forward-slash form for use inside Claude Code's `statusLine.command`
  /// (Git Bash eats backslashes).
  static String forwardSlashes(String path) => path.replaceAll('\\', '/');

  static Future<Directory> ensureAppDataDir() => Directory(appDataDir).create(recursive: true);
}
