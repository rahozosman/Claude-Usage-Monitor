import 'usage_stats.dart';

/// Token usage of one local Claude Code session (task), computed from the
/// transcript files Claude Code keeps on this machine.
class SessionUsage {
  const SessionUsage({
    required this.sessionId,
    required this.title,
    required this.projectPath,
    required this.models,
    this.latestModel,
    required this.inputTokens,
    required this.cacheCreationTokens,
    required this.cacheReadTokens,
    required this.outputTokens,
    required this.messageCount,
    required this.firstAt,
    required this.lastAt,
    this.isActive = false,
  });

  final String sessionId;
  final String title;
  final String projectPath;
  final List<String> models;

  /// The model that produced the newest response (from `message.model` in
  /// the transcript) — for a running session, the one answering right now.
  final String? latestModel;
  final int inputTokens;
  final int cacheCreationTokens;
  final int cacheReadTokens;
  final int outputTokens;
  final int messageCount;
  final DateTime firstAt;
  final DateTime lastAt;
  final bool isActive;

  /// Everything Claude Code sent/received — the same basis as its own
  /// per-day token figures (input + cache write + cache read + output).
  int get totalTokens => inputTokens + cacheCreationTokens + cacheReadTokens + outputTokens;

  String get projectName {
    final parts = projectPath.replaceAll('\\', '/').split('/').where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? projectPath : parts.last;
  }
}

/// One clock hour of today, counted from the same transcripts as everything
/// else in this file.
///
/// All 24 hours are always present, including the ones nothing happened in: a
/// quiet night is a fact about the day, and a chart that dropped empty hours
/// would slide the busy ones together and make 03:00 look like 14:00.
class HourActivity {
  const HourActivity({
    required this.hour,
    required this.outputTokens,
    required this.responses,
    required this.sessions,
    required this.activeMinutes,
  });

  /// Local hour of the day, 0-23. It covers [hour]:00 up to [hour]:59.
  final int hour;

  /// What Claude generated in the hour — [SessionUsage.outputTokens] only.
  ///
  /// Not the four-way total the cards above use: input and cache are the same
  /// conversation re-sent on every turn, so they climb with how long a chat
  /// has grown rather than with how much was produced in the hour. Output is
  /// the part that is actually new work.
  final int outputTokens;

  /// Assistant responses Claude produced inside the hour.
  final int responses;

  /// How many sessions were in flight in the hour, not how many started in it:
  /// a session running 09:20 → 11:40 is counted in all three of its hours,
  /// because the question the strip answers is how many pieces of work were
  /// going at once.
  final int sessions;

  /// How many of the hour's 60 minutes carried at least one response, counted
  /// once however many sessions were running.
  ///
  /// A count of busy minutes, not a stopwatch: it cannot see thinking time
  /// between two answers, and it does not pretend to. What it does say
  /// exactly is whether an hour was worked through or spent in one burst.
  final int activeMinutes;

  bool get isActive => outputTokens > 0 || responses > 0 || sessions > 0;

  /// 0-1, how much of the hour carried work — what the bar's height is drawn
  /// from. Measured against the full 60 minutes rather than against the day's
  /// busiest hour, so a full-height bar always means a whole hour worked and
  /// two different days can be compared without rescaling.
  double get minuteShare => (activeMinutes / 60).clamp(0.0, 1.0);

  /// "14:00".
  String get label => '${hour.toString().padLeft(2, '0')}:00';

  /// "14:00–15:00".
  String get range => '$label–${((hour + 1) % 24).toString().padLeft(2, '0')}:00';
}

/// Aggregate of local session usage over the last 7 days.
class LocalUsageReport {
  const LocalUsageReport({
    required this.computedAt,
    required this.sessions,
    required this.todayTokensByModel,
    required this.weekTokensByModel,
    required this.todaySessionCount,
    required this.activeSessionCount,
    required this.scannedFiles,
    this.dayRollups = const <DayRollup>[],
    this.todayHours = const <HourActivity>[],
  });

  final DateTime computedAt;

  /// Newest activity first.
  final List<SessionUsage> sessions;
  final Map<String, int> todayTokensByModel;
  final Map<String, int> weekTokensByModel;
  final int todaySessionCount;
  final int activeSessionCount;
  final int scannedFiles;

  /// The same scan, rolled up per calendar day: messages, sessions, tool calls
  /// and the per-model token split. Ascending by date, last 7 days.
  final List<DayRollup> dayRollups;

  /// Today's 24 local hours, ascending from 00:00. Empty only before the first
  /// scan has produced anything — never a partial day, so a caller can index
  /// it by hour once it is non-empty.
  final List<HourActivity> todayHours;

  int get todayTotal => todayTokensByModel.values.fold(0, (a, b) => a + b);
  int get weekTotal => weekTokensByModel.values.fold(0, (a, b) => a + b);
  bool get isEmpty => sessions.isEmpty;

  /// The hour [now] falls in, or null before the first scan finished.
  HourActivity? hourAt(DateTime now) => todayHours.length == 24 ? todayHours[now.hour] : null;

  /// The hour that generated the most today, or null if today is empty.
  /// Ties go to the earlier hour — the first time the day peaked.
  HourActivity? get busiestHour {
    HourActivity? best;
    for (final h in todayHours) {
      if (h.outputTokens > 0 && (best == null || h.outputTokens > best.outputTokens)) best = h;
    }
    return best;
  }

  /// Hours today that carried any work at all.
  int get activeHourCount => todayHours.where((h) => h.isActive).length;

  /// Today's generated tokens, which is exactly the hours added up — the hour
  /// chart and the figure above it are the same measure.
  int get todayOutputTotal => todayHours.fold<int>(0, (sum, h) => sum + h.outputTokens);

  /// Minutes of today that carried work, across every hour.
  int get todayActiveMinutes => todayHours.fold<int>(0, (sum, h) => sum + h.activeMinutes);
}
