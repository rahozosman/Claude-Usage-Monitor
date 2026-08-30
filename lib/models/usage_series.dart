import 'dart:collection';

import '../core/utils/server_time.dart';
import 'limit_window.dart';

/// One percentage Claude reported for one window, at one moment.
///
/// This is a record of something observed, never of something computed. The
/// whole history is built only from percentages Claude itself stated; nothing
/// derived from local token counts ever enters it, because transcript totals
/// do not map to Anthropic's rate-limit maths and pretending otherwise would
/// make every number downstream a guess.
class UsageReading {
  const UsageReading({
    required this.windowId,
    required this.percentage,
    required this.observedAt,
    this.resetsAt,
    this.source = DataSource.statusLine,
  });

  final String windowId;
  final double percentage;
  final DateTime observedAt;

  /// The reset instant Claude gave for the window this reading belongs to.
  /// It is what tells one window from the next.
  final DateTime? resetsAt;
  final DataSource source;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'w': windowId,
    'p': percentage,
    'r': ?_seconds(resetsAt),
    't': _seconds(observedAt),
    's': source.name,
  };

  static int? _seconds(DateTime? at) => at == null ? null : at.toUtc().millisecondsSinceEpoch ~/ 1000;

  /// Tolerant: one unreadable line must never cost the rest of the file.
  static UsageReading? fromJson(Map<String, dynamic> json) {
    final id = json['w'];
    final pct = json['p'];
    final at = ServerTime.parse(json['t']);
    if (id is! String || id.isEmpty || pct is! num || at == null) return null;
    return UsageReading(
      windowId: id,
      percentage: pct.toDouble(),
      observedAt: at,
      resetsAt: ServerTime.parse(json['r']),
      source: DataSource.values.firstWhere(
        (s) => s.name == json['s'],
        orElse: () => DataSource.statusLine,
      ),
    );
  }
}

/// One window's life, from when it opened to when it reset.
///
/// Segments exist so a rate is never measured across a reset. The percentage
/// falling from 96 back to 3 is a new window starting, not usage going
/// backwards, and averaging through it would produce a confidently wrong
/// number — the one arithmetic mistake worth designing against.
class UsageSegment {
  UsageSegment(List<UsageReading> readings) : readings = UnmodifiableListView<UsageReading>(readings);

  /// Ascending by [UsageReading.observedAt], never empty.
  final List<UsageReading> readings;

  DateTime get startedAt => readings.first.observedAt;
  DateTime get endedAt => readings.last.observedAt;
  double get lastPercentage => readings.last.percentage;
  DateTime? get resetsAt => readings.last.resetsAt;

  double get peakPercentage => readings.fold<double>(0, (m, r) => r.percentage > m ? r.percentage : m);

  /// Two sources measured the same window. Their numbers agree in principle,
  /// but the card says so rather than blending them silently.
  bool get mixedSources => readings.map((r) => r.source).toSet().length > 1;

  /// How fast the percentage is climbing, over the trailing [lookback] only.
  ///
  /// Returns null rather than a weak answer: too few readings, too short a
  /// span, a stale last reading or a flat/falling line all mean there is
  /// nothing honest to say yet.
  UsageRate? rate(
    DateTime now, {
    Duration lookback = const Duration(minutes: 90),
    int minReadings = 3,
    Duration minSpan = const Duration(minutes: 15),
    Duration freshWithin = const Duration(minutes: 10),
  }) {
    final last = readings.last;
    if (now.difference(last.observedAt) > freshWithin) return null;

    final from = last.observedAt.subtract(lookback);
    final recent = readings.where((r) => !r.observedAt.isBefore(from)).toList();
    if (recent.length < minReadings) return null;

    final span = recent.last.observedAt.difference(recent.first.observedAt);
    if (span < minSpan) return null;

    final climb = recent.last.percentage - recent.first.percentage;
    final hours = span.inMilliseconds / Duration.millisecondsPerHour;
    if (hours <= 0) return null;

    return UsageRate(
      perHour: climb / hours,
      readings: recent.length,
      span: span,
      anchorAt: recent.last.observedAt,
      anchorPercentage: recent.last.percentage,
    );
  }

  /// The readings split wherever the app was not running to take any.
  ///
  /// The card draws each run as its own line so a gap stays a gap. Joining
  /// across an absence would draw a straight line through hours nobody
  /// observed, which is the picture lying rather than the data.
  List<List<UsageReading>> runs({Duration gapAfter = const Duration(minutes: 20)}) {
    final out = <List<UsageReading>>[];
    var current = <UsageReading>[readings.first];
    for (var i = 1; i < readings.length; i++) {
      if (readings[i].observedAt.difference(readings[i - 1].observedAt) > gapAfter) {
        out.add(current);
        current = <UsageReading>[];
      }
      current.add(readings[i]);
    }
    out.add(current);
    return out;
  }
}

/// A measured climb, carrying everything needed to state its own basis.
class UsageRate {
  const UsageRate({
    required this.perHour,
    required this.readings,
    required this.span,
    required this.anchorAt,
    required this.anchorPercentage,
  });

  /// Percentage points per hour. Can be zero or negative — the card treats
  /// anything that is not climbing as "no projection", not as a countdown.
  final double perHour;
  final int readings;
  final Duration span;

  /// The last reading this was measured from: projections run from the last
  /// thing Claude actually said, not from the current clock.
  final DateTime anchorAt;
  final double anchorPercentage;

  bool get climbing => perHour > 0.01;

  /// When this pace would reach [target] percent, or null if it never would.
  DateTime? reaches(double target) {
    if (!climbing || anchorPercentage >= target) return null;
    final hours = (target - anchorPercentage) / perHour;
    if (!hours.isFinite || hours < 0) return null;
    return anchorAt.add(Duration(milliseconds: (hours * Duration.millisecondsPerHour).round()));
  }
}

/// Every segment recorded for one window, oldest first.
class UsageSeries {
  const UsageSeries({required this.windowId, required this.segments});

  final String windowId;
  final List<UsageSegment> segments;

  UsageSegment? get current => segments.isEmpty ? null : segments.last;

  /// Splits a flat list of readings into segments at each reset boundary.
  ///
  /// A new `resets_at` is the reliable signal; a sharp drop is the fallback
  /// for readings that arrived without one.
  static UsageSeries build(String windowId, List<UsageReading> readings) {
    if (readings.isEmpty) return UsageSeries(windowId: windowId, segments: const <UsageSegment>[]);
    final sorted = List<UsageReading>.from(readings)..sort((a, b) => a.observedAt.compareTo(b.observedAt));
    final segments = <UsageSegment>[];
    var current = <UsageReading>[sorted.first];
    for (var i = 1; i < sorted.length; i++) {
      if (_opensNewWindow(sorted[i - 1], sorted[i])) {
        segments.add(UsageSegment(current));
        current = <UsageReading>[];
      }
      current.add(sorted[i]);
    }
    segments.add(UsageSegment(current));
    return UsageSeries(windowId: windowId, segments: segments);
  }

  static bool _opensNewWindow(UsageReading prev, UsageReading next) {
    final a = prev.resetsAt;
    final b = next.resetsAt;
    // A minute of tolerance: the same reset instant can be reported with
    // slightly different precision by different sources.
    if (a != null && b != null) return b.difference(a).abs() > const Duration(minutes: 1);
    // No reset time to compare, so fall back to the shape of the data: usage
    // within one window only ever climbs.
    return next.percentage < prev.percentage - 5;
  }

  /// The length a window is named for, used only to say how far through it we
  /// are. The reset instant itself always comes from Claude.
  static Duration? nominalLength(String windowId) {
    if (windowId.startsWith(LimitWindow.fiveHourId)) return const Duration(hours: 5);
    if (windowId.startsWith(LimitWindow.sevenDayId)) return const Duration(days: 7);
    return null;
  }
}

/// The highest percentage seen on one local day.
class DailyPeak {
  const DailyPeak({required this.day, required this.peak, required this.readings});

  /// Local midnight of the day this covers.
  final DateTime day;
  final double peak;
  final int readings;

  /// Claude reported the window as full at some point that day.
  bool get hitCap => peak >= 99.5;
}

/// Everything derived from the stored readings, recomputed once per append
/// rather than per frame.
class UsageHistory {
  const UsageHistory({
    this.series = const <String, UsageSeries>{},
    this.dailyPeaks = const <DailyPeak>[],
    this.totalReadings = 0,
    this.oldest,
    this.newest,
  });

  static const UsageHistory empty = UsageHistory();

  final Map<String, UsageSeries> series;

  /// Ascending, one entry per local day that has readings, most recent last.
  final List<DailyPeak> dailyPeaks;
  final int totalReadings;
  final DateTime? oldest;
  final DateTime? newest;

  bool get isEmpty => totalReadings == 0;

  UsageSeries? seriesFor(String windowId) => series[windowId];
}
