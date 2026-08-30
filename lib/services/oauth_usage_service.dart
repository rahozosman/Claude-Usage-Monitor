import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/constants/app_constants.dart';
import '../core/errors/app_error.dart';
import '../core/utils/server_time.dart';
import '../models/limit_window.dart';

/// Result of one call to the Claude usage endpoint.
class UsageEndpointResult {
  const UsageEndpointResult({required this.windows, required this.observedAt, this.extraUsage});

  final List<LimitWindow> windows;
  final DateTime observedAt;

  /// Raw `extra_usage` block if present (usage credits). Displayed verbatim.
  final Map<String, dynamic>? extraUsage;
}

/// OPT-IN ONLY. Calls the same endpoint Claude Code's `/usage` uses, with the
/// user's own local OAuth token. The endpoint is not publicly documented and
/// may change; the parser is tolerant and the UI labels the source.
///
/// Throttled to one call per [AppConstants.usageEndpointMinInterval] and backs
/// off on 429 so it never hammers the endpoint.
class OAuthUsageService {
  OAuthUsageService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  DateTime? _lastCallAt;
  DateTime? _backoffUntil;
  UsageEndpointResult? _last;

  UsageEndpointResult? get lastResult => _last;

  Future<UsageEndpointResult> fetch(String accessToken, {bool force = false}) async {
    final now = DateTime.now();
    if (_backoffUntil != null && now.isBefore(_backoffUntil!)) {
      if (_last != null) return _last!;
      throw AppError(
        AppErrorKind.rateLimited,
        'Usage endpoint rate limited',
        retryAfter: _backoffUntil!.difference(now),
      );
    }
    if (!force &&
        _last != null &&
        _lastCallAt != null &&
        now.difference(_lastCallAt!) < AppConstants.usageEndpointMinInterval) {
      return _last!;
    }

    _lastCallAt = now;
    final uri = Uri.parse('${AppConstants.anthropicApiBase}${AppConstants.oauthUsagePath}');
    http.Response response;
    try {
      response = await _client.get(uri, headers: <String, String>{
        'Authorization': 'Bearer $accessToken',
        'anthropic-beta': AppConstants.oauthBetaHeader,
        'anthropic-version': AppConstants.anthropicVersion,
        'Accept': 'application/json',
        'User-Agent': AppConstants.userAgent,
      }).timeout(AppConstants.httpTimeout);
    } on SocketException catch (e) {
      throw AppError.network(e.osError?.message);
    } on TimeoutException {
      throw AppError.network('timed out');
    } on http.ClientException catch (e) {
      throw AppError.network(e.message);
    }

    if (response.statusCode == 429) {
      final retry = int.tryParse(response.headers['retry-after'] ?? '');
      final wait = retry != null ? Duration(seconds: retry) : AppConstants.usageEndpointBackoff;
      _backoffUntil = DateTime.now().add(wait);
      throw AppError(AppErrorKind.rateLimited, 'Usage endpoint rate limited', retryAfter: wait);
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const AppError(
        AppErrorKind.tokenExpired,
        'Claude Code sign-in expired — open Claude Code once to refresh it',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AppError.fromStatus(response.statusCode, apiMessage: _errorMessage(response.body));
    }

    final result = _parse(response.body);
    _last = result;
    return result;
  }

  UsageEndpointResult _parse(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw AppError.malformed('usage endpoint returned non-JSON');
    }
    if (decoded is! Map) throw AppError.malformed('usage endpoint returned ${decoded.runtimeType}');

    final now = DateTime.now();
    final windows = <LimitWindow>[];
    Map<String, dynamic>? extra;

    decoded.forEach((key, value) {
      if (value is! Map) return;
      final id = key.toString();
      if (id == 'extra_usage') {
        extra = Map<String, dynamic>.from(value);
        return;
      }
      final util = value['utilization'] ?? value['used_percentage'];
      if (util is! num) return;
      windows.add(LimitWindow(
        id: id,
        label: LimitWindow.labelFor(id),
        usedPercentage: util.toDouble(),
        resetsAt: ServerTime.parse(value['resets_at']),
        observedAt: now,
        source: DataSource.usageEndpoint,
      ));
    });

    if (windows.isEmpty) {
      throw AppError.malformed('usage endpoint returned no usage windows');
    }
    return UsageEndpointResult(windows: windows, observedAt: now, extraUsage: extra);
  }

  static String? _errorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final err = decoded['error'];
        if (err is Map && err['message'] is String) return err['message'] as String;
        if (decoded['message'] is String) return decoded['message'] as String;
      }
    } catch (_) {}
    return null;
  }

  void dispose() => _client.close();
}
