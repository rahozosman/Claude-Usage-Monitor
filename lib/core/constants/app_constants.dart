import 'dart:io';

/// Application-wide constants. No secrets live here.
class AppConstants {
  AppConstants._();

  static const String appName = 'Claude Usage Monitor';
  static const String appId = 'com.hoza.claude_usage_monitor';
  static const String developer = 'Rahoz Osman';
  static const String contactEmail = 'hozahoza2001@gmail.com';
  static const String projectUrl = 'https://github.com/rahozosman/Claude-Usage-Monitor';

  /// Shown along the bottom edge of the dashboard.
  static const String copyright = '© 2026 Rahoz Osman';

  // Anthropic API (official, documented).
  static const String anthropicApiBase = 'https://api.anthropic.com';
  static const String anthropicVersion = '2023-06-01';
  static String get userAgent =>
      Platform.isWindows ? 'ClaudeUsageMonitor/1.0 (Windows)' : 'ClaudeUsageMonitor/1.0 (macOS)';

  /// The "launch at login" toggle, in each platform's own words.
  static String get startupLabel => Platform.isWindows ? 'Start with Windows' : 'Open at login';

  /// Where secrets actually live, named the way the OS names it.
  static String get secureStoreName =>
      Platform.isWindows ? 'Windows-encrypted secure storage' : 'the macOS Keychain';

  // Claude Code OAuth usage endpoint (used by `/usage`; NOT publicly
  // documented). Only called when the user explicitly opts in.
  static const String oauthUsagePath = '/api/oauth/usage';
  static const String oauthBetaHeader = 'oauth-2025-04-20';

  // Local bridge files (under %LOCALAPPDATA%\ClaudeUsageMonitor).
  static const String localFolderName = 'ClaudeUsageMonitor';
  static const String statusLineFileName = 'statusline.json';
  /// The last payload that actually carried a `rate_limits` block, kept beside
  /// the live one. Every session writes to the same [statusLineFileName], and a
  /// session renders its status line before it has had an API response — with
  /// no limits in it — so without this copy one new session erases what another
  /// reported seconds ago.
  static const String statusLineLimitsFileName = 'statusline-limits.json';
  static const String bridgeFolderName = 'bridge';
  /// PowerShell on Windows, POSIX sh on macOS — Claude Code runs whatever
  /// `statusLine.command` says, so the script just has to suit the platform.
  static String get bridgeScriptName =>
      Platform.isWindows ? 'statusline-bridge.ps1' : 'statusline-bridge.sh';
  static const String bridgeConfigName = 'bridge-config.json';

  /// The previous status line, stored as plain text for the sh bridge to
  /// pipe into. Parsing JSON in sh is not worth the fragility.
  static const String bridgeForwardName = 'forward';
  static String get bridgeMarker => bridgeScriptName;

  /// The Claude Code CLI's process name. Watched so the monitor can close
  /// itself when the last session goes.
  static String get claudeProcessName => Platform.isWindows ? 'claude.exe' : 'claude';

  /// The file name of the Claude Code CLI on this platform.
  static String get claudeExecutableName => Platform.isWindows ? 'claude.exe' : 'claude';

  // Claude Code SessionStart hook that opens the monitor with every session.
  static String get launchHookScriptName =>
      Platform.isWindows ? 'launch-monitor.ps1' : 'launch-monitor.sh';
  static String get launchHookMarker => launchHookScriptName;

  // Freshness / throttling.
  static const Duration staleAfter = Duration(minutes: 10);
  static const Duration usageEndpointMinInterval = Duration(seconds: 60);
  static const Duration usageEndpointBackoff = Duration(minutes: 5);
  static const Duration apiProbeMinInterval = Duration(minutes: 1);
  static const Duration cliDetectCacheFor = Duration(minutes: 2);
  static const Duration httpTimeout = Duration(seconds: 20);

  // Edge-docked geometry (logical pixels). The window is right-aligned to the
  // work area and the content grows leftward from that edge.
  //
  //   STATE 1  tiny vertical glass tab, stuck to the right edge
  //   STATE 2  compact limits panel (5H / WEEK / API)
  //   STATE 3  the normal Home screen
  static const double edgeTabWidth = 20;
  static const double edgeTabHeight = 76;
  static const double limitsWidth = 296;
  static const double limitsHeight = 236;
  static const double homeWidth = 560;
  static const double homeHeight = 660;

  /// Transparent room kept inside the window (left, top, bottom) so the glass
  /// shadow has somewhere to fall. The right side stays flush with the screen.
  static const double shadowPad = 22;

  /// Corner radii per state — only the left corners are rounded, so the glass
  /// always reads as attached to the edge.
  static const double edgeTabRadius = 9;
  static const double limitsRadius = 14;
  static const double homeRadius = 16;

  static const String defaultProbeModel = 'claude-haiku-4-5';
  static const List<String> probeModels = <String>[
    'claude-haiku-4-5',
    'claude-sonnet-5',
    'claude-sonnet-4-6',
    'claude-opus-5',
    'claude-opus-4-8',
    'claude-fable-5',
  ];
}
