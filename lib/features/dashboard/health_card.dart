import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimens.dart';
import '../../app/theme/app_motion.dart';
import '../../core/services/app_paths.dart';
import '../../core/utils/format_utils.dart';
import '../../models/app_settings.dart';
import '../../models/limit_window.dart';
import '../../models/usage_snapshot.dart';
import '../../services/notification_service.dart';
import '../../services/statusline_bridge_service.dart';
import '../../widgets/app_button.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/section_header.dart';
import '../../widgets/usage_card.dart';
import '../settings/settings_controller.dart';
import 'usage_controller.dart';

/// Every source the numbers come from, and whether it is actually working.
///
/// Each input this app has is external, invisible and quietly breakable: a key
/// inside Claude Code's own `settings.json`, a script on disk, a Keychain
/// item, a folder some cloud client syncs. When one stops, the card that
/// depended on it can only say "Unavailable"; nothing says *which* link is
/// down or what fixes it. This does.
///
/// Every row reports something checked on the last refresh — the bridge row
/// stats the script file rather than trusting the settings key that names it.
/// A row is green only when the thing it names was found.
class HealthCard extends StatefulWidget {
  const HealthCard({
    super.key,
    required this.snapshot,
    required this.motion,
    required this.clock,
    this.opacity = 1,
  });

  final UsageSnapshot snapshot;
  final AppMotion motion;
  final ValueListenable<DateTime> clock;
  final double opacity;

  @override
  State<HealthCard> createState() => _HealthCardState();
}

class _HealthCardState extends State<HealthCard> {
  bool _busy = false;
  String? _message;

  /// The one thing this card writes, and only on a click: it rewrites the
  /// bridge script and corrects a stale command. When the bridge is missing
  /// altogether the same button installs it — which is exactly what pressing
  /// "Repair" asked for.
  Future<void> _repair(bool install) async {
    final bridge = context.read<StatusLineBridgeService>();
    final usage = context.read<UsageController>();
    setState(() {
      _busy = true;
      _message = null;
    });
    final ok = await bridge.ensureBridge(autoInstall: install);
    await usage.refresh(force: true);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = install && !ok
          ? 'Could not write the bridge. Claude Code\'s config folder may be missing, or settings.json is not '
                'valid JSON — it is never modified when it cannot be parsed.'
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final settings = context.watch<SettingsController>().settings;
    final usage = context.watch<UsageController>();
    final notificationsReady = context.read<NotificationService>().ready;
    final cli = widget.snapshot.cli;
    // Only offered when there is something to put right; otherwise the button
    // just re-runs the checks.
    final needsRepair = cli.installed && !cli.bridgeHealthy;

    return GlassPanel(
      elevated: true,
      opacity: widget.opacity,
      radius: AppDimens.radiusLg,
      padding: const EdgeInsets.fromLTRB(AppDimens.s16, AppDimens.s14, AppDimens.s16, AppDimens.s14),
      child: ValueListenableBuilder<DateTime>(
        valueListenable: widget.clock,
        builder: (context, now, _) {
          final checks = _checks(settings, usage, notificationsReady, now);
          final failed = checks.where((k) => k.state == _Health.fail).length;
          final warned = checks.where((k) => k.state == _Health.warn).length;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SectionHeader(
                title: 'Where the numbers come from',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    AppButton(
                      label: needsRepair ? 'Repair' : 'Re-check',
                      style: needsRepair ? AppButtonStyle.primary : AppButtonStyle.secondary,
                      motion: widget.motion,
                      loading: _busy,
                      onTap: _busy ? null : () => _repair(needsRepair),
                    ),
                    const SizedBox(width: AppDimens.s8),
                    StatusChip(
                      label: failed > 0
                          ? '$failed not working'
                          : warned > 0
                          ? '$warned to check'
                          : 'All working',
                      color: failed > 0
                          ? c.statusOffline
                          : warned > 0
                          ? c.statusWarning
                          : c.connected,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppDimens.s10),
              for (final check in checks) _CheckRow(check: check),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppDimens.s8),
                  child: Text(_message!, style: t.bodySmall?.copyWith(color: c.statusWarning)),
                ),
              const SizedBox(height: AppDimens.s12),
              DetailGrid(
                dim: true,
                rows: <(String, String)>[
                  ('Claude settings', cli.settingsPath ?? AppPaths.claudeSettingsFile),
                  ('Status line', AppPaths.statusLineFile),
                  ('Bridge script', AppPaths.bridgeScript),
                  ('Backups', AppPaths.backupsDir),
                ],
              ),
              const SizedBox(height: AppDimens.s8),
              Text(
                'Checked on this machine on every refresh. Nothing here is assumed — a row turns green only when '
                'the thing it names was found.',
                style: t.bodySmall?.copyWith(color: c.textTertiary, fontSize: 11),
              ),
            ],
          );
        },
      ),
    );
  }

  /// The chain, in the order the data actually travels it: Claude Code is
  /// installed, it is signed in, the bridge is in place, something arrived,
  /// and then the optional sources that only some setups use.
  List<_Check> _checks(AppSettings settings, UsageController usage, bool notificationsReady, DateTime now) {
    final snap = widget.snapshot;
    final cli = snap.cli;
    final devices = snap.devices;
    final checks = <_Check>[];

    checks.add(
      cli.installed
          ? _Check(
              'Claude Code',
              _Health.ok,
              '${cli.version ?? 'installed'}${cli.executablePath != null ? ' · ${cli.executablePath}' : ''}',
            )
          : const _Check('Claude Code', _Health.fail, 'Not found on PATH or in the usual install folders.'),
    );

    if (!cli.installed) {
      checks.add(const _Check('Sign-in', _Health.off, 'Needs Claude Code first.'));
    } else if (cli.tokenExpired) {
      checks.add(const _Check('Sign-in', _Health.warn, 'Expired — open Claude Code once to refresh it.'));
    } else if (cli.hasOAuth) {
      checks.add(
        _Check(
          'Sign-in',
          _Health.ok,
          cli.subscriptionType != null
              ? 'Claude.ai subscription · ${cli.subscriptionType}'
                    '${cli.rateLimitTier != null ? ' (${cli.rateLimitTier})' : ''}'
              // The plan lives inside the secret, which is only read for the
              // opt-in usage endpoint, so on macOS it stays unknown here.
              : 'Claude.ai subscription${Platform.isMacOS ? ' · found in the Keychain' : ''}',
        ),
      );
    } else if (cli.apiKeyEnvPresent) {
      checks.add(
        const _Check(
          'Sign-in',
          _Health.warn,
          'API key from the environment — Claude reports no subscription limits for that sign-in.',
        ),
      );
    } else {
      checks.add(const _Check('Sign-in', _Health.fail, 'Not signed in — run `claude` and use /login.'));
    }

    // Three separate facts, kept separate: a bridge can be registered, and
    // still not run, and still point somewhere else.
    if (!cli.installed) {
      checks.add(const _Check('Status-line bridge', _Health.off, 'Needs Claude Code first.'));
    } else if (!cli.bridgeInstalled) {
      checks.add(
        const _Check(
          'Status-line bridge',
          _Health.fail,
          'Not in settings.json — Claude Code has nowhere to send limits. Repair installs it.',
        ),
      );
    } else if (!cli.bridgeScriptPresent) {
      checks.add(
        const _Check(
          'Status-line bridge',
          _Health.fail,
          'Registered, but the script file is gone — Repair writes it back.',
        ),
      );
    } else if (!cli.bridgeCommandCurrent) {
      checks.add(
        const _Check(
          'Status-line bridge',
          _Health.warn,
          'Points somewhere other than this build would write — Repair corrects it.',
        ),
      );
    } else {
      checks.add(const _Check('Status-line bridge', _Health.ok, 'Registered, script present, command current.'));
    }

    if (!cli.bridgeInstalled) {
      checks.add(const _Check('Last status line', _Health.off, 'Waiting for the bridge.'));
    } else if (cli.statusLineUpdatedAt == null) {
      checks.add(
        const _Check(
          'Last status line',
          _Health.warn,
          'Nothing received yet — start (or restart) a Claude Code session.',
        ),
      );
    } else if (!cli.statusLineHasRateLimits) {
      checks.add(
        _Check(
          'Last status line',
          _Health.warn,
          'Arrived ${FormatUtils.relative(cli.statusLineUpdatedAt, now)} with no rate limits in it — restart the '
              'session (Pro/Max plans only).',
        ),
      );
    } else if (!cli.statusLineWindowIds.contains(LimitWindow.fiveHourId)) {
      // A payload can carry the weekly window and not the 5-hour one. Saying
      // "rate limits included" there reads as a contradiction of the card
      // beside it, which is exactly the thing this panel exists to settle.
      checks.add(
        _Check(
          'Last status line',
          _Health.warn,
          'Arrived ${FormatUtils.relative(cli.statusLineUpdatedAt, now)} with '
              '${cli.statusLineWindowIds.map(LimitWindow.labelFor).join(', ')} — '
              '${LimitWindow.noActiveWindow(LimitWindow.fiveHourId)}. Claude Code sends a window only while it '
              'is open.',
        ),
      );
    } else {
      checks.add(
        _Check(
          'Last status line',
          _Health.ok,
          'Arrived ${FormatUtils.relative(cli.statusLineUpdatedAt, now)} · '
              '${cli.statusLineWindowIds.map(LimitWindow.labelFor).join(', ')}.',
        ),
      );
    }

    if (!settings.useUsageEndpoint) {
      checks.add(const _Check('Usage endpoint', _Health.off, 'Off — the bridge is the primary source.'));
    } else if (snap.subscriptionError != null) {
      checks.add(_Check('Usage endpoint', _Health.warn, snap.subscriptionError!.message));
    } else {
      checks.add(const _Check('Usage endpoint', _Health.ok, 'Enabled.'));
    }

    if (!usage.apiConfigured && !usage.adminConfigured) {
      checks.add(
        const _Check(
          'Anthropic API',
          _Health.off,
          'No key — the API card stays empty. Billed separately from your subscription.',
        ),
      );
    } else if (snap.apiError != null) {
      checks.add(_Check('Anthropic API', _Health.warn, snap.apiError!.message));
    } else {
      checks.add(
        _Check(
          'Anthropic API',
          _Health.ok,
          usage.adminConfigured ? 'API key and Admin key configured.' : 'API key configured.',
        ),
      );
    }

    if (!settings.deviceSyncEnabled) {
      checks.add(const _Check('Shared folder', _Health.off, 'Sharing is off.'));
    } else if (devices.folder == null) {
      checks.add(
        const _Check(
          'Shared folder',
          _Health.warn,
          'None found — pick a folder that syncs between your machines in Settings.',
        ),
      );
    } else if (devices.error != null) {
      checks.add(_Check('Shared folder', _Health.fail, devices.error!));
    } else if (devices.publishError != null) {
      checks.add(_Check('Shared folder', _Health.warn, devices.publishError!));
    } else if (devices.publishedAt == null) {
      checks.add(_Check('Shared folder', _Health.warn, 'Waiting to publish · ${devices.folder}'));
    } else {
      checks.add(
        _Check(
          'Shared folder',
          _Health.ok,
          'Published ${FormatUtils.relative(devices.publishedAt, now)} · ${devices.folder}',
        ),
      );
    }

    if (!settings.notificationsEnabled) {
      checks.add(const _Check('Notifications', _Health.off, 'Off.'));
    } else if (notificationsReady) {
      checks.add(const _Check('Notifications', _Health.ok, 'Enabled.'));
    } else {
      checks.add(const _Check('Notifications', _Health.warn, 'On, but this system did not allow them.'));
    }

    if (!settings.launchWithClaude) {
      checks.add(const _Check('Open with Claude', _Health.off, 'Off.'));
    } else if (cli.launchHookInstalled) {
      checks.add(const _Check('Open with Claude', _Health.ok, 'SessionStart hook registered.'));
    } else {
      checks.add(const _Check('Open with Claude', _Health.warn, 'Hook missing — it is put back on the next launch.'));
    }

    return checks;
  }
}

/// `off` is not a failure: it is a source the user has switched off, or one
/// that cannot apply yet. It is counted in neither total.
enum _Health { ok, warn, fail, off }

class _Check {
  const _Check(this.label, this.state, this.detail);

  final String label;
  final _Health state;
  final String detail;
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.check});

  final _Check check;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final color = switch (check.state) {
      _Health.ok => c.connected,
      _Health.warn => c.statusWarning,
      _Health.fail => c.statusOffline,
      _Health.off => c.textTertiary,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          ),
          const SizedBox(width: AppDimens.s8),
          SizedBox(
            width: 116,
            child: Text(check.label, style: t.bodySmall?.copyWith(color: c.textSecondary)),
          ),
          const SizedBox(width: AppDimens.s8),
          Expanded(
            child: Text(
              check.detail,
              style: t.bodySmall?.copyWith(color: check.state == _Health.off ? c.textTertiary : c.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
