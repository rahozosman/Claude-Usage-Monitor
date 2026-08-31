import 'package:flutter/foundation.dart';

/// Everything Claude Code keeps in `~/.claude/stats-cache.json` — the backing
/// store of its own `/usage` → Overview tab — plus the pure range maths the
/// "How you use it" card renders.
///
/// Nothing here is estimated. Every field is a number Claude Code wrote, or a
/// count this app took from the same transcripts Claude Code counts (see
/// [UsageStats.withTranscriptDays]).

/// The four token classes Claude bills separately, as Claude Code stores them.
@immutable
class ModelTotals {
  const ModelTotals({this.input = 0, this.output = 0, this.cacheRead = 0, this.cacheWrite = 0, this.costUsd = 0});

  final int input;
  final int output;
  final int cacheRead;
  final int cacheWrite;

  /// Claude Code writes `costUSD: 0` for subscription usage — it only fills in
  /// for API-key sessions, so the card shows it only when it is non-zero.
  final double costUsd;

  /// The same basis as Claude Code's per-day token figures.
  int get total => input + output + cacheRead + cacheWrite;

  bool get isEmpty => total == 0;

  ModelTotals operator +(ModelTotals other) => ModelTotals(
    input: input + other.input,
    output: output + other.output,
    cacheRead: cacheRead + other.cacheRead,
    cacheWrite: cacheWrite + other.cacheWrite,
    costUsd: costUsd + other.costUsd,
  );

  static ModelTotals fromJson(Map<dynamic, dynamic> json) {
    int n(Object? v) => v is num ? v.toInt() : 0;
    final cost = json['costUSD'];
    return ModelTotals(
      input: n(json['inputTokens']),
      output: n(json['outputTokens']),
      cacheRead: n(json['cacheReadInputTokens']),
      cacheWrite: n(json['cacheCreationInputTokens']),
      costUsd: cost is num ? cost.toDouble() : 0,
    );
  }
}

/// One calendar day, in local time — Claude Code stores plain `YYYY-MM-DD`
/// keys, which are the days the user actually lived, not UTC days.
@immutable
class DayActivity {
  const DayActivity({
    required this.date,
    required this.messages,
    required this.sessions,
    required this.toolCalls,
    required this.tokensByModel,
    this.fromTranscripts = false,
  });

  /// Local midnight.
  final DateTime date;
  final int messages;
  final int sessions;
  final int toolCalls;

  /// Model id → tokens (input + cache write + cache read + output).
  final Map<String, int> tokensByModel;

  /// True when this app counted the day from the transcripts because Claude
  /// Code had not finished counting it yet.
  final bool fromTranscripts;

  int get tokens {
    var sum = 0;
    for (final v in tokensByModel.values) {
      sum += v;
    }
    return sum;
  }

  bool get isActive => messages > 0 || sessions > 0 || tokens > 0;

  static String key(DateTime day) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${day.year}-${two(day.month)}-${two(day.day)}';
  }
}

/// A day this app rolled up from `~/.claude/projects/**.jsonl` itself, with the
/// per-model split the stats cache only keeps for all time.
@immutable
class DayRollup {
  const DayRollup({
    required this.date,
    required this.messages,
    required this.sessions,
    required this.toolCalls,
    required this.tokensByModel,
  });

  final DateTime date;
  final int messages;
  final int sessions;
  final int toolCalls;
  final Map<String, ModelTotals> tokensByModel;

  ModelTotals get totals {
    var sum = const ModelTotals();
    for (final v in tokensByModel.values) {
      sum = sum + v;
    }
    return sum;
  }

  DayActivity toActivity() => DayActivity(
    date: date,
    messages: messages,
    sessions: sessions,
    toolCalls: toolCalls,
    tokensByModel: <String, int>{for (final e in tokensByModel.entries) e.key: e.value.total},
    fromTranscripts: true,
  );
}

/// Claude Code's longest single session, as it recorded it.
@immutable
class LongestSession {
  const LongestSession({required this.duration, required this.messageCount, this.sessionId, this.at});

  final Duration duration;
  final int messageCount;
  final String? sessionId;

  /// When the session ended, in local time.
  final DateTime? at;
}

/// The parsed stats cache.
@immutable
class UsageStats {
  const UsageStats({
    required this.observedAt,
    required this.version,
    required this.days,
    required this.modelUsage,
    required this.totalSessions,
    required this.totalMessages,
    this.lastComputedDate,
    this.longestSession,
    this.firstSessionDate,
    this.hourCounts = const <int, int>{},
    this.toppedUpFrom,
  });

  /// The version this parser was written against; a different one is read as
  /// far as it can be and flagged rather than presented as certain.
  static const int knownVersion = 5;

  /// The file's mtime — when Claude Code last wrote these numbers.
  final DateTime observedAt;
  final int version;

  /// Ascending by date, one entry per day Claude Code recorded.
  final List<DayActivity> days;

  /// All-time totals per model. Claude Code keeps the input/output/cache split
  /// for all time only — never per day.
  final Map<String, ModelTotals> modelUsage;
  final int totalSessions;
  final int totalMessages;

  /// The last day Claude Code counted. That day may be half-counted: it stops
  /// at whatever the transcripts held when it last wrote the file.
  final DateTime? lastComputedDate;
  final LongestSession? longestSession;
  final DateTime? firstSessionDate;

  /// Hour of day (0-23) → sessions started in it, all time. Sparse: Claude
  /// Code omits hours with no sessions.
  final Map<int, int> hourCounts;

  /// First day this app filled in from the transcripts, if any.
  final DateTime? toppedUpFrom;

  bool get versionUnderstood => version == knownVersion;

  bool get hasSplit => modelUsage.values.any((m) => !m.isEmpty);

  ModelTotals get allTimeTotals {
    var sum = const ModelTotals();
    for (final v in modelUsage.values) {
      sum = sum + v;
    }
    return sum;
  }

  /// Local midnight of the first session, which is where the heatmap starts.
  DateTime? get firstDay {
    final first = firstSessionDate;
    if (first != null) return DateTime(first.year, first.month, first.day);
    return days.isEmpty ? null : days.first.date;
  }

  UsageStats copyWith({List<DayActivity>? days, int? totalSessions, int? totalMessages, DateTime? toppedUpFrom}) =>
      UsageStats(
        observedAt: observedAt,
        version: version,
        days: days ?? this.days,
        modelUsage: modelUsage,
        totalSessions: totalSessions ?? this.totalSessions,
        totalMessages: totalMessages ?? this.totalMessages,
        lastComputedDate: lastComputedDate,
        longestSession: longestSession,
        firstSessionDate: firstSessionDate,
        hourCounts: hourCounts,
        toppedUpFrom: toppedUpFrom ?? this.toppedUpFrom,
      );

  /// Tolerant parser: an unreadable field is dropped, never guessed at.
  static UsageStats? fromJson(Map<dynamic, dynamic> json, DateTime observedAt) {
    final activity = <String, DayActivity>{};
    final tokens = <String, Map<String, int>>{};

    final dailyTokens = json['dailyModelTokens'];
    if (dailyTokens is List) {
      for (final row in dailyTokens) {
        if (row is! Map) continue;
        final date = row['date'];
        final byModel = row['tokensByModel'];
        if (date is! String || byModel is! Map) continue;
        final out = <String, int>{};
        byModel.forEach((model, value) {
          if (value is num && value > 0) out[model.toString()] = value.toInt();
        });
        tokens[date] = out;
      }
    }

    final daily = json['dailyActivity'];
    if (daily is List) {
      for (final row in daily) {
        if (row is! Map) continue;
        final date = row['date'];
        if (date is! String) continue;
        final day = parseDay(date);
        if (day == null) continue;
        int n(Object? v) => v is num ? v.toInt() : 0;
        activity[date] = DayActivity(
          date: day,
          messages: n(row['messageCount']),
          sessions: n(row['sessionCount']),
          toolCalls: n(row['toolCallCount']),
          tokensByModel: tokens[date] ?? const <String, int>{},
        );
      }
    }
    // A day with tokens but no activity row still happened; it would otherwise
    // vanish from the heatmap.
    tokens.forEach((date, byModel) {
      if (activity.containsKey(date) || byModel.isEmpty) return;
      final day = parseDay(date);
      if (day == null) return;
      activity[date] = DayActivity(date: day, messages: 0, sessions: 0, toolCalls: 0, tokensByModel: byModel);
    });

    final models = <String, ModelTotals>{};
    final usage = json['modelUsage'];
    if (usage is Map) {
      usage.forEach((model, value) {
        if (value is Map) models[model.toString()] = ModelTotals.fromJson(value);
      });
    }

    final hours = <int, int>{};
    final hourCounts = json['hourCounts'];
    if (hourCounts is Map) {
      hourCounts.forEach((hour, value) {
        final h = hour is num ? hour.toInt() : int.tryParse(hour.toString());
        if (h != null && h >= 0 && h <= 23 && value is num) hours[h] = value.toInt();
      });
    }

    LongestSession? longest;
    final ls = json['longestSession'];
    if (ls is Map && ls['duration'] is num) {
      longest = LongestSession(
        duration: Duration(milliseconds: (ls['duration'] as num).toInt()),
        messageCount: ls['messageCount'] is num ? (ls['messageCount'] as num).toInt() : 0,
        sessionId: ls['sessionId']?.toString(),
        at: _parseInstant(ls['timestamp']),
      );
    }

    final sorted = activity.values.toList()..sort((a, b) => a.date.compareTo(b.date));
    final version = json['version'];
    final totals = json['totalSessions'];
    final messages = json['totalMessages'];
    // Nothing recognisable at all is not a stats cache; the card says so
    // rather than drawing an empty year.
    if (sorted.isEmpty && models.isEmpty && totals is! num) return null;

    return UsageStats(
      observedAt: observedAt,
      version: version is num ? version.toInt() : -1,
      days: sorted,
      modelUsage: models,
      totalSessions: totals is num ? totals.toInt() : sorted.fold(0, (a, b) => a + b.sessions),
      totalMessages: messages is num ? messages.toInt() : sorted.fold(0, (a, b) => a + b.messages),
      lastComputedDate: json['lastComputedDate'] is String ? parseDay(json['lastComputedDate'] as String) : null,
      longestSession: longest,
      firstSessionDate: _parseInstant(json['firstSessionDate']),
      hourCounts: hours,
    );
  }

  /// Claude Code renders `/usage` from this file *plus* whatever the
  /// transcripts have gained since [lastComputedDate] — which is why its screen
  /// can read several sessions ahead of the file. This does the same, from the
  /// same transcripts, so the card matches what `/usage` shows.
  ///
  /// Only days from [lastComputedDate] onwards are touched: everything before
  /// it Claude Code has already counted in full. [scanned] must come from a
  /// complete scan of those days (this app scans 7 days back), so [window]
  /// bounds how far back a rollup is trusted.
  UsageStats withTranscriptDays(
    List<DayRollup> scanned, {
    required DateTime now,
    Duration window = const Duration(days: 7),
  }) {
    if (scanned.isEmpty) return this;
    final today = DateTime(now.year, now.month, now.day);
    final windowStart = DateTime(today.year, today.month, today.day - (window.inDays - 1));
    final from = lastComputedDate;
    final byKey = <String, DayActivity>{for (final d in days) DayActivity.key(d.date): d};

    var sessions = totalSessions;
    var messages = totalMessages;
    DateTime? topped;

    for (final rollup in scanned) {
      final day = DateTime(rollup.date.year, rollup.date.month, rollup.date.day);
      if (day.isBefore(windowStart)) continue;
      if (from != null && day.isBefore(from)) continue;
      if (day.isAfter(today)) continue;
      final key = DayActivity.key(day);
      final existing = byKey[key];
      // Claude Code counted this day too, and saw transcripts that may since
      // have been deleted. The fuller record of the same day wins; the two are
      // never blended into each other.
      if (existing != null && existing.messages >= rollup.messages) continue;
      byKey[key] = rollup.toActivity();
      sessions += rollup.sessions - (existing?.sessions ?? 0);
      messages += rollup.messages - (existing?.messages ?? 0);
      topped = topped == null || day.isBefore(topped) ? day : topped;
    }

    if (topped == null) return this;
    final merged = byKey.values.toList()..sort((a, b) => a.date.compareTo(b.date));
    return copyWith(days: merged, totalSessions: sessions, totalMessages: messages, toppedUpFrom: topped);
  }

  /// `2026-08-21` → local midnight. Claude Code's day keys are local calendar
  /// days, so reading them as UTC would slide every day by the offset.
  static DateTime? parseDay(String value) {
    final parts = value.split('-');
    if (parts.length < 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2].split('T').first);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  static DateTime? _parseInstant(Object? value) {
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    return null;
  }
}

/// The three spans the card can show.
enum StatsRange {
  allTime(null, 'All time'),
  last30(30, '30 days'),
  last7(7, '7 days');

  const StatsRange(this.days, this.label);

  /// Calendar days counted back from today, inclusive. Null = everything.
  final int? days;
  final String label;
}

/// One [StatsRange] worth of [UsageStats], all of it counted, none of it
/// interpolated.
@immutable
class RangeStats {
  const RangeStats({
    required this.range,
    required this.days,
    required this.from,
    required this.to,
    required this.activeDays,
    required this.spanDays,
    required this.longestStreak,
    required this.currentStreak,
    required this.sessions,
    required this.messages,
    required this.toolCalls,
    required this.tokensByModel,
    this.mostActiveDay,
    this.longestSessionInRange = false,
  });

  final StatsRange range;

  /// Ascending, only the days Claude Code actually recorded.
  final List<DayActivity> days;

  /// First and last day the heatmap draws (local midnights, inclusive).
  final DateTime from;
  final DateTime to;
  final int activeDays;

  /// Days available to be active — the range, or the time since the first
  /// session if that is shorter.
  final int spanDays;
  final int longestStreak;
  final int currentStreak;
  final int sessions;
  final int messages;
  final int toolCalls;
  final Map<String, int> tokensByModel;
  final DayActivity? mostActiveDay;

  /// Whether the all-time longest session happened inside this range.
  final bool longestSessionInRange;

  int get totalTokens {
    var sum = 0;
    for (final v in tokensByModel.values) {
      sum += v;
    }
    return sum;
  }

  /// The model that burned the most tokens in the range, with its share.
  (String, double)? get favoriteModel {
    if (tokensByModel.isEmpty) return null;
    var best = tokensByModel.entries.first;
    for (final e in tokensByModel.entries) {
      if (e.value > best.value) best = e;
    }
    final total = totalTokens;
    if (best.value <= 0 || total <= 0) return null;
    return (best.key, best.value / total);
  }

  /// The busiest day's message count — the scale the heatmap shades against.
  int get busiestMessages => mostActiveDay?.messages ?? 0;

  static RangeStats compute({required UsageStats stats, required StatsRange range, required DateTime now}) {
    final today = DateTime(now.year, now.month, now.day);
    final first = stats.firstDay;
    final rangeStart = range.days == null ? null : DateTime(today.year, today.month, today.day - (range.days! - 1));
    // All time starts at the first session; a fixed range starts at its own
    // cut-off, but never earlier than the first session — a 30-day box on a
    // 9-day history would otherwise read "9 of 30 active days".
    var from = rangeStart ?? first ?? today;
    if (first != null && from.isBefore(first)) from = first;

    final inRange = <DayActivity>[
      for (final d in stats.days)
        if (!d.date.isBefore(from) && !d.date.isAfter(today)) d,
    ];

    final active = <String>{
      for (final d in inRange)
        if (d.isActive) DayActivity.key(d.date),
    };

    final tokens = <String, int>{};
    var sessions = 0;
    var messages = 0;
    var toolCalls = 0;
    DayActivity? busiest;
    for (final d in inRange) {
      sessions += d.sessions;
      messages += d.messages;
      toolCalls += d.toolCalls;
      d.tokensByModel.forEach((model, value) => tokens[model] = (tokens[model] ?? 0) + value);
      if (busiest == null || d.messages > busiest.messages) busiest = d;
    }
    // All time has authoritative totals in the file: they survive even if
    // Claude Code ever prunes old day rows.
    if (range == StatsRange.allTime) {
      sessions = stats.totalSessions;
      messages = stats.totalMessages;
    }

    final longest = stats.longestSession?.at;
    final longestDay = longest == null ? null : DateTime(longest.year, longest.month, longest.day);

    return RangeStats(
      range: range,
      days: inRange,
      from: from,
      to: today,
      activeDays: active.length,
      spanDays: today.difference(from).inDays + 1,
      longestStreak: _longestStreak(active),
      currentStreak: _currentStreak(active, today),
      sessions: sessions,
      messages: messages,
      toolCalls: toolCalls,
      tokensByModel: tokens,
      mostActiveDay: busiest != null && busiest.isActive ? busiest : null,
      longestSessionInRange: longestDay != null && !longestDay.isBefore(from) && !longestDay.isAfter(today),
    );
  }

  /// Day arithmetic goes through [DateTime] fields, never `Duration(days: 1)`:
  /// adding 24 hours across a daylight-saving change lands at 23:00 the same
  /// day and would break the run.
  static DateTime _shift(DateTime day, int by) => DateTime(day.year, day.month, day.day + by);

  static int _longestStreak(Set<String> active) {
    var best = 0;
    for (final key in active) {
      final day = UsageStats.parseDay(key);
      if (day == null) continue;
      // Count each run once, from the day that starts it.
      if (active.contains(DayActivity.key(_shift(day, -1)))) continue;
      var run = 0;
      var cursor = day;
      while (active.contains(DayActivity.key(cursor))) {
        run++;
        cursor = _shift(cursor, 1);
      }
      if (run > best) best = run;
    }
    return best;
  }

  /// Counted back from today. A day that has not started yet does not break a
  /// run, so before the first session of the day the streak still stands.
  static int _currentStreak(Set<String> active, DateTime today) {
    var cursor = active.contains(DayActivity.key(today)) ? today : _shift(today, -1);
    var run = 0;
    while (active.contains(DayActivity.key(cursor))) {
      run++;
      cursor = _shift(cursor, -1);
    }
    return run;
  }
}
