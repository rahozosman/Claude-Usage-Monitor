import '../core/errors/app_error.dart';
import 'api_rate_limits.dart';
import 'api_usage_report.dart';
import 'cli_status.dart';
import 'device_activity.dart';
import 'connection_status.dart';
import 'limit_window.dart';
import 'session_usage.dart';
import 'usage_stats.dart';

/// Everything the dashboard renders, produced by [UsageRepository].
class UsageSnapshot {
  const UsageSnapshot({
    required this.fiveHour,
    required this.weekly,
    required this.extraWindows,
    required this.cli,
    required this.connection,
    this.api,
    this.apiReport,
    this.local,
    this.stats,
    this.devices = DeviceSyncResult.none,
    this.apiError,
    this.subscriptionError,
    this.lastUpdated,
    this.lastAttempt,
  });

  factory UsageSnapshot.initial() => const UsageSnapshot(
    fiveHour: LimitWindow.unavailable(
      id: LimitWindow.fiveHourId,
      label: '5-hour limit',
      reason: 'Waiting for first refresh',
    ),
    weekly: LimitWindow.unavailable(
      id: LimitWindow.sevenDayId,
      label: 'Weekly limit',
      reason: 'Waiting for first refresh',
    ),
    extraWindows: <LimitWindow>[],
    cli: CliStatus.notInstalled(),
    connection: ConnectionStatus.idle,
  );

  final LimitWindow fiveHour;
  final LimitWindow weekly;

  /// Model-specific or other windows the source exposed (e.g. Weekly · Opus).
  final List<LimitWindow> extraWindows;
  final CliStatus cli;
  final ConnectionStatus connection;
  final ApiRateLimits? api;
  final ApiUsageReport? apiReport;

  /// Local Claude Code session usage (this PC only).
  final LocalUsageReport? local;

  /// Claude Code's own usage statistics (`~/.claude/stats-cache.json`), with
  /// the days it has not finished counting filled in from the transcripts.
  final UsageStats? stats;

  /// What the other devices on this account are doing (shared folder).
  final DeviceSyncResult devices;
  final AppError? apiError;
  final AppError? subscriptionError;

  /// Newest observation across every source.
  final DateTime? lastUpdated;
  final DateTime? lastAttempt;

  bool get hasAnySubscriptionData => fiveHour.isAvailable || weekly.isAvailable;

  List<LimitWindow> get allWindows => <LimitWindow>[fiveHour, weekly, ...extraWindows];

  UsageSnapshot copyWith({
    LimitWindow? fiveHour,
    LimitWindow? weekly,
    List<LimitWindow>? extraWindows,
    CliStatus? cli,
    ConnectionStatus? connection,
    ApiRateLimits? api,
    ApiUsageReport? apiReport,
    LocalUsageReport? local,
    UsageStats? stats,
    DeviceSyncResult? devices,
    AppError? apiError,
    AppError? subscriptionError,
    DateTime? lastUpdated,
    DateTime? lastAttempt,
    bool clearApiError = false,
    bool clearSubscriptionError = false,
  }) {
    return UsageSnapshot(
      fiveHour: fiveHour ?? this.fiveHour,
      weekly: weekly ?? this.weekly,
      extraWindows: extraWindows ?? this.extraWindows,
      cli: cli ?? this.cli,
      connection: connection ?? this.connection,
      api: api ?? this.api,
      apiReport: apiReport ?? this.apiReport,
      local: local ?? this.local,
      stats: stats ?? this.stats,
      devices: devices ?? this.devices,
      apiError: clearApiError ? null : (apiError ?? this.apiError),
      subscriptionError: clearSubscriptionError ? null : (subscriptionError ?? this.subscriptionError),
      lastUpdated: lastUpdated ?? this.lastUpdated,
      lastAttempt: lastAttempt ?? this.lastAttempt,
    );
  }
}
