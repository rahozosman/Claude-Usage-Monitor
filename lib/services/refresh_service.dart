import 'dart:async';

import 'package:flutter/foundation.dart';

/// Owns the periodic timers. Three independent cadences:
/// * data refresh (cheap local reads + optional usage endpoint)
/// * API probe (costs a real request — kept slow by default)
/// * activity (local transcripts + the shared device folder) — fast, so other
///   devices see what this one is doing in near-real time
///
/// Nothing here runs every second; the countdown ticker lives in the
/// controller and only runs while the window is visible.
class RefreshService {
  Timer? _dataTimer;
  Timer? _apiTimer;
  Timer? _activityTimer;

  void configure({
    required Duration? dataInterval,
    required Duration? apiInterval,
    required Duration? activityInterval,
    required VoidCallback onData,
    required VoidCallback onApi,
    required VoidCallback onActivity,
  }) {
    _dataTimer?.cancel();
    _apiTimer?.cancel();
    _activityTimer?.cancel();
    _dataTimer = dataInterval == null ? null : Timer.periodic(dataInterval, (_) => onData());
    _apiTimer = apiInterval == null ? null : Timer.periodic(apiInterval, (_) => onApi());
    _activityTimer = activityInterval == null ? null : Timer.periodic(activityInterval, (_) => onActivity());
  }

  void dispose() {
    _dataTimer?.cancel();
    _apiTimer?.cancel();
    _activityTimer?.cancel();
    _dataTimer = null;
    _apiTimer = null;
    _activityTimer = null;
  }
}
