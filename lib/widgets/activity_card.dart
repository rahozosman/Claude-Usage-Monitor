import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_dimens.dart';
import '../app/theme/app_motion.dart';
import '../core/utils/format_utils.dart';
import '../models/session_usage.dart';
import 'app_button.dart';
import 'glass_panel.dart';
import 'section_header.dart';
import 'usage_card.dart';

/// "What used it": local Claude Code sessions (tasks), tokens and models.
class ActivityCard extends StatelessWidget {
  const ActivityCard({
    super.key,
    required this.report,
    required this.scanning,
    required this.motion,
    required this.clock,
    this.opacity = 1,
    this.maxSessions = 6,
  });

  final LocalUsageReport? report;
  final bool scanning;
  final AppMotion motion;
  final ValueListenable<DateTime> clock;
  final double opacity;
  final int maxSessions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final r = report;

    return GlassPanel(
      elevated: true,
      opacity: opacity,
      radius: AppDimens.radiusMd,
      padding: const EdgeInsets.fromLTRB(AppDimens.s16, AppDimens.s14, AppDimens.s16, AppDimens.s14),
      child: ValueListenableBuilder<DateTime>(
        valueListenable: clock,
        builder: (context, now, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionHeader(
              title: 'What used it · this PC',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (r != null && r.activeSessionCount > 0) ...<Widget>[
                    StatusChip(label: '${r.activeSessionCount} active', color: c.connected),
                    const SizedBox(width: AppDimens.s6),
                  ],
                  StatusChip(label: 'Local · Claude Code', color: c.textTertiary),
                ],
              ),
            ),
            const SizedBox(height: AppDimens.s10),
            if (r == null)
              Text(
                scanning ? 'Scanning local Claude Code sessions…' : 'No local Claude Code sessions found.',
                style: t.bodySmall?.copyWith(color: c.textSecondary),
              )
            else ...<Widget>[
              Row(
                children: <Widget>[
                  _Stat(
                    label: 'Today',
                    value: FormatUtils.compact(r.todayTotal),
                    sub: '${r.todaySessionCount} session${r.todaySessionCount == 1 ? '' : 's'}',
                  ),
                  const SizedBox(width: AppDimens.s20),
                  _Stat(
                    label: '7 days',
                    value: FormatUtils.compact(r.weekTotal),
                    sub: '${r.sessions.length} session${r.sessions.length == 1 ? '' : 's'}',
                  ),
                  const SizedBox(width: AppDimens.s20),
                  _Stat(
                    label: 'Output today',
                    value: FormatUtils.compact(_outputToday(r, now)),
                    sub: 'generated tokens',
                  ),
                ],
              ),
              if (r.weekTokensByModel.values.any((v) => v > 0)) ...<Widget>[
                const SizedBox(height: AppDimens.s12),
                _ModelShares(byModel: r.weekTokensByModel, total: r.weekTotal, motion: motion),
              ],
              if (r.sessions.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppDimens.s12),
                Container(height: 1, color: c.border),
                const SizedBox(height: AppDimens.s6),
                _SessionList(sessions: r.sessions, now: now, motion: motion, recentCount: maxSessions - 2),
              ],
              const SizedBox(height: AppDimens.s8),
              Text(
                'Real token counts from Claude Code\'s transcripts on this PC (input + cache read/write + output — '
                'the same basis as its /usage breakdown). Other devices and claude.ai are not included; '
                'tokens do not map 1:1 to the limit percentages above.',
                style: t.bodySmall?.copyWith(color: c.textTertiary, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static int _outputToday(LocalUsageReport r, DateTime now) {
    var sum = 0;
    for (final s in r.sessions) {
      if (s.lastAt.year == now.year && s.lastAt.month == now.month && s.lastAt.day == now.day) {
        sum += s.outputTokens;
      }
    }
    return sum;
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.sub});

  final String label;
  final String value;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: t.labelMedium),
        const SizedBox(height: 2),
        Text(
          value,
          style: t.titleMedium?.copyWith(
            fontSize: 20,
            height: 1.1,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        Text(sub, style: t.bodySmall?.copyWith(color: c.textTertiary)),
      ],
    );
  }
}

class _ModelShares extends StatelessWidget {
  const _ModelShares({required this.byModel, required this.total, required this.motion});

  final Map<String, int> byModel;
  final int total;
  final AppMotion motion;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    // A model that burned no tokens has nothing to compare, and its row read as
    // a blank line in a list of blank-looking lines.
    final entries = byModel.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    // One colour — Claude's orange — stepped down in opacity by rank, so the
    // rows read as one measure against each other instead of borrowing the
    // green/amber that mean "healthy" and "getting close" elsewhere.
    const shades = <double>[1, 0.76, 0.56, 0.4, 0.28];
    return Column(
      children: <Widget>[
        for (var i = 0; i < entries.length && i < 5; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.5),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 92,
                  child: Text(
                    FormatUtils.modelShortName(entries[i].key),
                    style: t.bodySmall?.copyWith(color: c.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: SizedBox(
                      height: 5,
                      child: Stack(
                        children: <Widget>[
                          Positioned.fill(child: ColoredBox(color: c.track)),
                          // Positioned.fill, or the ColoredBox collapses to
                          // constraints.smallest under the Stack's loose
                          // constraints and every bar renders empty.
                          Positioned.fill(
                            child: TweenAnimationBuilder<double>(
                              tween: Tween<double>(end: total == 0 ? 0 : entries[i].value / total),
                              duration: motion.value,
                              curve: motion.settle,
                              builder: (context, v, _) => FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: v.clamp(0, 1),
                                child: ColoredBox(color: c.accent.withValues(alpha: shades[i % shades.length])),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppDimens.s10),
                SizedBox(
                  width: 64,
                  child: Text(
                    FormatUtils.compact(entries[i].value),
                    textAlign: TextAlign.right,
                    style: t.bodySmall?.copyWith(
                      color: c.textPrimary,
                      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Home shows every *active* session plus the [recentCount] most recent
/// finished ones; everything else from the last 7 days lives in a separate
/// "History" section that the button opens and closes.
class _SessionList extends StatefulWidget {
  const _SessionList({required this.sessions, required this.now, required this.motion, required this.recentCount});

  final List<SessionUsage> sessions;
  final DateTime now;
  final AppMotion motion;
  final int recentCount;

  @override
  State<_SessionList> createState() => _SessionListState();
}

class _SessionListState extends State<_SessionList> {
  bool _showHistory = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final active = widget.sessions.where((s) => s.isActive).toList();
    final finished = widget.sessions.where((s) => !s.isActive).toList();
    final recent = finished.take(widget.recentCount).toList();
    final history = finished.skip(widget.recentCount).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (active.isNotEmpty) ...<Widget>[
          _SubHeader(title: 'Active now', count: active.length, color: c.connected),
          for (final s in active) _SessionRow(session: s, now: widget.now),
        ],
        if (recent.isNotEmpty) ...<Widget>[
          if (active.isNotEmpty) const SizedBox(height: AppDimens.s6),
          _SubHeader(title: 'Recent', count: recent.length, color: c.textTertiary),
          for (final s in recent) _SessionRow(session: s, now: widget.now),
        ],
        if (history.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppDimens.s8),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _showHistory
                      ? 'History · ${history.length} more in the last 7 days'
                      : '${history.length} more session${history.length == 1 ? '' : 's'} in the last 7 days',
                  style: t.bodySmall?.copyWith(color: c.textTertiary),
                ),
              ),
              AppButton(
                label: _showHistory ? 'Hide history' : 'Show history',
                motion: widget.motion,
                onTap: () => setState(() => _showHistory = !_showHistory),
              ),
            ],
          ),
          AnimatedSize(
            duration: widget.motion.component,
            curve: widget.motion.transition,
            alignment: Alignment.topCenter,
            child: !_showHistory
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const SizedBox(height: AppDimens.s8),
                      Container(height: 1, color: c.border),
                      const SizedBox(height: AppDimens.s6),
                      _SubHeader(title: 'History · 7 days', count: history.length, color: c.textTertiary),
                      for (final s in history) _SessionRow(session: s, now: widget.now),
                    ],
                  ),
          ),
        ],
      ],
    );
  }
}

class _SubHeader extends StatelessWidget {
  const _SubHeader({required this.title, required this.count, required this.color});

  final String title;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppDimens.s4, bottom: AppDimens.s2),
      child: Row(
        children: <Widget>[
          Text(title.toUpperCase(), style: t.labelSmall?.copyWith(color: color, letterSpacing: 0.6)),
          const SizedBox(width: AppDimens.s6),
          Text('$count', style: t.labelSmall?.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session, required this.now});

  final SessionUsage session;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final s = session;
    // Real model ids from the transcript (`message.model`): the newest
    // response's model first — for a running session, the one answering now —
    // then any other model the session used earlier.
    final latest = s.latestModel;
    final others = s.models.where((m) => m != latest).map(FormatUtils.modelShortName).toList();
    final modelText = latest == null
        ? others.join(', ')
        : '${s.isActive ? 'now ' : ''}${FormatUtils.modelShortName(latest)}'
              '${others.isEmpty ? '' : ' (earlier: ${others.join(', ')})'}';
    final subtitle = <String>[
      if (s.projectName.isNotEmpty) s.projectName,
      if (modelText.isNotEmpty) modelText,
      s.isActive ? 'running' : FormatUtils.relative(s.lastAt, now),
    ].join(' · ');

    return Tooltip(
      message:
          '${s.title}\n${s.projectPath}\n'
          'Model${s.models.length == 1 ? '' : 's'}: ${s.models.isEmpty ? 'unknown' : s.models.join(', ')}'
          '${latest != null ? '\n${s.isActive ? 'Answering now' : 'Last response'}: $latest' : ''}\n'
          'Input ${FormatUtils.integer(s.inputTokens)} · cache write ${FormatUtils.integer(s.cacheCreationTokens)} · '
          'cache read ${FormatUtils.integer(s.cacheReadTokens)} · output ${FormatUtils.integer(s.outputTokens)}\n'
          '${s.messageCount} responses · started ${FormatUtils.absolute(s.firstAt, now)}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppDimens.s4),
        child: Row(
          children: <Widget>[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(shape: BoxShape.circle, color: s.isActive ? c.connected : c.borderStrong),
            ),
            const SizedBox(width: AppDimens.s10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    s.title,
                    style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: t.bodySmall?.copyWith(color: c.textTertiary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppDimens.s10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  FormatUtils.compact(s.totalTokens),
                  style: t.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
                Text('${FormatUtils.compact(s.outputTokens)} out', style: t.bodySmall?.copyWith(color: c.textTertiary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
