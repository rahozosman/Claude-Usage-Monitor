import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/motion_scope.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimens.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_error.dart';
import '../../core/services/app_paths.dart';
import '../../models/app_settings.dart';
import '../../services/notification_service.dart';
import '../../services/settings_service.dart';
import '../../services/statusline_bridge_service.dart';
import '../../widgets/app_button.dart';
import '../../widgets/folder_editor.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/app_scroll_view.dart';
import '../../widgets/mac_controls.dart';
import '../../widgets/window_caption.dart';
import '../../widgets/section_header.dart';
import '../../widgets/setting_row.dart';
import '../dashboard/usage_controller.dart';
import '../shell/shell_controller.dart';
import 'settings_controller.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _apiKey = TextEditingController();
  final TextEditingController _adminKey = TextEditingController();
  late final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  bool _bridgeBusy = false;
  bool _testing = false;
  String? _bridgeMessage;
  String? _hookMessage;
  String? _testMessage;
  bool _testOk = false;

  @override
  void dispose() {
    _apiKey.dispose();
    _adminKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sc = context.watch<SettingsController>();
    final usage = context.watch<UsageController>();
    final shell = context.read<ShellController>();
    final motion = context.motion;
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final s = sc.settings;
    final cli = usage.snapshot.cli;

    return GlassPanel(
      opacity: s.transparency,
      radius: AppDimens.radiusLg,
      child: Column(
        children: <Widget>[
          WindowCaptionBar(
            title: 'Settings',
            motion: motion,
            onDragStart: shell.startDragging,
            onMinimize: shell.collapse,
            onClose: shell.close,
            minimizeTooltip: 'Minimize to the edge tab',
            closeTooltip: 'Close',
            actions: <Widget>[
              AppIconButton(
                icon: Icons.arrow_back_rounded,
                motion: motion,
                tooltip: 'Back to dashboard',
                onTap: shell.closeSettings,
              ),
            ],
          ),
          Container(height: 0.5, color: c.separator),
          Expanded(
            child: AppScrollView(
              padding: const EdgeInsets.all(AppDimens.s12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _section('General', <Widget>[
                    SettingRow(
                      title: AppConstants.startupLabel,
                      subtitle: 'Registers a per-user startup entry (no admin rights).',
                      trailing: _Toggle(value: sc.startWithWindows, onChanged: sc.setStartWithWindows),
                    ),
                    SettingRow(
                      title: 'Launch minimized',
                      subtitle: 'Start hidden in the tray.',
                      trailing: _Toggle(
                        value: s.launchMinimized,
                        onChanged: (v) => sc.update((x) => x.copyWith(launchMinimized: v)),
                      ),
                    ),
                    SettingRow(
                      title: 'Always on top',
                      trailing: _Toggle(
                        value: s.alwaysOnTop,
                        onChanged: (v) async {
                          await sc.update((x) => x.copyWith(alwaysOnTop: v));
                          await shell.setAlwaysOnTop(v);
                        },
                      ),
                    ),
                    SettingRow(
                      title: 'Shrink when I click elsewhere',
                      subtitle: 'Collapse straight back to the tiny edge tab as soon as you click outside the app.',
                      trailing: _Toggle(
                        value: s.collapseOnClickOutside,
                        onChanged: (v) => sc.update((x) => x.copyWith(collapseOnClickOutside: v)),
                      ),
                    ),
                    SettingRow(
                      title: 'Compact mode at launch',
                      subtitle: 'Start as the tiny edge tab instead of the Home window.',
                      trailing: _Toggle(
                        value: s.compactMode,
                        onChanged: (v) => sc.update((x) => x.copyWith(compactMode: v)),
                      ),
                    ),
                    SettingRow(
                      title: 'Refresh interval',
                      subtitle: 'Reads local Claude Code data (and the usage endpoint if enabled).',
                      trailing: SettingDropdown<RefreshInterval>(
                        value: s.refreshInterval,
                        items: RefreshInterval.values,
                        labelOf: (v) => v.label,
                        onChanged: (v) => v == null ? null : sc.update((x) => x.copyWith(refreshInterval: v)),
                      ),
                    ),
                  ]),
                  _section('Appearance', <Widget>[
                    SettingRow(
                      title: 'Theme',
                      trailing: SettingDropdown<ThemeMode>(
                        value: s.themeMode,
                        items: ThemeMode.values,
                        labelOf: (v) => v == ThemeMode.system ? 'System' : (v == ThemeMode.dark ? 'Dark' : 'Light'),
                        onChanged: (v) => v == null ? null : sc.update((x) => x.copyWith(themeMode: v)),
                      ),
                    ),
                    SettingRow(
                      title: 'Transparency',
                      subtitle: '${((1 - s.transparency) * 100).round()}% see-through',
                      trailing: SizedBox(
                        width: 140,
                        child: Slider(
                          value: s.transparency,
                          min: 0.7,
                          max: 1,
                          onChanged: (v) => sc.update((x) => x.copyWith(transparency: v)),
                        ),
                      ),
                    ),
                    SettingRow(
                      title: 'Animations',
                      subtitle: 'Progress, number and status motion.',
                      trailing: _Toggle(
                        value: s.animationsEnabled,
                        onChanged: (v) => sc.update((x) => x.copyWith(animationsEnabled: v)),
                      ),
                    ),
                  ]),
                  _section('Usage', <Widget>[
                    SettingRow(
                      title: 'Show 5-hour limit',
                      trailing: _Toggle(
                        value: s.showFiveHour,
                        onChanged: (v) => sc.update((x) => x.copyWith(showFiveHour: v)),
                      ),
                    ),
                    SettingRow(
                      title: 'Show API usage',
                      trailing: _Toggle(
                        value: s.showApi,
                        onChanged: (v) => sc.update((x) => x.copyWith(showApi: v)),
                      ),
                    ),
                    SettingRow(
                      title: 'Show weekly limit',
                      trailing: _Toggle(
                        value: s.showWeekly,
                        onChanged: (v) => sc.update((x) => x.copyWith(showWeekly: v)),
                      ),
                    ),
                    SettingRow(
                      title: 'Show activity (what used it)',
                      subtitle: 'Local Claude Code sessions, tasks and token counts on this PC.',
                      trailing: _Toggle(
                        value: s.showActivity,
                        onChanged: (v) => sc.update((x) => x.copyWith(showActivity: v)),
                      ),
                    ),
                    SettingRow(
                      title: 'Share activity with my other devices',
                      subtitle:
                          'Publishes this PC\x27s Claude Code activity (sessions, tokens, models) to a synced folder '
                          'and shows what your other devices on the same account are doing. Real data only — '
                          'Claude itself does not report per-device activity.',
                      trailing: _Toggle(
                        value: s.deviceSyncEnabled,
                        onChanged: (v) async {
                          await sc.update((x) => x.copyWith(deviceSyncEnabled: v));
                          await usage.refresh(force: true);
                        },
                      ),
                    ),
                    FolderEditor(
                      current: s.deviceSyncFolder,
                      resolved: usage.snapshot.devices.folder,
                      motion: motion,
                      onOpen: usage.snapshot.devices.folder == null
                          ? null
                          : () => _openFolder(usage.snapshot.devices.folder!),
                      onSave: (v) async {
                        await sc.update(
                          (x) => v == null ? x.copyWith(clearDeviceSyncFolder: true) : x.copyWith(deviceSyncFolder: v),
                        );
                        await usage.refresh(force: true);
                      },
                    ),
                    SettingRow(
                      title: 'Show percentages',
                      trailing: _Toggle(
                        value: s.showPercentages,
                        onChanged: (v) => sc.update((x) => x.copyWith(showPercentages: v)),
                      ),
                    ),
                    SettingRow(
                      title: 'Show reset countdown',
                      trailing: _Toggle(
                        value: s.showCountdown,
                        onChanged: (v) => sc.update((x) => x.copyWith(showCountdown: v)),
                      ),
                    ),
                  ]),
                  _section('Notifications', <Widget>[
                    SettingRow(
                      title: 'Enable notifications',
                      subtitle: 'Each threshold fires once per usage window.',
                      trailing: _Toggle(
                        value: s.notificationsEnabled,
                        onChanged: (v) => sc.update((x) => x.copyWith(notificationsEnabled: v)),
                      ),
                    ),
                    SettingRow(
                      title: '80% warning',
                      enabled: s.notificationsEnabled,
                      trailing: _Toggle(
                        value: s.notifyAt80,
                        enabled: s.notificationsEnabled,
                        onChanged: (v) => sc.update((x) => x.copyWith(notifyAt80: v)),
                      ),
                    ),
                    SettingRow(
                      title: '90% warning',
                      enabled: s.notificationsEnabled,
                      trailing: _Toggle(
                        value: s.notifyAt90,
                        enabled: s.notificationsEnabled,
                        onChanged: (v) => sc.update((x) => x.copyWith(notifyAt90: v)),
                      ),
                    ),
                    SettingRow(
                      title: '100% limit reached',
                      enabled: s.notificationsEnabled,
                      trailing: _Toggle(
                        value: s.notifyAt100,
                        enabled: s.notificationsEnabled,
                        onChanged: (v) => sc.update((x) => x.copyWith(notifyAt100: v)),
                      ),
                    ),
                    SettingRow(
                      title: 'Limit reset',
                      enabled: s.notificationsEnabled,
                      trailing: _Toggle(
                        value: s.notifyOnReset,
                        enabled: s.notificationsEnabled,
                        onChanged: (v) => sc.update((x) => x.copyWith(notifyOnReset: v)),
                      ),
                    ),
                    SettingRow(
                      title: 'Send a test notification',
                      trailing: AppButton(
                        label: 'Test',
                        motion: motion,
                        onTap: () => context.read<NotificationService>().showTest(),
                      ),
                    ),
                  ]),
                  _section('Claude Code', <Widget>[
                    SettingRow(
                      title: cli.installed ? 'Claude Code ${cli.version ?? ''}'.trim() : 'Claude Code not detected',
                      subtitle: cli.installed
                          ? '${cli.authType ?? 'Not signed in'}'
                                '${cli.subscriptionType != null ? ' · ${cli.subscriptionType}' : ''}'
                          : 'Install Claude Code and sign in to see subscription limits.',
                    ),
                    SettingRow(
                      title: cli.bridgeInstalled ? 'Status-line bridge installed' : 'Install status-line bridge',
                      subtitle: cli.bridgeInstalled
                          ? 'Claude Code hands its official rate_limits JSON to this app after every response. '
                                'Your previous status line is still forwarded.'
                          : 'Official source. Adds a statusLine command to ~/.claude/settings.json (backed up first) '
                                'that saves the rate_limits JSON Claude Code emits. Needs an open Claude Code session to update.',
                      trailing: AppButton(
                        label: cli.bridgeInstalled ? 'Uninstall' : 'Install',
                        style: cli.bridgeInstalled ? AppButtonStyle.danger : AppButtonStyle.primary,
                        motion: motion,
                        loading: _bridgeBusy,
                        onTap: cli.installed ? () => _toggleBridge(cli.bridgeInstalled) : null,
                      ),
                    ),
                    if (_bridgeMessage != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(AppDimens.s10, 0, AppDimens.s10, AppDimens.s8),
                        child: Text(_bridgeMessage!, style: t.bodySmall?.copyWith(color: c.textSecondary)),
                      ),
                    SettingRow(
                      title: 'Open with Claude Code',
                      subtitle:
                          'Adds a SessionStart hook to ~/.claude/settings.json (backed up first) that opens the '
                          'monitor as the small pill whenever a Claude Code session starts or resumes. '
                          'Does nothing when the monitor is already running.',
                      trailing: _Toggle(value: s.launchWithClaude, onChanged: _toggleLaunchHook),
                    ),
                    if (_hookMessage != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(AppDimens.s10, 0, AppDimens.s10, AppDimens.s8),
                        child: Text(_hookMessage!, style: t.bodySmall?.copyWith(color: c.textSecondary)),
                      ),
                    SettingRow(
                      title: 'Close with Claude Code',
                      subtitle:
                          'Quit the monitor once the last Claude Code session has closed, so it is only running '
                          'while you are. Turn this off to keep it open on its own.',
                      trailing: _Toggle(
                        value: s.quitWithClaude,
                        onChanged: (v) => sc.update((cur) => cur.copyWith(quitWithClaude: v)),
                      ),
                    ),
                    SettingRow(
                      title: 'Use Claude usage endpoint',
                      subtitle:
                          'Calls the same endpoint Claude Code\'s /usage uses, with your local sign-in token. '
                          'Works without an open session, but the endpoint is not publicly documented and may change. '
                          'Throttled to once per minute.',
                      trailing: _Toggle(
                        value: s.useUsageEndpoint,
                        onChanged: (v) async {
                          await sc.update((x) => x.copyWith(useUsageEndpoint: v));
                          await usage.refresh(force: true);
                        },
                      ),
                    ),
                    SettingRow(
                      title: 'Open bridge folder',
                      subtitle: AppPaths.appDataDir,
                      trailing: AppButton(label: 'Open', motion: motion, onTap: () => _openFolder(AppPaths.appDataDir)),
                    ),
                  ]),
                  _section('API', <Widget>[
                    SettingRow(
                      title: 'Anthropic API key',
                      subtitle: _secretSubtitle(sc.apiKeyMasked, sc.apiKeyOrigin, 'ANTHROPIC_API_KEY'),
                    ),
                    _SecretEditor(
                      controller: _apiKey,
                      hint: 'sk-ant-api03-…',
                      canClear: sc.apiKeyOrigin == SecretOrigin.secureStorage,
                      onSave: () async {
                        await sc.setApiKey(_apiKey.text);
                        _apiKey.clear();
                        await usage.refresh(probeApi: true, force: true);
                      },
                      onClear: () async {
                        await sc.setApiKey(null);
                        await usage.refresh(force: true);
                      },
                    ),
                    SettingRow(
                      title: 'Admin API key (optional)',
                      subtitle: _secretSubtitle(sc.adminKeyMasked, sc.adminKeyOrigin, 'ANTHROPIC_ADMIN_KEY'),
                    ),
                    _SecretEditor(
                      controller: _adminKey,
                      hint: 'sk-ant-admin01-…',
                      canClear: sc.adminKeyOrigin == SecretOrigin.secureStorage,
                      onSave: () async {
                        await sc.setAdminKey(_adminKey.text);
                        _adminKey.clear();
                        await usage.refresh(probeApi: true, force: true);
                      },
                      onClear: () async {
                        await sc.setAdminKey(null);
                        await usage.refresh(force: true);
                      },
                    ),
                    SettingRow(
                      title: 'Probe model',
                      subtitle: 'Rate limits are per model. Each probe sends one 1-token request.',
                      trailing: SettingDropdown<String>(
                        value: AppConstants.probeModels.contains(s.apiProbeModel)
                            ? s.apiProbeModel
                            : AppConstants.defaultProbeModel,
                        items: AppConstants.probeModels,
                        labelOf: (v) => v,
                        onChanged: (v) => v == null ? null : sc.update((x) => x.copyWith(apiProbeModel: v)),
                      ),
                    ),
                    SettingRow(
                      title: 'Probe interval',
                      trailing: SettingDropdown<ApiProbeInterval>(
                        value: s.apiProbeInterval,
                        items: ApiProbeInterval.values,
                        labelOf: (v) => v.label,
                        onChanged: (v) => v == null ? null : sc.update((x) => x.copyWith(apiProbeInterval: v)),
                      ),
                    ),
                    SettingRow(
                      title: 'Test connection',
                      subtitle: _testMessage ?? 'Sends one probe and reads the rate-limit headers.',
                      trailing: AppButton(
                        label: 'Test',
                        motion: motion,
                        loading: _testing,
                        style: AppButtonStyle.primary,
                        onTap: (sc.apiKeySet || sc.adminKeySet) ? _testConnection : null,
                      ),
                    ),
                    if (_testMessage != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(AppDimens.s10, 0, AppDimens.s10, AppDimens.s8),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              _testOk ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
                              size: AppDimens.iconSm,
                              color: _testOk ? c.connected : c.statusCritical,
                            ),
                            const SizedBox(width: AppDimens.s6),
                            Expanded(child: Text(_testMessage!, style: t.bodySmall)),
                          ],
                        ),
                      ),
                    if (!sc.secureStorageAvailable)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(AppDimens.s10, 0, AppDimens.s10, AppDimens.s8),
                        child: Text(
                          'Secure storage is unavailable on this machine. Use the ANTHROPIC_API_KEY environment variable instead.',
                          style: t.bodySmall?.copyWith(color: c.statusWarning),
                        ),
                      ),
                  ]),
                  _section('About', <Widget>[
                    FutureBuilder<PackageInfo>(
                      future: _packageInfo,
                      builder: (context, snap) => SettingRow(
                        title: AppConstants.appName,
                        subtitle: snap.hasData
                            ? 'Version ${snap.data!.version} (${snap.data!.buildNumber}) · ${AppConstants.developer}'
                            : AppConstants.developer,
                      ),
                    ),
                    const SettingRow(
                      title: 'Data sources',
                      subtitle:
                          'Subscription limits: Claude Code status line (official) or the opt-in usage endpoint. '
                          'API: anthropic-ratelimit-* headers and the Admin Usage API. Nothing is estimated.',
                    ),
                    if (AppConstants.projectUrl.isNotEmpty)
                      SettingRow(
                        title: 'Project',
                        subtitle: AppConstants.projectUrl,
                        onTap: () => launchUrl(Uri.parse(AppConstants.projectUrl)),
                      ),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.s14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: AppDimens.s4, bottom: AppDimens.s6),
            child: SectionHeader(title: title),
          ),
          GlassPanel(
            elevated: true,
            radius: AppDimens.radiusMd,
            padding: const EdgeInsets.symmetric(vertical: AppDimens.s2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (var i = 0; i < children.length; i++) ...<Widget>[
                  if (i > 0)
                    Divider(height: 1, thickness: 1, color: c.border, indent: AppDimens.s10, endIndent: AppDimens.s10),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _secretSubtitle(String masked, SecretOrigin origin, String envName) {
    switch (origin) {
      case SecretOrigin.secureStorage:
        return '$masked · stored in ${AppConstants.secureStoreName}';
      case SecretOrigin.environment:
        return '$masked · from $envName (read-only)';
      case SecretOrigin.none:
        return 'Not set. Stored encrypted; never written to disk in plain text or logged.';
    }
  }

  Future<void> _toggleBridge(bool installed) async {
    final bridge = context.read<StatusLineBridgeService>();
    final usage = context.read<UsageController>();
    setState(() {
      _bridgeBusy = true;
      _bridgeMessage = null;
    });
    try {
      if (installed) {
        await bridge.uninstall();
        _bridgeMessage = 'Bridge removed. Your previous status line (if any) was restored.';
      } else {
        await bridge.install();
        _bridgeMessage =
            'Bridge installed. Start (or restart) a Claude Code session — limits appear after its first response.';
      }
      await usage.refresh(force: true);
    } on AppError catch (e) {
      _bridgeMessage = e.toString();
    } catch (e) {
      _bridgeMessage = 'Could not update settings.json (${e.runtimeType}).';
    } finally {
      if (mounted) setState(() => _bridgeBusy = false);
    }
  }

  Future<void> _toggleLaunchHook(bool enabled) async {
    final bridge = context.read<StatusLineBridgeService>();
    final sc = context.read<SettingsController>();
    setState(() => _hookMessage = null);
    try {
      if (enabled) {
        await bridge.installLaunchHook();
        _hookMessage = 'Hook installed. The monitor opens with your next Claude Code session.';
      } else {
        await bridge.uninstallLaunchHook();
        _hookMessage = 'Hook removed. Claude Code no longer opens the monitor.';
      }
      await sc.update((x) => x.copyWith(launchWithClaude: enabled));
    } on AppError catch (e) {
      _hookMessage = e.toString();
    } catch (e) {
      _hookMessage = 'Could not update settings.json (${e.runtimeType}).';
    }
    if (mounted) setState(() {});
  }

  Future<void> _testConnection() async {
    final usage = context.read<UsageController>();
    setState(() {
      _testing = true;
      _testMessage = null;
    });
    await usage.refresh(probeApi: true, force: true);
    if (!mounted) return;
    final snap = usage.snapshot;
    final api = snap.api;
    final err = snap.apiError;
    setState(() {
      _testing = false;
      if (err != null) {
        _testOk = false;
        _testMessage = err.toString();
      } else if (api != null) {
        _testOk = api.isHealthy;
        _testMessage = api.isHealthy
            ? 'Connected · HTTP ${api.httpStatus} · ${api.hasAnyHeader ? 'rate-limit headers received' : 'no rate-limit headers'}'
            : 'HTTP ${api.httpStatus}${api.errorMessage != null ? ' · ${api.errorMessage}' : ''}';
      } else if (snap.apiReport != null) {
        _testOk = true;
        _testMessage = 'Admin API connected · usage report received';
      } else {
        _testOk = false;
        _testMessage = 'No response — check the key and your connection.';
      }
    });
  }

  Future<void> _openFolder(String path) async {
    try {
      await launchUrl(Uri.directory(path));
    } catch (_) {}
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.value, required this.onChanged, this.enabled = true});

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return MacSwitch(value: value, onChanged: onChanged, enabled: enabled, motion: context.motion);
  }
}

class _SecretEditor extends StatefulWidget {
  const _SecretEditor({
    required this.controller,
    required this.hint,
    required this.canClear,
    required this.onSave,
    required this.onClear,
  });

  final TextEditingController controller;
  final String hint;
  final bool canClear;
  final Future<void> Function() onSave;
  final Future<void> Function() onClear;

  @override
  State<_SecretEditor> createState() => _SecretEditorState();
}

class _SecretEditorState extends State<_SecretEditor> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final motion = context.motion;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppDimens.s10, 0, AppDimens.s10, AppDimens.s10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: widget.controller,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.colors.textPrimary),
              decoration: InputDecoration(hintText: widget.hint),
              onSubmitted: (_) => _run(widget.onSave),
            ),
          ),
          const SizedBox(width: AppDimens.s8),
          AppButton(
            label: 'Save',
            motion: motion,
            style: AppButtonStyle.primary,
            loading: _busy,
            onTap: () => _run(widget.onSave),
          ),
          if (widget.canClear) ...<Widget>[
            const SizedBox(width: AppDimens.s6),
            AppButton(label: 'Clear', motion: motion, style: AppButtonStyle.danger, onTap: () => _run(widget.onClear)),
          ],
        ],
      ),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
