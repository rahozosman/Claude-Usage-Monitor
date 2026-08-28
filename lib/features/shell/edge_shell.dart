import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/motion_scope.dart';
import '../../app/theme/app_motion.dart';
import '../../core/constants/app_constants.dart';
import '../../widgets/glass_panel.dart';
import '../dashboard/dashboard_page.dart';
import '../dashboard/edge_tab.dart';
import '../dashboard/limits_panel.dart';
import '../settings/settings_controller.dart';
import '../settings/settings_page.dart';
import 'shell_controller.dart';

/// One piece of glass that morphs between the three states.
///
/// Size and corner radius are interpolated across the three stops, so a
/// collapse from Home travels *through* the panel width on its way back to the
/// edge. Only the outgoing and incoming contents are built, cross-faded
/// against each other, so nothing the surface passes over ever flashes.
class EdgeShell extends StatelessWidget {
  const EdgeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = context.watch<ShellController>();
    final motion = context.motion;
    final opacity = context.select<SettingsController, double>((s) => s.settings.transparency);

    return LayoutBuilder(
      builder: (context, constraints) {
        final homeW = math.min(AppConstants.homeWidth, constraints.maxWidth);
        final homeH = math.min(AppConstants.homeHeight, constraints.maxHeight);
        final stage = shell.stage;
        final from = shell.previousStage;

        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: stage.index.toDouble()),
          duration: _durationFor(stage, motion),
          curve: stage == ShellStage.collapsed ? motion.transition : motion.enter,
          builder: (context, t, _) {
            final width = _lerp3(t, AppConstants.edgeTabWidth, AppConstants.limitsWidth, homeW);
            final height = _lerp3(t, AppConstants.edgeTabHeight, AppConstants.limitsHeight, homeH);
            final radius = _lerp3(t, AppConstants.edgeTabRadius, AppConstants.limitsRadius, AppConstants.homeRadius);

            // Progress of the current transition, 0 at the stage being left.
            final a = from.index.toDouble();
            final b = stage.index.toDouble();
            final p = a == b ? 1.0 : ((t - a) / (b - a)).clamp(0.0, 1.0);
            final incoming = a == b ? 1.0 : ((p - 0.35) / 0.65).clamp(0.0, 1.0);
            final outgoing = a == b ? 0.0 : (1 - p * 1.8).clamp(0.0, 1.0);

            double opacityOf(ShellStage s) {
              if (s == stage) return incoming;
              if (s == from) return outgoing;
              return 0;
            }

            return Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: width,
                height: height,
                child: GlassPanel(
                  opacity: opacity,
                  // Only the left corners are rounded: the glass stays visually
                  // attached to the screen edge in every state.
                  borderRadius: BorderRadius.horizontal(left: Radius.circular(radius)),
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      _Layer(
                        opacity: opacityOf(ShellStage.collapsed),
                        size: const Size(AppConstants.edgeTabWidth, AppConstants.edgeTabHeight),
                        child: const EdgeTab(),
                      ),
                      _Layer(
                        opacity: opacityOf(ShellStage.limits),
                        size: const Size(AppConstants.limitsWidth, AppConstants.limitsHeight),
                        child: const LimitsPanel(),
                      ),
                      _Layer(
                        opacity: opacityOf(ShellStage.home),
                        size: Size(homeW, homeH),
                        child: _HomeContent(page: shell.page, motion: motion),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  static Duration _durationFor(ShellStage stage, AppMotion motion) {
    if (!motion.enabled) return Duration.zero;
    switch (stage) {
      case ShellStage.collapsed:
        return const Duration(milliseconds: 200);
      case ShellStage.limits:
        return const Duration(milliseconds: 240);
      case ShellStage.home:
        return const Duration(milliseconds: 380);
    }
  }

  /// Piecewise interpolation across the three stops (tab → limits → home).
  static double _lerp3(double t, double a, double b, double c) {
    if (t <= 1) return lerpDouble(a, b, t.clamp(0.0, 1.0))!;
    return lerpDouble(b, c, (t - 1).clamp(0.0, 1.0))!;
  }
}

/// One state's content, laid out at its natural size and pinned to the right
/// edge so the surface appears to grow and shrink horizontally.
class _Layer extends StatelessWidget {
  const _Layer({required this.opacity, required this.size, required this.child});

  final double opacity;
  final Size size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Never lay a page out at a size it was not designed for.
    if (opacity <= 0.01) return const SizedBox.shrink();
    return IgnorePointer(
      ignoring: opacity < 0.98,
      child: Opacity(
        opacity: opacity,
        child: OverflowBox(
          alignment: Alignment.centerRight,
          minWidth: size.width,
          maxWidth: size.width,
          minHeight: size.height,
          maxHeight: size.height,
          child: child,
        ),
      ),
    );
  }
}

/// Home is the app's normal interface: the dashboard, or settings.
class _HomeContent extends StatelessWidget {
  const _HomeContent({required this.page, required this.motion});

  final ShellPage page;
  final AppMotion motion;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: motion.component,
      switchInCurve: motion.enter,
      switchOutCurve: motion.exit,
      layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: <Widget>[...previous, ?current]),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0.02, 0), end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
      child: page == ShellPage.settings
          ? const SettingsPage(key: ValueKey<String>('settings'))
          : const DashboardPage(key: ValueKey<String>('dashboard')),
    );
  }
}
