import '../core/utils/server_time.dart';
import '../core/utils/usage_math.dart';

/// One limiter parsed from `anthropic-ratelimit-<name>-{limit,remaining,reset}`.
class RateLimitBucket {
  const RateLimitBucket({required this.name, this.limit, this.remaining, this.resetsAt});

  final String name;
  final int? limit;
  final int? remaining;
  final DateTime? resetsAt;

  bool get isPresent => limit != null || remaining != null;
  int? get used =>
      (limit != null && remaining != null) ? (limit! - remaining!).clamp(0, limit!).toInt() : null;
  double? get usedPercentage =>
      UsageMath.percentageFromRemaining(remaining: remaining, limit: limit);
}

/// Snapshot of the official rate-limit headers from the last probe request.
class ApiRateLimits {
  const ApiRateLimits({
    required this.observedAt,
    required this.model,
    required this.httpStatus,
    required this.requests,
    required this.tokens,
    required this.inputTokens,
    required this.outputTokens,
    this.retryAfter,
    this.requestId,
    this.probeInputTokens,
    this.probeOutputTokens,
    this.errorMessage,
  });

  final DateTime observedAt;
  final String model;
  final int httpStatus;
  final RateLimitBucket requests;
  final RateLimitBucket tokens;
  final RateLimitBucket inputTokens;
  final RateLimitBucket outputTokens;
  final Duration? retryAfter;
  final String? requestId;
  final int? probeInputTokens;
  final int? probeOutputTokens;
  final String? errorMessage;

  bool get isHealthy => httpStatus >= 200 && httpStatus < 300;
  bool get isRateLimited => httpStatus == 429;
  bool get hasAnyHeader =>
      requests.isPresent || tokens.isPresent || inputTokens.isPresent || outputTokens.isPresent;

  /// The most constrained limiter, used for the headline percentage.
  double? get headlineUsedPercentage {
    final candidates = <double>[
      for (final b in [requests, tokens, inputTokens, outputTokens])
        if (b.usedPercentage != null) b.usedPercentage!,
    ];
    if (candidates.isEmpty) return null;
    candidates.sort();
    return candidates.last;
  }

  DateTime? get earliestReset {
    final times = <DateTime>[
      for (final b in [requests, tokens, inputTokens, outputTokens])
        if (b.resetsAt != null) b.resetsAt!,
    ];
    if (times.isEmpty) return null;
    times.sort();
    return times.first;
  }

  /// Parses HTTP response headers (keys are lower-cased by `package:http`).
  static ApiRateLimits fromHeaders(
    Map<String, String> headers, {
    required String model,
    required int httpStatus,
    int? probeInputTokens,
    int? probeOutputTokens,
    String? errorMessage,
  }) {
    RateLimitBucket bucket(String name) {
      final prefix = 'anthropic-ratelimit-$name';
      return RateLimitBucket(
        name: name,
        limit: _int(headers['$prefix-limit']),
        remaining: _int(headers['$prefix-remaining']),
        resetsAt: _date(headers['$prefix-reset']),
      );
    }

    final retry = _int(headers['retry-after']);
    return ApiRateLimits(
      observedAt: DateTime.now(),
      model: model,
      httpStatus: httpStatus,
      requests: bucket('requests'),
      tokens: bucket('tokens'),
      inputTokens: bucket('input-tokens'),
      outputTokens: bucket('output-tokens'),
      retryAfter: retry == null ? null : Duration(seconds: retry),
      requestId: headers['request-id'],
      probeInputTokens: probeInputTokens,
      probeOutputTokens: probeOutputTokens,
      errorMessage: errorMessage,
    );
  }

  static int? _int(String? v) => v == null ? null : int.tryParse(v.trim());

  /// The reset instant Anthropic put in the header, parsed as sent.
  static DateTime? _date(String? v) => ServerTime.parse(v);
}
