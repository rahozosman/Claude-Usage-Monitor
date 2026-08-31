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

  /// Whether [resetsAt] can be believed at all.
  ///
  /// A reading cannot describe a window that had already ended when it was
  /// taken. The usage endpoint has been seen returning a `five_hour` window
  /// whose `resets_at` sat six hours in the past while its percentage climbed
  /// with live use — 8% to 16% across twenty minutes, one reset value the
  /// whole way. The figure was current; the reset field was stale. Gating on
  /// it turned an open window into a closed one on screen and hid a number
  /// that was perfectly good.
  bool get hasCredibleReset =>
      resetsAt != null && (observedAt == null || resetsAt!.isAfter(observedAt!));

  /// [resetsAt] when it can be believed, null when it cannot.
  ///
  /// Everything that reasons about the reset — countdown, closure,
  /// notifications — goes through this, so one stale field can never
  /// manufacture a closed window out of a live one.
  DateTime? get knownResetsAt => hasCredibleReset ? resetsAt : null;

  bool hasReset(DateTime now) => UsageMath.hasReset(knownResetsAt, now);
  Duration? untilReset(DateTime now) => UsageMath.untilReset(knownResetsAt, now);

  /// Whether this window is open right now: Claude is reporting it *and* its
  /// reset has not passed.
  ///
  /// A closed window still carries the last figure Claude gave. That figure is
  /// history, not a live reading, so this — never [isAvailable] alone — is what
  /// gates a percentage on screen.
  bool isActive(DateTime now) => isAvailable && !hasReset(now);

  /// The other half of [isActive]: a window that ended while its last figure
  /// is still on hand. Not the same as unavailable — there *is* a number, it
  /// just belongs to a block that is over.
  bool isClosed(DateTime now) => isAvailable && hasReset(now);

  /// How long ago this window ended, or null while it is still open.
  Duration? closedFor(DateTime now) => hasReset(now) ? now.difference(knownResetsAt!) : null;

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

  /// Whether a figure Claude gave earlier still says something true about now.
  ///
  /// Inside the window it measured it *is* the current figure. Past its reset
  /// it is only context, and a day is as far as that stretches — the card
  /// shows it as a closed window, never as a live number.
  static bool stillDescribesNow(DateTime? resetsAt, DateTime? observedAt, DateTime now) {
    if (resetsAt != null && resetsAt.isAfter(now)) return true;
    if (observedAt == null) return false;
    return now.difference(observedAt) <= const Duration(hours: 24);
  }

  static const String fiveHourId = 'five_hour';
  static const String sevenDayId = 'seven_day';

  /// The window's span on its own, for sentences like "No active 5-hour
  /// window". [labelFor] is the card title; this is the noun inside a phrase.
  static String spanFor(String id) {
    switch (id) {
      case fiveHourId:
        return '5-hour';
      case sevenDayId:
        return 'weekly';
      default:
        return labelFor(id).toLowerCase();
    }
  }

  /// The one sentence every surface uses for a window that is not open.
  ///
  /// Deliberately not "0%" and not "waiting for new data": Claude has not
  /// opened this window, so there is no number to show and none is implied.
  static String noActiveWindow(String id) => 'No active ${spanFor(id)} window';

  /// The counterpart to [noActiveWindow], for when the window is over *and*
  /// the last figure Claude gave for it is still worth reading.
  ///
  /// Both sentences refuse to pass a closed figure off as live. This one just
  /// declines to throw it away as well: a card that blanked an 8% the moment
  /// the block ended looked broken, when all that had happened was the block
  /// ending. [usedPercent] and [ago] arrive already formatted so this stays
  /// out of the presentation layer's business.
  static String closedWindow(String id, String usedPercent, String ago) =>
      'Last ${spanFor(id)} window: $usedPercent · closed $ago';

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
