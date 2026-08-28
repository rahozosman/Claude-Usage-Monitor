import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../services/tray_service.dart';
import '../../services/window_service.dart';
import '../dashboard/usage_controller.dart';
import '../settings/settings_controller.dart';

enum ShellPage { dashboard, settings }

/// The three states of the edge widget.
///
/// ```
/// COLLAPSED ──click──▶ LIMITS ──click──▶ HOME
///      ▲                  │                │
///      └────── click outside (either) ─────┘
/// ```
enum ShellStage { collapsed, limits, home }

/// Window-level state: which stage is showing, which page Home shows, and
/// whether the window is visible at all.
///
/// Growing sets the window bounds first so the glass has room to expand into;
/// shrinking plays the exit animation inside the current bounds and only then
/// pulls the window in, so the surface always looks like one piece of glass
/// changing shape rather than two windows swapping.
class ShellController extends ChangeNotifier {
  ShellController({required WindowService window, required SettingsController settings, required UsageController usage})
    : _window = window, // ignore: prefer_initializing_formals
      _settings = settings, // ignore: prefer_initializing_formals
      _usage = usage; // ignore: prefer_initializing_formals

  final WindowService _window;
  final SettingsController _settings;
  final UsageController _usage;
  TrayService? _tray;

  /// Exit-animation lengths, matched to the spec.
  static const int _toLimitsMs = 240;
  static const int _toHomeMs = 380;
  static const int _toCollapsedMs = 200;

  ShellStage _stage = ShellStage.collapsed;
  ShellStage _previousStage = ShellStage.collapsed;
  ShellPage _page = ShellPage.dashboard;
  bool _visible = true;
  bool _busy = false;
  Timer? _focusLossTimer;

  ShellStage get stage => _stage;

  /// The state the surface is morphing *from*, so the shell can cross-fade
  /// exactly two contents instead of flashing the one it passes over.
  ShellStage get previousStage => _previousStage;
  bool get collapsed => _stage == ShellStage.collapsed;
  bool get showingLimits => _stage == ShellStage.limits;
  bool get home => _stage == ShellStage.home;
  ShellPage get page => _page;
  bool get visible => _visible;

  void attachTray(TrayService tray) {
    _tray = tray;
    _settings.addListener(_syncTray);
    _syncTray();
  }

  void _syncTray() {
    unawaited(_tray?.updateMenu(dashboardVisible: _visible, startWithWindows: _settings.startWithWindows));
  }

  // ---- State transitions -----------------------------------------------------

  /// Tab → limits panel (grow), or Home → limits panel (shrink).
  Future<void> showLimits() => _goTo(ShellStage.limits, WindowMode.limits, _toLimitsMs);

  /// Limits panel → Home. Also used by Settings, from any state.
  Future<void> showHome({ShellPage page = ShellPage.dashboard}) async {
    _page = page;
    if (_stage == ShellStage.home) {
      notifyListeners();
      return;
    }
    await _goTo(ShellStage.home, WindowMode.home, _toHomeMs);
  }

  /// Anything → the tiny edge tab.
  Future<void> collapse() => _goTo(ShellStage.collapsed, WindowMode.tab, _toCollapsedMs);

  /// The click-through: tab → limits → home.
  Future<void> next() {
    switch (_stage) {
      case ShellStage.collapsed:
        return showLimits();
      case ShellStage.limits:
        return showHome();
      case ShellStage.home:
        return Future<void>.value();
    }
  }

  Future<void> _goTo(ShellStage stage, WindowMode mode, int exitMs) async {
    if (_stage == stage || _busy) return;
    _busy = true;
    try {
      final growing = stage.index > _stage.index;
      if (stage != ShellStage.home) _page = ShellPage.dashboard;

      if (growing) {
        // Make room first, then let the glass expand into it.
        await _window.applyMode(mode);
        _previousStage = _stage;
        _stage = stage;
        notifyListeners();
      } else {
        _previousStage = _stage;
        _stage = stage;
        notifyListeners();
        final ms = _settings.settings.animationsEnabled ? exitMs : 0;
        if (ms > 0) await Future<void>.delayed(Duration(milliseconds: ms));
        await _window.applyMode(mode);
      }
    } finally {
      _busy = false;
    }
  }

  /// The user clicked somewhere else on the screen: collapse straight back to
  /// the tiny edge tab — never to Home.
  ///
  /// A blur can also come from something transient (a native menu opening, the
  /// window re-docking itself), so this waits a moment and only acts if the
  /// window is *still* unfocused. Clicks inside the app never blur it.
  void handleFocusLost() {
    if (!_settings.settings.collapseOnClickOutside) return;
    if (!_visible || _stage == ShellStage.collapsed || _busy) return;
    _focusLossTimer?.cancel();
    _focusLossTimer = Timer(const Duration(milliseconds: 200), () async {
      if (!_settings.settings.collapseOnClickOutside) return;
      if (!_visible || _stage == ShellStage.collapsed || _busy) return;
      if (await _window.isFocused()) return;
      await collapse();
    });
  }

  Future<void> openSettings() async {
    if (!_visible) await show();
    await showHome(page: ShellPage.settings);
  }

  Future<void> closeSettings() async {
    _page = ShellPage.dashboard;
    notifyListeners();
  }

  // ---- Visibility ------------------------------------------------------------

  Future<void> show() async {
    await _window.show();
    _visible = true;
    _usage.setTicking(true);
    notifyListeners();
    _syncTray();
  }

  Future<void> hide() async {
    await _window.hide();
    _visible = false;
    _usage.setTicking(false);
    notifyListeners();
    _syncTray();
  }

  Future<void> toggleVisible() => _visible ? hide() : show();

  Future<void> startDragging() => _window.startDragging();

  Future<void> setAlwaysOnTop(bool value) => _window.setAlwaysOnTop(value);

  /// The × button and the native close: a normal Windows close (the tray menu
  /// still offers Hide for keeping it around invisibly).
  Future<void> close() => quit();

  Future<void> quit() async {
    try {
      await _tray?.destroy();
      _window.dispose();
      await _window.destroy();
    } finally {
      exit(0);
    }
  }

  @override
  void dispose() {
    _focusLossTimer?.cancel();
    _settings.removeListener(_syncTray);
    super.dispose();
  }
}
