import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/constants/app_constants.dart';
import '../core/errors/app_error.dart';
import '../core/services/app_paths.dart';

/// Installs a tiny PowerShell "bridge" as Claude Code's `statusLine.command`.
///
/// The bridge stores the JSON Claude Code emits (which includes the official
/// `rate_limits` block for subscribers) and then forwards it to whatever
/// status line the user had before, so nothing is lost.
///
/// This is the only place the app writes to `~/.claude/settings.json`, and it
/// backs the file up before every change. Installing runs on an explicit user
/// action or once automatically on first launch.
class StatusLineBridgeService {
  /// Every mutator below is a read-modify-write of the same
  /// `~/.claude/settings.json`, and startup can fire two of them at once (the
  /// first-run bridge install and the "Open with Claude Code" launch hook).
  /// Queueing them stops one from clobbering the other's edit.
  Future<void> _queue = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, stack) {
        completer.completeError(e, stack);
      }
    });
    return completer.future;
  }
  static const String _scriptTemplate = r'''
# Claude Usage Monitor - status-line bridge
# Receives Claude Code's status-line JSON on stdin, stores it for the monitor,
# then forwards it to your previous status line (if any) or prints a compact line.
$ErrorActionPreference = 'SilentlyContinue'
$json = [Console]::In.ReadToEnd()
$dir = Join-Path $env:LOCALAPPDATA 'ClaudeUsageMonitor'
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
$tmp = Join-Path $dir ('statusline.' + $PID + '.tmp')
[IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
Move-Item -Force -Path $tmp -Destination (Join-Path $dir 'statusline.json')

$forward = $null
$cfgPath = Join-Path $dir 'bridge\bridge-config.json'
if (Test-Path $cfgPath) {
  try { $forward = (Get-Content $cfgPath -Raw | ConvertFrom-Json).forward } catch { }
}

if ($forward) {
  $bash = Get-Command bash.exe -ErrorAction SilentlyContinue
  if ($bash) { $json | & $bash.Source -c $forward }
  else { $json | powershell -NoProfile -Command $forward }
} else {
  try {
    $d = $json | ConvertFrom-Json
    $parts = @()
    if ($d.model.display_name) { $parts += "[$($d.model.display_name)]" }
    if ($null -ne $d.context_window.used_percentage) { $parts += ('ctx ' + [math]::Round($d.context_window.used_percentage) + '%') }
    if ($null -ne $d.rate_limits.five_hour.used_percentage) { $parts += ('5h ' + [math]::Round($d.rate_limits.five_hour.used_percentage) + '%') }
    if ($null -ne $d.rate_limits.seven_day.used_percentage) { $parts += ('7d ' + [math]::Round($d.rate_limits.seven_day.used_percentage) + '%') }
    Write-Output ($parts -join ' | ')
  } catch { }
}
''';

  /// The macOS equivalent: same contract, written for `sh` because that is what
  /// Claude Code hands `statusLine.command` to. The previous status line is
  /// kept as plain text next to it rather than parsed back out of JSON — sh has
  /// no JSON parser worth relying on, and macOS ships no guaranteed python3.
  static const String _macScriptTemplate = r'''
#!/bin/sh
# Claude Usage Monitor - status-line bridge
# Receives Claude Code's status-line JSON on stdin, stores it for the monitor,
# then forwards it to your previous status line (if you had one).
dir="$HOME/Library/Application Support/ClaudeUsageMonitor"
mkdir -p "$dir" 2>/dev/null
json=$(cat)
tmp="$dir/statusline.$$.tmp"
printf '%s' "$json" > "$tmp" 2>/dev/null
mv -f "$tmp" "$dir/statusline.json" 2>/dev/null

fwd="$dir/bridge/forward"
if [ -s "$fwd" ]; then
  printf '%s' "$json" | /bin/sh -c "$(cat "$fwd")"
  exit 0
fi

model=$(printf '%s' "$json" | sed -n 's/.*"display_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
five=$(printf '%s' "$json" | sed -n 's/.*"five_hour"[^}]*"used_percentage"[[:space:]]*:[[:space:]]*\([0-9][0-9.]*\).*/\1/p')
week=$(printf '%s' "$json" | sed -n 's/.*"seven_day"[^}]*"used_percentage"[[:space:]]*:[[:space:]]*\([0-9][0-9.]*\).*/\1/p')
out=""
[ -n "$model" ] && out="[$model]"
[ -n "$five" ] && out="$out 5h ${five%%.*}%"
[ -n "$week" ] && out="$out 7d ${week%%.*}%"
[ -n "$out" ] && printf '%s\n' "$out"
exit 0
''';

  String get bridgeCommand => Platform.isWindows
      ? 'powershell -NoProfile -ExecutionPolicy Bypass -File ${AppPaths.forwardSlashes(AppPaths.bridgeScript)}'
      // The path contains a space on macOS ("Application Support"), and
      // Claude Code runs this through a shell, so it must stay quoted.
      : '/bin/sh "${AppPaths.bridgeScript}"';

  /// `/bin/sh` treats a trailing CR as part of the command, so a CRLF script
  /// fails on macOS with a baffling error. The templates are LF in source,
  /// but a Windows checkout with `core.autocrlf` would rewrite them, so the
  /// bytes are normalised on the way out rather than trusted.
  static String _shellSafe(String script) =>
      Platform.isWindows ? script : script.replaceAll('\r\n', '\n');

  Future<bool> isInstalled() async {
    final settings = await _readSettings();
    return _isBridge(settings?['statusLine']);
  }

  /// Installs the bridge, preserving any status line the user already had.
  Future<void> install() => _serialized(_install);

  Future<void> _install() async {
    await Directory(AppPaths.bridgeDir).create(recursive: true);
    await File(AppPaths.bridgeScript)
        .writeAsString(_shellSafe((Platform.isWindows ? _scriptTemplate : _macScriptTemplate).trimLeft()));

    final settings = await _readSettings(throwOnMalformed: true) ?? <String, dynamic>{};
    final existing = settings['statusLine'];
    if (_isBridge(existing)) return; // already installed

    String? forward;
    Object? previous;
    int? padding;
    if (existing is Map) {
      previous = Map<String, dynamic>.from(existing);
      final cmd = existing['command'];
      if (cmd is String && cmd.trim().isNotEmpty) forward = cmd;
      final pad = existing['padding'];
      if (pad is int) padding = pad;
    }

    await File(AppPaths.bridgeConfig).writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
        'forward': forward,
        'previousStatusLine': previous,
        'installedAt': DateTime.now().toIso8601String(),
      }),
    );
    // The sh bridge reads the forward command from here; an empty file means
    // "there was nothing to forward to".
    await File(AppPaths.bridgeForward).writeAsString(forward ?? '');

    await _backupSettings();
    settings['statusLine'] = <String, dynamic>{'type': 'command', 'command': bridgeCommand, 'padding': ?padding};
    await _writeSettings(settings);
  }

  /// Removes the bridge and restores the previous status line.
  Future<void> uninstall() => _serialized(_uninstall);

  Future<void> _uninstall() async {
    final settings = await _readSettings(throwOnMalformed: true);
    if (settings != null && _isBridge(settings['statusLine'])) {
      Object? previous;
      try {
        final cfg = File(AppPaths.bridgeConfig);
        if (await cfg.exists()) {
          final decoded = jsonDecode(await cfg.readAsString());
          if (decoded is Map) previous = decoded['previousStatusLine'];
        }
      } catch (_) {}
      await _backupSettings();
      if (previous is Map && previous.isNotEmpty) {
        settings['statusLine'] = Map<String, dynamic>.from(previous);
      } else {
        settings.remove('statusLine');
      }
      await _writeSettings(settings);
    }
    try {
      final dir = Directory(AppPaths.bridgeDir);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  // ---- "Open with Claude Code" (SessionStart hook) ---------------------------

  static const String _launchScriptTemplate = r'''
# Claude Usage Monitor - run by Claude Code's SessionStart hook.
# Opens the monitor (as the small top tab) unless it is already running.
# Prints nothing on purpose: SessionStart output is added to Claude's context.
$ErrorActionPreference = 'SilentlyContinue'
$exe = '{{EXE}}'
$wake = Join-Path (Join-Path $env:LOCALAPPDATA 'ClaudeUsageMonitor') 'wake'
if (Get-Process -Name '{{PROC}}' -ErrorAction SilentlyContinue) {
  # Already running: just bring it forward (it may be hidden in the tray).
  [IO.File]::WriteAllText($wake, (Get-Date).ToString('o'))
  exit 0
}
if (Test-Path -LiteralPath $exe) {
  Start-Process -FilePath $exe -ArgumentList '--from-claude' -WorkingDirectory (Split-Path -Parent $exe) | Out-Null
}
exit 0
''';

  static const String _macLaunchScriptTemplate = r'''
#!/bin/sh
# Claude Usage Monitor - run by Claude Code's SessionStart hook.
# Opens the monitor (as the small edge tab) unless it is already running.
# Prints nothing on purpose: SessionStart output is added to Claude's context.
app='{{APP}}'
proc='{{PROC}}'
dir="$HOME/Library/Application Support/ClaudeUsageMonitor"
if pgrep -x "$proc" >/dev/null 2>&1 || pgrep -f "/$proc" >/dev/null 2>&1; then
  # Already running: just bring it forward (it may be hidden in the menu bar).
  mkdir -p "$dir" 2>/dev/null
  date +%Y-%m-%dT%H:%M:%S > "$dir/wake" 2>/dev/null
  exit 0
fi
if [ -d "$app" ]; then
  open -a "$app" --args --from-claude >/dev/null 2>&1
elif [ -x "$app" ]; then
  "$app" --from-claude >/dev/null 2>&1 &
fi
exit 0
''';

  /// The command Claude Code runs when a session starts or resumes.
  String get launchHookCommand => Platform.isWindows
      ? 'powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File '
            '${AppPaths.forwardSlashes(AppPaths.launchHookScript)}'
      : '/bin/sh "${AppPaths.launchHookScript}"';

  Future<bool> isLaunchHookInstalled() async => _hasLaunchHook(await _readSettings());

  /// Writes the launcher script and adds one `hooks.SessionStart` entry
  /// (matcher `startup|resume`). Existing hooks are preserved untouched.
  Future<void> installLaunchHook() => _serialized(_installLaunchHook);

  Future<void> _installLaunchHook() async {
    await AppPaths.ensureAppDataDir();
    final exe = Platform.resolvedExecutable;
    final proc = p.basenameWithoutExtension(exe);
    final String script;
    if (Platform.isWindows) {
      script = _launchScriptTemplate
          .trimLeft()
          .replaceAll('{{EXE}}', exe.replaceAll("'", "''"))
          .replaceAll('{{PROC}}', proc);
    } else {
      // `open` wants the .app bundle, which is three levels above the binary
      // (<name>.app/Contents/MacOS/<binary>). Fall back to the binary itself
      // when running unbundled, e.g. straight from `flutter run`.
      final macOsDir = p.dirname(exe);
      final bundle = p.dirname(p.dirname(macOsDir));
      final target = p.extension(bundle) == '.app' ? bundle : exe;
      script = _macLaunchScriptTemplate
          .trimLeft()
          .replaceAll('{{APP}}', target.replaceAll("'", "'\\''"))
          .replaceAll('{{PROC}}', proc);
    }
    await File(AppPaths.launchHookScript).writeAsString(_shellSafe(script));

    final settings = await _readSettings(throwOnMalformed: true) ?? <String, dynamic>{};
    if (_hasLaunchHook(settings)) return; // already installed

    final rawHooks = settings['hooks'];
    final hooks = rawHooks is Map ? Map<String, dynamic>.from(rawHooks) : <String, dynamic>{};
    final rawStart = hooks['SessionStart'];
    final sessionStart = rawStart is List ? List<Object?>.from(rawStart) : <Object?>[];
    sessionStart.add(<String, dynamic>{
      'matcher': 'startup|resume',
      'hooks': <Object?>[
        <String, dynamic>{'type': 'command', 'command': launchHookCommand, 'timeout': 15},
      ],
    });
    hooks['SessionStart'] = sessionStart;
    settings['hooks'] = hooks;

    await _backupSettings();
    await _writeSettings(settings);
  }

  /// Removes only our hook entries; empty `SessionStart` / `hooks` containers
  /// left behind are dropped so the file looks as it did before.
  Future<void> uninstallLaunchHook() => _serialized(_uninstallLaunchHook);

  Future<void> _uninstallLaunchHook() async {
    final settings = await _readSettings(throwOnMalformed: true);
    if (settings != null && _hasLaunchHook(settings)) {
      final hooks = Map<String, dynamic>.from(settings['hooks'] as Map);
      final kept = <Object?>[];
      for (final entry in hooks['SessionStart'] as List) {
        final inner = entry is Map ? entry['hooks'] : null;
        if (inner is! List) {
          kept.add(entry);
          continue;
        }
        final remaining = inner.where((h) => !_isLaunchHook(h)).toList();
        if (remaining.isEmpty) continue;
        if (remaining.length == inner.length) {
          kept.add(entry);
        } else {
          kept.add(Map<String, dynamic>.from(entry as Map)..['hooks'] = remaining);
        }
      }
      if (kept.isEmpty) {
        hooks.remove('SessionStart');
      } else {
        hooks['SessionStart'] = kept;
      }
      if (hooks.isEmpty) {
        settings.remove('hooks');
      } else {
        settings['hooks'] = hooks;
      }
      await _backupSettings();
      await _writeSettings(settings);
    }
    try {
      final file = File(AppPaths.launchHookScript);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Startup path for the "Open with Claude Code" setting: installs once if
  /// missing, refreshes the launcher script, and never throws.
  Future<void> ensureLaunchHook() async {
    try {
      await installLaunchHook();
    } catch (e) {
      debugPrint('Launch hook install failed: ${e.runtimeType}');
    }
  }

  bool _hasLaunchHook(Map<String, dynamic>? settings) {
    final hooks = settings?['hooks'];
    if (hooks is! Map) return false;
    final sessionStart = hooks['SessionStart'];
    if (sessionStart is! List) return false;
    for (final entry in sessionStart) {
      final inner = entry is Map ? entry['hooks'] : null;
      if (inner is List && inner.any(_isLaunchHook)) return true;
    }
    return false;
  }

  bool _isLaunchHook(Object? hook) {
    if (hook is! Map) return false;
    final cmd = hook['command'];
    return cmd is String && cmd.contains(AppConstants.launchHookMarker);
  }

  bool _isBridge(Object? statusLine) {
    if (statusLine is! Map) return false;
    final cmd = statusLine['command'];
    return cmd is String && cmd.contains(AppConstants.bridgeMarker);
  }

  Future<Map<String, dynamic>?> _readSettings({bool throwOnMalformed = false}) async {
    final file = File(AppPaths.claudeSettingsFile);
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) return decoded;
      if (throwOnMalformed) {
        throw AppError.malformed('settings.json is not a JSON object');
      }
      return null;
    } on AppError {
      rethrow;
    } catch (e) {
      if (throwOnMalformed) {
        throw AppError(
          AppErrorKind.malformed,
          'Claude Code settings.json could not be parsed — not modifying it',
          detail: e.runtimeType.toString(),
        );
      }
      return null;
    }
  }

  Future<void> _backupSettings() async {
    final src = File(AppPaths.claudeSettingsFile);
    if (!await src.exists()) return;
    await Directory(AppPaths.backupsDir).create(recursive: true);
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    await src.copy(p.join(AppPaths.backupsDir, 'settings.json.$stamp.bak'));
  }

  Future<void> _writeSettings(Map<String, dynamic> settings) async {
    final file = File(AppPaths.claudeSettingsFile);
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString('${const JsonEncoder.withIndent('  ').convert(settings)}\n');
    await tmp.rename(file.path);
  }
}
