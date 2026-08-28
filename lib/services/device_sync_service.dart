import 'dart:convert';
import 'dart:io';

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

  /// Near-real-time: republish on this cadence, and immediately whenever the
  /// local picture actually changed. The floor is the shared folder's own sync
  /// lag, which no app can beat.
  static const Duration _publishEvery = Duration(seconds: 15);
  static const Duration _forgetAfter = Duration(days: 30);

  /// Every open session is always published; finished ones are capped.
  static const int _maxIdleSessions = 8;

  String get deviceId => Platform.localHostname;

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
    if (!settings.deviceSyncEnabled) return DeviceSyncResult(folder: folder, enabled: false);
    if (folder == null) return const DeviceSyncResult();

    try {
      final dir = Directory(folder);
      await dir.create(recursive: true);
      if (local != null) await _publish(dir, local, now);
      final devices = await _readOthers(dir, now);
      return DeviceSyncResult(folder: folder, devices: devices);
    } catch (e) {
      debugPrint('Device sync failed: ${e.runtimeType}');
      return DeviceSyncResult(folder: folder, error: 'Could not read the shared folder (${e.runtimeType}).');
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

  Future<void> _publish(Directory dir, LocalUsageReport local, DateTime now) async {
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
      deviceId: deviceId,
      name: deviceId,
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

    final target = File(p.join(dir.path, '$deviceId.json'));
    final tmp = File('${target.path}.$pid.tmp');
    await tmp.writeAsString(jsonEncode(me.toJson()));
    await tmp.rename(target.path);
    _lastPublish = now;
    _lastFingerprint = fingerprint;
  }

  Future<List<DeviceActivity>> _readOthers(Directory dir, DateTime now) async {
    final devices = <DeviceActivity>[];
    await for (final entry in dir.list(followLinks: false)) {
      if (entry is! File || p.extension(entry.path).toLowerCase() != '.json') continue;
      if (p.basenameWithoutExtension(entry.path).toLowerCase() == deviceId.toLowerCase()) continue;
      try {
        final decoded = jsonDecode(await entry.readAsString());
        if (decoded is! Map<String, dynamic>) continue;
        final device = DeviceActivity.fromJson(decoded);
        if (device == null || device.deviceId.toLowerCase() == deviceId.toLowerCase()) continue;
        if (now.toUtc().difference(device.updatedAt) > _forgetAfter) continue;
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
