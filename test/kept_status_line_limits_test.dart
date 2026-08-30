import 'package:claude_usage_monitor/models/limit_window.dart';
import 'package:claude_usage_monitor/models/status_line_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'five_hour_window_test.dart' show payload;

/// What Claude Code sends for a session that has started but has not had an API
/// response yet: a complete, healthy status line with no `rate_limits` in it.
Map<String, dynamic> silentPayload() => <String, dynamic>{
  'model': <String, dynamic>{'id': 'claude-opus-5', 'display_name': 'Opus 5'},
  'workspace': <String, dynamic>{'current_dir': 'C:/work'},
  'version': '2.1.251',
  'context_window': <String, dynamic>{'used_percentage': 2},
  'session_id': 'new-session',
};

void main() {
  group('a status line with no rate_limits', () {
    final now = DateTime.now();

    test('falls back to the limits the bridge kept', () {
      final live = StatusLineData.fromJson(silentPayload(), now);
      final kept = StatusLineData.fromJson(payload(), now.subtract(const Duration(minutes: 1)));

      expect(live.hasRateLimits, isFalse, reason: 'the new session has nothing to report yet');

      final merged = StatusLineData.mergeKeptLimits(live, kept, now)!;
      expect(merged.hasRateLimits, isTrue);
      expect(merged.reported(LimitWindow.sevenDayId), isTrue);
      expect(merged.windows.single.usedPercentage, 82);
    });

    test('keeps the carried window at the age it was really observed', () {
      final observedAt = now.subtract(const Duration(minutes: 1));
      final merged = StatusLineData.mergeKeptLimits(
        StatusLineData.fromJson(silentPayload(), now),
        StatusLineData.fromJson(payload(), observedAt),
        now,
      )!;

      expect(merged.observedAt, now, reason: 'the feed itself is live');
      expect(merged.windows.single.observedAt, observedAt, reason: 'the number is a minute old, and says so');
    });

    test('keeps the live session details, not the kept payload\'s', () {
      final merged = StatusLineData.mergeKeptLimits(
        StatusLineData.fromJson(silentPayload(), now),
        StatusLineData.fromJson(payload(), now.subtract(const Duration(minutes: 1))),
        now,
      )!;

      expect(merged.sessionId, 'new-session');
      expect(merged.contextUsedPercentage, 2);
    });

    test('ignores a kept reading too old to describe now', () {
      final closed = now.subtract(const Duration(days: 3));
      final merged = StatusLineData.mergeKeptLimits(
        StatusLineData.fromJson(silentPayload(), now),
        StatusLineData.fromJson(<String, dynamic>{
          'rate_limits': <String, dynamic>{
            'seven_day': <String, dynamic>{
              'used_percentage': 82,
              'resets_at': closed.millisecondsSinceEpoch ~/ 1000,
            },
          },
        }, closed),
        now,
      )!;

      expect(merged.hasRateLimits, isFalse, reason: 'observed days ago and its window has closed since');
    });

    test('carries a window whose reset has not passed, however old the reading', () {
      final merged = StatusLineData.mergeKeptLimits(
        StatusLineData.fromJson(silentPayload(), now),
        StatusLineData.fromJson(payload(), now.subtract(const Duration(days: 3))),
        now,
      )!;

      expect(merged.hasRateLimits, isTrue, reason: 'the weekly window it measured is still open');
    });

    test('a live payload that has limits is never touched', () {
      final live = StatusLineData.fromJson(payload(withFiveHour: true), now);
      final merged = StatusLineData.mergeKeptLimits(live, StatusLineData.fromJson(payload(), now), now);

      expect(identical(merged, live), isTrue);
    });

    test('nothing live and nothing kept stays nothing', () {
      expect(StatusLineData.mergeKeptLimits(null, null, now), isNull);
    });

    test('only a kept payload is still better than no window at all', () {
      final kept = StatusLineData.fromJson(payload(), now.subtract(const Duration(minutes: 2)));
      final merged = StatusLineData.mergeKeptLimits(null, kept, now)!;

      expect(merged.reported(LimitWindow.sevenDayId), isTrue);
    });
  });
}
