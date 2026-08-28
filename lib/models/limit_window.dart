import '../core/utils/usage_math.dart';

/// Where a value came from. Shown in the UI so the user always knows whether
/// a number is official, derived, or unavailable.
enum DataSource {
  /// Claude Code status-line JSON (`rate_limits`) — documented by Anthropic.
  statusLine,

  /// The `/api/oauth/usage` endpoint Claude Code's `/usage` calls (undocumented,
  /// opt-in only).
  usageEndpoint,

  /// `anthropic-ratelimit-*` response headers — documented.
  apiHeaders,

  /// Admin Usage & Cost API — documented, needs an Admin key.
  adminApi,

  /// No data.
  none,
}

extension DataSourceLabel on DataSource {
  String get label {
    switch (this) {
      case DataSource.statusLine:
        return 'Claude Code status line';
      case DataSource.usageEndpoint:
        return 'Claude usage endpoint (undocumented)';
      case DataSource.apiHeaders:
        return 'API rate-limit headers';
      case DataSource.adminApi:
        return 'Admin Usage API';
      case DataSource.none:
        return 'No source';
    }
  }

  bool get isOfficial =>
      this == DataSource.statusLine ||
      this == DataSource.apiHeaders ||
      this == DataSource.adminApi;
}

/// One rolling usage window (5-hour, weekly, model-specific weekly…).
///
/// Every field is nullable on purpose: Claude only exposes a percentage and a
/// reset time for subscription windows. Absolute "used"/"remaining" amounts
/// are not provided, and the UI says so instead of inventing them.
class LimitWindow {
  const LimitWindow({
    required this.id,
    required this.label,
    this.usedPercentage,
    this.resetsAt,
    this.observedAt,
    this.source = DataSource.none,
    this.used,
    this.remaining,
    this.limit,
    this.unit,
    this.unavailableReason,
  });

  const LimitWindow.unavailable({
    required this.id,
    required this.label,
    required String reason,
  })  : usedPercentage = null,
        resetsAt = null,
        observedAt = null,
        source = DataSource.none,
        used = null,
        remaining = null,
        limit = null,
        unit = null,
        unavailableReason = reason;

  final String id;
  final String label;
  final double? usedPercentage;
  final DateTime? resetsAt;
  final DateTime? observedAt;
  final DataSource source;
  final num? used;
  final num? remaining;
  final num? limit;
  final String? unit;
  final String? unavailableReason;

  bool get isAvailable => usedPercentage != null;
  double? get remainingPercentage => UsageMath.remainingPercentage(usedPercentage);
  UsageStatus get status => UsageMath.statusFor(usedPercentage);

  bool hasReset(DateTime now) => UsageMath.hasReset(resetsAt, now);
  Duration? untilReset(DateTime now) => UsageMath.untilReset(resetsAt, now);

  bool isStale(DateTime now, Duration staleAfter) =>
      observedAt != null && now.difference(observedAt!) > staleAfter;

  LimitWindow copyWith({
    double? usedPercentage,
    DateTime? resetsAt,
    DateTime? observedAt,
    DataSource? source,
    String? unavailableReason,
  }) {
    return LimitWindow(
      id: id,
      label: label,
      usedPercentage: usedPercentage ?? this.usedPercentage,
      resetsAt: resetsAt ?? this.resetsAt,
      observedAt: observedAt ?? this.observedAt,
      source: source ?? this.source,
      used: used,
      remaining: remaining,
      limit: limit,
      unit: unit,
      unavailableReason: unavailableReason ?? this.unavailableReason,
    );
  }

  static const String fiveHourId = 'five_hour';
  static const String sevenDayId = 'seven_day';

  static String labelFor(String id) {
    switch (id) {
      case fiveHourId:
        return '5-hour limit';
      case sevenDayId:
        return 'Weekly limit';
      case 'seven_day_opus':
        return 'Weekly · Opus';
      case 'seven_day_sonnet':
        return 'Weekly · Sonnet';
      case 'seven_day_oauth_apps':
        return 'Weekly · OAuth apps';
      default:
        return id
            .replaceAll('_', ' ')
            .split(' ')
            .where((w) => w.isNotEmpty)
            .map((w) => w[0].toUpperCase() + w.substring(1))
            .join(' ');
    }
  }
}
