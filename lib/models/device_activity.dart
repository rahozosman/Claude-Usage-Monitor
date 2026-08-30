/// What one device running this monitor is doing, as published by that
/// device into the shared sync folder. Every number here is real: it comes
/// from that machine's own Claude Code transcripts, the same way the
/// "What used it · this PC" card is built locally.
class DeviceActivity {
  const DeviceActivity({
    required this.deviceId,
    required this.name,
    required this.updatedAt,
    required this.activeSessions,
    required this.todaySessionCount,
    required this.todayTokens,
    required this.weekTokens,
    required this.todayTokensByModel,
    required this.sessions,
    this.user,
    this.platform,
  });

  final String deviceId;
  final String name;
  final String? user;
  final String? platform;

  /// When that device last wrote its file (its own clock, UTC).
  final DateTime updatedAt;
  final int activeSessions;
  final int todaySessionCount;
  final int todayTokens;
  final int weekTokens;
  final Map<String, int> todayTokensByModel;

  /// Newest first; at most a handful.
  final List<DeviceSession> sessions;

  /// Its monitor has reported within the last few minutes (sync lag included).
  ///
  /// A timestamp ahead of ours means that machine's clock runs fast, not that
  /// it went quiet, so it counts as having just reported. Comparing the
  /// distance in both directions (the previous behaviour) turned a few
  /// minutes of ordinary clock skew into a device that never looks online.
  bool isOnline(DateTime now) => now.toUtc().difference(updatedAt) <= const Duration(seconds: 120);

  /// Sessions that device reported as open right now.
  List<DeviceSession> openSessions(DateTime now) =>
      isOnline(now) ? sessions.where((s) => s.active).toList() : const <DeviceSession>[];

  /// Online *and* has a Claude Code session with recent activity.
  bool isActive(DateTime now) => isOnline(now) && activeSessions > 0;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': 1,
    'deviceId': deviceId,
    'name': name,
    'user': ?user,
    'platform': ?platform,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'activeSessions': activeSessions,
    'todaySessionCount': todaySessionCount,
    'todayTokens': todayTokens,
    'weekTokens': weekTokens,
    'todayTokensByModel': todayTokensByModel,
    'sessions': sessions.map((s) => s.toJson()).toList(),
  };

  /// Tolerant: unknown or missing fields fall back instead of failing.
  static DeviceActivity? fromJson(Map<String, dynamic> json) {
    final id = json['deviceId'];
    final updated = DateTime.tryParse(json['updatedAt'] is String ? json['updatedAt'] as String : '');
    if (id is! String || id.isEmpty || updated == null) return null;
    int i(String k) => json[k] is num ? (json[k] as num).toInt() : 0;
    final byModel = <String, int>{};
    final rawModels = json['todayTokensByModel'];
    if (rawModels is Map) {
      rawModels.forEach((k, v) {
        if (k is String && v is num) byModel[k] = v.toInt();
      });
    }
    final sessions = <DeviceSession>[];
    final rawSessions = json['sessions'];
    if (rawSessions is List) {
      for (final s in rawSessions) {
        if (s is Map<String, dynamic>) {
          final parsed = DeviceSession.fromJson(s);
          if (parsed != null) sessions.add(parsed);
        }
      }
    }
    return DeviceActivity(
      deviceId: id,
      name: json['name'] is String && (json['name'] as String).isNotEmpty ? json['name'] as String : id,
      user: json['user'] is String ? json['user'] as String : null,
      platform: json['platform'] is String ? json['platform'] as String : null,
      updatedAt: updated.toUtc(),
      activeSessions: i('activeSessions'),
      todaySessionCount: i('todaySessionCount'),
      todayTokens: i('todayTokens'),
      weekTokens: i('weekTokens'),
      todayTokensByModel: byModel,
      sessions: sessions,
    );
  }
}

/// One session on another device: what it is working on.
class DeviceSession {
  const DeviceSession({
    required this.title,
    required this.project,
    required this.models,
    required this.tokens,
    required this.lastAt,
    required this.active,
    this.latestModel,
    this.outputTokens = 0,
    this.messages = 0,
  });

  final String title;
  final String project;
  final List<String> models;

  /// Model of that session's newest response (real, from its transcript).
  final String? latestModel;

  /// Everything that session sent and received (input + cache + output).
  final int tokens;

  /// Of that, what Claude generated.
  final int outputTokens;

  /// How many responses that session has had.
  final int messages;
  final DateTime lastAt;
  final bool active;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'title': title,
    'project': project,
    'models': models,
    'latestModel': ?latestModel,
    'tokens': tokens,
    'outputTokens': outputTokens,
    'messages': messages,
    'lastAt': lastAt.toUtc().toIso8601String(),
    'active': active,
  };

  static DeviceSession? fromJson(Map<String, dynamic> json) {
    final last = DateTime.tryParse(json['lastAt'] is String ? json['lastAt'] as String : '');
    if (last == null) return null;
    return DeviceSession(
      title: json['title'] is String ? json['title'] as String : 'Untitled session',
      project: json['project'] is String ? json['project'] as String : '',
      models: json['models'] is List ? (json['models'] as List).whereType<String>().toList() : const <String>[],
      tokens: json['tokens'] is num ? (json['tokens'] as num).toInt() : 0,
      outputTokens: json['outputTokens'] is num ? (json['outputTokens'] as num).toInt() : 0,
      messages: json['messages'] is num ? (json['messages'] as num).toInt() : 0,
      lastAt: last.toUtc(),
      active: json['active'] == true,
      latestModel: json['latestModel'] is String ? json['latestModel'] as String : null,
    );
  }
}

/// Outcome of one sync pass: where we looked and what the other devices said.
class DeviceSyncResult {
  const DeviceSyncResult({
    this.folder,
    this.devices = const <DeviceActivity>[],
    this.error,
    this.enabled = true,
    this.thisDeviceName,
    this.publishedAt,
    this.publishError,
  });

  /// Resolved shared folder, or null when none is configured/available.
  final String? folder;
  final List<DeviceActivity> devices;

  /// Reading the folder failed. The other devices are unknown this pass.
  final String? error;
  final bool enabled;

  /// This machine, so the card can show that it is holding up its own end.
  final String? thisDeviceName;

  /// When this device last wrote its own file, null until it has.
  final DateTime? publishedAt;

  /// Writing our file failed while reading others still worked — kept apart
  /// from [error] because the two have completely different consequences.
  final String? publishError;

  static const DeviceSyncResult none = DeviceSyncResult();

  int onlineCount(DateTime now) => devices.where((d) => d.isOnline(now)).length;
  int activeCount(DateTime now) => devices.where((d) => d.isActive(now)).length;

  /// Total Claude Code sessions open across every online device.
  int openSessionCount(DateTime now) =>
      devices.where((d) => d.isOnline(now)).fold(0, (sum, d) => sum + d.activeSessions);
}
