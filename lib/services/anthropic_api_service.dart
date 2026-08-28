import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/constants/app_constants.dart';
import '../core/errors/app_error.dart';
import '../models/api_rate_limits.dart';
import '../models/api_usage_report.dart';

/// Official Anthropic API integration.
///
/// * [probe] sends the smallest possible Messages request and reads the
///   documented `anthropic-ratelimit-*` headers (they come back on success
///   *and* on 429). This is the only official way to observe live API
///   rate-limit headroom.
/// * [adminReport] uses the documented Admin Usage, Cost and Rate Limits APIs
///   (Admin key required).
class AnthropicApiService {
  AnthropicApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Map<String, String> _headers(String key, {bool bearer = false}) => <String, String>{
        if (bearer) 'Authorization': 'Bearer $key' else 'x-api-key': key,
        'anthropic-version': AppConstants.anthropicVersion,
        'content-type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': AppConstants.userAgent,
      };

  Future<ApiRateLimits> probe({required String apiKey, required String model}) async {
    final uri = Uri.parse('${AppConstants.anthropicApiBase}/v1/messages');
    final body = jsonEncode(<String, dynamic>{
      'model': model,
      'max_tokens': 1,
      'messages': <Map<String, String>>[
        <String, String>{'role': 'user', 'content': 'ping'},
      ],
    });

    final response = await _send(() => _client.post(uri, headers: _headers(apiKey), body: body));

    int? inTok;
    int? outTok;
    String? errorMessage;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        final usage = decoded['usage'];
        if (usage is Map) {
          inTok = (usage['input_tokens'] as num?)?.toInt();
          outTok = (usage['output_tokens'] as num?)?.toInt();
        }
        final err = decoded['error'];
        if (err is Map && err['message'] is String) errorMessage = err['message'] as String;
      }
    } catch (_) {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        throw AppError.malformed('messages response was not JSON');
      }
    }

    final limits = ApiRateLimits.fromHeaders(
      response.headers,
      model: model,
      httpStatus: response.statusCode,
      probeInputTokens: inTok,
      probeOutputTokens: outTok,
      errorMessage: errorMessage,
    );

    if (response.statusCode == 401) {
      throw AppError.fromStatus(401, apiMessage: errorMessage);
    }
    if (response.statusCode == 403) {
      throw AppError.fromStatus(403, apiMessage: errorMessage);
    }
    // 429 and other statuses still carry headers — return them and let the
    // caller surface the message.
    return limits;
  }

  Future<ApiUsageReport> adminReport({required String adminKey, required String model}) async {
    final end = DateTime.now().toUtc();
    final start = DateTime.utc(end.year, end.month, end.day).subtract(const Duration(days: 6));
    final startIso = _rfc3339(start);
    final endIso = _rfc3339(end);

    // Usage report (required).
    final usageUri = Uri.parse(
      '${AppConstants.anthropicApiBase}/v1/organizations/usage_report/messages'
      '?starting_at=$startIso&ending_at=$endIso&bucket_width=1d&limit=31',
    );
    final usageResp = await _send(() => _client.get(usageUri, headers: _headers(adminKey)));
    if (usageResp.statusCode < 200 || usageResp.statusCode >= 300) {
      throw AppError.fromStatus(usageResp.statusCode, apiMessage: _errorMessage(usageResp.body));
    }
    final usage = _sumUsage(usageResp.body);

    // Cost report (best effort).
    double? cost;
    String? costError;
    try {
      final costUri = Uri.parse(
        '${AppConstants.anthropicApiBase}/v1/organizations/cost_report'
        '?starting_at=$startIso&ending_at=$endIso&bucket_width=1d&limit=31',
      );
      final costResp = await _send(() => _client.get(costUri, headers: _headers(adminKey)));
      if (costResp.statusCode >= 200 && costResp.statusCode < 300) {
        cost = _sumCost(costResp.body);
      } else {
        costError = AppError.fromStatus(costResp.statusCode, apiMessage: _errorMessage(costResp.body)).toString();
      }
    } on AppError catch (e) {
      costError = e.toString();
    }

    // Configured rate limits for the probe model (best effort).
    var limits = const <ConfiguredLimit>[];
    String? limitsError;
    try {
      final rlUri = Uri.parse(
        '${AppConstants.anthropicApiBase}/v1/organizations/rate_limits?model=${Uri.encodeQueryComponent(model)}',
      );
      final rlResp = await _send(() => _client.get(rlUri, headers: _headers(adminKey)));
      if (rlResp.statusCode >= 200 && rlResp.statusCode < 300) {
        limits = _parseLimits(rlResp.body);
      } else {
        limitsError = AppError.fromStatus(rlResp.statusCode, apiMessage: _errorMessage(rlResp.body)).toString();
      }
    } on AppError catch (e) {
      limitsError = e.toString();
    }

    return ApiUsageReport(
      observedAt: DateTime.now(),
      rangeStart: start.toLocal(),
      rangeEnd: end.toLocal(),
      uncachedInputTokens: usage.uncached,
      cacheReadInputTokens: usage.cacheRead,
      cacheCreationInputTokens: usage.cacheCreation,
      outputTokens: usage.output,
      costUsd: cost,
      configuredLimits: limits,
      costError: costError,
      limitsError: limitsError,
    );
  }

  // ---- helpers ---------------------------------------------------------------

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(AppConstants.httpTimeout);
    } on SocketException catch (e) {
      throw AppError.network(e.osError?.message);
    } on TimeoutException {
      throw AppError.network('timed out');
    } on http.ClientException catch (e) {
      throw AppError.network(e.message);
    } on HandshakeException catch (e) {
      throw AppError.network('TLS: ${e.message}');
    }
  }

  static String _rfc3339(DateTime utc) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${utc.year}-${two(utc.month)}-${two(utc.day)}T${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}Z';
  }

  static ({int? uncached, int? cacheRead, int? cacheCreation, int? output}) _sumUsage(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw AppError.malformed('usage report was not JSON');
    }
    if (decoded is! Map || decoded['data'] is! List) {
      throw AppError.malformed('usage report missing data[]');
    }
    int? uncached;
    int? cacheRead;
    int? cacheCreation;
    int? output;
    int add(int? acc, num? v) => v == null ? (acc ?? 0) : (acc ?? 0) + v.toInt();

    for (final bucket in decoded['data'] as List) {
      if (bucket is! Map || bucket['results'] is! List) continue;
      for (final r in bucket['results'] as List) {
        if (r is! Map) continue;
        uncached = add(uncached, r['uncached_input_tokens'] as num?);
        cacheRead = add(cacheRead, r['cache_read_input_tokens'] as num?);
        output = add(output, r['output_tokens'] as num?);
        final cc = r['cache_creation'];
        if (cc is Map) {
          num sum = 0;
          for (final v in cc.values) {
            if (v is num) sum += v;
          }
          cacheCreation = add(cacheCreation, sum);
        } else if (r['cache_creation_input_tokens'] is num) {
          cacheCreation = add(cacheCreation, r['cache_creation_input_tokens'] as num);
        }
      }
    }
    return (uncached: uncached, cacheRead: cacheRead, cacheCreation: cacheCreation, output: output);
  }

  static double? _sumCost(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map || decoded['data'] is! List) return null;
    double? total;
    for (final bucket in decoded['data'] as List) {
      if (bucket is! Map || bucket['results'] is! List) continue;
      for (final r in bucket['results'] as List) {
        if (r is! Map) continue;
        final amount = r['amount'];
        final cents = amount is num ? amount.toDouble() : double.tryParse(amount?.toString() ?? '');
        if (cents == null) continue;
        total = (total ?? 0) + cents / 100.0;
      }
    }
    return total;
  }

  static List<ConfiguredLimit> _parseLimits(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map || decoded['data'] is! List) return const <ConfiguredLimit>[];
    final out = <ConfiguredLimit>[];
    for (final group in decoded['data'] as List) {
      if (group is! Map || group['limits'] is! List) continue;
      final models = (group['models'] is List)
          ? (group['models'] as List).map((e) => e.toString()).toList()
          : const <String>[];
      for (final l in group['limits'] as List) {
        if (l is! Map) continue;
        final type = l['type']?.toString();
        final value = l['value'];
        if (type == null || value is! num) continue;
        out.add(ConfiguredLimit(type: type, value: value.toInt(), models: models));
      }
    }
    return out;
  }

  static String? _errorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final err = decoded['error'];
        if (err is Map && err['message'] is String) return err['message'] as String;
      }
    } catch (_) {}
    return null;
  }

  void dispose() => _client.close();
}
