import 'package:claude_usage_monitor/core/utils/format_utils.dart';
import 'package:claude_usage_monitor/models/usage_stats.dart';
import 'package:flutter_test/flutter_test.dart';

/// A real `~/.claude/stats-cache.json` (version 5), kept whole apart from the
/// hour histogram, which is trimmed.
///
/// The two instants are written without a `Z` on purpose: Claude Code writes
/// UTC, and the parser converts to local time, so a fixture with `Z` in it
/// would land on a different calendar day depending on where the test runs.
/// That conversion has its own test below.
Map<String, dynamic> cache() => <String, dynamic>{
  'version': 5,
  'lastComputedDate': '2026-08-29',
  'dailyActivity': <Map<String, dynamic>>[
    <String, dynamic>{'date': '2026-08-21', 'messageCount': 4429, 'sessionCount': 2, 'toolCallCount': 1073},
    <String, dynamic>{'date': '2026-08-22', 'messageCount': 8973, 'sessionCount': 12, 'toolCallCount': 2424},
    <String, dynamic>{'date': '2026-08-23', 'messageCount': 8167, 'sessionCount': 11, 'toolCallCount': 1923},
    <String, dynamic>{'date': '2026-08-24', 'messageCount': 4602, 'sessionCount': 17, 'toolCallCount': 1112},
    <String, dynamic>{'date': '2026-08-25', 'messageCount': 7674, 'sessionCount': 10, 'toolCallCount': 2043},
    <String, dynamic>{'date': '2026-08-26', 'messageCount': 9680, 'sessionCount': 14, 'toolCallCount': 2378},
    <String, dynamic>{'date': '2026-08-27', 'messageCount': 6625, 'sessionCount': 20, 'toolCallCount': 1524},
    <String, dynamic>{'date': '2026-08-28', 'messageCount': 4765, 'sessionCount': 9, 'toolCallCount': 1025},
    <String, dynamic>{'date': '2026-08-29', 'messageCount': 692, 'sessionCount': 4, 'toolCallCount': 164},
  ],
  'dailyModelTokens': <Map<String, dynamic>>[
    <String, dynamic>{
      'date': '2026-08-21',
      'tokensByModel': <String, dynamic>{'claude-opus-5': 744403281},
    },
    <String, dynamic>{
      'date': '2026-08-22',
      'tokensByModel': <String, dynamic>{'claude-opus-5': 772604082},
    },
    <String, dynamic>{
      'date': '2026-08-23',
      'tokensByModel': <String, dynamic>{'claude-opus-5': 807945923, 'claude-fable-5': 184078768},
    },
    <String, dynamic>{
      'date': '2026-08-24',
      'tokensByModel': <String, dynamic>{'claude-opus-5': 219219428, 'claude-fable-5': 53503812},
    },
    <String, dynamic>{
      'date': '2026-08-25',
      'tokensByModel': <String, dynamic>{'claude-opus-5': 993315864},
    },
    <String, dynamic>{
      'date': '2026-08-26',
      'tokensByModel': <String, dynamic>{'claude-opus-5': 704986106, 'claude-fable-5': 425046836},
    },
    <String, dynamic>{
      'date': '2026-08-27',
      'tokensByModel': <String, dynamic>{
        'claude-fable-5': 150174620,
        'claude-opus-4-8': 11407324,
        'claude-opus-5': 525973363,
      },
    },
    <String, dynamic>{
      'date': '2026-08-28',
      'tokensByModel': <String, dynamic>{'claude-fable-5': 239120599, 'claude-opus-5': 495604809},
    },
    <String, dynamic>{
      'date': '2026-08-29',
      'tokensByModel': <String, dynamic>{'claude-opus-5': 25949612},
    },
  ],
  'dailyModelTokensVersion': 5,
  'modelUsage': <String, dynamic>{
    'claude-opus-5': <String, dynamic>{
      'inputTokens': 39560,
      'outputTokens': 26118610,
      'cacheReadInputTokens': 5199875886,
      'cacheCreationInputTokens': 63968412,
      'webSearchRequests': 0,
      'costUSD': 0,
    },
    'claude-fable-5': <String, dynamic>{
      'inputTokens': 1225629,
      'outputTokens': 10013940,
      'cacheReadInputTokens': 1015035561,
      'cacheCreationInputTokens': 25649505,
      'webSearchRequests': 0,
      'costUSD': 0,
    },
    'claude-opus-4-8': <String, dynamic>{
      'inputTokens': 432,
      'outputTokens': 44385,
      'cacheReadInputTokens': 8205236,
      'cacheCreationInputTokens': 3157271,
      'webSearchRequests': 0,
      'costUSD': 0,
    },
  },
  'totalSessions': 99,
  'totalMessages': 55607,
  'longestSession': <String, dynamic>{
    'sessionId': '391944bd-9077-48d0-b80b-8b710d611b21',
    'duration': 39464529,
    'messageCount': 403,
    'timestamp': '2026-08-29T18:02:47.639',
  },
  'firstSessionDate': '2026-08-21T13:19:41.771',
  'hourCounts': <String, dynamic>{'6': 10, '15': 10, '23': 3},
};

/// Days with something on them, one session and 10 messages each.
UsageStats streakStats(List<DateTime> active) => UsageStats(
  observedAt: DateTime(2026, 8, 30),
  version: 5,
  days: <DayActivity>[
    for (final day in active)
      DayActivity(
        date: day,
        messages: 10,
        sessions: 1,
        toolCalls: 1,
        tokensByModel: const <String, int>{'claude-opus-5': 100},
      ),
  ],
  modelUsage: const <String, ModelTotals>{},
  totalSessions: active.length,
  totalMessages: 10 * active.length,
  firstSessionDate: active.isEmpty ? null : active.first,
);

DayRollup rollup(DateTime date, {required int messages, required int sessions, int toolCalls = 0, int tokens = 0}) =>
    DayRollup(
      date: date,
      messages: messages,
      sessions: sessions,
      toolCalls: toolCalls,
      tokensByModel: <String, ModelTotals>{'claude-opus-5': ModelTotals(input: tokens)},
    );

void main() {
  // The evening the screenshot behind this card was taken.
  final now = DateTime(2026, 8, 29, 23, 13);

  group('reading the stats cache', () {
    test('parses every day, model and total Claude Code wrote', () {
      final stats = UsageStats.fromJson(cache(), DateTime(2026, 8, 29, 22, 58))!;

      expect(stats.version, 5);
      expect(stats.versionUnderstood, isTrue);
      expect(stats.days.length, 9);
      expect(stats.totalSessions, 99);
      expect(stats.totalMessages, 55607);
      expect(stats.lastComputedDate, DateTime(2026, 8, 29));
      expect(stats.firstDay, DateTime(2026, 8, 21));
      expect(stats.hourCounts[6], 10);
      // The day rows and the token rows are two arrays keyed by date; they
      // have to end up on the same day.
      final busiest = stats.days.firstWhere((d) => d.date == DateTime(2026, 8, 26));
      expect(busiest.messages, 9680);
      expect(busiest.sessions, 14);
      expect(busiest.toolCalls, 2378);
      expect(busiest.tokens, 704986106 + 425046836);
    });

    test('the model split matches the per-day totals, as Claude Code writes them', () {
      final stats = UsageStats.fromJson(cache(), DateTime(2026, 8, 29))!;
      var perDay = 0;
      for (final day in stats.days) {
        perDay += day.tokens;
      }
      expect(stats.allTimeTotals.total, 6353334427);
      expect(perDay, stats.allTimeTotals.total, reason: 'dailyModelTokens and modelUsage describe the same tokens');
      expect(stats.modelUsage['claude-opus-5']!.cacheRead, 5199875886);
    });

    test('the longest session keeps the figure /usage prints', () {
      final stats = UsageStats.fromJson(cache(), DateTime(2026, 8, 29))!;
      expect(stats.longestSession!.duration.inMilliseconds, 39464529);
      expect(FormatUtils.durationLong(stats.longestSession!.duration), '10h 57m 45s');
      expect(stats.longestSession!.messageCount, 403);
    });

    test('a UTC instant is read as the local moment it was', () {
      final json = cache()..['firstSessionDate'] = '2026-08-21T13:19:41.771Z';
      final stats = UsageStats.fromJson(json, DateTime(2026, 8, 29))!;
      expect(stats.firstSessionDate!.isUtc, isFalse);
      expect(stats.firstSessionDate!.toUtc(), DateTime.utc(2026, 8, 21, 13, 19, 41, 771));
    });

    test('an unknown version is flagged, not guessed at', () {
      final stats = UsageStats.fromJson(cache()..['version'] = 9, DateTime(2026, 8, 29))!;
      expect(stats.versionUnderstood, isFalse);
      expect(stats.days.length, 9, reason: 'what is recognisable is still read');
    });

    test('nothing recognisable reads as no stats at all', () {
      expect(UsageStats.fromJson(<String, dynamic>{}, DateTime(2026, 8, 29)), isNull);
      expect(UsageStats.fromJson(<String, dynamic>{'version': 5}, DateTime(2026, 8, 29)), isNull);
    });

    test('a malformed day row is dropped, and the rest survive', () {
      final json = cache();
      (json['dailyActivity'] as List<Map<String, dynamic>>).add(<String, dynamic>{'date': 'not-a-date'});
      final stats = UsageStats.fromJson(json, DateTime(2026, 8, 29))!;
      expect(stats.days.length, 9);
    });
  });

  group('range maths', () {
    final stats = UsageStats.fromJson(cache(), DateTime(2026, 8, 29, 22, 58))!;

    test('all time uses the totals from the file itself', () {
      final range = RangeStats.compute(stats: stats, range: StatsRange.allTime, now: now);
      expect(range.sessions, 99);
      expect(range.messages, 55607);
      expect(range.toolCalls, 13666);
      expect(range.totalTokens, 6353334427);
      expect(range.activeDays, 9);
      expect(range.spanDays, 9);
      expect(range.from, DateTime(2026, 8, 21));
      expect(range.mostActiveDay!.date, DateTime(2026, 8, 26));
      final favourite = range.favoriteModel!;
      expect(favourite.$1, 'claude-opus-5');
      expect(favourite.$2, closeTo(0.8326, 0.0001));
    });

    test('7 days counts only the last seven calendar days, today included', () {
      final range = RangeStats.compute(stats: stats, range: StatsRange.last7, now: now);
      expect(range.from, DateTime(2026, 8, 23));
      expect(range.days.length, 7);
      expect(range.sessions, 85);
      expect(range.messages, 42205);
      expect(range.toolCalls, 10169);
      expect(range.totalTokens, 4836327064);
      expect(range.spanDays, 7);
    });

    test('a 30-day box on a 9-day history starts at the first session, not 30 days ago', () {
      final range = RangeStats.compute(stats: stats, range: StatsRange.last30, now: now);
      expect(range.from, DateTime(2026, 8, 21));
      expect(range.spanDays, 9, reason: 'nine of nine days, not nine of thirty');
      expect(range.activeDays, 9);
      expect(range.sessions, 99);
    });

    test('the longest session is tagged as in range only when it is', () {
      expect(RangeStats.compute(stats: stats, range: StatsRange.last7, now: now).longestSessionInRange, isTrue);
      final older = RangeStats.compute(
        stats: stats,
        range: StatsRange.last7,
        now: DateTime(2026, 9, 20, 12),
      );
      expect(older.longestSessionInRange, isFalse);
    });
  });

  group('streaks', () {
    test('the longest run is measured across the gaps, not through them', () {
      final stats = streakStats(<DateTime>[
        DateTime(2026, 8, 20),
        DateTime(2026, 8, 21),
        DateTime(2026, 8, 22),
        // 23rd missing
        DateTime(2026, 8, 24),
        DateTime(2026, 8, 25),
      ]);
      final range = RangeStats.compute(stats: stats, range: StatsRange.allTime, now: DateTime(2026, 8, 25, 10));
      expect(range.longestStreak, 3);
      expect(range.currentStreak, 2);
      expect(range.activeDays, 5);
      expect(range.spanDays, 6);
    });

    test('a day that has not started yet does not break the run', () {
      final stats = streakStats(<DateTime>[DateTime(2026, 8, 27), DateTime(2026, 8, 28), DateTime(2026, 8, 29)]);
      // Nothing today: the streak counts back from yesterday and still stands.
      final range = RangeStats.compute(stats: stats, range: StatsRange.allTime, now: DateTime(2026, 8, 30, 9));
      expect(range.currentStreak, 3);
      // Two silent days is a break.
      final broken = RangeStats.compute(stats: stats, range: StatsRange.allTime, now: DateTime(2026, 8, 31, 9));
      expect(broken.currentStreak, 0);
      expect(broken.longestStreak, 3);
    });

    test('no activity at all is a streak of nothing, not a crash', () {
      final stats = streakStats(<DateTime>[]);
      final range = RangeStats.compute(stats: stats, range: StatsRange.allTime, now: now);
      expect(range.activeDays, 0);
      expect(range.longestStreak, 0);
      expect(range.currentStreak, 0);
      expect(range.totalTokens, 0);
      expect(range.favoriteModel, isNull);
      expect(range.mostActiveDay, isNull);
    });
  });

  group('topping up the days Claude Code has not finished counting', () {
    final stats = UsageStats.fromJson(cache(), DateTime(2026, 8, 29, 22, 58))!;
    final today = DateTime(2026, 8, 30, 12);

    test('a day the cache never saw is added, with the totals moved to match', () {
      final merged = stats.withTranscriptDays(<DayRollup>[
        rollup(DateTime(2026, 8, 30), messages: 129, sessions: 2, toolCalls: 28, tokens: 5000),
      ], now: today);

      expect(merged.days.length, 10);
      expect(merged.totalSessions, 101);
      expect(merged.totalMessages, 55736);
      expect(merged.toppedUpFrom, DateTime(2026, 8, 30));
      expect(merged.days.last.fromTranscripts, isTrue);
      expect(merged.days.last.tokens, 5000);
    });

    test('the half-counted last day is replaced by the fuller count', () {
      final merged = stats.withTranscriptDays(<DayRollup>[
        rollup(DateTime(2026, 8, 29), messages: 1051, sessions: 7, toolCalls: 255),
      ], now: today);

      final day = merged.days.firstWhere((d) => d.date == DateTime(2026, 8, 29));
      expect(day.messages, 1051);
      expect(day.sessions, 7);
      // 99 - 4 + 7, 55607 - 692 + 1051: the day is swapped, not added twice.
      expect(merged.totalSessions, 102);
      expect(merged.totalMessages, 55966);
    });

    test('a thinner count of the same day is left alone', () {
      final merged = stats.withTranscriptDays(<DayRollup>[
        rollup(DateTime(2026, 8, 29), messages: 100, sessions: 1),
      ], now: today);

      expect(merged.toppedUpFrom, isNull);
      expect(merged.totalSessions, 99);
      expect(merged.days.firstWhere((d) => d.date == DateTime(2026, 8, 29)).messages, 692);
    });

    test('days Claude Code has already counted in full are never touched', () {
      final merged = stats.withTranscriptDays(<DayRollup>[
        rollup(DateTime(2026, 8, 26), messages: 99999, sessions: 99),
      ], now: today);

      expect(merged.toppedUpFrom, isNull);
      expect(merged.days.firstWhere((d) => d.date == DateTime(2026, 8, 26)).messages, 9680);
    });

    test('a day older than the transcript scan is not trusted to be complete', () {
      final noCutoff = UsageStats.fromJson(cache()..remove('lastComputedDate'), DateTime(2026, 8, 29))!;
      final merged = noCutoff.withTranscriptDays(<DayRollup>[
        rollup(DateTime(2026, 8, 21), messages: 99999, sessions: 99),
        rollup(DateTime(2026, 8, 30), messages: 129, sessions: 2),
      ], now: today);

      expect(merged.days.firstWhere((d) => d.date == DateTime(2026, 8, 21)).messages, 4429);
      expect(merged.toppedUpFrom, DateTime(2026, 8, 30));
    });

    test('nothing scanned changes nothing', () {
      expect(identical(stats.withTranscriptDays(const <DayRollup>[], now: today), stats), isTrue);
    });

    test('the topped-up days flow into the range maths', () {
      final merged = stats.withTranscriptDays(<DayRollup>[
        rollup(DateTime(2026, 8, 30), messages: 129, sessions: 2, toolCalls: 28, tokens: 5000),
      ], now: today);
      final range = RangeStats.compute(stats: merged, range: StatsRange.last7, now: today);

      expect(range.from, DateTime(2026, 8, 24));
      expect(range.days.last.date, DateTime(2026, 8, 30));
      expect(range.currentStreak, 7);
      expect(range.activeDays, 7);
    });
  });

  group('durations, the way /usage prints them', () {
    test('rounds to the nearest second like Claude Code does', () {
      expect(FormatUtils.durationLong(const Duration(milliseconds: 39464529)), '10h 57m 45s');
      expect(FormatUtils.durationLong(const Duration(milliseconds: 39464400)), '10h 57m 44s');
      expect(FormatUtils.durationLong(const Duration(minutes: 3, seconds: 7)), '3m 7s');
      expect(FormatUtils.durationLong(const Duration(seconds: 9)), '9s');
      expect(FormatUtils.durationLong(null), '—');
    });
  });
}
