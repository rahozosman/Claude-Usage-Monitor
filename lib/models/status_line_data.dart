import '../core/utils/server_time.dart';
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

  /// The window ids this status line actually carried.
  ///
  /// Claude Code drops a window out of `rate_limits` entirely once it is no
  /// longer open — a payload with `seven_day` and no `five_hour` is normal,
  /// not broken — so "did the feed carry this window?" has to be asked per
  /// id. [hasRateLimits] answers it for the block as a whole and
  /// would call that payload complete.
  List<String> get windowIds => <String>[for (final w in windows) w.id];

  bool reported(String id) => windows.any((w) => w.id == id);

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
          // Straight from Claude Code's own JSON, never derived.
          resetsAt: ServerTime.parse(reset),
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
