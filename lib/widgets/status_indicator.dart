import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_motion.dart';
import '../models/connection_status.dart';

/// Connection dot with an optional label. Breathes gently while live (and
/// only then — no continuous animation when idle or offline).
class StatusIndicator extends StatefulWidget {
  const StatusIndicator({
    super.key,
    required this.status,
    required this.motion,
    this.label,
    this.size = 7,
  });

  final ConnectionStatus status;
  final AppMotion motion;
  final String? label;
  final double size;

  @override
  State<StatusIndicator> createState() => _StatusIndicatorState();
}

class _StatusIndicatorState extends State<StatusIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.motion.ambient == Duration.zero ? const Duration(seconds: 2) : widget.motion.ambient,
  );

  bool get _shouldPulse => widget.status.isConnected && widget.motion.enabled;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant StatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (_shouldPulse) {
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
    final c = context.colors;
    final color = c.forConnection(widget.status);
    final dot = RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = Curves.easeInOut.transform(_controller.value);
          return Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: _shouldPulse
                  ? <BoxShadow>[
                      BoxShadow(
                        color: color.withValues(alpha: 0.25 + 0.35 * t),
                        blurRadius: 3 + 5 * t,
                        spreadRadius: 0.5 + 1.5 * t,
                      ),
                    ]
                  : null,
            ),
          );
        },
      ),
    );

    if (widget.label == null) return dot;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        dot,
        const SizedBox(width: 7),
        Text(
          widget.label!,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: widget.status.isConnected ? c.textPrimary : c.textSecondary,
                fontWeight: FontWeight.w500,
              ),
        ),
      ],
    );
  }
}
