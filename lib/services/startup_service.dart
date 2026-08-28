import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:path/path.dart' as p;

import '../core/constants/app_constants.dart';

/// Start automatically when the user logs in.
///
/// Windows: a per-user Run registry entry (no admin needed).
/// macOS: a per-user login item.
class StartupService {
  bool _ready = false;

  Future<void> init() async {
    try {
      launchAtStartup.setup(
        appName: AppConstants.appName,
        appPath: _launchTarget,
        args: const <String>['--autostart'],
      );
      _ready = true;
    } catch (e) {
      debugPrint('launchAtStartup setup failed: ${e.runtimeType}');
    }
  }

  /// What the OS should actually launch.
  ///
  /// On macOS a login item has to point at the `.app` bundle, which sits
  /// three levels above the binary (`<name>.app/Contents/MacOS/<binary>`);
  /// registering the bare executable produces an item that launches without
  /// its resources. Everywhere else the executable is the right answer.
  static String get _launchTarget {
    final exe = Platform.resolvedExecutable;
    if (!Platform.isMacOS) return exe;
    final bundle = p.dirname(p.dirname(p.dirname(exe)));
    return p.extension(bundle) == '.app' ? bundle : exe;
  }

  Future<bool> isEnabled() async {
    if (!_ready) return false;
    try {
      return await launchAtStartup.isEnabled();
    } catch (_) {
      return false;
    }
  }

  Future<bool> setEnabled(bool enabled) async {
    if (!_ready) return false;
    try {
      return enabled ? await launchAtStartup.enable() : await launchAtStartup.disable();
    } catch (e) {
      debugPrint('launchAtStartup toggle failed: ${e.runtimeType}');
      return false;
    }
  }
}
