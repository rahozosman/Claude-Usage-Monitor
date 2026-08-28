/// Aggregated Admin Usage & Cost API results for a time range.
class ApiUsageReport {
  const ApiUsageReport({
    required this.observedAt,
    required this.rangeStart,
    required this.rangeEnd,
    this.uncachedInputTokens,
    this.cacheReadInputTokens,
    this.cacheCreationInputTokens,
    this.outputTokens,
    this.costUsd,
    this.configuredLimits = const <ConfiguredLimit>[],
    this.costError,
    this.limitsError,
  });

  final DateTime observedAt;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final int? uncachedInputTokens;
  final int? cacheReadInputTokens;
  final int? cacheCreationInputTokens;
  final int? outputTokens;
  final double? costUsd;
  final List<ConfiguredLimit> configuredLimits;
  final String? costError;
  final String? limitsError;

  int? get totalInputTokens {
    if (uncachedInputTokens == null && cacheReadInputTokens == null && cacheCreationInputTokens == null) {
      return null;
    }
    return (uncachedInputTokens ?? 0) + (cacheReadInputTokens ?? 0) + (cacheCreationInputTokens ?? 0);
  }

  int? get totalTokens {
    final i = totalInputTokens;
    if (i == null && outputTokens == null) return null;
    return (i ?? 0) + (outputTokens ?? 0);
  }
}

/// One configured limiter from the Rate Limits Admin API.
class ConfiguredLimit {
  const ConfiguredLimit({required this.type, required this.value, this.models = const <String>[]});

  final String type;
  final int value;
  final List<String> models;

  String get label {
    switch (type) {
      case 'requests_per_minute':
        return 'Requests / min';
      case 'input_tokens_per_minute':
        return 'Input tokens / min';
      case 'output_tokens_per_minute':
        return 'Output tokens / min';
      default:
        return type.replaceAll('_', ' ');
    }
  }
}
