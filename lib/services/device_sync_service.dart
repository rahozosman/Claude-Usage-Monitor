import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/services/app_paths.dart';
import '../models/app_settings.dart';
import '../models/device_activity.dart';
import '../models/session_usage.dart';

/// Cross-device activity through a shared, synced folder (OneDrive by default).
///
/// Claude does not expose per-device sessions anywhere — the status line and
/// the transcripts are per machine and the usage endpoint is one combined
/// number — so each monitor publishes its *own* real local activity as
/// `<hostname>.json` into the folder, and reads every other device's file
/// back. No estimation, no invented numbers: if a device has not reported,
/// it is simply not shown.
class DeviceSyncService {
  DateTime? _lastPublish;
  String? _lastFingerprint;
  String? _deviceId;

  /// Near-real-time: republish on this cadence, and immediately whenever the
  /// local picture actually changed. The floor is the shared folder's own sync
  /// lag, which no app can beat.
  static const Duration _publishEvery = Duration(seconds: 15);
  static const Duration _forgetAfter = Duration(days: 30);

  /// Every open session is always published; finished ones are capped.
  static const int _maxIdleSessions = 8;

  /// The machine's name - a label, never an identity.
  String get deviceName {
    try {
      final host = Platform.localHostname.trim();
      if (host.isNotEmpty) return host;
    } catch (_) {
      // Some macOS network states make this throw rather than answer.
    }
    return 'This device';
  }

  /// A stable id for this machine, kept next to the app's own files.
  ///
  /// The hostname cannot serve as the identity: macOS reports the Bonjour
  /// name, which flips between `Name.local` and `Name` and changes with the
  /// network or a rename. Keyed on that, one Mac publishes under two file
  /// names and then lists *itself* as another device for a month. The id is
  /// generated once and never changes; the hostname is still published, as a
  /// label the user recognises.
  Future<String> _resolveDeviceId() async {
    final cached = _deviceId;
    if (cached != null) return cached;
    final file = File(AppPaths.deviceIdFile);
    try {
      if (await file.exists()) {
        final existing = _fileSafe(await file.readAsString());
        if (existing.isNotEmpty) return _deviceId = existing;
      }
    } catch (_) {
      // Unreadable: fall through and mint a new one.
    }
    final random = Random.secure();
    final generated = _fileSafe(
      List<int>.generate(8, (_) => random.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
    );
    try {
      await AppPaths.ensureAppDataDir();
      await file.writeAsString(generated);
    } catch (_) {
      // Still usable for this run, just not stable across restarts.
    }
    return _deviceId = generated;
  }

  /// The id ends up in a file name, so it may only ever be plain characters.
  static String _fileSafe(String value) {
    final cleaned = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '');
    return cleaned.length > 64 ? cleaned.substring(0, 64) : cleaned;
  }

  /// Hostnames are compared with the macOS `.local` suffix removed, so the
  /// same Mac seen under both spellings is still recognised as this machine.
  static String _normalizeName(String value) {
    final lower = value.trim().toLowerCase();
    return lower.endsWith('.local') ? lower.substring(0, lower.length - 6) : lower;
  }

  /// The folder to use: the user's own choice, else a synced cloud folder.
  String? resolveFolder(AppSettings settings) {
    final custom = settings.deviceSyncFolder?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    final root = _cloudRoot();
    if (root == null || root.isEmpty) return null;
    return p.join(root, 'ClaudeUsageMonitor', 'devices');
  }

  /// A folder that syncs between the user's own machines.
  ///
  /// Windows advertises OneDrive through the environment. macOS does not: it
  /// mounts providers under `~/Library/CloudStorage`, so OneDrive is looked
  /// for there first (to keep both platforms on the same folder when the user
  /// has it) before falling back to iCloud Drive.
  String? _cloudRoot() {
    final env =
        Platform.environment['OneDrive'] ??
        Platform.environment['OneDriveConsumer'] ??
        Platform.environment['OneDriveCommercial'];
    if (env != null && env.isNotEmpty) return env;
    if (!Platform.isMacOS) return null;
    final home = AppPaths.home;
    try {
      final cloud = Directory(p.join(home, 'Library', 'CloudStorage'));
      if (cloud.existsSync()) {
        for (final entry in cloud.listSync()) {
          if (entry is Directory && p.basename(entry.path).startsWith('OneDrive')) {
            return entry.path;
          }
        }
      }
    } catch (_) {}
    for (final candidate in <String>[
      p.join(home, 'OneDrive'),
      p.join(home, 'Library', 'Mobile Documents', 'com~apple~CloudDocs'),
    ]) {
      if (Directory(candidate).existsSync()) return candidate;
    }
    return null;
  }

  Future<DeviceSyncResult> sync({
    required AppSettings settings,
    required LocalUsageReport? local,
    required DateTime now,
  }) async {
    final folder = resolveFolder(settings);
    final name = deviceName;
    if (!settings.deviceSyncEnabled) {
      return DeviceSyncResult(folder: folder, enabled: false, thisDeviceName: name);
    }
    if (folder == null) return DeviceSyncResult(thisDeviceName: name);

    final id = await _resolveDeviceId();
    final dir = Directory(folder);
    try {
      await dir.create(recursive: true);
    } catch (e) {
      debugPrint('Device folder unavailable: ${e.runtimeType}');
      return DeviceSyncResult(
        folder: folder,
        thisDeviceName: name,
        error: 'Could not open the shared folder (${e.runtimeType}). Check that it exists and is not offline.',
      );
    }

    // Publishing and reading are deliberately kept apart. A cloud client
    // holding our own file open is routine and transient, and it must not
    // cost the user every other device's report - which was readable the
    // whole time it was happening.
    String? publishError;
    if (local != null) {
      try {
        await _publish(dir, id, name, local, now);
      } catch (e) {
        debugPrint('Device publish failed: ${e.runtimeType}');
        publishError = 'This device could not publish just now (${e.runtimeType}) - it retries on the next pass.';
      }
    }

    try {
      final devices = await _readOthers(dir, id, name, now);
      return DeviceSyncResult(
        folder: folder,
        devices: devices,
        thisDeviceName: name,
        publishedAt: _lastPublish,
        publishError: publishError,
      );
    } catch (e) {
      debugPrint('Device sync failed: ${e.runtimeType}');
      return DeviceSyncResult(
        folder: folder,
        thisDeviceName: name,
        publishedAt: _lastPublish,
        publishError: publishError,
        error: 'Could not read the shared folder (${e.runtimeType}).',
      );
    }
  }

  /// What another device would actually see change: which sessions are open,
  /// on which model, and how far each has got.
  static String _fingerprint(LocalUsageReport local) {
    final parts = <String>[
      '${local.activeSessionCount}',
      '${local.todayTotal}',
      for (final s in local.sessions.where((s) => s.isActive)) '${s.sessionId}:${s.totalTokens}:${s.latestModel ?? ''}',
    ];
    return parts.join('|');
  }

  Future<void> _publish(Directory dir, String id, String name, LocalUsageReport local, DateTime now) async {
    final last = _lastPublish;
    final fingerprint = _fingerprint(local);
    final changed = fingerprint != _lastFingerprint;
    if (last != null && now.difference(last) < _publishEvery && !changed) return;

    // Open sessions first so a device with many finished tasks still reports
    // everything it currently has running.
    final ordered = <SessionUsage>[
      ...local.sessions.where((s) => s.isActive),
      ...local.sessions.where((s) => !s.isActive).take(_maxIdleSessions),
    ];

    final me = DeviceActivity(
      deviceId: id,
      name: name,
      user: Platform.environment['USERNAME'] ?? Platform.environment['USER'],
      platform: Platform.operatingSystem,
      updatedAt: now.toUtc(),
      activeSessions: local.activeSessionCount,
      todaySessionCount: local.todaySessionCount,
      todayTokens: local.todayTotal,
      weekTokens: local.weekTotal,
      todayTokensByModel: local.todayTokensByModel,
      sessions: ordered
          .map(
            (s) => DeviceSession(
              title: s.title,
              project: s.projectName,
              models: s.models,
              tokens: s.totalTokens,
              outputTokens: s.outputTokens,
              messages: s.messageCount,
              lastAt: s.lastAt,
              active: s.isActive,
              latestModel: s.latestModel,
            ),
          )
          .toList(),
    );

    final target = File(p.join(dir.path, '$id.json'));
    final tmp = File('${target.path}.$pid.tmp');
    try {
      await tmp.writeAsString(jsonEncode(me.toJson()));
      await tmp.rename(target.path);
    } catch (_) {
      // Never leave a half-written file behind in a folder that syncs: every
      // other device replicates the litter, and nothing ever expires it.
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      rethrow;
    }
    _lastPublish = now;
    _lastFingerprint = fingerprint;
  }

  Future<List<DeviceActivity>> _readOthers(Directory dir, String id, String name, DateTime now) async {
    final devices = <DeviceActivity>[];
    final seen = <String>{};
    final me = _normalizeName(name);
    await for (final entry in dir.list(followLinks: false)) {
      if (entry is! File || p.extension(entry.path).toLowerCase() != '.json') continue;
      final base = p.basenameWithoutExtension(entry.path).toLowerCase();
      // Ours by file name, or one an older build of this app named after the
      // hostname, before the id was stable.
      if (base == id.toLowerCase() || _normalizeName(base) == me) continue;
      try {
        final decoded = jsonDecode(await entry.readAsString());
        if (decoded is! Map<String, dynamic>) continue;
        final device = DeviceActivity.fromJson(decoded);
        if (device == null || device.deviceId.toLowerCase() == id.toLowerCase()) continue;
        // The same machine reporting under a previous identity: showing the
        // user their own PC as a second device is worse than showing nothing.
        if (_normalizeName(device.name) == me) continue;
        if (now.toUtc().difference(device.updatedAt) > _forgetAfter) continue;
        if (!seen.add(device.deviceId.toLowerCase())) continue;
        devices.add(device);
      } catch (_) {
        // A half-synced or foreign file: skip it, never fail the refresh.
      }
    }
    devices.sort((a, b) {
      final activeCmp = (b.isActive(now) ? 1 : 0).compareTo(a.isActive(now) ? 1 : 0);
      return activeCmp != 0 ? activeCmp : b.updatedAt.compareTo(a.updatedAt);
    });
    return devices;
  }
}
