/// UI warning thresholds. These are display thresholds only — they are NOT
/// Claude's limits. The real limits come from the data sources.
enum UsageStatus { normal, moderate, warning, critical, unknown }

class UsageMath {
  UsageMath._();

  static const double moderateAt = 60;
  static const double warningAt = 80;
  static const double criticalAt = 90;

  static UsageStatus statusFor(double? usedPercentage) {
    if (usedPercentage == null || usedPercentage.isNaN) {
      return UsageStatus.unknown;
    }
    if (usedPercentage >= criticalAt) return UsageStatus.critical;
    if (usedPercentage >= warningAt) return UsageStatus.warning;
    if (usedPercentage >= moderateAt) return UsageStatus.moderate;
    return UsageStatus.normal;
  }

  /// Percentage used, from absolute values. Returns null when a limit is
  /// unknown or zero so the UI never fabricates a percentage.
  static double? percentage({num? used, num? limit}) {
    if (used == null || limit == null || limit <= 0) return null;
    return (used / limit * 100).clamp(0, 100).toDouble();
  }

  /// Percentage used from a remaining/limit pair (rate-limit headers).
  static double? percentageFromRemaining({num? remaining, num? limit}) {
    if (remaining == null || limit == null || limit <= 0) return null;
    final used = (limit - remaining).clamp(0, limit);
    return (used / limit * 100).toDouble();
  }

  static double? remainingPercentage(double? usedPercentage) {
    if (usedPercentage == null) return null;
    return (100 - usedPercentage).clamp(0, 100).toDouble();
  }

  /// 0..1 fraction for progress bars; clamps out-of-range input.
  static double fraction(double? usedPercentage) {
    if (usedPercentage == null || usedPercentage.isNaN) return 0;
    return (usedPercentage / 100).clamp(0, 1).toDouble();
  }

  static Duration? untilReset(DateTime? resetsAt, DateTime now) {
    if (resetsAt == null) return null;
    final d = resetsAt.difference(now);
    return d.isNegative ? Duration.zero : d;
  }

  static bool hasReset(DateTime? resetsAt, DateTime now) =>
      resetsAt != null && !now.isBefore(resetsAt);
}
