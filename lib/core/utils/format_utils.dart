import 'package:intl/intl.dart';

/// Human-readable formatting helpers (no business logic here).
class FormatUtils {
  FormatUtils._();

  static final NumberFormat _int = NumberFormat.decimalPattern();
  static final DateFormat _time = DateFormat.Hm();
  static final DateFormat _dayTime = DateFormat('EEE HH:mm');
  static final DateFormat _dateTime = DateFormat('d MMM HH:mm');

  static String percent(double? value, {int decimals = 0}) {
    if (value == null || value.isNaN) return '—';
    return '${value.toStringAsFixed(decimals)}%';
  }

  static String integer(num? value) => value == null ? '—' : _int.format(value);

  static String compact(num? value) {
    if (value == null) return '—';
    final v = value.toDouble();
    if (v.abs() >= 1e9) return '${(v / 1e9).toStringAsFixed(2)}B';
    if (v.abs() >= 1e6) return '${(v / 1e6).toStringAsFixed(2)}M';
    if (v.abs() >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}k';
    return _int.format(v);
  }

  static String usd(double? value) {
    if (value == null) return '—';
    return NumberFormat.currency(symbol: r'$', decimalDigits: 2).format(value);
  }

  /// "2h 14m", "4d 8h", "35m", "<1m".
  static String countdown(Duration? d) {
    if (d == null) return '—';
    if (d.isNegative || d.inSeconds <= 0) return 'now';
    if (d.inDays >= 1) {
      final h = d.inHours % 24;
      return h == 0 ? '${d.inDays}d' : '${d.inDays}d ${h}h';
    }
    if (d.inHours >= 1) {
      final m = d.inMinutes % 60;
      return m == 0 ? '${d.inHours}h' : '${d.inHours}h ${m}m';
    }
    if (d.inMinutes >= 1) return '${d.inMinutes}m';
    return '<1m';
  }

  /// "just now", "12 seconds ago", "2 minutes ago", "3 hours ago".
  static String relative(DateTime? at, DateTime now) {
    if (at == null) return 'never';
    final d = now.difference(at);
    if (d.inSeconds < 5) return 'just now';
    if (d.inSeconds < 60) return '${d.inSeconds} seconds ago';
    if (d.inMinutes < 60) {
      return d.inMinutes == 1 ? '1 minute ago' : '${d.inMinutes} minutes ago';
    }
    if (d.inHours < 24) {
      return d.inHours == 1 ? '1 hour ago' : '${d.inHours} hours ago';
    }
    return d.inDays == 1 ? '1 day ago' : '${d.inDays} days ago';
  }

  /// Absolute reset time: "Today 14:30", "Thu 09:00", "12 Sep 09:00".
  static String absolute(DateTime? at, DateTime now) {
    if (at == null) return '—';
    final local = at.toLocal();
    final sameDay = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    if (sameDay) return 'Today ${_time.format(local)}';
    if (local.difference(now).inDays.abs() < 6) return _dayTime.format(local);
    return _dateTime.format(local);
  }

  static String duration(Duration d) {
    if (d.inMinutes < 1) return '${d.inSeconds}s';
    if (d.inHours < 1) return '${d.inMinutes}m';
    return '${d.inHours}h ${d.inMinutes % 60}m';
  }

  /// "10h 57m 45s" — the exact figure Claude Code prints for a session length.
  ///
  /// It stores milliseconds and rounds to the nearest second (39,464,529 ms is
  /// its "10h 57m 45s", not 44s), so this rounds the same way; truncating
  /// would put the app one second below `/usage` on half of all sessions.
  static String durationLong(Duration? d) {
    if (d == null) return '—';
    final total = (d.inMilliseconds / 1000).round();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  /// Masks a secret: "sk-ant-…7f3a". Never returns more than 4 trailing chars.
  static String maskSecret(String? secret) {
    if (secret == null || secret.isEmpty) return 'Not set';
    if (secret.length <= 8) return '••••';
    final head = secret.startsWith('sk-ant-') ? 'sk-ant-' : secret.substring(0, 3);
    return '$head…${secret.substring(secret.length - 4)}';
  }

  /// "claude-opus-5" → "Opus 5", "claude-sonnet-4-6" → "Sonnet 4.6".
  static String modelShortName(String id) {
    var s = id.startsWith('claude-') ? id.substring(7) : id;
    s = s.replaceAll(RegExp(r'-\d{8}$'), '');
    final parts = s.split('-');
    if (parts.isEmpty) return id;
    final family = parts.first[0].toUpperCase() + parts.first.substring(1);
    final version = parts.skip(1).where((p) => int.tryParse(p) != null).join('.');
    return version.isEmpty ? family : '$family $version';
  }

  static String humanizeKey(String key) {
    final words = key
        .replaceAll('_', ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1));
    return words.join(' ');
  }
}
