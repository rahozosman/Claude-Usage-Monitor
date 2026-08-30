import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';

import '../core/constants/app_constants.dart';
import '../models/app_settings.dart';
import '../models/limit_window.dart';
import '../models/usage_snapshot.dart';
import 'settings_service.dart';

/// Windows toast notifications with once-per-window de-duplication.
///
/// State is keyed by `<windowId>:<resetsAt epoch>` so each threshold fires at
/// most once per usage window, even across app restarts.
class NotificationService {
  NotificationService(this._settings);

  final SettingsService _settings;
  late Map<String, dynamic> _state;
  bool _ready = false;

  /// Whether the system actually accepted us as a notifier. False means
  /// the setting can be on while nothing will ever be delivered.
  bool get ready => _ready;

  Future<void> init() async {
    _state = _settings.loadNotificationState();
    try {
      await localNotifier.setup(
        appName: AppConstants.appName,
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
      _ready = true;
    } catch (e) {
      debugPrint('Notification setup failed: ${e.runtimeType}');
      _ready = false;
    }
    _prune();
  }

  /// Threshold notifications for the current snapshot.
  Future<void> evaluate(UsageSnapshot snapshot, AppSettings settings) async {
    if (!settings.notificationsEnabled) return;
    final now = DateTime.now();
    for (final w in <LimitWindow>[snapshot.fiveHour, snapshot.weekly]) {
      // A closed window's last figure is history. Restoring one at 85% after a
      // restart must not raise a threshold alert for a window Claude has shut.
      if (!w.isActive(now) || w.resetsAt == null) continue;
      final key = _key(w);
      final fired = _firedSet(key);
      final used = w.usedPercentage!;
      final checks = <(int, bool)>[
        (80, settings.notifyAt80),
        (90, settings.notifyAt90),
        (100, settings.notifyAt100),
      ];
      for (final (threshold, enabled) in checks) {
        if (!enabled || used < threshold || fired.contains('$threshold')) continue;
        fired.add('$threshold');
        _state[key] = fired.toList();
        final title = threshold >= 100
            ? 'Claude ${_short(w)} limit reached'
            : 'Claude ${_short(w)} usage reached $threshold%';
        final body = w.resetsAt == null
            ? 'Usage is at ${used.toStringAsFixed(0)}%.'
            : 'Usage is at ${used.toStringAsFixed(0)}%. Resets ${_when(w.resetsAt!)}.';
        await _show(title, body);
      }
    }
    await _settings.saveNotificationState(_state);
  }

  /// Called from the 1-second ticker: fires "limit reset" exactly once when a
  /// window's reset time passes.
  Future<void> checkResets(UsageSnapshot snapshot, AppSettings settings, DateTime now) async {
    if (!settings.notificationsEnabled || !settings.notifyOnReset) return;
    var changed = false;
    for (final w in <LimitWindow>[snapshot.fiveHour, snapshot.weekly]) {
      if (w.resetsAt == null || !w.hasReset(now)) continue;
      final key = 'reset:${_key(w)}';
      if (_state.containsKey(key)) continue;
      _state[key] = true;
      changed = true;
      await _show('Claude ${_short(w)} limit reset', 'A new ${_short(w)} usage window has started.');
    }
    if (changed) await _settings.saveNotificationState(_state);
  }

  Future<void> showTest() => _show(AppConstants.appName, 'Notifications are working.');

  Future<void> _show(String title, String body) async {
    if (!_ready) return;
    try {
      await LocalNotification(title: title, body: body).show();
    } catch (e) {
      debugPrint('Notification failed: ${e.runtimeType}');
    }
  }

  String _key(LimitWindow w) => '${w.id}:${w.resetsAt!.millisecondsSinceEpoch}';

  Set<String> _firedSet(String key) {
    final v = _state[key];
    if (v is List) return v.map((e) => e.toString()).toSet();
    return <String>{};
  }

  String _short(LimitWindow w) => LimitWindow.spanFor(w.id);

  String _when(DateTime at) {
    final d = at.difference(DateTime.now());
    if (d.isNegative) return 'soon';
    if (d.inDays >= 1) return 'in ${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours >= 1) return 'in ${d.inHours}h ${d.inMinutes % 60}m';
    return 'in ${d.inMinutes}m';
  }

  /// Drops state older than 14 days so the map never grows unbounded.
  void _prune() {
    final cutoff = DateTime.now().subtract(const Duration(days: 14)).millisecondsSinceEpoch;
    _state.removeWhere((key, _) {
      final epoch = int.tryParse(key.split(':').last);
      return epoch != null && epoch < cutoff;
    });
  }
}
