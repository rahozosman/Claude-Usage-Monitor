import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

/// A named Windows kernel mutex — the canonical single-instance primitive.
///
/// A byte-range lock on a file was not good enough here: under a burst of
/// simultaneous launches (the Claude Code hook firing for two sessions, an
/// impatient double-click) two copies were repeatedly observed taking the same
/// file lock, and each then built its own window and tray icon. Creating a
/// named mutex is serialised by the kernel, so exactly one process is ever told
/// it created the object; every other copy is told it already existed.
///
/// The handle is deliberately never closed: Windows releases it when the
/// process ends, however it ends, and holding it in a static keeps the garbage
/// collector from releasing the guard early.
class SingleInstanceLock {
  SingleInstanceLock._();

  /// `Local\` scopes the name to this login session, so two signed-in users
  /// each get their own monitor.
  static const String _name = r'Local\ClaudeUsageMonitor.singleton';

  static const int _errorAlreadyExists = 183;

  static int? _handle;

  /// Whether this process holds the guard.
  static bool get held => _handle != null;

  /// `true` when this process is the first (and therefore the only) copy,
  /// `false` when another copy already holds it, and `null` when the mutex
  /// could not be used at all — the caller then falls back to a weaker check
  /// rather than refusing to start.
  static bool? tryAcquire() {
    if (!Platform.isWindows) return null;
    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      final createMutex = kernel32.lookupFunction<
          IntPtr Function(Pointer<Void>, Int32, Pointer<Utf16>),
          int Function(Pointer<Void>, int, Pointer<Utf16>)>('CreateMutexW');
      final getLastError = kernel32.lookupFunction<Uint32 Function(), int Function()>('GetLastError');

      final name = _name.toNativeUtf16();
      try {
        final handle = createMutex(nullptr, 0, name);
        final lastError = getLastError();
        if (handle == 0) {
          debugPrint('CreateMutexW failed: $lastError');
          return null;
        }
        if (lastError == _errorAlreadyExists) return false;
        _handle = handle; // held for the life of the process
        return true;
      } finally {
        malloc.free(name);
      }
    } catch (e) {
      debugPrint('Single-instance mutex unavailable: ${e.runtimeType}');
      return null;
    }
  }
}
