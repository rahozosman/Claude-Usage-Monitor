import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/utils/format_utils.dart';
import '../core/utils/usage_math.dart';

/// Live "resets in" text. Listens only to the shared 1-second [clock], so
/// nothing else in the tree rebuilds per second.
class Countdown extends StatelessWidget {
  const Countdown({
    super.key,
    required this.resetsAt,
    required this.clock,
    this.prefix = '',
    this.style,
    this.resetText = 'reset',
  });

  final DateTime? resetsAt;
  final ValueListenable<DateTime> clock;
  final String prefix;
  final TextStyle? style;
  final String resetText;

  @override
  Widget build(BuildContext context) {
    final s = (style ?? DefaultTextStyle.of(context).style).copyWith(
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
    if (resetsAt == null) return Text('$prefix—', style: s);
    return ValueListenableBuilder<DateTime>(
      valueListenable: clock,
      builder: (context, now, _) {
        if (UsageMath.hasReset(resetsAt, now)) return Text('$prefix$resetText', style: s);
        return Text('$prefix${FormatUtils.countdown(UsageMath.untilReset(resetsAt, now))}', style: s);
      },
    );
  }
}
