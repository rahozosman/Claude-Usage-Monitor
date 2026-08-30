// Throwaway: runs the real repository against this machine's real
// statusline.json and prints what the 5-hour card would now render.
import 'package:claude_usage_monitor/models/app_settings.dart';
import 'package:claude_usage_monitor/models/device_activity.dart';
import 'package:claude_usage_monitor/models/limit_window.dart';
import 'package:claude_usage_monitor/models/session_usage.dart';
import 'package:claude_usage_monitor/models/usage_series.dart';
import 'package:claude_usage_monitor/models/usage_snapshot.dart';
import 'package:claude_usage_monitor/repositories/usage_repository.dart';
import 'package:claude_usage_monitor/services/anthropic_api_service.dart';
import 'package:claude_usage_monitor/services/claude_cli_service.dart';
import 'package:claude_usage_monitor/services/device_sync_service.dart';
import 'package:claude_usage_monitor/services/local_usage_service.dart';
import 'package:claude_usage_monitor/services/oauth_usage_service.dart';
import 'package:claude_usage_monitor/services/settings_service.dart';
import 'package:claude_usage_monitor/services/usage_history_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('live', () async {
    final cli = ClaudeCliService();
    final data = await cli.readStatusLineFile();
    print('--- real statusline.json ---');
    print('windowIds: ${data?.windowIds}');
    print('hasRateLimits: ${data?.hasRateLimits}');
    print('reported(five_hour): ${data?.reported(LimitWindow.fiveHourId)}');

    final status = await cli.detect(force: true);
    print('installed=${status.installed} oauth=${status.hasOAuth} '
        'bridge=${status.bridgeInstalled} script=${status.bridgeScriptPresent} '
        'current=${status.bridgeCommandCurrent}');

    final repo = UsageRepository(
      cli: cli,
      oauth: OAuthUsageService(),
      api: AnthropicApiService(),
      settingsService: _NoKeys(),
      local: LocalUsageService(),
      history: _NoWrite(),
      devices: _NoDevices(),
    );
    final snap = await repo.fetch(
      settings: const AppSettings(showActivity: false, deviceSyncEnabled: false),
      previous: UsageSnapshot.initial(),
      probeApi: false,
    );
    print('--- 5-hour card ---');
    print('available: ${snap.fiveHour.isAvailable}');
    print('percent:   ${snap.fiveHour.usedPercentage}');
    print('reason:    ${snap.fiveHour.unavailableReason}');
    print('--- weekly card ---');
    print('available: ${snap.weekly.isAvailable}  percent: ${snap.weekly.usedPercentage}');
    print('connection: ${snap.connection}');
  });
}

class _NoKeys extends SettingsService {
  @override
  Future<SecretValue> readApiKey() async => const SecretValue(null, SecretOrigin.none);
  @override
  Future<SecretValue> readAdminKey() async => const SecretValue(null, SecretOrigin.none);
}

class _NoWrite extends UsageHistoryService {
  @override
  Iterable<UsageReading> get lastKnown => const <UsageReading>[];
  @override
  Future<void> record(Iterable<LimitWindow> windows, DateTime now) async {}
}

class _NoDevices extends DeviceSyncService {
  @override
  Future<DeviceSyncResult> sync({
    required AppSettings settings,
    required LocalUsageReport? local,
    required DateTime now,
  }) async => DeviceSyncResult.none;
}
