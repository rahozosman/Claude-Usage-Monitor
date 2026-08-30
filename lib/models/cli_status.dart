/// What we could safely learn about the local Claude Code installation.
/// Never holds tokens — only metadata.
class CliStatus {
  const CliStatus({
    required this.installed,
    this.version,
    this.executablePath,
    this.configDir,
    this.settingsPath,
    this.credentialsFound = false,
    this.authType,
    this.subscriptionType,
    this.rateLimitTier,
    this.tokenExpiresAt,
    this.apiKeyEnvPresent = false,
    this.bridgeInstalled = false,
    this.bridgeScriptPresent = false,
    this.bridgeCommandCurrent = false,
    this.launchHookInstalled = false,
    this.statusLineHasRateLimits = false,
    this.statusLineWindowIds = const <String>[],
    this.existingStatusLineCommand,
    this.statusLineUpdatedAt,
    this.sessionModel,
    this.sessionContextPercent,
    this.sessionDirectory,
    this.claudeCodeVersion,
    this.detectionError,
  });

  const CliStatus.notInstalled({this.detectionError})
      : installed = false,
        version = null,
        executablePath = null,
        configDir = null,
        settingsPath = null,
        credentialsFound = false,
        authType = null,
        subscriptionType = null,
        rateLimitTier = null,
        tokenExpiresAt = null,
        apiKeyEnvPresent = false,
        bridgeInstalled = false,
        bridgeScriptPresent = false,
        bridgeCommandCurrent = false,
        launchHookInstalled = false,
        statusLineHasRateLimits = false,
        statusLineWindowIds = const <String>[],
        existingStatusLineCommand = null,
        statusLineUpdatedAt = null,
        sessionModel = null,
        sessionContextPercent = null,
        sessionDirectory = null,
        claudeCodeVersion = null;

  final bool installed;
  final String? version;
  final String? executablePath;
  final String? configDir;
  final String? settingsPath;
  final bool credentialsFound;

  /// "Claude.ai subscription (OAuth)", "API key (environment)", or null.
  final String? authType;
  final String? subscriptionType;
  final String? rateLimitTier;
  final DateTime? tokenExpiresAt;
  final bool apiKeyEnvPresent;
  /// Our command is the one in `settings.json`.
  final bool bridgeInstalled;

  /// The script that command runs is actually on disk. Separate from
  /// [bridgeInstalled] on purpose: a registered bridge whose script was
  /// deleted looks installed and feeds nothing.
  final bool bridgeScriptPresent;

  /// The recorded command still matches the one this build would write —
  /// false after the app or the user profile moved.
  final bool bridgeCommandCurrent;

  /// The `SessionStart` hook that opens the monitor is registered.
  final bool launchHookInstalled;

  /// The last status line Claude Code sent carried a `rate_limits` block.
  /// Without it the windows have nothing to show, however healthy the
  /// rest of the chain is.
  final bool statusLineHasRateLimits;

  /// Which windows that block actually named. A feed can be perfectly healthy
  /// and still be missing `five_hour`, so the health card reports the ids
  /// rather than a bare "rate limits included" that contradicts a card
  /// showing "Unavailable" right next to it.
  final List<String> statusLineWindowIds;
  final String? existingStatusLineCommand;
  final DateTime? statusLineUpdatedAt;
  final String? sessionModel;
  final double? sessionContextPercent;
  final String? sessionDirectory;
  final String? claudeCodeVersion;
  final String? detectionError;

  /// [credentialsFound] is only ever set from an OAuth block that parsed, so
  /// it is the whole test. It does not also require [subscriptionType]: on
  /// macOS the token lives in the Keychain and only its *presence* is read,
  /// which would otherwise report every signed-in Mac as signed out.
  bool get hasOAuth => credentialsFound;

  /// All three parts of the bridge agree. Anything less feeds nothing,
  /// however healthy `settings.json` looks on its own.
  bool get bridgeHealthy => bridgeInstalled && bridgeScriptPresent && bridgeCommandCurrent;
  bool get tokenExpired =>
      tokenExpiresAt != null && DateTime.now().isAfter(tokenExpiresAt!);

  bool sessionActive(DateTime now) =>
      statusLineUpdatedAt != null && now.difference(statusLineUpdatedAt!).inMinutes < 3;

  CliStatus copyWith({
    bool? bridgeInstalled,
    bool? bridgeScriptPresent,
    bool? bridgeCommandCurrent,
    bool? launchHookInstalled,
    bool? statusLineHasRateLimits,
    List<String>? statusLineWindowIds,
    String? existingStatusLineCommand,
    DateTime? statusLineUpdatedAt,
    String? sessionModel,
    double? sessionContextPercent,
    String? sessionDirectory,
    String? claudeCodeVersion,
  }) {
    return CliStatus(
      installed: installed,
      version: version,
      executablePath: executablePath,
      configDir: configDir,
      settingsPath: settingsPath,
      credentialsFound: credentialsFound,
      authType: authType,
      subscriptionType: subscriptionType,
      rateLimitTier: rateLimitTier,
      tokenExpiresAt: tokenExpiresAt,
      apiKeyEnvPresent: apiKeyEnvPresent,
      bridgeInstalled: bridgeInstalled ?? this.bridgeInstalled,
      bridgeScriptPresent: bridgeScriptPresent ?? this.bridgeScriptPresent,
      bridgeCommandCurrent: bridgeCommandCurrent ?? this.bridgeCommandCurrent,
      launchHookInstalled: launchHookInstalled ?? this.launchHookInstalled,
      statusLineHasRateLimits: statusLineHasRateLimits ?? this.statusLineHasRateLimits,
      statusLineWindowIds: statusLineWindowIds ?? this.statusLineWindowIds,
      existingStatusLineCommand: existingStatusLineCommand ?? this.existingStatusLineCommand,
      statusLineUpdatedAt: statusLineUpdatedAt ?? this.statusLineUpdatedAt,
      sessionModel: sessionModel ?? this.sessionModel,
      sessionContextPercent: sessionContextPercent ?? this.sessionContextPercent,
      sessionDirectory: sessionDirectory ?? this.sessionDirectory,
      claudeCodeVersion: claudeCodeVersion ?? this.claudeCodeVersion,
      detectionError: detectionError,
    );
  }
}
