import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_dimens.dart';
import '../app/theme/app_motion.dart';
import '../core/constants/app_constants.dart';
import 'claude_mark.dart';
import 'github_mark.dart';
import 'glass_panel.dart';
import 'section_header.dart';

/// "About" — who made this, how to reach them, where the source lives.
class AboutCard extends StatelessWidget {
  const AboutCard({super.key, required this.motion, this.opacity = 1});

  final AppMotion motion;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;

    return GlassPanel(
      elevated: true,
      opacity: opacity,
      radius: AppDimens.radiusLg,
      padding: const EdgeInsets.fromLTRB(AppDimens.s16, AppDimens.s14, AppDimens.s16, AppDimens.s14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionHeader(title: 'About'),
          const SizedBox(height: AppDimens.s10),
          Row(
            children: <Widget>[
              ClaudeMark(color: c.accent, size: 18),
              const SizedBox(width: AppDimens.s10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      AppConstants.appName,
                      style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Developed by ${AppConstants.developer}',
                      style: t.bodySmall?.copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.s10),
          _LinkRow(
            icon: Icon(Icons.mail_outline_rounded, size: AppDimens.iconSm, color: c.textSecondary),
            label: 'Contact',
            value: AppConstants.contactEmail,
            motion: motion,
            onTap: () => _open(Uri(scheme: 'mailto', path: AppConstants.contactEmail)),
          ),
          const SizedBox(height: AppDimens.s6),
          _LinkRow(
            icon: GitHubMark(color: c.textSecondary, size: AppDimens.iconSm),
            label: 'GitHub',
            value: 'rahozosman/Claude-Usage-Monitor',
            motion: motion,
            onTap: () => _open(Uri.parse(AppConstants.projectUrl)),
          ),
        ],
      ),
    );
  }

  static Future<void> _open(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // No mail client or browser registered: nothing useful to do here.
    }
  }
}

/// One tappable row: mark, label, value, and a hover tint like the setting rows.
class _LinkRow extends StatefulWidget {
  const _LinkRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.motion,
    required this.onTap,
  });

  final Widget icon;
  final String label;
  final String value;
  final AppMotion motion;
  final VoidCallback onTap;

  @override
  State<_LinkRow> createState() => _LinkRowState();
}

class _LinkRowState extends State<_LinkRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: widget.motion.micro,
          curve: widget.motion.enter,
          padding: const EdgeInsets.symmetric(horizontal: AppDimens.s8, vertical: AppDimens.s6),
          decoration: BoxDecoration(
            color: _hover ? c.fill : Colors.transparent,
            borderRadius: BorderRadius.circular(AppDimens.radiusSm),
          ),
          child: Row(
            children: <Widget>[
              widget.icon,
              const SizedBox(width: AppDimens.s10),
              Text(widget.label, style: t.bodySmall?.copyWith(color: c.textSecondary)),
              const SizedBox(width: AppDimens.s10),
              Expanded(
                child: Text(
                  widget.value,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall?.copyWith(color: _hover ? c.accent : c.textPrimary),
                ),
              ),
              const SizedBox(width: AppDimens.s6),
              Icon(Icons.north_east_rounded, size: 12, color: _hover ? c.accent : c.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
