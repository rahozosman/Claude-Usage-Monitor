import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/services/app_paths.dart';
import '../models/session_usage.dart';
import '../models/usage_stats.dart';

/// Reads the transcripts Claude Code keeps under `~/.claude/projects/` and
/// aggregates real token counts per session (task) and per model.
///
/// This is the same local data Claude Code's own `/usage` breakdown uses; it
/// covers this machine only and is not a limit percentage.
///
/// Cost control: the first scan runs in an isolate; afterwards only files that
/// grew are read, from the previous byte offset, capped per refresh.
class LocalUsageService {
  static const Duration window = Duration(days: 7);
  static const int maxBytesPerFilePerScan = 4 * 1024 * 1024;

  final Map<String, _FileState> _files = <String, _FileState>{};
  Future<void>? _initialScan;
  bool _initialDone = false;
  LocalUsageReport? _last;

  LocalUsageReport? get lastReport => _last;
  bool get scanning => _initialScan != null && !_initialDone;

  /// Returns the latest report, or null while the first scan is still running.
  Future<LocalUsageReport?> scan() async {
    final dir = Directory(p.join(AppPaths.claudeConfigDir, 'projects'));
    if (!await dir.exists()) return null;
    final cutoff = DateTime.now().subtract(window);
    final files = await _recentTranscripts(dir, cutoff);

    if (!_initialDone) {
      _initialScan ??= _runInitialScan(files).whenComplete(() => _initialDone = true);
      if (!_initialDone) return _last;
    }

    // Incremental pass on the main isolate — only changed files, bounded reads.
    for (final entry in files) {
      final state = _files.putIfAbsent(entry.path, () => _FileState(p.basenameWithoutExtension(entry.path)));
      if (entry.size == state.size && entry.size == state.offset) continue;
      try {
        await _readIncremental(entry.path, state);
      } catch (e) {
        debugPrint('transcript read failed: ${e.runtimeType}');
      }
    }
    _files.removeWhere((path, _) => !files.any((f) => f.path == path));

    final active = await _activeSessionIds();
    _last = _buildReport(active, files.length);
    return _last;
  }

  Future<void> _runInitialScan(List<_Entry> files) async {
    try {
      final paths = files.map((e) => e.path).toList();
      final result = await Isolate.run(() => _scanAll(paths));
      _files.addAll(result);
    } catch (e) {
      debugPrint('initial transcript scan failed: ${e.runtimeType}');
    }
  }

  static Map<String, _FileState> _scanAll(List<String> paths) {
    final out = <String, _FileState>{};
    for (final path in paths) {
      final state = _FileState(p.basenameWithoutExtension(path));
      try {
        final bytes = File(path).readAsBytesSync();
        state.consume(utf8.decode(bytes, allowMalformed: true));
        state.offset = bytes.length;
        state.size = bytes.length;
      } catch (_) {
        // unreadable file: leave empty state so we retry incrementally later
      }
      out[path] = state;
    }
    return out;
  }

  Future<void> _readIncremental(String path, _FileState state) async {
    final file = File(path);
    final length = await file.length();
    if (length < state.offset) {
      // Truncated/rewritten: start over.
      state.reset();
    }
    if (length == state.offset) {
      state.size = length;
      return;
    }
    final raf = await file.open();
    try {
      await raf.setPosition(state.offset);
      final toRead = (length - state.offset).clamp(0, maxBytesPerFilePerScan);
      final bytes = await raf.read(toRead);
      state.consume(utf8.decode(bytes, allowMalformed: true));
      state.offset += bytes.length;
      state.size = length;
    } finally {
      await raf.close();
    }
  }

  Future<List<_Entry>> _recentTranscripts(Directory dir, DateTime cutoff) async {
    final out = <_Entry>[];
    await for (final project in dir.list(followLinks: false)) {
      if (project is! Directory) continue;
      await for (final f in project.list(followLinks: false)) {
        if (f is! File || !f.path.endsWith('.jsonl')) continue;
        try {
          final stat = await f.stat();
          if (stat.modified.isAfter(cutoff)) {
            out.add(_Entry(f.path, stat.size, stat.modified));
          }
        } catch (_) {}
      }
    }
    return out;
  }

  /// Session IDs whose Claude Code process is still alive.
  Future<Set<String>> _activeSessionIds() async {
    final result = <String>{};
    try {
      final dir = Directory(p.join(AppPaths.claudeConfigDir, 'sessions'));
      if (!await dir.exists()) return result;
      final candidates = <int, String>{};
      await for (final f in dir.list(followLinks: false)) {
        if (f is! File || !f.path.endsWith('.json')) continue;
        try {
          final decoded = jsonDecode(await f.readAsString());
          if (decoded is Map && decoded['pid'] is int && decoded['sessionId'] is String) {
            candidates[decoded['pid'] as int] = decoded['sessionId'] as String;
          }
        } catch (_) {}
      }
      if (candidates.isEmpty) return result;
      final alive = await _livePids();
      candidates.forEach((pid, id) {
        if (alive.contains(pid)) result.add(id);
      });
    } catch (_) {}
    return result;
  }

  Set<int>? _pidCache;
  DateTime? _pidCacheAt;

  /// `tasklist` is a process spawn, and the activity tick runs every 15 s, so
  /// the answer is reused for a few seconds.
  Future<Set<int>> _livePids() async {
    final cached = _pidCache;
    final at = _pidCacheAt;
    if (cached != null && at != null && DateTime.now().difference(at) < const Duration(seconds: 10)) {
      return cached;
    }
    try {
      final pids = <int>{};
      if (Platform.isWindows) {
        final r = await Process.run('tasklist', ['/fo', 'csv', '/nh']).timeout(const Duration(seconds: 8));
        for (final line in (r.stdout as String).split('\n')) {
          final cols = line.split('","');
          if (cols.length > 1) {
            final pid = int.tryParse(cols[1].replaceAll('"', '').trim());
            if (pid != null) pids.add(pid);
          }
        }
      } else {
        // macOS/POSIX: one pid per line, no header.
        final r = await Process.run('ps', ['-A', '-o', 'pid=']).timeout(const Duration(seconds: 8));
        for (final line in (r.stdout as String).split('\n')) {
          final pid = int.tryParse(line.trim());
          if (pid != null) pids.add(pid);
        }
      }
      _pidCache = pids;
      _pidCacheAt = DateTime.now();
      return pids;
    } catch (_) {
      return _pidCache ?? <int>{};
    }
  }

  LocalUsageReport _buildReport(Set<String> active, int scanned) {
    final now = DateTime.now();
    final cutoff = now.subtract(window);
    final cutoffDay = DateTime(cutoff.year, cutoff.month, cutoff.day);
    final todayKey = _dayKey(now);
    final today = <String, int>{};
    final week = <String, int>{};
    final sessions = <SessionUsage>[];
    var todaySessions = 0;

    for (final st in _files.values) {
      if (st.messages == 0 || st.lastAt == null || st.lastAt!.isBefore(cutoff)) continue;
      st.dayModelTokens.forEach((day, byModel) {
        final dayDate = UsageStats.parseDay(day);
        if (dayDate == null || dayDate.isBefore(cutoffDay)) return;
        byModel.forEach((model, tokens) {
          week[model] = (week[model] ?? 0) + tokens.total;
          if (day == todayKey) today[model] = (today[model] ?? 0) + tokens.total;
        });
      });
      if (st.dayModelTokens.containsKey(todayKey)) todaySessions++;
      sessions.add(
        SessionUsage(
          sessionId: st.sessionId,
          title: st.title ?? st.firstPrompt ?? 'Untitled session',
          projectPath: st.cwd ?? '',
          models: st.models.toList()..sort(),
          latestModel: st.latestModel,
          inputTokens: st.input,
          cacheCreationTokens: st.cacheWrite,
          cacheReadTokens: st.cacheRead,
          outputTokens: st.output,
          messageCount: st.messages,
          firstAt: st.firstAt ?? st.lastAt!,
          lastAt: st.lastAt!,
          isActive: active.contains(st.sessionId),
        ),
      );
    }
    sessions.sort((a, b) => b.lastAt.compareTo(a.lastAt));
    return LocalUsageReport(
      computedAt: now,
      sessions: sessions,
      todayTokensByModel: today,
      weekTokensByModel: week,
      todaySessionCount: todaySessions,
      activeSessionCount: active.length,
      scannedFiles: scanned,
      dayRollups: _rollups(cutoffDay),
    );
  }

  /// The same per-day figures Claude Code keeps in its stats cache — messages,
  /// sessions, tool calls and tokens per model — counted from the transcripts
  /// this scan already read. Used to fill in the days Claude Code has not
  /// finished counting (see [UsageStats.withTranscriptDays]) and to give the
  /// 7-day input/output/cache split, which its cache only holds for all time.
  List<DayRollup> _rollups(DateTime cutoffDay) {
    final byDay = <String, _DayAggregate>{};
    for (final st in _files.values) {
      final days = <String>{...st.dayMessages.keys, ...st.dayToolCalls.keys, ...st.dayModelTokens.keys};
      for (final day in days) {
        final date = UsageStats.parseDay(day);
        if (date == null || date.isBefore(cutoffDay)) continue;
        final agg = byDay.putIfAbsent(day, () => _DayAggregate(date));
        final messages = st.dayMessages[day] ?? 0;
        agg.messages += messages;
        agg.toolCalls += st.dayToolCalls[day] ?? 0;
        // One transcript is one session, counted for every day it spoke on —
        // which is how Claude Code's own per-day session counts come out.
        if (messages > 0) agg.sessions++;
        st.dayModelTokens[day]?.forEach(agg.addTokens);
      }
    }
    final out = byDay.values.map((a) => a.toRollup()).toList()..sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  static String _dayKey(DateTime t) {
    final l = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)}';
  }
}

class _Entry {
  const _Entry(this.path, this.size, this.modified);

  final String path;
  final int size;
  final DateTime modified;
}

/// Parser state for one transcript (= one session). Append-only friendly.
class _FileState {
  _FileState(this.sessionId);

  final String sessionId;
  int size = 0;
  int offset = 0;
  String carry = '';
  String? title;
  String? firstPrompt;
  String? cwd;
  final Set<String> models = <String>{};

  /// Model of the newest assistant response — the one actually answering now.
  String? latestModel;
  DateTime? latestModelAt;
  final Set<String> seen = <String>{};
  int input = 0;
  int cacheWrite = 0;
  int cacheRead = 0;
  int output = 0;
  int messages = 0;
  DateTime? firstAt;
  DateTime? lastAt;
  final Map<String, Map<String, _Tokens>> dayModelTokens = <String, Map<String, _Tokens>>{};

  /// Day → entries in this transcript's message chain, and → tool calls: the
  /// two counts Claude Code publishes per day in its stats cache.
  final Map<String, int> dayMessages = <String, int>{};
  final Map<String, int> dayToolCalls = <String, int>{};

  void reset() {
    size = 0;
    offset = 0;
    carry = '';
    title = null;
    firstPrompt = null;
    cwd = null;
    models.clear();
    latestModel = null;
    latestModelAt = null;
    seen.clear();
    input = cacheWrite = cacheRead = output = messages = 0;
    firstAt = lastAt = null;
    dayModelTokens.clear();
    dayMessages.clear();
    dayToolCalls.clear();
  }

  void consume(String chunk) {
    final text = carry + chunk;
    final lines = text.split('\n');
    carry = lines.removeLast(); // incomplete trailing line (or '')
    for (final line in lines) {
      // Claude Code counts, per day, every entry in the transcript's message
      // chain — user, assistant, attachment and system. Those are exactly the
      // lines that open with `parentUuid`; the bookkeeping entries beside them
      // (file history, queue operations, frame links) carry no uuid and are
      // not counted. Checked against its own stats cache, to the message.
      if (line.startsWith(_chainPrefix)) {
        final day = _dayOfLine(line);
        if (day != null) dayMessages[day] = (dayMessages[day] ?? 0) + 1;
      }
      if (line.contains('"type":"assistant"')) {
        _assistant(line);
      } else if (title == null && line.contains('"type":"ai-title"')) {
        _title(line);
      } else if (firstPrompt == null && title == null && line.contains('"type":"user"')) {
        _user(line);
      }
    }
  }

  void _assistant(String line) {
    final o = _decode(line);
    if (o == null || o['type'] != 'assistant') return;
    final msg = o['message'];
    if (msg is! Map) return;

    final at = _time(o['timestamp']);
    final dayKey = at == null ? null : LocalUsageService._dayKey(at);

    // One tool call per `tool_use` block, counted on every line: a message
    // split across blocks repeats its requestId, but its calls are separate
    // calls, so this is counted before the de-duplication below.
    final content = msg['content'];
    if (dayKey != null && content is List) {
      var calls = 0;
      for (final block in content) {
        if (block is Map && block['type'] == 'tool_use') calls++;
      }
      if (calls > 0) dayToolCalls[dayKey] = (dayToolCalls[dayKey] ?? 0) + calls;
    }

    final usage = msg['usage'];
    if (usage is! Map) return;
    final id = (o['requestId'] ?? msg['id'])?.toString();
    if (id != null && !seen.add(id)) return; // multi-block message: count once

    int n(Object? v) => v is num ? v.toInt() : 0;
    final i = n(usage['input_tokens']);
    final cw = n(usage['cache_creation_input_tokens']);
    final cr = n(usage['cache_read_input_tokens']);
    final out = n(usage['output_tokens']);
    input += i;
    cacheWrite += cw;
    cacheRead += cr;
    output += out;
    messages++;

    final model = msg['model']?.toString();
    if (model != null && model.isNotEmpty) models.add(model);
    cwd ??= o['cwd']?.toString();

    if (at != null && dayKey != null) {
      firstAt = firstAt == null || at.isBefore(firstAt!) ? at : firstAt;
      lastAt = lastAt == null || at.isAfter(lastAt!) ? at : lastAt;
      if (model != null && model.isNotEmpty && (latestModelAt == null || !at.isBefore(latestModelAt!))) {
        latestModel = model;
        latestModelAt = at;
      }
      final byModel = dayModelTokens.putIfAbsent(dayKey, () => <String, _Tokens>{});
      final tokens = byModel.putIfAbsent(model ?? 'unknown', _Tokens.new);
      tokens.input += i;
      tokens.cacheWrite += cw;
      tokens.cacheRead += cr;
      tokens.output += out;
    }
  }

  void _title(String line) {
    final o = _decode(line);
    if (o == null) return;
    final t = (o['aiTitle'] ?? o['title'])?.toString().trim();
    if (t != null && t.isNotEmpty) title = t;
  }

  void _user(String line) {
    final o = _decode(line);
    if (o == null || o['type'] != 'user' || o['isSidechain'] == true || o['isMeta'] == true) return;
    final msg = o['message'];
    if (msg is! Map) return;
    final content = msg['content'];
    if (content is! String) return;
    var text = content.trim();
    if (text.isEmpty || text.startsWith('<') || text.startsWith('/')) return;
    text = text.split('\n').first.replaceAll(RegExp(r'^#+\s*'), '').trim();
    if (text.isEmpty) return;
    firstPrompt = text.length > 90 ? '${text.substring(0, 90)}…' : text;
  }

  /// Every message-chain entry opens with this key, and nothing else does.
  static const String _chainPrefix = '{"parentUuid":';
  static const String _timestampKey = '"timestamp":"';

  /// The entry's own timestamp, without decoding the line — in a chain entry
  /// the first `timestamp` is always the top-level one (the nested ones, if
  /// any, sit inside the message body that follows it).
  static String? _dayOfLine(String line) {
    final at = line.indexOf(_timestampKey);
    if (at < 0) return null;
    final start = at + _timestampKey.length;
    final end = line.indexOf('"', start);
    if (end <= start) return null;
    final time = DateTime.tryParse(line.substring(start, end));
    return time == null ? null : LocalUsageService._dayKey(time);
  }

  static Map<String, dynamic>? _decode(String line) {
    try {
      final o = jsonDecode(line);
      return o is Map<String, dynamic> ? o : null;
    } catch (_) {
      return null;
    }
  }

  static DateTime? _time(Object? v) {
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    return null;
  }
}

/// Running per-model token counts for one day of one transcript.
class _Tokens {
  int input = 0;
  int cacheWrite = 0;
  int cacheRead = 0;
  int output = 0;

  int get total => input + cacheWrite + cacheRead + output;

  ModelTotals toTotals() => ModelTotals(input: input, output: output, cacheRead: cacheRead, cacheWrite: cacheWrite);
}

/// One day, summed across every transcript that spoke on it.
class _DayAggregate {
  _DayAggregate(this.date);

  final DateTime date;
  int messages = 0;
  int sessions = 0;
  int toolCalls = 0;
  final Map<String, ModelTotals> tokens = <String, ModelTotals>{};

  void addTokens(String model, _Tokens value) {
    tokens[model] = (tokens[model] ?? const ModelTotals()) + value.toTotals();
  }

  DayRollup toRollup() => DayRollup(
    date: date,
    messages: messages,
    sessions: sessions,
    toolCalls: toolCalls,
    tokensByModel: tokens,
  );
}
