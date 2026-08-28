import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_dimens.dart';
import '../app/theme/app_motion.dart';
import '../core/errors/app_error.dart';
import '../core/utils/format_utils.dart';
import '../core/utils/usage_math.dart';
import '../models/api_rate_limits.dart';
import '../models/api_usage_report.dart';
import 'animated_number.dart';
import 'app_icon_button.dart';
import 'countdown.dart';
import 'glass_panel.dart';
import 'section_header.dart';
import 'usage_bar.dart';
import 'usage_card.dart';

/// Expanded-view card for the Anthropic API (official headers + Admin API).
class ApiCard extends StatelessWidget {
  const ApiCard({
    super.key,
    required this.api,
    required this.report,
    required this.error,
    required this.apiConfigured,
    required this.adminConfigured,
    required this.probing,
    required this.onProbe,
    required this.motion,
    required this.clock,
    required this.showPercentages,
    required this.showCountdown,
    this.opacity = 1,
  });

  final ApiRateLimits? api;
  final ApiUsageReport? report;
  final AppError? error;
  final bool apiConfigured;
  final bool adminConfigured;
  final bool probing;
  final VoidCallback onProbe;
  final AppMotion motion;
  final ValueListenable<DateTime> clock;
  final bool showPercentages;
  final bool showCountdown;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final configured = apiConfigured || adminConfigured;

    return GlassPanel(
      elevated: true,
      opacity: opacity,
      radius: AppDimens.radiusMd,
      padding: const EdgeInsets.fromLTRB(AppDimens.s16, AppDimens.s14, AppDimens.s16, AppDimens.s14),
      child: ValueListenableBuilder<DateTime>(
        valueListenable: clock,
        builder: (context, now, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SectionHeader(
                title: 'API usage',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _headerChip(c),
                    if (configured) ...<Widget>[
                      const SizedBox(width: AppDimens.s4),
                      AppIconButton(
                        icon: Icons.sync_rounded,
                        motion: motion,
                        tooltip: 'Probe now (sends one 1-token request)',
                        spinning: probing,
                        size: AppDimens.iconSm,
                        onTap: probing ? null : onProbe,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppDimens.s10),
              if (!configured) _notConfigured(context) else ..._configured(context, now),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppDimens.s8),
                  child: Text(
                    error!.toString(),
                    style: t.bodySmall?.copyWith(color: error!.isNetwork ? c.statusOffline : c.statusCritical),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _headerChip(AppColors c) {
    if (!apiConfigured && !adminConfigured) return StatusChip(label: 'Not configured', color: c.statusOffline);
    final a = api;
    if (a == null) return StatusChip(label: 'Pending', color: c.statusOffline);
    if (a.isRateLimited) return StatusChip(label: 'Rate limited', color: c.statusCritical);
    if (!a.isHealthy) return StatusChip(label: 'Error', color: c.statusCritical);
    final status = UsageMath.statusFor(a.headlineUsedPercentage);
    return StatusChip(label: status == UsageStatus.unknown ? 'Healthy' : 'Healthy · ${_label(status)}', color: c.forStatus(status));
  }

  Widget _notConfigured(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        UsageBar(fraction: null, status: UsageStatus.unknown, motion: motion, height: AppDimens.barThick),
        const SizedBox(height: AppDimens.s10),
        Text(
          'Add an Anthropic API key in Settings to monitor API rate limits. '
          'API usage is billed separately from your Claude subscription and is not part of the 5-hour or weekly limits.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.textSecondary),
        ),
      ],
    );
  }

  List<Widget> _configured(BuildContext context, DateTime now) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final a = api;
    final widgets = <Widget>[];

    if (apiConfigured) {
      final headline = a?.headlineUsedPercentage;
      final status = UsageMath.statusFor(headline);
      widgets.addAll(<Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            if (showPercentages)
              AnimatedNumber(
                value: headline,
                motion: motion,
                style: t.titleMedium?.copyWith(fontSize: 26, height: 1, fontWeight: FontWeight.w600),
              ),
            const SizedBox(width: AppDimens.s8),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(a == null ? 'no probe yet' : 'of the tightest per-minute limit', style: t.bodySmall),
            ),
            const Spacer(),
            if (showCountdown && a?.earliestReset != null)
              Countdown(
                resetsAt: a!.earliestReset,
                clock: clock,
                prefix: 'Replenished in ',
                resetText: 'replenished',
                style: t.bodySmall?.copyWith(color: c.textSecondary, fontWeight: FontWeight.w500),
              ),
          ],
        ),
        const SizedBox(height: AppDimens.s10),
        UsageBar(
          fraction: headline == null ? null : UsageMath.fraction(headline),
          status: status,
          motion: motion,
          height: AppDimens.barThick,
        ),
        const SizedBox(height: AppDimens.s12),
      ]);

      if (a != null) {
        final rows = <(String, String)>[
          for (final b in <RateLimitBucket>[a.requests, a.inputTokens, a.outputTokens, a.tokens])
            if (b.isPresent) (_bucketLabel(b.name), _bucketValue(b, now)),
          if (a.retryAfter != null) ('Retry after', FormatUtils.duration(a.retryAfter!)),
          ('Probe', '${a.model} · HTTP ${a.httpStatus} · ${FormatUtils.relative(a.observedAt, now)}'),
          if (a.probeInputTokens != null)
            ('Probe cost', '${a.probeInputTokens} in / ${a.probeOutputTokens ?? 0} out tokens'),
          ('Source', 'anthropic-ratelimit-* response headers (official)'),
        ];
        if (!a.hasAnyHeader) {
          rows.insert(0, ('Headers', 'No rate-limit headers in the response'));
        }
        widgets.add(DetailGrid(rows: rows));
      } else {
        widgets.add(Text(
          probing ? 'Probing…' : 'Waiting for the first probe.',
          style: t.bodySmall?.copyWith(color: c.textSecondary),
        ));
      }
    }

    if (adminConfigured) {
      widgets.add(const SizedBox(height: AppDimens.s12));
      widgets.add(SectionHeader(title: 'Last 7 days · Admin usage API', color: c.textTertiary));
      widgets.add(const SizedBox(height: AppDimens.s6));
      final r = report;
      if (r == null) {
        widgets.add(Text(
          probing ? 'Loading report…' : 'No report yet.',
          style: t.bodySmall?.copyWith(color: c.textSecondary),
        ));
      } else {
        widgets.add(DetailGrid(rows: <(String, String)>[
          ('Input tokens', FormatUtils.compact(r.totalInputTokens)),
          ('  uncached', FormatUtils.compact(r.uncachedInputTokens)),
          ('  cache read', FormatUtils.compact(r.cacheReadInputTokens)),
          ('  cache write', FormatUtils.compact(r.cacheCreationInputTokens)),
          ('Output tokens', FormatUtils.compact(r.outputTokens)),
          ('Total tokens', FormatUtils.compact(r.totalTokens)),
          ('Cost', r.costUsd == null ? (r.costError ?? 'Unavailable') : FormatUtils.usd(r.costUsd)),
          for (final l in r.configuredLimits) ('Limit · ${l.label}', FormatUtils.integer(l.value)),
          if (r.configuredLimits.isEmpty && r.limitsError != null) ('Configured limits', r.limitsError!),
          ('Updated', FormatUtils.relative(r.observedAt, now)),
        ]));
      }
    }

    return widgets;
  }

  static String _bucketLabel(String name) {
    switch (name) {
      case 'requests':
        return 'Requests';
      case 'input-tokens':
        return 'Input tokens';
      case 'output-tokens':
        return 'Output tokens';
      case 'tokens':
        return 'Tokens';
      default:
        return name;
    }
  }

  static String _bucketValue(RateLimitBucket b, DateTime now) {
    final parts = <String>[];
    if (b.remaining != null && b.limit != null) {
      parts.add('${FormatUtils.compact(b.remaining)} of ${FormatUtils.compact(b.limit)} left');
    } else if (b.remaining != null) {
      parts.add('${FormatUtils.compact(b.remaining)} left');
    } else if (b.limit != null) {
      parts.add('limit ${FormatUtils.compact(b.limit)}');
    }
    if (b.usedPercentage != null) parts.add('${b.usedPercentage!.toStringAsFixed(0)}% used');
    if (b.resetsAt != null) {
      final d = UsageMath.untilReset(b.resetsAt, now);
      parts.add('full in ${FormatUtils.countdown(d)}');
    }
    return parts.join(' · ');
  }

  static String _label(UsageStatus s) {
    switch (s) {
      case UsageStatus.normal:
        return 'normal';
      case UsageStatus.moderate:
        return 'moderate';
      case UsageStatus.warning:
        return 'warning';
      case UsageStatus.critical:
        return 'critical';
      case UsageStatus.unknown:
        return '';
    }
  }
}
