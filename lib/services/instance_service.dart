import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/services/app_paths.dart';
import 'single_instance_lock.dart';

/// Keeps the app to one running copy.
///
/// The first instance claims a named kernel mutex ([SingleInstanceLock]) and
/// holds it for its whole lifetime; Windows releases it when the process ends,
/// however it ends. Any later copy is told the mutex already exists, drops a
/// `wake` marker so the running copy comes forward, and exits before it creates
/// a window or a tray icon — so the Claude Code hook, "Start with Windows", the
/// launcher and a double-click in Explorer can all fire without ever showing
/// the monitor twice.
///
/// A file lock on `instance.lock` is kept as a fallback and as a visible marker
/// of the live process, but it is not the guard: two copies starting in the
/// same instant were repeatedly observed taking that lock simultaneously, each
/// then building its own tray icon. The kernel serialises mutex creation, so it
/// cannot go the same way.
class InstanceService {
  /// The lock handle and the service itself are held **statically**, for the
  /// life of the process, and that is load-bearing: a [RandomAccessFile] that
  /// becomes unreachable is closed by the garbage collector's finalizer, and
  /// closing the file releases the OS lock with it. Held only in a local, the
  /// guard quietly evaporated a few seconds after startup and every later copy
  /// sailed straight through — which is exactly how the tray filled up with
  /// duplicate icons.
  static RandomAccessFile? _lock;
  static InstanceService? _held;
  StreamSubscription<FileSystemEvent>? _watch;
  Timer? _wakeDebounce;

  /// `true` when this process is (now) the single instance.
  ///
  /// A named kernel mutex decides this: it is the one check Windows serialises,
  /// so a burst of simultaneous launches produces exactly one winner. The file
  /// lock below is only the fallback for the case where the mutex is somehow
  /// unavailable.
  Future<bool> acquire() async {
    final viaMutex = SingleInstanceLock.tryAcquire();
    if (viaMutex != null) {
      // Still take the lock file when we won, so anything inspecting the app's
      // folder can see which process is live.
      if (viaMutex) unawaited(_takeLockFile());
      return viaMutex;
    }
    // Only Windows is expected to have the mutex; elsewhere the file lock is
    // the intended guard, so this is not worth recording as a problem.
    if (Platform.isWindows) _note('named mutex unavailable; falling back to the lock file');
    return _acquireViaLockFile();
  }

  Future<void> _takeLockFile() async {
    try {
      await _acquireViaLockFile();
    } catch (_) {}
  }

  /// Opening the lock file can fail transiently when several copies start in
  /// the same instant, so a failure to *open* is retried before it is believed.
  /// A failure to *lock* is final: that is another copy holding it.
  Future<bool> _acquireViaLockFile() async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      RandomAccessFile file;
      try {
        await AppPaths.ensureAppDataDir();
        // Append: creates the file when missing and never truncates a file the
        // running copy holds a byte-range lock on.
        file = await File(AppPaths.instanceLockFile).open(mode: FileMode.append);
      } catch (e) {
        lastError = e;
        await Future<void>.delayed(const Duration(milliseconds: 120));
        continue;
      }
      try {
        // Non-blocking: throws at once when another process holds the lock.
        await file.lock(FileLock.exclusive);
      } catch (_) {
        await file.close();
        return false;
      }
      _lock = file;
      _held = this;
      return true;
    }

    // The lock file is unusable (locked folder, AV, odd profile). Fall back to
    // a process check instead of silently allowing a second tray icon: start
    // only when nothing else of ours is running.
    debugPrint('Instance lock unavailable: ${lastError.runtimeType}');
    final other = await _anotherCopyRunning();
    _note('lock file unusable (${lastError.runtimeType}); otherCopyRunning=$other');
    return !other;
  }

  /// Records the rare case where the lock file could not be used at all, so a
  /// duplicate tray icon can be explained after the fact. Normal startups write
  /// nothing, so this file stays empty on a healthy machine.
  static void _note(String line) {
    try {
      File(p.join(AppPaths.appDataDir, 'instance-problems.log'))
          .writeAsStringSync('${DateTime.now().toIso8601String()} pid=$pid $line\n', mode: FileMode.append);
    } catch (_) {}
  }

  /// Ask the running copy to show itself (used by a second copy before it exits).
  Future<void> wakeOther() async {
    try {
      await File(AppPaths.wakeFile).writeAsString(DateTime.now().toIso8601String());
    } catch (_) {}
  }

  /// Watch the app-data folder for the two markers other processes drop there:
  /// `wake` (a second copy or the Claude Code launch script asking the running
  /// copy to come forward) and `quit` (the launcher's "Turn OFF" / "Rebuild",
  /// which asks for a clean shutdown so the tray icon is removed properly
  /// instead of being left behind as a ghost by a forced kill).
  void watchMarkers({required VoidCallback onWake, required VoidCallback onQuit}) {
    final wakeName = p.basename(AppPaths.wakeFile).toLowerCase();
    final quitName = p.basename(AppPaths.quitFile).toLowerCase();
    try {
      _watch = Directory(AppPaths.appDataDir)
          .watch(events: FileSystemEvent.create | FileSystemEvent.modify)
          .listen(
        (event) {
          final name = p.basename(event.path).toLowerCase();
          if (name == quitName) {
            onQuit();
            return;
          }
          if (name != wakeName) return;
          _wakeDebounce?.cancel();
          _wakeDebounce = Timer(const Duration(milliseconds: 150), onWake);
        },
        onError: (Object e) => debugPrint('Marker watch error: ${e.runtimeType}'),
      );
    } catch (e) {
      debugPrint('Marker watch unavailable: ${e.runtimeType}');
    }
  }

  /// `true` when the OS already lists another process running this executable.
  Future<bool> _anotherCopyRunning() async {
    try {
      final exe = Platform.resolvedExecutable;
      if (Platform.isWindows) {
        final name = p.basename(exe).toLowerCase();
        final result = await Process.run(
          'tasklist',
          <String>['/fi', 'imagename eq $name', '/nh', '/fo', 'csv'],
        ).timeout(const Duration(seconds: 5));
        final out = (result.stdout is String ? result.stdout as String : '').toLowerCase();
        // Our own process is in the list too, so two or more rows means company.
        return '"$name"'.allMatches(out).length > 1;
      }
      final name = p.basename(exe);
      final result = await Process.run(
        'ps',
        <String>['-A', '-o', 'comm='],
      ).timeout(const Duration(seconds: 5));
      final out = result.stdout is String ? result.stdout as String : '';
      var seen = 0;
      for (final line in out.split('\n')) {
        if (p.basename(line.trim()) == name) seen++;
      }
      // Ours is in the list too.
      return seen > 1;
    } catch (e) {
      debugPrint('Copy check failed: ${e.runtimeType}');
      return false;
    }
  }

  void dispose() {
    _wakeDebounce?.cancel();
    _watch?.cancel();
    if (identical(_held, this)) {
      _lock?.close();
      _lock = null;
      _held = null;
    }
  }
}
