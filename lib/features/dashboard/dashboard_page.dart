import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/motion_scope.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimens.dart';
import '../../app/theme/app_motion.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/format_utils.dart';
import '../../models/cli_status.dart';
import '../../models/connection_status.dart';
import '../../models/usage_snapshot.dart';
import '../../widgets/about_card.dart';
import '../../widgets/activity_card.dart';
import '../../widgets/api_card.dart';
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

class _CliCard extends StatelessWidget {
  const _CliCard({required this.cli, required this.snapshot, required this.opacity});

  final CliStatus cli;
  final UsageSnapshot snapshot;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = DateTime.now();
    final active = cli.sessionActive(now);

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
      opacity: opacity,
      radius: AppDimens.radiusLg,
      padding: const EdgeInsets.fromLTRB(AppDimens.s16, AppDimens.s14, AppDimens.s16, AppDimens.s14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: 'Claude Code',
            trailing: StatusChip(
              label: !cli.installed
                  ? 'Not installed'
                  : active
                  ? 'Session active'
                  : 'Installed',
              color: !cli.installed ? c.statusOffline : (active ? c.connected : c.textTertiary),
            ),
          ),
          const SizedBox(height: AppDimens.s10),
          DetailGrid(rows: rows),
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
}
