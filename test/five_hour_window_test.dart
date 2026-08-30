import 'package:claude_usage_monitor/models/app_settings.dart';
import 'package:claude_usage_monitor/models/cli_status.dart';
import 'package:claude_usage_monitor/models/device_activity.dart';
import 'package:claude_usage_monitor/models/limit_window.dart';
import 'package:claude_usage_monitor/models/session_usage.dart';
import 'package:claude_usage_monitor/models/status_line_data.dart';
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

/// Shaped after a real `statusline.json` from Claude Code 2.1.251, trimmed to
/// the fields the app reads. The `rate_limits` block carries `seven_day` and
/// no `five_hour`: Claude Code drops a window it has nothing to report for,
/// which is what left the 5-hour card reading "Unavailable · Not provided by
/// Claude" while the weekly card beside it worked.
Map<String, dynamic> payload({bool withFiveHour = false}) => <String, dynamic>{
  'model': <String, dynamic>{'id': 'claude-opus-5', 'display_name': 'Opus 5'},
  'workspace': <String, dynamic>{'current_dir': 'C:/work'},
  'version': '2.1.251',
  'context_window': <String, dynamic>{'used_percentage': 7},
  'rate_limits': <String, dynamic>{
    if (withFiveHour) 'five_hour': <String, dynamic>{'used_percentage': 3, 'resets_at': 1788001200},
    'seven_day': <String, dynamic>{'used_percentage': 82, 'resets_at': 1788260400},
  },
};

void main() {
  group('StatusLineData', () {
    test('a rate_limits block missing five_hour still counts as rate limits', () {
      final data = StatusLineData.fromJson(payload(), DateTime.now());
      expect(data.hasRateLimits, isTrue, reason: 'seven_day is there, so the feed is working');
      expect(data.reported(LimitWindow.sevenDayId), isTrue);
      expect(data.reported(LimitWindow.fiveHourId), isFalse);
      expect(data.windowIds, <String>[LimitWindow.sevenDayId]);
    });

    test('reports both ids when Claude Code sends both', () {
      final data = StatusLineData.fromJson(payload(withFiveHour: true), DateTime.now());
      expect(data.reported(LimitWindow.fiveHourId), isTrue);
      expect(data.windowIds, containsAll(<String>[LimitWindow.fiveHourId, LimitWindow.sevenDayId]));
    });
  });

  group('UsageRepository · a window Claude is not reporting', () {
    test('explains the gap instead of blaming the whole chain', () async {
      final snap = await _fetch();

      expect(snap.weekly.isAvailable, isTrue, reason: 'the feed is healthy');
      expect(snap.weekly.usedPercentage, 82);

      expect(snap.fiveHour.isAvailable, isFalse);
      expect(
        snap.fiveHour.unavailableReason,
        isNot('Not provided by Claude'),
        reason: 'the generic fallback is what made a one-window gap look like a broken install',
      );
      expect(snap.fiveHour.unavailableReason, contains('not reporting this window'));
      expect(snap.fiveHour.unavailableReason, contains('Weekly limit'));
    });

    test('restores the last figure on disk while that window is still open', () async {
      final now = DateTime.now();
      final snap = await _fetch(
        history: <UsageReading>[
          UsageReading(
            windowId: LimitWindow.fiveHourId,
            percentage: 41,
            observedAt: now.subtract(const Duration(minutes: 20)),
            resetsAt: now.add(const Duration(hours: 2)),
          ),
        ],
      );

      expect(snap.fiveHour.isAvailable, isTrue);
      expect(snap.fiveHour.usedPercentage, 41);
      expect(snap.fiveHour.hasReset(now), isFalse);
      expect(snap.fiveHour.source, DataSource.statusLine);
    });

    test('keeps a window that reset within the day, so the card can say so', () async {
      final now = DateTime.now();
      final snap = await _fetch(
        history: <UsageReading>[
          UsageReading(
            windowId: LimitWindow.fiveHourId,
            percentage: 3,
            observedAt: now.subtract(const Duration(hours: 6)),
            resetsAt: now.subtract(const Duration(hours: 5)),
          ),
        ],
      );

      expect(snap.fiveHour.isAvailable, isTrue);
      expect(snap.fiveHour.hasReset(now), isTrue, reason: 'shown as reset, never as a live number');
    });

    test('drops a reading too old to say anything about now', () async {
      final now = DateTime.now();
      final snap = await _fetch(
        history: <UsageReading>[
          UsageReading(
            windowId: LimitWindow.fiveHourId,
            percentage: 3,
            observedAt: now.subtract(const Duration(days: 3)),
            resetsAt: now.subtract(const Duration(days: 3)),
          ),
        ],
      );

      expect(snap.fiveHour.isAvailable, isFalse);
      expect(snap.fiveHour.unavailableReason, contains('not reporting this window'));
    });

    test('a status line carrying both windows is untouched by any of this', () async {
      final snap = await _fetch(withFiveHour: true);
      expect(snap.fiveHour.isAvailable, isTrue);
      expect(snap.fiveHour.usedPercentage, 3);
      expect(snap.weekly.usedPercentage, 82);
    });

    test('an absent status line still reports the chain, not the window', () async {
      final snap = await _fetch(statusLine: false);
      expect(snap.fiveHour.isAvailable, isFalse);
      expect(snap.fiveHour.unavailableReason, contains('Waiting for Claude Code'));
    });
  });
}

Future<UsageSnapshot> _fetch({
  bool withFiveHour = false,
  bool statusLine = true,
  List<UsageReading> history = const <UsageReading>[],
}) {
  final repo = UsageRepository(
    cli: _FakeCli(statusLine ? payload(withFiveHour: withFiveHour) : null),
    oauth: OAuthUsageService(),
    api: AnthropicApiService(),
    settingsService: _FakeSettings(),
    local: LocalUsageService(),
    history: _FakeHistory(history),
    devices: _FakeDevices(),
  );
  return repo.fetch(
    settings: const AppSettings(showActivity: false, deviceSyncEnabled: false),
    previous: UsageSnapshot.initial(),
    probeApi: false,
  );
}

/// A healthy install: Claude Code present, signed in with OAuth, bridge in
/// place — everything the reason logic checks before it reaches the window.
class _FakeCli extends ClaudeCliService {
  _FakeCli(this.json);

  final Map<String, dynamic>? json;

  StatusLineData? get _data => json == null ? null : StatusLineData.fromJson(json!, DateTime.now());

  @override
  Future<CliStatus> detect({bool force = false}) async {
    final data = _data;
    return CliStatus(
      installed: true,
      version: '2.1.251',
      credentialsFound: true,
      authType: 'Claude.ai subscription (OAuth)',
      bridgeInstalled: true,
      bridgeScriptPresent: true,
      bridgeCommandCurrent: true,
      statusLineHasRateLimits: data?.hasRateLimits ?? false,
      statusLineWindowIds: data?.windowIds ?? const <String>[],
      statusLineUpdatedAt: data?.observedAt,
    );
  }

  @override
  Future<StatusLineData?> readStatusLineFile() async => _data;
}

class _FakeSettings extends SettingsService {
  @override
  Future<SecretValue> readApiKey() async => const SecretValue(null, SecretOrigin.none);

  @override
  Future<SecretValue> readAdminKey() async => const SecretValue(null, SecretOrigin.none);
}

class _FakeHistory extends UsageHistoryService {
  _FakeHistory(this._last);

  final List<UsageReading> _last;

  @override
  Iterable<UsageReading> get lastKnown => _last;

  @override
  Future<void> record(Iterable<LimitWindow> windows, DateTime now) async {}
}

class _FakeDevices extends DeviceSyncService {
  @override
  Future<DeviceSyncResult> sync({
    required AppSettings settings,
    required LocalUsageReport? local,
    required DateTime now,
  }) async => DeviceSyncResult.none;
}
