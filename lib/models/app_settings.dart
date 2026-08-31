import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';

enum RefreshInterval {
  s10(Duration(seconds: 10), '10 seconds'),
  s30(Duration(seconds: 30), '30 seconds'),
  m1(Duration(minutes: 1), '1 minute'),
  m5(Duration(minutes: 5), '5 minutes'),
  manual(null, 'Manual');

  const RefreshInterval(this.duration, this.label);
  final Duration? duration;
  final String label;
}

enum ApiProbeInterval {
  m1(Duration(minutes: 1), '1 minute'),
  m5(Duration(minutes: 5), '5 minutes'),
  m15(Duration(minutes: 15), '15 minutes'),
  m30(Duration(minutes: 30), '30 minutes'),
  manual(null, 'Manual only');

  const ApiProbeInterval(this.duration, this.label);
  final Duration? duration;
  final String label;
}

/// Persisted user preferences (no secrets — those live in secure storage).
@immutable
class AppSettings {
  const AppSettings({
    this.launchMinimized = false,
    this.alwaysOnTop = true,
    this.compactMode = true,
    this.collapseOnClickOutside = true,
    this.refreshInterval = RefreshInterval.s30,
    this.apiProbeInterval = ApiProbeInterval.m5,
    this.themeMode = ThemeMode.system,
    this.transparency = 0.96,
    this.animationsEnabled = true,
    this.showFiveHour = true,
    this.showApi = true,
    this.showWeekly = true,
    this.showPace = true,
    this.showActivity = true,
    this.showStats = true,
    this.showPercentages = true,
    this.showCountdown = true,
    this.notificationsEnabled = true,
    this.notifyAt80 = true,
    this.notifyAt90 = true,
    this.notifyAt100 = true,
    this.notifyOnReset = true,
    this.useUsageEndpoint = false,
    this.apiProbeModel = AppConstants.defaultProbeModel,
    this.anchorCenterY,
    this.onboardingSeen = false,
    this.bridgeAutoInstallDone = false,
    this.launchWithClaude = true,
    this.quitWithClaude = true,
    this.deviceSyncEnabled = true,
    this.deviceSyncFolder,
  });

  final bool launchMinimized;
  final bool alwaysOnTop;
  final bool compactMode;

  /// Shrink back to the small tab when the user clicks anywhere outside the
  /// app. Clicks inside it never collapse it.
  final bool collapseOnClickOutside;
  final RefreshInterval refreshInterval;
  final ApiProbeInterval apiProbeInterval;
  final ThemeMode themeMode;

  /// 0.7 – 1.0 surface opacity.
  final double transparency;
  final bool animationsEnabled;
  final bool showFiveHour;
  final bool showApi;
  final bool showWeekly;

  /// The pace card: rate, projection and the 7-day peaks.
  final bool showPace;

  /// Show what consumed usage (local Claude Code sessions on this PC).
  final bool showActivity;

  /// Show how the account is used over time, from Claude Code's own stats
  /// cache (the numbers behind its `/usage` Overview tab).
  final bool showStats;
  final bool showPercentages;
  final bool showCountdown;
  final bool notificationsEnabled;
  final bool notifyAt80;
  final bool notifyAt90;
  final bool notifyAt100;
  final bool notifyOnReset;

  /// Opt-in: query the undocumented usage endpoint with the Claude Code token.
  final bool useUsageEndpoint;
  final String apiProbeModel;

  /// Vertical centre of the edge widget, remembered across states.
  final double? anchorCenterY;
  final bool onboardingSeen;

  /// The status-line bridge has been installed from the Home screen prompt.
  /// Set once the first launch has installed the bridge, so the automatic
  /// install runs exactly once (an uninstall from Settings stays uninstalled)
  /// and the offer next to the Claude Code status never comes back.
  final bool bridgeAutoInstallDone;

  /// Open the monitor (as the small pill) whenever a Claude Code session starts.
  final bool launchWithClaude;

  /// Close the monitor once the last Claude Code session has gone, so its
  /// lifetime matches the CLI's.
  final bool quitWithClaude;

  /// Publish this PC's Claude Code activity to a synced folder and read the
  /// other devices' files back ("Other devices" card).
  final bool deviceSyncEnabled;

  /// Custom shared folder; null = `<OneDrive>ClaudeUsageMonitordevices`.
  final String? deviceSyncFolder;

  AppSettings copyWith({
    bool? launchMinimized,
    bool? alwaysOnTop,
    bool? compactMode,
    bool? collapseOnClickOutside,
    RefreshInterval? refreshInterval,
    ApiProbeInterval? apiProbeInterval,
    ThemeMode? themeMode,
    double? transparency,
    bool? animationsEnabled,
    bool? showFiveHour,
    bool? showApi,
    bool? showWeekly,
    bool? showPace,
    bool? showActivity,
    bool? showStats,
    bool? showPercentages,
    bool? showCountdown,
    bool? notificationsEnabled,
    bool? notifyAt80,
    bool? notifyAt90,
    bool? notifyAt100,
    bool? notifyOnReset,
    bool? useUsageEndpoint,
    String? apiProbeModel,
    double? anchorCenterY,
    bool? onboardingSeen,
    bool? bridgeAutoInstallDone,
    bool? launchWithClaude,
    bool? quitWithClaude,
    bool? deviceSyncEnabled,
    String? deviceSyncFolder,
    bool clearDeviceSyncFolder = false,
  }) {
    return AppSettings(
      launchMinimized: launchMinimized ?? this.launchMinimized,
      alwaysOnTop: alwaysOnTop ?? this.alwaysOnTop,
      compactMode: compactMode ?? this.compactMode,
      collapseOnClickOutside: collapseOnClickOutside ?? this.collapseOnClickOutside,
      refreshInterval: refreshInterval ?? this.refreshInterval,
      apiProbeInterval: apiProbeInterval ?? this.apiProbeInterval,
      themeMode: themeMode ?? this.themeMode,
      transparency: transparency ?? this.transparency,
      animationsEnabled: animationsEnabled ?? this.animationsEnabled,
      showFiveHour: showFiveHour ?? this.showFiveHour,
      showApi: showApi ?? this.showApi,
      showWeekly: showWeekly ?? this.showWeekly,
      showPace: showPace ?? this.showPace,
      showActivity: showActivity ?? this.showActivity,
      showStats: showStats ?? this.showStats,
      showPercentages: showPercentages ?? this.showPercentages,
      showCountdown: showCountdown ?? this.showCountdown,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      notifyAt80: notifyAt80 ?? this.notifyAt80,
      notifyAt90: notifyAt90 ?? this.notifyAt90,
      notifyAt100: notifyAt100 ?? this.notifyAt100,
      notifyOnReset: notifyOnReset ?? this.notifyOnReset,
      useUsageEndpoint: useUsageEndpoint ?? this.useUsageEndpoint,
      apiProbeModel: apiProbeModel ?? this.apiProbeModel,
      anchorCenterY: anchorCenterY ?? this.anchorCenterY,
      onboardingSeen: onboardingSeen ?? this.onboardingSeen,
      bridgeAutoInstallDone: bridgeAutoInstallDone ?? this.bridgeAutoInstallDone,
      launchWithClaude: launchWithClaude ?? this.launchWithClaude,
      quitWithClaude: quitWithClaude ?? this.quitWithClaude,
      deviceSyncEnabled: deviceSyncEnabled ?? this.deviceSyncEnabled,
      deviceSyncFolder: clearDeviceSyncFolder ? null : (deviceSyncFolder ?? this.deviceSyncFolder),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'launchMinimized': launchMinimized,
    'alwaysOnTop': alwaysOnTop,
    'compactMode': compactMode,
    'collapseOnClickOutside': collapseOnClickOutside,
    'refreshInterval': refreshInterval.name,
    'apiProbeInterval': apiProbeInterval.name,
    'themeMode': themeMode.name,
    'transparency': transparency,
    'animationsEnabled': animationsEnabled,
    'showFiveHour': showFiveHour,
    'showApi': showApi,
    'showWeekly': showWeekly,
    'showPace': showPace,
    'showActivity': showActivity,
    'showStats': showStats,
    'showPercentages': showPercentages,
    'showCountdown': showCountdown,
    'notificationsEnabled': notificationsEnabled,
    'notifyAt80': notifyAt80,
    'notifyAt90': notifyAt90,
    'notifyAt100': notifyAt100,
    'notifyOnReset': notifyOnReset,
    'useUsageEndpoint': useUsageEndpoint,
    'apiProbeModel': apiProbeModel,
    'anchorCenterY': anchorCenterY,
    'onboardingSeen': onboardingSeen,
    'bridgeAutoInstallDone': bridgeAutoInstallDone,
    'launchWithClaude': launchWithClaude,
    'quitWithClaude': quitWithClaude,
    'deviceSyncEnabled': deviceSyncEnabled,
    'deviceSyncFolder': deviceSyncFolder,
  };

  static AppSettings fromJson(Map<String, dynamic> json) {
    const d = AppSettings();
    bool b(String k, bool fallback) => json[k] is bool ? json[k] as bool : fallback;
    T e<T extends Enum>(String k, List<T> values, T fallback) {
      final v = json[k];
      if (v is! String) return fallback;
      for (final x in values) {
        if (x.name == v) return x;
      }
      return fallback;
    }

    final t = json['transparency'];
    final ax = json['anchorCenterY'];
    return AppSettings(
      launchMinimized: b('launchMinimized', d.launchMinimized),
      alwaysOnTop: b('alwaysOnTop', d.alwaysOnTop),
      compactMode: b('compactMode', d.compactMode),
      collapseOnClickOutside: b('collapseOnClickOutside', d.collapseOnClickOutside),
      refreshInterval: e('refreshInterval', RefreshInterval.values, d.refreshInterval),
      apiProbeInterval: e('apiProbeInterval', ApiProbeInterval.values, d.apiProbeInterval),
      themeMode: e('themeMode', ThemeMode.values, d.themeMode),
      transparency: t is num ? t.toDouble().clamp(0.7, 1.0).toDouble() : d.transparency,
      animationsEnabled: b('animationsEnabled', d.animationsEnabled),
      showFiveHour: b('showFiveHour', d.showFiveHour),
      showApi: b('showApi', d.showApi),
      showWeekly: b('showWeekly', d.showWeekly),
      showPace: b('showPace', d.showPace),
      showActivity: b('showActivity', d.showActivity),
      showStats: b('showStats', d.showStats),
      showPercentages: b('showPercentages', d.showPercentages),
      showCountdown: b('showCountdown', d.showCountdown),
      notificationsEnabled: b('notificationsEnabled', d.notificationsEnabled),
      notifyAt80: b('notifyAt80', d.notifyAt80),
      notifyAt90: b('notifyAt90', d.notifyAt90),
      notifyAt100: b('notifyAt100', d.notifyAt100),
      notifyOnReset: b('notifyOnReset', d.notifyOnReset),
      useUsageEndpoint: b('useUsageEndpoint', d.useUsageEndpoint),
      apiProbeModel: json['apiProbeModel'] is String ? json['apiProbeModel'] as String : d.apiProbeModel,
      anchorCenterY: ax is num ? ax.toDouble() : null,
      onboardingSeen: b('onboardingSeen', d.onboardingSeen),
      bridgeAutoInstallDone: b('bridgeAutoInstallDone', d.bridgeAutoInstallDone),
      launchWithClaude: b('launchWithClaude', d.launchWithClaude),
      quitWithClaude: b('quitWithClaude', d.quitWithClaude),
      deviceSyncEnabled: b('deviceSyncEnabled', d.deviceSyncEnabled),
      deviceSyncFolder: json['deviceSyncFolder'] is String ? json['deviceSyncFolder'] as String : null,
    );
  }
}
