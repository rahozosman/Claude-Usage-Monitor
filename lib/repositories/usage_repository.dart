import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import '../core/errors/app_error.dart';
import '../models/api_rate_limits.dart';
import '../models/api_usage_report.dart';
import '../models/app_settings.dart';
import '../models/cli_status.dart';
import '../models/connection_status.dart';
import '../models/limit_window.dart';
import '../models/session_usage.dart';
import '../models/status_line_data.dart';
import '../models/usage_series.dart';
import '../models/usage_snapshot.dart';
import '../services/anthropic_api_service.dart';
import '../services/claude_cli_service.dart';
import '../services/device_sync_service.dart';
import '../services/local_usage_service.dart';
import '../services/oauth_usage_service.dart';
import '../services/settings_service.dart';
import '../services/usage_history_service.dart';

/// Combines every source into one [UsageSnapshot].
///
/// Source policy (subscription windows):
///  1. Claude Code status-line JSON (official) — read from the bridge file.
///  2. Usage endpoint (undocumented, opt-in) — only when enabled in Settings.
/// The freshest observation per window wins; nothing is estimated.
class UsageRepository {
  UsageRepository({
    required ClaudeCliService cli,
    required OAuthUsageService oauth,
    required AnthropicApiService api,
    required SettingsService settingsService,
    required LocalUsageService local,
    required UsageHistoryService history,
    DeviceSyncService? devices,
  }) : _cli = cli, // ignore: prefer_initializing_formals
       _history = history, // ignore: prefer_initializing_formals
       _local = local, // ignore: prefer_initializing_formals
       _devices = devices ?? DeviceSyncService(),
       _oauth = oauth, // ignore: prefer_initializing_formals
       _api = api, // ignore: prefer_initializing_formals
       _settingsService = settingsService; // ignore: prefer_initializing_formals

  final ClaudeCliService _cli;
  final OAuthUsageService _oauth;
  final AnthropicApiService _api;
  final SettingsService _settingsService;
  final LocalUsageService _local;
  final DeviceSyncService _devices;
  final UsageHistoryService _history;

  bool get localScanning => _local.scanning;

  /// Everything recorded so far, already grouped into windows and
  /// segments. Recomputed on append, not per frame.
  UsageHistory get history => _history.history;

  bool apiConfigured = false;
  bool adminConfigured = false;

  /// A cheap pass used by the fast activity timer: re-reads the local
  /// transcripts (incrementally) and exchanges files with the other devices.
  /// It starts no network requests of its own.
  Future<UsageSnapshot> refreshActivity({required AppSettings settings, required UsageSnapshot previous}) async {
    var local = previous.local;
    // Also scanned for sharing alone: the published file is built from this
    // report, so tying it to the card would make this device go quiet on every
    // other machine the moment the user hid the card.
    if (settings.showActivity || settings.deviceSyncEnabled) {
      try {
        local = await _local.scan() ?? local;
      } catch (_) {
        // Best-effort: never fail a tick over the transcripts.
      }
    }
    var devices = previous.devices;
    try {
      devices = await _devices.sync(settings: settings, local: local, now: DateTime.now());
    } catch (_) {
      // Best-effort: a folder that is syncing or locked just keeps the old view.
    }
    return previous.copyWith(local: local, devices: devices);
  }

  Future<UsageSnapshot> fetch({
    required AppSettings settings,
    required UsageSnapshot previous,
    required bool probeApi,
    bool force = false,
  }) async {
    final now = DateTime.now();

    // ---- Claude Code / subscription -----------------------------------------
    final cliStatus = await _cli.detect(force: force);
    final statusLine = await _cli.readStatusLineFile();
    final windows = <String, LimitWindow>{};
    AppError? subError;

    if (statusLine != null) {
      for (final w in statusLine.windows) {
        windows[w.id] = w;
      }
    }

    if (settings.useUsageEndpoint) {
      final token = await _cli.readOAuthAccessToken();
      if (token == null) {
        subError = const AppError(
          AppErrorKind.unauthenticated,
          'No Claude Code sign-in found — run `claude` and sign in',
        );
      } else if (cliStatus.tokenExpired) {
        subError = const AppError(
          AppErrorKind.tokenExpired,
          'Claude Code sign-in expired — open Claude Code once to refresh it',
        );
      } else {
        try {
          final result = await _oauth.fetch(token, force: force);
          _merge(windows, result.windows);
        } on AppError catch (e) {
          subError = e;
          final last = _oauth.lastResult;
          if (last != null) _merge(windows, last.windows);
        }
      }
    }

    // Retain last-known values when a source went quiet (UI marks them stale),
    // under the same age policy as the file below. Without the bound a window
    // that closed hours ago was re-injected on every refresh for the life of
    // the process, so its last percentage never went away.
    for (final prev in previous.allWindows) {
      if (!prev.isAvailable || windows.containsKey(prev.id)) continue;
      if (!_stillDescribesNow(prev.resetsAt, prev.observedAt, now)) continue;
      windows[prev.id] = prev;
    }

    // On the first refresh after a launch there is nothing to carry forward,
    // so a window Claude is not reporting right now would read "Unavailable"
    // even though the last figure it gave is on disk. Restoring it invents
    // nothing: it is the same observation, with the same timestamp, and the
    // card labels it reset or stale from the fields it always used.
    for (final reading in _history.lastKnown) {
      if (windows.containsKey(reading.windowId)) continue;
      if (!_worthRestoring(reading, now)) continue;
      windows[reading.windowId] = LimitWindow(
        id: reading.windowId,
        label: LimitWindow.labelFor(reading.windowId),
        usedPercentage: reading.percentage,
        resetsAt: reading.resetsAt,
        observedAt: reading.observedAt,
        source: reading.source,
      );
    }

    LimitWindow resolve(String id) =>
        windows.remove(id) ??
        LimitWindow.unavailable(
          id: id,
          label: LimitWindow.labelFor(id),
          reason: _unavailableReason(id, cliStatus, statusLine, settings, subError),
        );
    final fiveHour = resolve(LimitWindow.fiveHourId);
    final weekly = resolve(LimitWindow.sevenDayId);
    final extra = windows.values.toList()..sort((a, b) => a.id.compareTo(b.id));

    // Recorded here because this is where a window is fully resolved. Only
    // changes are stored, so a value carried forward writes nothing, and a
    // failure to record must never cost the refresh that produced it.
    try {
      await _history.record(<LimitWindow>[fiveHour, weekly, ...extra], now);
    } catch (e) {
      debugPrint('History record failed: ${e.runtimeType}');
    }

    // ---- Anthropic API --------------------------------------------------------
    final apiKey = await _settingsService.readApiKey();
    final adminKey = await _settingsService.readAdminKey();
    apiConfigured = apiKey.isSet;
    adminConfigured = adminKey.isSet;

    ApiRateLimits? apiLimits = previous.api;
    ApiUsageReport? report = previous.apiReport;
    AppError? apiError = previous.apiError;

    if (!apiKey.isSet) apiLimits = null;
    if (!adminKey.isSet) report = null;

    if (probeApi && (apiKey.isSet || adminKey.isSet)) {
      apiError = null;
      if (apiKey.isSet) {
        try {
          apiLimits = await _api.probe(apiKey: apiKey.value!, model: settings.apiProbeModel);
          if (!apiLimits.isHealthy) {
            apiError = AppError.fromStatus(
              apiLimits.httpStatus,
              apiMessage: apiLimits.errorMessage,
              retryAfter: apiLimits.retryAfter,
            );
          }
        } on AppError catch (e) {
          apiError = e;
        }
      }
      if (adminKey.isSet) {
        try {
          report = await _api.adminReport(adminKey: adminKey.value!, model: settings.apiProbeModel);
        } on AppError catch (e) {
          apiError ??= e;
        }
      }
    }

    // ---- Local activity (what used it) ---------------------------------------
    LocalUsageReport? local = previous.local;
    // Also scanned for sharing alone: the published file is built from this
    // report, so tying it to the card would make this device go quiet on every
    // other machine the moment the user hid the card.
    if (settings.showActivity || settings.deviceSyncEnabled) {
      try {
        local = await _local.scan() ?? local;
      } catch (e) {
        // Local transcripts are best-effort; never fail the refresh over them.
      }
    }

    // ---- Other devices (shared folder) ----------------------------------------
    var devices = previous.devices;
    try {
      devices = await _devices.sync(settings: settings, local: local, now: now);
    } catch (_) {
      // Best-effort like the local scan.
    }

    // ---- Freshness & connection ------------------------------------------------
    DateTime? newest;
    void consider(DateTime? t) {
      if (t == null) return;
      if (newest == null || t.isAfter(newest!)) newest = t;
    }

    for (final w in <LimitWindow>[fiveHour, weekly, ...extra]) {
      if (w.isAvailable) consider(w.observedAt);
    }
    consider(apiLimits?.observedAt);
    consider(report?.observedAt);

    final fresh = newest != null && now.difference(newest!) <= AppConstants.staleAfter;
    final networkError = (subError?.isNetwork ?? false) || (apiError?.isNetwork ?? false);
    final authError = (subError?.isAuth ?? false) || (apiError?.isAuth ?? false);
    final configured = cliStatus.bridgeInstalled || settings.useUsageEndpoint || apiKey.isSet || adminKey.isSet;

    ConnectionStatus connection;
    if (networkError && !fresh) {
      connection = ConnectionStatus.offline;
    } else if (fresh) {
      connection = ConnectionStatus.live;
    } else if (authError) {
      connection = ConnectionStatus.unauthenticated;
    } else if (!configured) {
      connection = ConnectionStatus.notConfigured;
    } else if (newest != null) {
      connection = ConnectionStatus.stale;
    } else if (subError != null || apiError != null) {
      connection = ConnectionStatus.error;
    } else {
      connection = ConnectionStatus.idle;
    }

    return UsageSnapshot(
      fiveHour: fiveHour,
      weekly: weekly,
      extraWindows: extra,
      cli: cliStatus,
      connection: connection,
      api: apiLimits,
      apiReport: report,
      local: local,
      devices: devices,
      apiError: apiError,
      subscriptionError: subError,
      lastUpdated: newest ?? previous.lastUpdated,
      lastAttempt: now,
    );
  }

  static void _merge(Map<String, LimitWindow> into, List<LimitWindow> incoming) {
    for (final w in incoming) {
      final existing = into[w.id];
      if (existing == null ||
          existing.observedAt == null ||
          (w.observedAt != null && w.observedAt!.isAfter(existing.observedAt!))) {
        into[w.id] = w;
      }
    }
  }

  static bool _worthRestoring(UsageReading reading, DateTime now) =>
      _stillDescribesNow(reading.resetsAt, reading.observedAt, now);

  /// Whether a figure Claude gave earlier still says something true about now.
  ///
  /// Inside the window it measured it *is* the current figure. Past its reset
  /// it is only context, and a day is as far as that stretches — the card
  /// shows it as a closed window, never as a live number.
  static bool _stillDescribesNow(DateTime? resetsAt, DateTime? observedAt, DateTime now) {
    if (resetsAt != null && resetsAt.isAfter(now)) return true;
    if (observedAt == null) return false;
    return now.difference(observedAt) <= const Duration(hours: 24);
  }

  static String _unavailableReason(
    String id,
    CliStatus cli,
    StatusLineData? statusLine,
    AppSettings settings,
    AppError? subError,
  ) {
    if (!cli.installed) {
      return 'Claude Code is not installed — subscription limits unavailable';
    }
    if (cli.apiKeyEnvPresent && !cli.hasOAuth) {
      return 'Not provided by Claude for API-key sign-in';
    }
    if (!cli.hasOAuth) {
      return 'Not signed in to Claude Code — run `claude` and use /login';
    }
    if (subError != null) return subError.message;
    if (!cli.bridgeInstalled && !settings.useUsageEndpoint) {
      return 'Connecting to Claude Code — reinstall the status-line bridge in Settings if this stays';
    }
    // Claude Code reads settings.json when a session starts, so a session that
    // was already open when the bridge went in will not use it yet. Say so,
    // rather than leaving the window looking broken.
    if (cli.bridgeInstalled && statusLine == null) {
      return 'Waiting for Claude Code — start (or restart) a session; limits arrive after its first response';
    }
    if (statusLine != null && !statusLine.hasRateLimits) {
      return 'Waiting for Claude Code to report limits — restart your session (Pro/Max plans only)';
    }
    // The feed is healthy and carrying other windows; this one is simply not
    // in it. Claude Code sends a window only while it is open, so the generic
    // fallback below would blame the whole chain for a gap of one.
    if (statusLine != null && !statusLine.reported(id)) {
      final others = statusLine.windowIds.map(LimitWindow.labelFor).join(', ');
      return '${LimitWindow.noActiveWindow(id)} — Claude Code is not reporting '
          'this window right now; it sent '
          '${others.isEmpty ? 'nothing else' : others}. Its real percentage and '
          'reset time return when a new window opens.';
    }
    return 'Not provided by Claude';
  }
}
