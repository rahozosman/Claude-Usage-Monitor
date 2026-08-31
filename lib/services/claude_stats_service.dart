import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/services/app_paths.dart';
import '../models/usage_stats.dart';

/// Reads `~/.claude/stats-cache.json` — the file behind Claude Code's own
/// `/usage` → Overview tab.
///
/// The file is ~4 KB and this runs on the 15-second activity tick, so the
/// parse is skipped whenever the file has not changed. Nothing here throws:
/// a missing, locked or malformed file leaves the card saying so.
class ClaudeStatsService {
  UsageStats? _cached;
  DateTime? _modified;
  int? _size;

  /// Why the last read produced nothing, in the user's terms. Null once a
  /// read has succeeded.
  String? get unavailableReason => _cached != null ? null : _reason;
  String? _reason = 'Looking for Claude Code’s stats cache…';

  UsageStats? get last => _cached;

  Future<UsageStats?> read() async {
    final file = File(AppPaths.claudeStatsFile);
    try {
      if (!await file.exists()) {
        _reason =
            'Claude Code has not written its stats cache yet '
            '(${AppPaths.claudeStatsFile}) — open Claude Code and run /usage once.';
        return _cached;
      }
      final stat = await file.stat();
      // Same file, same size: the parsed copy is still the truth.
      if (_cached != null && stat.modified == _modified && stat.size == _size) return _cached;

      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        _reason = 'Claude Code’s stats cache is not in a shape this app recognises.';
        return _cached;
      }
      final stats = UsageStats.fromJson(decoded, stat.modified);
      if (stats == null) {
        _reason = 'Claude Code’s stats cache carries no usage yet — run /usage once.';
        return _cached;
      }
      _cached = stats;
      _modified = stat.modified;
      _size = stat.size;
      _reason = null;
      return stats;
    } catch (e) {
      // A half-written file (Claude Code rewrites it whole) or a locked one:
      // keep the last good parse rather than blanking the card.
      debugPrint('stats-cache read failed: ${e.runtimeType}');
      _reason ??= 'Claude Code’s stats cache could not be read (${e.runtimeType}).';
      return _cached;
    }
  }
}
