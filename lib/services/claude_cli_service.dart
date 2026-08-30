import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/constants/app_constants.dart';
import '../core/services/app_paths.dart';
import '../models/cli_status.dart';
import '../models/status_line_data.dart';
import 'statusline_bridge_service.dart';

/// Read-only integration with the locally installed Claude Code CLI.
///
/// Reads: `claude --version`, `~/.claude/settings.json` (statusLine only),
/// `~/.claude/.credentials.json` (metadata only) plus, on macOS, whether the
/// Keychain holds a Claude Code sign-in (existence only), and the bridge's
/// `statusline.json`. Never writes to Claude's files.
class ClaudeCliService {
  CliStatus? _cached;
  DateTime? _cachedAt;

  Future<CliStatus> detect({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _cached != null &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < AppConstants.cliDetectCacheFor) {
      return _refreshVolatile(_cached!);
    }

    CliStatus status;
    try {
      final exe = await _locateExecutable();
      if (exe == null) {
        status = const CliStatus.notInstalled();
      } else {
        final version = await _readVersion(exe);
        final creds = await _readCredentialMetadata();
        final envKey = Platform.environment['ANTHROPIC_API_KEY'];
        final apiKeyEnv = envKey != null && envKey.trim().isNotEmpty;
        String? authType;
        if (creds != null) {
          authType = 'Claude.ai subscription (OAuth)';
        } else if (apiKeyEnv) {
          authType = 'API key (environment)';
        }
        status = CliStatus(
          installed: true,
          version: version,
          executablePath: exe,
          configDir: AppPaths.claudeConfigDir,
          settingsPath: AppPaths.claudeSettingsFile,
          credentialsFound: creds != null,
          authType: authType,
          subscriptionType: creds?.subscriptionType,
          rateLimitTier: creds?.rateLimitTier,
          tokenExpiresAt: creds?.expiresAt,
          apiKeyEnvPresent: apiKeyEnv,
        );
      }
    } catch (e) {
      status = CliStatus.notInstalled(detectionError: e.runtimeType.toString());
    }

    _cached = status;
    _cachedAt = now;
    return _refreshVolatile(status);
  }

  /// Re-reads the cheap, frequently changing bits (settings.json statusLine,
  /// status-line file freshness) without re-running the CLI.
  Future<CliStatus> _refreshVolatile(CliStatus base) async {
    final facts = _readSettingsFacts();
    final data = await readStatusLineFile();
    // One extra stat per refresh, and the only way to tell a bridge that is
    // registered from one that can actually run.
    final scriptPresent = await File(AppPaths.bridgeScript).exists();
    return base.copyWith(
      bridgeInstalled: facts.bridgeInstalled,
      bridgeScriptPresent: scriptPresent,
      bridgeCommandCurrent: facts.commandCurrent,
      launchHookInstalled: facts.launchHookInstalled,
      statusLineHasRateLimits: data?.hasRateLimits ?? false,
      statusLineWindowIds: data?.windowIds ?? const <String>[],
      existingStatusLineCommand: facts.command,
      statusLineUpdatedAt: data?.observedAt,
      sessionModel: data?.modelDisplayName,
      sessionContextPercent: data?.contextUsedPercentage,
      sessionDirectory: data?.currentDirectory,
      claudeCodeVersion: data?.claudeCodeVersion,
    );
  }

  Future<String?> _locateExecutable() async {
    try {
      // `where` is Windows' locator; `which` is the POSIX one.
      final locator = Platform.isWindows ? 'where' : 'which';
      final result = await Process.run(locator, ['claude'], runInShell: false)
          .timeout(const Duration(seconds: 8));
      if (result.exitCode == 0) {
        final lines = (result.stdout as String)
            .split(RegExp(r'\r?\n'))
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
        if (lines.isNotEmpty) return lines.first;
      }
    } catch (e) {
      debugPrint('locating claude failed: ${e.runtimeType}');
    }
    // A GUI-launched macOS app inherits only /usr/bin:/bin:/usr/sbin:/sbin,
    // not the login shell's PATH, so `which` misses every Homebrew, npm or
    // Volta install and the app declares Claude Code "not installed". Windows
    // does not have this problem — `where` reads the PATH from the registry.
    for (final candidate in _executableCandidates) {
      if (await File(candidate).exists()) return candidate;
    }
    return null;
  }

  /// Where Claude Code actually installs itself, checked directly so the
  /// answer does not depend on the PATH this process happened to inherit.
  static List<String> get _executableCandidates {
    final home = AppPaths.home;
    final name = AppConstants.claudeExecutableName;
    return <String>[
      p.join(home, '.local', 'bin', name),
      p.join(home, '.claude', 'local', name),
      if (!Platform.isWindows) ...<String>[
        '/opt/homebrew/bin/$name',
        '/usr/local/bin/$name',
        p.join(home, '.bun', 'bin', name),
        p.join(home, '.volta', 'bin', name),
        p.join(home, '.npm-global', 'bin', name),
        p.join(home, 'node_modules', '.bin', name),
      ],
    ];
  }

  Future<String?> _readVersion(String exe) async {
    try {
      final result = await Process.run(exe, ['--version'], runInShell: false)
          .timeout(const Duration(seconds: 20));
      final out = (result.stdout as String).trim();
      if (result.exitCode == 0 && out.isNotEmpty) {
        return out.split(RegExp(r'\r?\n')).first.trim();
      }
    } catch (e) {
      debugPrint('claude --version failed: ${e.runtimeType}');
    }
    return null;
  }

  /// The Keychain items Claude Code signs in to on macOS. Only ever queried
  /// for existence, never for the secret itself.
  static const List<String> _macKeychainServices = <String>[
    'Claude Code-credentials',
    'Claude Code',
  ];

  Future<_CredentialMetadata?> _readCredentialMetadata() async {
    final fromFile = _readCredentialFile();
    if (fromFile != null) return fromFile;
    // macOS keeps the OAuth token in the login Keychain rather than in
    // ~/.claude/.credentials.json, so the file check alone reports every Mac
    // as signed out. Asking for attributes only (no `-w`) answers "is there a
    // sign-in?" without reading the secret, and so without the authorization
    // prompt that reading it would raise. The plan and token expiry stay
    // unknown on macOS because they live inside the secret.
    if (Platform.isMacOS && await _keychainSignInExists()) {
      return const _CredentialMetadata();
    }
    return null;
  }

  Future<bool> _keychainSignInExists() async {
    for (final service in _macKeychainServices) {
      try {
        final result = await Process.run('security', ['find-generic-password', '-s', service])
            .timeout(const Duration(seconds: 8));
        if (result.exitCode == 0) return true;
      } catch (e) {
        debugPrint('keychain lookup failed: ${e.runtimeType}');
      }
    }
    return false;
  }

  _CredentialMetadata? _readCredentialFile() {
    try {
      final file = File(AppPaths.claudeCredentialsFile);
      if (!file.existsSync()) return null;
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return null;
      final oauth = decoded['claudeAiOauth'];
      if (oauth is! Map) return null;
      final exp = oauth['expiresAt'];
      return _CredentialMetadata(
        subscriptionType: oauth['subscriptionType']?.toString(),
        rateLimitTier: oauth['rateLimitTier']?.toString(),
        expiresAt: exp is num ? DateTime.fromMillisecondsSinceEpoch(exp.toInt()) : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// Returns the OAuth access token for the opt-in usage endpoint only.
  /// The value stays in memory for the duration of one request.
  Future<String?> readOAuthAccessToken() async {
    try {
      final file = File(AppPaths.claudeCredentialsFile);
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        final oauth = decoded is Map ? decoded['claudeAiOauth'] : null;
        final token = oauth is Map ? oauth['accessToken'] : null;
        if (token is String && token.isNotEmpty) return token;
      }
    } catch (_) {
      // Fall through to the Keychain on macOS.
    }
    // Reached only for the opt-in usage endpoint, which is the one place the
    // secret itself is needed. Unlike the presence check above this may raise
    // a one-time Keychain prompt — acceptable because the user turned the
    // setting on deliberately.
    if (Platform.isMacOS) return _keychainAccessToken();
    return null;
  }

  Future<String?> _keychainAccessToken() async {
    for (final service in _macKeychainServices) {
      try {
        final result = await Process.run('security', ['find-generic-password', '-s', service, '-w'])
            .timeout(AppConstants.httpTimeout);
        if (result.exitCode != 0) continue;
        final decoded = jsonDecode((result.stdout as String).trim());
        if (decoded is! Map) continue;
        final oauth = decoded['claudeAiOauth'];
        if (oauth is! Map) continue;
        final token = oauth['accessToken'];
        if (token is String && token.isNotEmpty) return token;
      } catch (e) {
        debugPrint('keychain token read failed: ${e.runtimeType}');
      }
    }
    return null;
  }

  /// One read of `settings.json`, answering everything that is asked of it:
  /// is our status line registered, is it still the command this build would
  /// write, and is the SessionStart hook there.
  _SettingsFacts _readSettingsFacts() {
    const empty = _SettingsFacts();
    try {
      final file = File(AppPaths.claudeSettingsFile);
      if (!file.existsSync()) return empty;
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return empty;
      final sl = decoded['statusLine'];
      final cmd = sl is Map ? sl['command']?.toString() : null;
      final isBridge = cmd != null && cmd.contains(AppConstants.bridgeMarker);
      return _SettingsFacts(
        bridgeInstalled: isBridge,
        command: cmd,
        commandCurrent: isBridge && cmd == StatusLineBridgeService.bridgeCommand,
        launchHookInstalled: _hasLaunchHook(decoded['hooks']),
      );
    } catch (_) {
      return empty;
    }
  }

  /// Mirrors the test the bridge service makes when it installs the hook.
  static bool _hasLaunchHook(Object? hooks) {
    if (hooks is! Map) return false;
    final sessionStart = hooks['SessionStart'];
    if (sessionStart is! List) return false;
    for (final entry in sessionStart) {
      final inner = entry is Map ? entry['hooks'] : null;
      if (inner is! List) continue;
      for (final hook in inner) {
        final cmd = hook is Map ? hook['command'] : null;
        if (cmd is String && cmd.contains(AppConstants.launchHookMarker)) return true;
      }
    }
    return false;
  }

  Future<StatusLineData?> readStatusLineFile() async {
    try {
      final file = File(AppPaths.statusLineFile);
      if (!await file.exists()) return null;
      final stat = await file.stat();
      final text = await file.readAsString();
      if (text.trim().isEmpty) return null;
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return null;
      return StatusLineData.fromJson(decoded, stat.modified);
    } catch (e) {
      debugPrint('statusline.json unreadable: ${e.runtimeType}');
      return null;
    }
  }
}

/// What one read of `settings.json` told us.
class _SettingsFacts {
  const _SettingsFacts({
    this.bridgeInstalled = false,
    this.command,
    this.commandCurrent = false,
    this.launchHookInstalled = false,
  });

  final bool bridgeInstalled;
  final String? command;
  final bool commandCurrent;
  final bool launchHookInstalled;
}

class _CredentialMetadata {
  const _CredentialMetadata({this.subscriptionType, this.rateLimitTier, this.expiresAt});

  final String? subscriptionType;
  final String? rateLimitTier;
  final DateTime? expiresAt;
}
