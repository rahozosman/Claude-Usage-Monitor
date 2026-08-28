import 'limit_window.dart';

/// Parsed contents of the status-line JSON that Claude Code hands to its
/// `statusLine.command` (captured by the bridge script).
class StatusLineData {
  const StatusLineData({
    required this.observedAt,
    required this.windows,
    this.modelDisplayName,
    this.contextUsedPercentage,
    this.currentDirectory,
    this.claudeCodeVersion,
    this.sessionId,
  });

  final DateTime observedAt;
  final List<LimitWindow> windows;
  final String? modelDisplayName;
  final double? contextUsedPercentage;
  final String? currentDirectory;
  final String? claudeCodeVersion;
  final String? sessionId;

  bool get hasRateLimits => windows.isNotEmpty;

  /// Tolerant parser — every field is optional per the Claude Code docs.
  static StatusLineData fromJson(Map<String, dynamic> json, DateTime observedAt) {
    final windows = <LimitWindow>[];
    final rl = json['rate_limits'];
    if (rl is Map) {
      rl.forEach((key, value) {
        if (value is! Map) return;
        final used = value['used_percentage'];
        final reset = value['resets_at'];
        if (used is! num) return;
        windows.add(LimitWindow(
          id: key.toString(),
          label: LimitWindow.labelFor(key.toString()),
          usedPercentage: used.toDouble(),
          resetsAt: reset is num
              ? DateTime.fromMillisecondsSinceEpoch((reset * 1000).round(), isUtc: true).toLocal()
              : (reset is String ? DateTime.tryParse(reset)?.toLocal() : null),
          observedAt: observedAt,
          source: DataSource.statusLine,
        ));
      });
    }

    final model = json['model'];
    final ctx = json['context_window'];
    final ws = json['workspace'];
    final ctxUsed = ctx is Map ? ctx['used_percentage'] : null;

    return StatusLineData(
      observedAt: observedAt,
      windows: windows,
      modelDisplayName: model is Map ? model['display_name']?.toString() : null,
      contextUsedPercentage: ctxUsed is num ? ctxUsed.toDouble() : null,
      currentDirectory: ws is Map ? ws['current_dir']?.toString() : null,
      claudeCodeVersion: json['version']?.toString(),
      sessionId: json['session_id']?.toString(),
    );
  }
}
