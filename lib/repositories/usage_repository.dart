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
import '../models/usage_snapshot.dart';
import '../services/anthropic_api_service.dart';
import '../services/claude_cli_service.dart';
import '../services/device_sync_service.dart';
import '../services/local_usage_service.dart';
import '../services/oauth_usage_service.dart';
import '../services/settings_service.dart';

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
    DeviceSyncService? devices,
  }) : _cli = cli, // ignore: prefer_initializing_formals
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

  bool get localScanning => _local.scanning;

  bool apiConfigured = false;
  bool adminConfigured = false;

  /// A cheap pass used by the fast activity timer: re-reads the local
  /// transcripts (incrementally) and exchanges files with the other devices.
  /// It starts no network requests of its own.
  Future<UsageSnapshot> refreshActivity({required AppSettings settings, required UsageSnapshot previous}) async {
    var local = previous.local;
    if (settings.showActivity) {
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

    // Retain last-known values when a source went quiet (UI marks them stale).
    for (final prev in previous.allWindows) {
      if (prev.isAvailable && !windows.containsKey(prev.id)) windows[prev.id] = prev;
    }

    final reason = _unavailableReason(cliStatus, statusLine, settings, subError);
    final fiveHour =
        windows.remove(LimitWindow.fiveHourId) ??
        LimitWindow.unavailable(id: LimitWindow.fiveHourId, label: '5-hour limit', reason: reason);
    final weekly =
        windows.remove(LimitWindow.sevenDayId) ??
        LimitWindow.unavailable(id: LimitWindow.sevenDayId, label: 'Weekly limit', reason: reason);
    final extra = windows.values.toList()..sort((a, b) => a.id.compareTo(b.id));

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
    if (settings.showActivity) {
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

  static String _unavailableReason(
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
      return 'Install the Claude Code bridge in Settings to receive limits';
    }
    if (cli.bridgeInstalled && statusLine == null) {
      return 'Waiting for a Claude Code session — limits arrive after its first response';
    }
    if (statusLine != null && !statusLine.hasRateLimits) {
      return 'Claude Code sent no rate limits yet (Pro/Max only; after the first response)';
    }
    return 'Not provided by Claude';
  }
}
