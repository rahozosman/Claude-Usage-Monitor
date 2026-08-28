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
  final bool bridgeInstalled;
  final String? existingStatusLineCommand;
  final DateTime? statusLineUpdatedAt;
  final String? sessionModel;
  final double? sessionContextPercent;
  final String? sessionDirectory;
  final String? claudeCodeVersion;
  final String? detectionError;

  bool get hasOAuth => credentialsFound && subscriptionType != null;
  bool get tokenExpired =>
      tokenExpiresAt != null && DateTime.now().isAfter(tokenExpiresAt!);

  bool sessionActive(DateTime now) =>
      statusLineUpdatedAt != null && now.difference(statusLineUpdatedAt!).inMinutes < 3;

  CliStatus copyWith({
    bool? bridgeInstalled,
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
