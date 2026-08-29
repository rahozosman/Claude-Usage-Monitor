import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/motion_scope.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimens.dart';
import '../../app/theme/app_motion.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_error.dart';
import '../../core/utils/format_utils.dart';
import '../../models/cli_status.dart';
import '../../models/connection_status.dart';
import '../../models/usage_snapshot.dart';
import '../../services/statusline_bridge_service.dart';
import '../../widgets/about_card.dart';
import '../../widgets/activity_card.dart';
import '../../widgets/api_card.dart';
import '../../widgets/app_button.dart';
import '../../widgets/devices_card.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/app_scroll_view.dart';
import '../../widgets/window_caption.dart';
import '../../widgets/section_header.dart';
import '../../widgets/status_indicator.dart';
import '../../widgets/usage_card.dart';
import '../settings/settings_controller.dart';
import '../shell/shell_controller.dart';
import 'usage_controller.dart';

/// Expanded dashboard: header, cards, footer.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final usage = context.watch<UsageController>();
    final settings = context.watch<SettingsController>().settings;
    final shell = context.read<ShellController>();
    final motion = context.motion;
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final snap = usage.snapshot;

    final cards = <Widget>[
      if (snap.connection != ConnectionStatus.live && snap.connection != ConnectionStatus.idle) _Banner(snapshot: snap),
      if (settings.showFiveHour)
        UsageCard(
          window: snap.fiveHour,
          motion: motion,
          clock: usage.clock,
          showPercentages: settings.showPercentages,
          showCountdown: settings.showCountdown,
          opacity: settings.transparency,
        ),
      if (settings.showApi)
        ApiCard(
          api: snap.api,
          report: snap.apiReport,
          error: snap.apiError,
          apiConfigured: usage.apiConfigured,
          adminConfigured: usage.adminConfigured,
          probing: usage.probingApi,
          onProbe: () => usage.refresh(probeApi: true, force: true),
          motion: motion,
          clock: usage.clock,
          showPercentages: settings.showPercentages,
          showCountdown: settings.showCountdown,
          opacity: settings.transparency,
        ),
      if (settings.showWeekly)
        UsageCard(
          window: snap.weekly,
          motion: motion,
          clock: usage.clock,
          showPercentages: settings.showPercentages,
          showCountdown: settings.showCountdown,
          opacity: settings.transparency,
        ),
      for (final w in snap.extraWindows)
        if (w.isAvailable)
          UsageCard(
            window: w,
            motion: motion,
            clock: usage.clock,
            showPercentages: settings.showPercentages,
            showCountdown: settings.showCountdown,
            opacity: settings.transparency,
          ),
      if (settings.showActivity)
        ActivityCard(
          report: snap.local,
          scanning: usage.localScanning,
          motion: motion,
          clock: usage.clock,
          opacity: settings.transparency,
        ),
      if (settings.showActivity)
        DevicesCard(result: snap.devices, motion: motion, clock: usage.clock, opacity: settings.transparency),
      _CliCard(cli: snap.cli, snapshot: snap, opacity: settings.transparency),
      AboutCard(motion: motion, opacity: settings.transparency),
    ];

    return GlassPanel(
      opacity: settings.transparency,
      radius: AppDimens.radiusLg,
      child: Column(
        children: <Widget>[
          WindowCaptionBar(
            title: AppConstants.appName,
            motion: motion,
            onDragStart: shell.startDragging,
            onDoubleTap: shell.showLimits,
            onMinimize: shell.collapse,
            onClose: shell.close,
            minimizeTooltip: 'Minimize to the edge tab',
            closeTooltip: 'Close',
            actions: <Widget>[
              StatusIndicator(status: snap.connection, motion: motion, label: snap.connection.label),
              const SizedBox(width: AppDimens.s8),
              AppIconButton(
                icon: Icons.refresh_rounded,
                motion: motion,
                tooltip: 'Refresh now',
                spinning: usage.refreshing,
                onTap: usage.refreshing ? null : () => usage.refresh(probeApi: true, force: true),
              ),
              AppIconButton(
                icon: Icons.settings_outlined,
                motion: motion,
                tooltip: 'Settings',
                onTap: shell.openSettings,
              ),
              AppIconButton(
                icon: Icons.chevron_right_rounded,
                motion: motion,
                tooltip: 'Back to the limits panel',
                onTap: shell.showLimits,
              ),
            ],
          ),
          Container(height: 0.5, color: c.separator),
          Expanded(
            child: AppScrollView(
              padding: const EdgeInsets.all(AppDimens.s12),
              child: Column(
                children: <Widget>[
                  for (var i = 0; i < cards.length; i++)
                    Padding(
                      padding: EdgeInsets.only(bottom: i == cards.length - 1 ? 0 : AppDimens.s10),
                      child: _Entrance(index: i, motion: motion, child: cards[i]),
                    ),
                ],
              ),
            ),
          ),
          Container(height: 1, color: c.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppDimens.s14, AppDimens.s8, AppDimens.s14, AppDimens.s8),
            child: Row(
              children: <Widget>[
                StatusIndicator(status: snap.connection, motion: motion, label: _footerLabel(snap.connection)),
                const SizedBox(width: AppDimens.s10),
                Expanded(
                  child: ValueListenableBuilder<DateTime>(
                    valueListenable: usage.clock,
                    builder: (context, now, _) => Text(
                      'Updated ${FormatUtils.relative(snap.lastUpdated, now)}',
                      style: t.bodySmall?.copyWith(color: c.textTertiary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                Text(
                  settings.refreshInterval.duration == null
                      ? 'Manual refresh'
                      : 'Every ${settings.refreshInterval.label}',
                  style: t.bodySmall?.copyWith(color: c.textTertiary),
                ),
              ],
            ),
          ),
          Container(height: 0.5, color: c.separator),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppDimens.s14, AppDimens.s6, AppDimens.s14, AppDimens.s8),
            child: Text(
              AppConstants.copyright,
              textAlign: TextAlign.center,
              style: t.bodySmall?.copyWith(color: c.textTertiary, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  static String _footerLabel(ConnectionStatus s) {
    switch (s) {
      case ConnectionStatus.live:
        return 'Connected';
      default:
        return s.label;
    }
  }
}

/// Staggered fade/slide entrance (runs once when the page is created).
class _Entrance extends StatelessWidget {
  const _Entrance({required this.index, required this.motion, required this.child});

  final int index;
  final AppMotion motion;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!motion.enabled) return child;
    final start = (index * 0.1).clamp(0.0, 0.6);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: motion.large,
      curve: Interval(start, 1, curve: motion.enter),
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 8), child: child),
      ),
      child: child,
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.snapshot});

  final UsageSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final s = snapshot.connection;
    final color = c.forConnection(s);
    String text;
    switch (s) {
      case ConnectionStatus.offline:
        text = 'Offline — showing last known values.';
      case ConnectionStatus.stale:
        text = 'Data is stale — no fresh update in the last ${AppConstants.staleAfter.inMinutes} minutes.';
      case ConnectionStatus.unauthenticated:
        text = snapshot.subscriptionError?.message ?? snapshot.apiError?.message ?? 'Sign-in needed.';
      case ConnectionStatus.notConfigured:
        text = 'No data source configured yet — open Settings to install the Claude Code bridge or add an API key.';
      case ConnectionStatus.error:
        text = snapshot.subscriptionError?.toString() ?? snapshot.apiError?.toString() ?? 'Something went wrong.';
      case ConnectionStatus.live:
      case ConnectionStatus.idle:
        text = '';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.s12, vertical: AppDimens.s8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.info_outline_rounded, size: AppDimens.iconSm, color: color),
          const SizedBox(width: AppDimens.s8),
          Expanded(
            child: Text(text, style: t.bodySmall?.copyWith(color: c.textPrimary)),
          ),
        ],
      ),
    );
  }
}

class _CliCard extends StatefulWidget {
  const _CliCard({required this.cli, required this.snapshot, required this.opacity});

  final CliStatus cli;
  final UsageSnapshot snapshot;
  final double opacity;

  @override
  State<_CliCard> createState() => _CliCardState();
}

class _CliCardState extends State<_CliCard> {
  /// The bridge is never put in place behind the user's back: the button next
  /// to the status opens this confirmation, and only a deliberate "Install"
  /// writes to `~/.claude/settings.json`.
  bool _asking = false;
  bool _busy = false;
  String? _error;

  Future<void> _install() async {
    final bridge = context.read<StatusLineBridgeService>();
    final settings = context.read<SettingsController>();
    final usage = context.read<UsageController>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await bridge.install();
      // Remembered for good, so the offer never comes back to this spot.
      await settings.update((s) => s.copyWith(bridgeAutoInstallDone: true));
      await usage.refresh(force: true);
      if (mounted) {
        setState(() {
          _asking = false;
          _busy = false;
        });
      }
    } on AppError catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not update settings.json (${e.runtimeType}).';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cli = widget.cli;
    final snapshot = widget.snapshot;
    final c = context.colors;
    final motion = context.motion;
    final now = DateTime.now();
    final active = cli.sessionActive(now);
    // Offered once, and only while there is a Claude Code to attach it to.
    final offerBridge =
        cli.installed &&
        !cli.bridgeInstalled &&
        !context.select<SettingsController, bool>((s) => s.settings.bridgeAutoInstallDone);

    final rows = <(String, String)>[
      ('Installed', cli.installed ? (cli.version ?? 'yes') : 'Not found on PATH'),
      if (cli.executablePath != null) ('Path', cli.executablePath!),
      ('Sign-in', cli.authType ?? (cli.installed ? 'Not signed in' : '—')),
      if (cli.subscriptionType != null)
        ('Plan', '${cli.subscriptionType}${cli.rateLimitTier != null ? ' · ${cli.rateLimitTier}' : ''}'),
      if (cli.tokenExpiresAt != null)
        (
          'Token',
          cli.tokenExpired
              ? 'Expired — open Claude Code to refresh'
              : 'Valid until ${FormatUtils.absolute(cli.tokenExpiresAt, now)}',
        ),
      ('Bridge', cli.bridgeInstalled ? 'Installed (status-line)' : 'Not installed'),
      (
        'Session',
        active
            ? '${cli.sessionModel ?? 'Active'}'
                  '${cli.sessionContextPercent != null ? ' · context ${cli.sessionContextPercent!.toStringAsFixed(0)}%' : ''}'
            : (cli.statusLineUpdatedAt == null
                  ? 'No session data yet'
                  : 'Idle · last seen ${FormatUtils.relative(cli.statusLineUpdatedAt, now)}'),
      ),
      if (active && cli.sessionDirectory != null) ('Directory', cli.sessionDirectory!),
      if (cli.settingsPath != null) ('Config', cli.settingsPath!),
    ];

    return GlassPanel(
      elevated: true,
      opacity: widget.opacity,
      radius: AppDimens.radiusLg,
      padding: const EdgeInsets.fromLTRB(AppDimens.s16, AppDimens.s14, AppDimens.s16, AppDimens.s14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: 'Claude Code',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (offerBridge) ...<Widget>[
                  _BridgeInstallButton(
                    motion: motion,
                    // The hand only points while the ask is still unanswered.
                    hint: !_asking,
                    onTap: () => setState(() {
                      _asking = !_asking;
                      _error = null;
                    }),
                  ),
                  const SizedBox(width: AppDimens.s12),
                ],
                StatusChip(
                  label: !cli.installed
                      ? 'Not installed'
                      : active
                      ? 'Session active'
                      : 'Installed',
                  color: !cli.installed ? c.statusOffline : (active ? c.connected : c.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimens.s10),
          DetailGrid(rows: rows),
          AnimatedSize(
            duration: motion.component,
            curve: motion.transition,
            alignment: Alignment.topCenter,
            child: offerBridge && _asking ? _confirm(context, motion) : const SizedBox(width: double.infinity),
          ),
          if (snapshot.subscriptionError != null)
            Padding(
              padding: const EdgeInsets.only(top: AppDimens.s8),
              child: Text(
                snapshot.subscriptionError!.toString(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: snapshot.subscriptionError!.isNetwork ? c.statusOffline : c.statusWarning,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The ask itself: what the install changes, and the two ways out of it.
  Widget _confirm(BuildContext context, AppMotion motion) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppDimens.s10),
      child: Container(
        padding: const EdgeInsets.all(AppDimens.s12),
        decoration: BoxDecoration(
          color: c.accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppDimens.radiusMd),
          border: Border.all(color: c.accent.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Install the status-line bridge?',
              style: t.bodySmall?.copyWith(color: c.textPrimary, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppDimens.s6),
            Text(
              'Adds a statusLine command to ~/.claude/settings.json (backed up first) so Claude Code hands its '
              'official rate_limits JSON to this app after every response. A status line you already have keeps '
              'working — the bridge forwards to it.',
              style: t.bodySmall?.copyWith(color: c.textSecondary),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: AppDimens.s6),
              Text(_error!, style: t.bodySmall?.copyWith(color: c.statusWarning)),
            ],
            const SizedBox(height: AppDimens.s10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                AppButton(
                  label: 'Not now',
                  motion: motion,
                  onTap: _busy
                      ? null
                      : () => setState(() {
                          _asking = false;
                          _error = null;
                        }),
                ),
                const SizedBox(width: AppDimens.s8),
                AppButton(
                  label: 'Install',
                  style: AppButtonStyle.primary,
                  motion: motion,
                  loading: _busy,
                  onTap: _install,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The "Install" button offered beside the Claude Code status, with a hand
/// tapping at it so the one thing the app still needs is impossible to miss.
class _BridgeInstallButton extends StatelessWidget {
  const _BridgeInstallButton({required this.motion, required this.hint, required this.onTap});

  final AppMotion motion;
  final bool hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        AppButton(label: 'Install', style: AppButtonStyle.primary, motion: motion, onTap: onTap),
        if (hint)
          Positioned(
            right: -8,
            bottom: -9,
            // Decoration only — every pixel of the button stays clickable.
            child: IgnorePointer(child: _HandTouch(motion: motion)),
          ),
      ],
    );
  }
}

/// A hand tapping on a slow loop: press in, ripple out, lift, pause. The hand
/// scales about its fingertip so the finger stays on target, and everything
/// holds still when animations are switched off.
class _HandTouch extends StatefulWidget {
  const _HandTouch({required this.motion});

  final AppMotion motion;

  @override
  State<_HandTouch> createState() => _HandTouchState();
}

class _HandTouchState extends State<_HandTouch> with SingleTickerProviderStateMixin {
  static const double _size = 26;

  /// Where the finger lands inside the box — the ripple starts from here.
  static const Offset _tip = Offset(11, 6);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _HandTouch oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.motion.enabled) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return RepaintBoundary(
      child: SizedBox(
        width: _size,
        height: _size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final v = _controller.value;
            // 0-.24 press down, .24-.38 held, .38-.62 lift, then a rest.
            final double press;
            if (v < 0.24) {
              press = Curves.easeIn.transform(v / 0.24);
            } else if (v < 0.38) {
              press = 1;
            } else if (v < 0.62) {
              press = 1 - Curves.easeOut.transform((v - 0.38) / 0.24);
            } else {
              press = 0;
            }
            // The ripple leaves the fingertip the moment it lands.
            final ripple = v < 0.24 ? 0.0 : ((v - 0.24) / 0.42).clamp(0.0, 1.0);
            final ring = 7 + 17 * ripple;
            return Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                if (ripple > 0 && ripple < 1)
                  Positioned(
                    left: _tip.dx - ring / 2,
                    top: _tip.dy - ring / 2,
                    child: Container(
                      width: ring,
                      height: ring,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: c.accent.withValues(alpha: 0.6 * (1 - ripple)), width: 1.2),
                      ),
                    ),
                  ),
                Transform.scale(
                  scale: 1 - 0.16 * press,
                  alignment: const Alignment(-0.45, -0.8),
                  child: Icon(
                    Icons.touch_app_rounded,
                    size: 19,
                    color: c.textPrimary,
                    shadows: <Shadow>[Shadow(color: c.shadow.withValues(alpha: 0.55), blurRadius: 3)],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
