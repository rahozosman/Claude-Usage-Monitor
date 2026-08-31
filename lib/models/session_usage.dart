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

  int get todayTotal => todayTokensByModel.values.fold(0, (a, b) => a + b);
  int get weekTotal => weekTokensByModel.values.fold(0, (a, b) => a + b);
  bool get isEmpty => sessions.isEmpty;
}
