import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/constants/app_constants.dart';

/// Watches whether any Claude Code CLI is still open, so the monitor can close
/// itself once the last one goes.
///
/// The counterpart of the `SessionStart` hook that opens the monitor: together
/// they make the app's lifetime match Claude Code's. A hook cannot do the
/// closing half reliably — `SessionEnd` never runs when a terminal window is
/// killed outright — so this polls the process list instead, which is true
/// however the CLI went away.
///
/// Two rules keep it from closing the app out from under someone:
///
/// * it never fires until it has actually seen a CLI running, so opening the
///   monitor on its own is not immediately undone;
/// * it needs [_missesBeforeQuit] consecutive empty polls, so the gap between
///   closing one session and starting another does not count as "all gone".
class ClaudeSessionWatcher {
  ClaudeSessionWatcher({required this.onAllSessionsClosed, this.enabled = true});

  /// Called once, when the last Claude Code session has gone.
  final VoidCallback onAllSessionsClosed;

  /// Mirrors the "Close with Claude Code" setting.
  bool enabled;

  static const Duration _interval = Duration(seconds: 15);
  static const int _missesBeforeQuit = 2;

  Timer? _timer;
  bool _everSeen = false;
  int _misses = 0;
  bool _fired = false;
  bool _checking = false;

  /// True once a Claude Code session has been seen since this app started.
  bool get sawSession => _everSeen;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => unawaited(_tick()));
    unawaited(_tick());
  }

  Future<void> _tick() async {
    if (_fired || _checking) return;
    _checking = true;
    try {
      final running = await anyRunning();
      if (running) {
        _everSeen = true;
        _misses = 0;
        return;
      }
      if (!_everSeen) return;
      if (++_misses < _missesBeforeQuit) return;
      _fired = true;
      // Still report the close even when the setting is off — the caller
      // decides what to do with it — but only act on it once.
      if (enabled) onAllSessionsClosed();
    } finally {
      _checking = false;
    }
  }

  /// Whether the OS currently lists a Claude Code CLI process.
  ///
  /// A failed or timed-out probe returns `true` (assume still open): a
  /// transient failure must never be read as "the user closed everything".
  ///
  /// On macOS this recognises the native `claude` binary. An npm-installed
  /// Claude Code runs under the name `node`, which cannot be told apart from
  /// any other Node process — there the watcher simply never sees a session
  /// and the monitor stays open, which is the safe way to be wrong.
  Future<bool> anyRunning() async {
    try {
      final name = AppConstants.claudeProcessName;
      if (Platform.isWindows) {
        final result = await Process.run(
          'tasklist',
          <String>['/fi', 'imagename eq $name', '/nh', '/fo', 'csv'],
        ).timeout(const Duration(seconds: 8));
        final out = (result.stdout is String ? result.stdout as String : '').toLowerCase();
        return out.contains('"${name.toLowerCase()}"');
      }
      // macOS/POSIX: match the process *name*, never the command line — this
      // app's own path contains "claude" and would happily match itself.
      final result = await Process.run(
        'ps',
        <String>['-A', '-o', 'comm='],
      ).timeout(const Duration(seconds: 8));
      final out = result.stdout is String ? result.stdout as String : '';
      for (final line in out.split('\n')) {
        if (p.basename(line.trim()) == name) return true;
      }
      return false;
    } catch (e) {
      debugPrint('Claude session check failed: ${e.runtimeType}');
      return true;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
