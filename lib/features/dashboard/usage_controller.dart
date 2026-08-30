import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/errors/app_error.dart';
import '../../models/connection_status.dart';
import '../../models/limit_window.dart';
import '../../models/usage_series.dart';
import '../../models/usage_snapshot.dart';
import '../../repositories/usage_repository.dart';
import '../../services/notification_service.dart';
import '../../services/refresh_service.dart';
import '../settings/settings_controller.dart';

/// Drives refreshes and exposes the latest [UsageSnapshot].
///
/// * Data refresh runs on the configured interval (cheap local reads).
/// * API probes run on their own slower cadence.
/// * The 1-second [clock] only ticks while the window is visible, and only
///   countdown widgets listen to it — the rest of the tree never rebuilds
///   per second.
class UsageController extends ChangeNotifier {
  UsageController({
    required UsageRepository repository,
    required SettingsController settings,
    required NotificationService notifications,
    required RefreshService refreshService,
  }) : _repo = repository,
       _settings = settings, // ignore: prefer_initializing_formals
       _notifications = notifications, // ignore: prefer_initializing_formals
       _refresh = refreshService;

  final UsageRepository _repo;
  final SettingsController _settings;
  final NotificationService _notifications;
  final RefreshService _refresh;

  final ValueNotifier<DateTime> clock = ValueNotifier<DateTime>(DateTime.now());

  UsageSnapshot _snapshot = UsageSnapshot.initial();
  bool _refreshing = false;
  bool _activityBusy = false;
  bool _probingApi = false;
  bool _queued = false;
  bool _queuedProbe = false;
  Timer? _ticker;
  Timer? _resetRefresh;
  final Set<String> _handledResets = <String>{};
  int _refreshCount = 0;
  DateTime? _lastApiProbeAt;

  UsageSnapshot get snapshot => _snapshot;
  bool get refreshing => _refreshing;
  bool get probingApi => _probingApi;
  int get refreshCount => _refreshCount;
  DateTime? get lastApiProbeAt => _lastApiProbeAt;
  bool get apiConfigured => _repo.apiConfigured;
  bool get adminConfigured => _repo.adminConfigured;
  bool get localScanning => _repo.localScanning;

  /// Recorded observations behind the pace card. Changes only on a
  /// refresh, which already notifies listeners.
  UsageHistory get history => _repo.history;

  AppError? get primaryError => _snapshot.subscriptionError ?? _snapshot.apiError;

  void start() {
    _settings.addListener(_onSettingsChanged);
    _configureTimers();
    unawaited(refresh(probeApi: true));
  }

  void _onSettingsChanged() => _configureTimers();

  /// How often the local/shared activity picture is refreshed while device
  /// sharing is on. Publishing this often is what makes the other devices'
  /// sessions show up in near-real time.
  static const Duration _activityTick = Duration(seconds: 15);

  void _configureTimers() {
    final s = _settings.settings;
    final activity = s.deviceSyncEnabled
        ? ((s.refreshInterval.duration ?? _activityTick) < _activityTick ? s.refreshInterval.duration : _activityTick)
        : null;
    _refresh.configure(
      dataInterval: s.refreshInterval.duration,
      apiInterval: s.apiProbeInterval.duration,
      activityInterval: activity,
      onData: () => unawaited(refresh()),
      onApi: () => unawaited(refresh(probeApi: true)),
      onActivity: () => unawaited(refreshActivity()),
    );
  }

  /// Fast, cheap tick: local transcripts + the shared device folder only.
  /// Skipped while a full refresh is running so the two never fight.
  Future<void> refreshActivity() async {
    if (_refreshing || _activityBusy) return;
    _activityBusy = true;
    try {
      _snapshot = await _repo.refreshActivity(settings: _settings.settings, previous: _snapshot);
      notifyListeners();
    } catch (e) {
      debugPrint('activity tick failed: ${e.runtimeType}');
    } finally {
      _activityBusy = false;
    }
  }

  Future<void> refresh({bool probeApi = false, bool force = false}) async {
    if (_refreshing) {
      _queued = true;
      _queuedProbe = _queuedProbe || probeApi;
      return;
    }
    _refreshing = true;
    _probingApi = probeApi;
    notifyListeners();
    try {
      final settings = _settings.settings;
      final next = await _repo.fetch(settings: settings, previous: _snapshot, probeApi: probeApi, force: force);
      _snapshot = next;
      _refreshCount++;
      if (probeApi && (next.api != null || next.apiReport != null)) {
        _lastApiProbeAt = DateTime.now();
      }
      await _notifications.evaluate(next, settings);
      await _notifications.checkResets(next, settings, DateTime.now());
    } catch (e, st) {
      debugPrint('refresh failed: ${e.runtimeType}\n$st');
      _snapshot = _snapshot.copyWith(
        connection: ConnectionStatus.error,
        lastAttempt: DateTime.now(),
        subscriptionError: AppError(AppErrorKind.unknown, 'Refresh failed', detail: e.runtimeType.toString()),
      );
    } finally {
      _refreshing = false;
      _probingApi = false;
      notifyListeners();
      if (_queued) {
        _queued = false;
        final probe = _queuedProbe;
        _queuedProbe = false;
        unawaited(refresh(probeApi: probe));
      }
    }
  }

  /// Start/stop the per-second clock. Called by the shell on show/hide.
  void setTicking(bool on) {
    if (on) {
      if (_ticker != null) return;
      _tick();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _tick() {
    final now = DateTime.now();
    clock.value = now;
    for (final w in <LimitWindow>[_snapshot.fiveHour, _snapshot.weekly, ..._snapshot.extraWindows]) {
      if (w.resetsAt == null || !w.hasReset(now)) continue;
      final key = '${w.id}:${w.resetsAt!.millisecondsSinceEpoch}';
      if (_handledResets.add(key)) _onWindowReset();
    }
  }

  /// A window just reset: notify once, then refresh so bars/reset times update.
  void _onWindowReset() {
    unawaited(_notifications.checkResets(_snapshot, _settings.settings, DateTime.now()));
    _resetRefresh?.cancel();
    _resetRefresh = Timer(const Duration(seconds: 3), () => unawaited(refresh(force: true)));
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    _ticker?.cancel();
    _resetRefresh?.cancel();
    _refresh.dispose();
    clock.dispose();
    super.dispose();
  }
}
