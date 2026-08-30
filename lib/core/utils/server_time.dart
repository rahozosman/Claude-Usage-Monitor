/// Parses a timestamp exactly as Claude sent it.
///
/// Every reset time in this app comes from a server: `rate_limits.*.resets_at`
/// in the Claude Code status-line JSON, `resets_at` from the usage endpoint,
/// and the `anthropic-ratelimit-*-reset` response headers. None of it is
/// derived from the local clock, and none of it is estimated — the local clock
/// is only ever used to count down to the instant the server named.
///
/// So the only job here is to not corrupt the value on the way in. It lives in
/// one place because the three sources used to parse it three slightly
/// different ways, and the differences were bugs.
class ServerTime {
  ServerTime._();

  /// Accepts what those sources actually send: RFC 3339 strings and Unix
  /// timestamps in seconds or milliseconds. Returns local time, which is the
  /// same instant — only its representation changes.
  static DateTime? parse(Object? value) {
    if (value is num) {
      if (!value.isFinite || value <= 0) return null;
      // Seconds or milliseconds, decided by magnitude rather than by which
      // caller it came from: 1e12 seconds is the year 33658, so any value
      // past it is milliseconds and any value below it is seconds.
      final ms = value > 1e12 ? value.round() : (value * 1000).round();
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    }
    if (value is! String) return null;
    final text = value.trim();
    if (text.isEmpty) return null;

    // Some sources send the epoch as a quoted number.
    final epoch = num.tryParse(text);
    if (epoch != null) return parse(epoch);

    // `DateTime.parse` reads a stamp carrying no zone designator as *local*
    // time. These sources all mean UTC, so on a machine at UTC+3 that quietly
    // moves every reset three hours. Say UTC where the server left it out.
    // A date with no time of day is midnight UTC for the same reason, and it
    // has to be spelled out: `DateTime.parse` rejects a bare `2026-08-29Z`.
    final hasTime = RegExp('[T ]').hasMatch(text);
    final normalized = _hasZone(text)
        ? text
        : hasTime
        ? '${text}Z'
        : '${text}T00:00:00Z';
    return DateTime.tryParse(normalized)?.toLocal();
  }

  /// A trailing `Z`, or an offset such as `+03:00` / `-0800`.
  static bool _hasZone(String text) =>
      text.endsWith('Z') || text.endsWith('z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(text);
}
