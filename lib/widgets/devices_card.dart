import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_dimens.dart';
import '../app/theme/app_motion.dart';
import '../core/utils/format_utils.dart';
import '../models/device_activity.dart';
import 'glass_panel.dart';
import 'section_header.dart';
import 'usage_card.dart';

/// "Other devices": what the same Claude account is doing on your other
/// machines — how many sessions are open there, which model each one is on,
/// and how many tokens each has used.
///
/// Every value is published by the monitor running on that machine, from its
/// own Claude Code transcripts. Nothing is invented: a device that has not
/// reported is simply not listed.
class DevicesCard extends StatelessWidget {
  const DevicesCard({
    super.key,
    required this.result,
    required this.motion,
    required this.clock,
    this.opacity = 1,
    this.maxIdleSessionsPerDevice = 3,
  });

  final DeviceSyncResult result;
  final AppMotion motion;
  final ValueListenable<DateTime> clock;
  final double opacity;

  /// Open sessions are always all shown; finished ones are capped.
  final int maxIdleSessionsPerDevice;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;

    return GlassPanel(
      elevated: true,
      opacity: opacity,
      radius: AppDimens.radiusMd,
      padding: const EdgeInsets.fromLTRB(AppDimens.s16, AppDimens.s14, AppDimens.s16, AppDimens.s14),
      child: ValueListenableBuilder<DateTime>(
        valueListenable: clock,
        builder: (context, now, _) {
          final devices = result.devices;
          final online = result.onlineCount(now);
          final open = result.openSessionCount(now);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SectionHeader(
                title: 'Other devices · same account',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (open > 0) ...<Widget>[
                      StatusChip(label: '$open session${open == 1 ? '' : 's'} open', color: c.connected),
                      const SizedBox(width: AppDimens.s6),
                    ],
                    StatusChip(
                      label: devices.isEmpty ? 'No reports' : '$online of ${devices.length} online',
                      color: online > 0 ? c.textSecondary : c.textTertiary,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppDimens.s10),
              if (!result.enabled)
                _Note('Sharing is off. Turn on "Share activity with my other devices" in Settings → Activity.')
              else if (result.folder == null)
                _Note(
                  'No shared folder yet. OneDrive was not found on this PC — choose any folder that syncs '
                  'between your devices in Settings → Activity.',
                )
              else if (result.error != null)
                _Note(result.error!, color: c.statusWarning)
              else if (devices.isEmpty)
                _Note(
                  'No other device has reported yet. Run Claude Usage Monitor on your other PCs with the '
                  'same shared folder; each one publishes its own Claude Code activity here.',
                )
              else
                for (var i = 0; i < devices.length; i++) ...<Widget>[
                  if (i > 0) Divider(height: AppDimens.s16, thickness: 0.5, color: c.separator),
                  _DeviceBlock(device: devices[i], now: now, motion: motion, maxIdleSessions: maxIdleSessionsPerDevice),
                ],
              const SizedBox(height: AppDimens.s10),
              Text(
                'Each device publishes its own Claude Code activity every few seconds; how fast it arrives '
                'depends on your shared folder syncing. Claude itself reports no per-device activity.',
                style: t.bodySmall?.copyWith(color: c.textTertiary, fontSize: 11),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Text(text, style: t.bodySmall?.copyWith(color: color ?? c.textSecondary));
  }
}

class _DeviceBlock extends StatelessWidget {
  const _DeviceBlock({required this.device, required this.now, required this.motion, required this.maxIdleSessions});

  final DeviceActivity device;
  final DateTime now;
  final AppMotion motion;
  final int maxIdleSessions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final online = device.isOnline(now);
    final open = device.openSessions(now);
    final idle = device.sessions.where((s) => !s.active || !online).take(maxIdleSessions).toList();
    final dot = open.isNotEmpty ? c.connected : (online ? c.statusNormal : c.textTertiary);
    final models = (device.todayTokensByModel.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        .map((e) => '${FormatUtils.modelShortName(e.key)} ${FormatUtils.compact(e.value)}')
        .join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            _Dot(color: dot, live: open.isNotEmpty, motion: motion),
            const SizedBox(width: AppDimens.s8),
            Expanded(
              child: Text(
                device.user == null ? device.name : '${device.name} · ${device.user}',
                style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              open.isNotEmpty
                  ? '${open.length} session${open.length == 1 ? '' : 's'} open'
                  : online
                  ? 'Online · idle'
                  : 'Last seen ${FormatUtils.relative(device.updatedAt.toLocal(), now)}',
              style: t.bodySmall?.copyWith(
                color: open.isNotEmpty ? c.connected : c.textTertiary,
                fontWeight: open.isNotEmpty ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.s4),
        Padding(
          padding: const EdgeInsets.only(left: AppDimens.s16 - 1),
          child: Text(
            'Today ${FormatUtils.compact(device.todayTokens)} tokens · '
            '${device.todaySessionCount} session${device.todaySessionCount == 1 ? '' : 's'} · '
            '7 days ${FormatUtils.compact(device.weekTokens)} · '
            'updated ${FormatUtils.relative(device.updatedAt.toLocal(), now)}'
            '${models.isEmpty ? '' : '\n$models'}',
            style: t.bodySmall?.copyWith(color: c.textSecondary, fontSize: 11),
          ),
        ),
        for (final s in open) _SessionRow(session: s, now: now, motion: motion, live: true),
        for (final s in idle) _SessionRow(session: s, now: now, motion: motion, live: false),
      ],
    );
  }
}

/// One session on another device: what it is working on, on which model, and
/// how many tokens it has used.
class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session, required this.now, required this.motion, required this.live});

  final DeviceSession session;
  final DateTime now;
  final AppMotion motion;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final s = session;
    final model = s.latestModel ?? (s.models.isEmpty ? null : s.models.last);
    final subtitle = <String>[
      if (s.project.isNotEmpty) s.project,
      if (model != null) FormatUtils.modelShortName(model),
      if (s.messages > 0) '${s.messages} response${s.messages == 1 ? '' : 's'}',
      live ? 'working now' : FormatUtils.relative(s.lastAt.toLocal(), now),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(left: AppDimens.s16 - 1, top: AppDimens.s8),
      child: Row(
        children: <Widget>[
          _Dot(color: live ? c.connected : c.borderStrong, live: live, motion: motion, size: 5),
          const SizedBox(width: AppDimens.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  s.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall?.copyWith(
                    color: live ? c.textPrimary : c.textSecondary,
                    fontWeight: live ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall?.copyWith(color: c.textTertiary, fontSize: 10.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppDimens.s8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                FormatUtils.compact(s.tokens),
                style: t.bodySmall?.copyWith(
                  color: c.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
              if (s.outputTokens > 0)
                Text(
                  '${FormatUtils.compact(s.outputTokens)} out',
                  style: t.bodySmall?.copyWith(color: c.textTertiary, fontSize: 10.5),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Status dot; breathes gently while that session is actually working.
class _Dot extends StatefulWidget {
  const _Dot({required this.color, required this.live, required this.motion, this.size = 7});

  final Color color;
  final bool live;
  final AppMotion motion;
  final double size;

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  bool get _pulsing => widget.live && widget.motion.enabled;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _Dot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (_pulsing) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
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
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final v = Curves.easeInOut.transform(_controller.value);
          return Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
              boxShadow: _pulsing
                  ? <BoxShadow>[
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.20 + 0.35 * v),
                        blurRadius: 3 + 4 * v,
                        spreadRadius: 0.5 + 1.2 * v,
                      ),
                    ]
                  : null,
            ),
          );
        },
      ),
    );
  }
}
