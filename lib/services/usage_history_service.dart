import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/services/app_paths.dart';
import '../models/limit_window.dart';
import '../models/usage_series.dart';

/// Keeps what Claude reported, so the app can say more than "right now".
///
/// Without this the monitor is a gauge: it reads a percentage 2,880 times a
/// day at the default interval and remembers none of it, so it can never
/// answer the question that actually matters — *will I run out before the
/// window resets?*
///
/// Storage is one JSON object per line in `history.jsonl`, appended to. A
/// growing series is the wrong shape for SharedPreferences, which rewrites
/// its whole blob on every change; appending a 40-byte line is not.
class UsageHistoryService {
  /// How far back the file is kept. The card needs a week; the rest is
  /// headroom, and 60 days of changes still comes to well under a megabyte.
  static const Duration retention = Duration(days: 60);

  /// A defensive ceiling in case something ever appends in a loop. Reaching
  /// it costs the oldest records, never a refresh.
  static const int maxReadings = 200000;

  /// Only the day the window peaked matters for the 7-day strip, so the
  /// readings behind it are grouped by local calendar day.
  static const int peakDays = 7;

  final List<UsageReading> _readings = <UsageReading>[];
  final Map<String, UsageReading> _lastByWindow = <String, UsageReading>{};
  UsageHistory _history = UsageHistory.empty;

  /// Recomputed on append, never per frame: the card reads a prepared object.
  UsageHistory get history => _history;

  /// The newest reading recorded for each window, from this run or from the
  /// file loaded at startup. The repository seeds a window Claude is not
  /// currently reporting from these, so a restart does not turn a known
  /// figure into "Unavailable".
  Iterable<UsageReading> get lastKnown => _lastByWindow.values;

  /// Loads the file and prunes it once. Never throws — a history that cannot
  /// be read costs one card, and must not cost the app its startup.
  Future<void> init() async {
    try {
      final file = File(AppPaths.historyFile);
      if (await file.exists()) {
        final now = DateTime.now();
        final cutoff = now.subtract(retention);
        var dropped = 0;
        for (final line in const LineSplitter().convert(await file.readAsString())) {
          final reading = _decode(line);
          // A torn last line (power loss mid-append) parses to null and is
          // simply not there; every other line is unaffected.
          if (reading == null) {
            dropped++;
            continue;
          }
          if (reading.observedAt.isBefore(cutoff)) {
            dropped++;
            continue;
          }
          _readings.add(reading);
        }
        _readings.sort((a, b) => a.observedAt.compareTo(b.observedAt));
        if (_readings.length > maxReadings) {
          _readings.removeRange(0, _readings.length - maxReadings);
          dropped++;
        }
        // One rewrite at startup, and only when something actually went.
        if (dropped > 0) await _rewrite();
      }
      for (final reading in _readings) {
        _lastByWindow[reading.windowId] = reading;
      }
      _rebuild();
    } catch (e) {
      debugPrint('History load failed: ${e.runtimeType}');
    }
  }

  /// Appends anything that changed since the last call.
  ///
  /// A window carried forward unchanged (the repository keeps the last known
  /// value when a source goes quiet) writes nothing: same instant, same
  /// number, nothing observed.
  Future<void> record(Iterable<LimitWindow> windows, DateTime now) async {
    final fresh = <UsageReading>[];
    for (final window in windows) {
      final percentage = window.usedPercentage;
      final observedAt = window.observedAt;
      if (percentage == null || observedAt == null) continue;
      if (observedAt.isAfter(now.add(const Duration(minutes: 5)))) continue; // nonsense clock
      final reading = UsageReading(
        windowId: window.id,
        percentage: percentage,
        observedAt: observedAt,
        resetsAt: window.resetsAt,
        source: window.source,
      );
      if (_isSameAsLast(reading)) continue;
      fresh.add(reading);
    }
    if (fresh.isEmpty) return;

    for (final reading in fresh) {
      _readings.add(reading);
      _lastByWindow[reading.windowId] = reading;
    }
    _rebuild();
    try {
      await AppPaths.ensureAppDataDir();
      await File(AppPaths.historyFile).writeAsString(
        '${fresh.map((r) => jsonEncode(r.toJson())).join('\n')}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (e) {
      // The in-memory series is already correct for this session; only the
      // record of it is lost, and the next append tries again.
      debugPrint('History append failed: ${e.runtimeType}');
    }
  }

  bool _isSameAsLast(UsageReading reading) {
    final last = _lastByWindow[reading.windowId];
    if (last == null) return false;
    // Not newer means the same observation, seen again.
    if (!reading.observedAt.isAfter(last.observedAt)) return true;
    return (reading.percentage - last.percentage).abs() < 0.005 && reading.resetsAt == last.resetsAt;
  }

  void _rebuild() {
    if (_readings.isEmpty) {
      _history = UsageHistory.empty;
      return;
    }
    final byWindow = <String, List<UsageReading>>{};
    for (final reading in _readings) {
      byWindow.putIfAbsent(reading.windowId, () => <UsageReading>[]).add(reading);
    }
    _history = UsageHistory(
      series: <String, UsageSeries>{
        for (final entry in byWindow.entries) entry.key: UsageSeries.build(entry.key, entry.value),
      },
      dailyPeaks: _peaks(byWindow[LimitWindow.fiveHourId] ?? const <UsageReading>[]),
      totalReadings: _readings.length,
      oldest: _readings.first.observedAt,
      newest: _readings.last.observedAt,
    );
  }

  /// The highest reading on each of the last [peakDays] local days that has
  /// any. Days the app never ran are absent rather than zero — nothing was
  /// observed, which is not the same as nothing was used.
  List<DailyPeak> _peaks(List<UsageReading> readings) {
    if (readings.isEmpty) return const <DailyPeak>[];
    final today = DateTime.now();
    final midnight = DateTime(today.year, today.month, today.day);
    final from = midnight.subtract(Duration(days: peakDays - 1));
    final byDay = <DateTime, List<double>>{};
    for (final reading in readings) {
      final at = reading.observedAt;
      final day = DateTime(at.year, at.month, at.day);
      if (day.isBefore(from)) continue;
      byDay.putIfAbsent(day, () => <double>[]).add(reading.percentage);
    }
    final days = byDay.keys.toList()..sort();
    return <DailyPeak>[
      for (final day in days)
        DailyPeak(
          day: day,
          peak: byDay[day]!.reduce((a, b) => a > b ? a : b),
          readings: byDay[day]!.length,
        ),
    ];
  }

  Future<void> _rewrite() async {
    final file = File(AppPaths.historyFile);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(_readings.map((r) => jsonEncode(r.toJson())).join('\n') + (_readings.isEmpty ? '' : '\n'));
    await tmp.rename(file.path);
  }

  static UsageReading? _decode(String line) {
    final text = line.trim();
    if (text.isEmpty) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return null;
      return UsageReading.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }
}
