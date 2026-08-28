import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:tray_manager/tray_manager.dart';

import '../core/constants/app_constants.dart';

/// System tray icon + right-click menu.
class TrayService with TrayListener {
  TrayService({
    required this.onShow,
    required this.onHide,
    required this.onToggle,
    required this.onRefresh,
    required this.onSettings,
    required this.onToggleStartup,
    required this.onQuit,
  });

  final VoidCallback onShow;
  final VoidCallback onHide;
  final VoidCallback onToggle;
  final VoidCallback onRefresh;
  final VoidCallback onSettings;
  final VoidCallback onToggleStartup;
  final VoidCallback onQuit;

  bool _ready = false;

  static const String _kShow = 'show';
  static const String _kHide = 'hide';
  static const String _kRefresh = 'refresh';
  static const String _kSettings = 'settings';
  static const String _kStartup = 'startup';
  static const String _kQuit = 'quit';

  /// Where the bundled tray image actually sits at runtime.
  ///
  /// Windows lays the assets out beside the exe; a macOS .app keeps them
  /// inside the App framework's Resources. The formats differ too — the
  /// status bar cannot use an .ico.
  String get _iconPath {
    final dir = p.dirname(Platform.resolvedExecutable);
    if (Platform.isMacOS) {
      return p.join(dir, '..', 'Frameworks', 'App.framework', 'Resources', 'flutter_assets', 'assets', 'icons',
          'app_icon.png');
    }
    return p.join(dir, 'data', 'flutter_assets', 'assets', 'icons', 'app_icon.ico');
  }

  Future<void> init() async {
    try {
      await trayManager.setIcon(_iconPath);
      await trayManager.setToolTip(AppConstants.appName);
      trayManager.addListener(this);
      _ready = true;
    } catch (e) {
      debugPrint('Tray init failed: ${e.runtimeType}');
    }
  }

  Future<void> updateMenu({required bool dashboardVisible, required bool startWithWindows}) async {
    if (!_ready) return;
    try {
      await trayManager.setContextMenu(Menu(items: <MenuItem>[
        MenuItem(key: _kShow, label: 'Show Dashboard', disabled: dashboardVisible),
        MenuItem(key: _kHide, label: 'Hide Dashboard', disabled: !dashboardVisible),
        MenuItem.separator(),
        MenuItem(key: _kRefresh, label: 'Refresh'),
        MenuItem(key: _kSettings, label: 'Settings'),
        MenuItem.checkbox(key: _kStartup, label: AppConstants.startupLabel, checked: startWithWindows),
        MenuItem.separator(),
        MenuItem(key: _kQuit, label: 'Quit'),
      ]));
    } catch (e) {
      debugPrint('Tray menu update failed: ${e.runtimeType}');
    }
  }

  Future<void> setTooltip(String text) async {
    if (!_ready) return;
    try {
      await trayManager.setToolTip(text);
    } catch (_) {}
  }

  Future<void> destroy() async {
    if (!_ready) return;
    trayManager.removeListener(this);
    try {
      await trayManager.destroy();
    } catch (_) {}
  }

  @override
  void onTrayIconMouseDown() => onToggle();

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _kShow:
        onShow();
      case _kHide:
        onHide();
      case _kRefresh:
        onRefresh();
      case _kSettings:
        onSettings();
      case _kStartup:
        onToggleStartup();
      case _kQuit:
        onQuit();
    }
  }
}
