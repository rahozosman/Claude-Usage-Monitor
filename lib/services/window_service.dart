import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../core/constants/app_constants.dart';

/// The three window sizes, one per UI state.
enum WindowMode { tab, limits, home }

/// Owns the native window: frameless, transparent, always-on-top and docked to
/// the **right edge** of the work area. The window is only ever as large as the
/// current state needs, so the desktop stays clickable around it.
class WindowService with WindowListener {
  WindowService({required this.onCloseRequested, required this.onAnchorChanged, required this.onFocusLost});

  /// Invoked when the user tries to close the window.
  final VoidCallback onCloseRequested;

  /// Invoked with the new vertical centre after the user drags the widget.
  final ValueChanged<double> onAnchorChanged;

  /// Invoked when the window loses focus — the user clicked somewhere else.
  final VoidCallback onFocusLost;

  WindowMode _mode = WindowMode.tab;
  double? _anchorCenterY;
  bool _visible = false;
  bool _applying = false;
  Timer? _moveDebounce;

  WindowMode get mode => _mode;
  bool get visible => _visible;

  Future<void> init({required bool alwaysOnTop, required double? anchorCenterY, required bool startHidden}) async {
    await windowManager.ensureInitialized();
    _anchorCenterY = anchorCenterY;

    const options = WindowOptions(
      size: Size(
        AppConstants.edgeTabWidth + AppConstants.shadowPad,
        AppConstants.edgeTabHeight + AppConstants.shadowPad * 2,
      ),
      backgroundColor: Colors.transparent,
      skipTaskbar: true,
      titleBarStyle: TitleBarStyle.hidden,
      alwaysOnTop: true,
      title: AppConstants.appName,
    );

    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setAsFrameless();
      // Windows refuses to make a window narrower than SM_CXMINTRACK (~133 px)
      // unless a minimum size is set, and the surplus would stay transparent
      // but still swallow clicks beside the tab. Asking for a 1 px minimum
      // overrides ptMinTrackSize so the window is really only as wide as the
      // glass.
      await windowManager.setMinimumSize(const Size(1, 1));
      await windowManager.setHasShadow(false);
      await windowManager.setResizable(false);
      await windowManager.setMinimizable(false);
      await windowManager.setMaximizable(false);
      await windowManager.setPreventClose(true);
      await windowManager.setAlwaysOnTop(alwaysOnTop);
      await applyMode(WindowMode.tab);
      if (!startHidden) {
        await windowManager.show();
        _visible = true;
      }
    });
    windowManager.addListener(this);
  }

  Future<Display> _primaryDisplay() => screenRetriever.getPrimaryDisplay();

  /// Content size (excluding the transparent shadow margin) for a state.
  static Size _contentSize(WindowMode mode) {
    switch (mode) {
      case WindowMode.tab:
        return const Size(AppConstants.edgeTabWidth, AppConstants.edgeTabHeight);
      case WindowMode.limits:
        return const Size(AppConstants.limitsWidth, AppConstants.limitsHeight);
      case WindowMode.home:
        return const Size(AppConstants.homeWidth, AppConstants.homeHeight);
    }
  }

  /// Sizes the window for [mode] and re-docks it against the right edge,
  /// keeping the remembered vertical centre.
  Future<void> applyMode(WindowMode mode) async {
    if (_applying) return;
    _applying = true;
    try {
      _mode = mode;
      await _dock();
    } catch (e) {
      debugPrint('applyMode failed: ${e.runtimeType}');
    } finally {
      _applying = false;
    }
  }

  Future<void> _dock() async {
    final display = await _primaryDisplay();
    final left = display.visiblePosition?.dx ?? 0;
    final top = display.visiblePosition?.dy ?? 0;
    final workW = display.visibleSize?.width ?? display.size.width;
    final workH = display.visibleSize?.height ?? display.size.height;

    final content = _contentSize(_mode);
    final winW = math.min(content.width + AppConstants.shadowPad, workW - 8);
    final winH = math.min(content.height + AppConstants.shadowPad * 2, workH - 8);

    // Flush against the right edge; the content inside is right-aligned, so the
    // glass touches the screen border in every state.
    final x = left + workW - winW;
    final centerY = _anchorCenterY ?? (top + workH / 2);
    final y = (centerY - winH / 2).clamp(top, top + workH - winH).toDouble();

    await windowManager.setBounds(Rect.fromLTWH(x, y, winW, winH));

    // Belt and braces: if the platform refuses a window this narrow it will
    // hand back a wider one, and because the glass inside is right-aligned the
    // extra width would carry it off the edge of the screen. Re-place it from
    // the width we actually got, so the right edge stays flush either way.
    try {
      final actual = await windowManager.getBounds();
      final screenRight = left + workW;
      if ((actual.right - screenRight).abs() > 1) {
        await windowManager.setBounds(
          Rect.fromLTWH(screenRight - actual.width, actual.top, actual.width, actual.height),
        );
      }
    } catch (e) {
      debugPrint('Edge re-dock failed: ${e.runtimeType}');
    }
  }

  Future<void> show() async {
    await windowManager.show();
    await windowManager.focus();
    _visible = true;
  }

  Future<void> hide() async {
    await windowManager.hide();
    _visible = false;
  }

  Future<void> setAlwaysOnTop(bool value) => windowManager.setAlwaysOnTop(value);

  /// Whether the window currently holds focus. Used to confirm a blur really
  /// means "the user clicked away" before acting on it.
  Future<bool> isFocused() async {
    try {
      return await windowManager.isFocused();
    } catch (_) {
      return false;
    }
  }

  Future<void> startDragging() => windowManager.startDragging();

  Future<void> destroy() => windowManager.destroy();

  // ---- WindowListener --------------------------------------------------------

  @override
  void onWindowClose() => onCloseRequested();

  @override
  void onWindowBlur() => onFocusLost();

  /// After a drag the widget keeps its new height but snaps back to the edge,
  /// so it can never end up floating in the middle of the screen.
  @override
  void onWindowMoved() {
    _moveDebounce?.cancel();
    _moveDebounce = Timer(const Duration(milliseconds: 200), () async {
      if (_applying) return;
      try {
        final bounds = await windowManager.getBounds();
        _anchorCenterY = bounds.center.dy;
        onAnchorChanged(bounds.center.dy);

        final display = await _primaryDisplay();
        final left = display.visiblePosition?.dx ?? 0;
        final workW = display.visibleSize?.width ?? display.size.width;
        final targetX = left + workW - bounds.width;
        if ((bounds.left - targetX).abs() > 1) await _dock();
      } catch (_) {}
    });
  }

  void dispose() {
    _moveDebounce?.cancel();
    windowManager.removeListener(this);
  }
}
