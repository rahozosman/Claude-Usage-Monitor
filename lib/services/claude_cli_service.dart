import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/constants/app_constants.dart';
import '../core/services/app_paths.dart';
import '../models/cli_status.dart';
import '../models/status_line_data.dart';

/// Read-only integration with the locally installed Claude Code CLI.
///
/// Reads: `claude --version`, `~/.claude/settings.json` (statusLine only),
/// `~/.claude/.credentials.json` (metadata only), and the bridge's
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
        final creds = _readCredentialMetadata();
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
    final sl = _readStatusLineSetting();
    final data = await readStatusLineFile();
    return base.copyWith(
      bridgeInstalled: sl.bridgeInstalled,
      existingStatusLineCommand: sl.command,
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
    final fallback = p.join(AppPaths.home, '.local', 'bin', AppConstants.claudeExecutableName);
    if (await File(fallback).exists()) return fallback;
    return null;
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

  _CredentialMetadata? _readCredentialMetadata() {
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
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      final oauth = decoded['claudeAiOauth'];
      if (oauth is! Map) return null;
      final token = oauth['accessToken'];
      return token is String && token.isNotEmpty ? token : null;
    } catch (_) {
      return null;
    }
  }

  ({bool bridgeInstalled, String? command}) _readStatusLineSetting() {
    try {
      final file = File(AppPaths.claudeSettingsFile);
      if (!file.existsSync()) return (bridgeInstalled: false, command: null);
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return (bridgeInstalled: false, command: null);
      final sl = decoded['statusLine'];
      if (sl is! Map) return (bridgeInstalled: false, command: null);
      final cmd = sl['command']?.toString();
      return (
        bridgeInstalled: cmd != null && cmd.contains(AppConstants.bridgeMarker),
        command: cmd,
      );
    } catch (_) {
      return (bridgeInstalled: false, command: null);
    }
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

class _CredentialMetadata {
  const _CredentialMetadata({this.subscriptionType, this.rateLimitTier, this.expiresAt});

  final String? subscriptionType;
  final String? rateLimitTier;
  final DateTime? expiresAt;
}
