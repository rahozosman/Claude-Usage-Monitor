import 'package:claude_usage_monitor/app/theme/app_motion.dart';
import 'package:claude_usage_monitor/models/limit_window.dart';
import 'package:claude_usage_monitor/widgets/usage_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The real shape of the bug, straight off this machine's `history.jsonl`:
///
///     {"w":"five_hour","p":8.0,"r":1788107400,"t":1788130758,"s":"usageEndpoint"}
///
/// `r` (the reset) is 1788107400 = 16:30 UTC and `t` (the observation) is
/// 1788130758 = 22:59 UTC — the window's reset had already passed six and a
/// half hours before the reading was taken. The card used to blank the 8% and
/// print "Unavailable" over it; it now has to show the figure, dimmed, and say
/// the window is closed.
const double kUsed = 8;

Widget _host(LimitWindow window, DateTime now) => MaterialApp(
  home: Scaffold(
    body: UsageCard(
      window: window,
      motion: AppMotion.off,
      clock: ValueNotifier<DateTime>(now),
      showPercentages: true,
      showCountdown: true,
    ),
  ),
);

void main() {
  final now = DateTime(2026, 8, 30, 23, 5);

  LimitWindow five({required DateTime resetsAt, DateTime? observedAt}) => LimitWindow(
    id: LimitWindow.fiveHourId,
    label: LimitWindow.labelFor(LimitWindow.fiveHourId),
    usedPercentage: kUsed,
    resetsAt: resetsAt,
    observedAt: observedAt ?? now.subtract(const Duration(hours: 7)),
    source: DataSource.usageEndpoint,
  );

  testWidgets('a closed 5-hour window shows its figure instead of a blank', (tester) async {
    await tester.pumpWidget(_host(five(resetsAt: now.subtract(const Duration(hours: 6, minutes: 35))), now));
    await tester.pumpAndSettle();

    expect(find.text('5-hour limit'), findsOneWidget);
    // The whole point: the number is on screen, not erased.
    expect(find.text('8%'), findsWidgets);
    expect(find.text('Closed'), findsOneWidget);
    expect(find.text('closed 6 hours ago'), findsOneWidget);
    expect(find.text('used before it closed'), findsOneWidget);

    // …and it is never dressed up as live.
    expect(find.text('Unavailable'), findsNothing);
    expect(find.text('—'), findsNothing);
    expect(find.textContaining('No active 5-hour window'), findsNothing);
    expect(find.textContaining('Resets in'), findsNothing);
    expect(find.text('Closed at'), findsOneWidget);
    expect(find.text('Resets at'), findsNothing);
    expect(find.text('Remaining'), findsNothing);
    expect(
      find.textContaining('Last 5-hour window: 8% · closed 6 hours ago'),
      findsOneWidget,
    );
  });

  testWidgets('a stale resets_at leaves the live figure alone', (tester) async {
    // The live bug: resets_at six hours in the past on a reading taken two
    // minutes ago, while the percentage climbs with use. Nothing here is
    // closed, so nothing may be greyed or hidden.
    await tester.pumpWidget(
      _host(
        LimitWindow(
          id: LimitWindow.fiveHourId,
          label: LimitWindow.labelFor(LimitWindow.fiveHourId),
          usedPercentage: 16,
          resetsAt: now.subtract(const Duration(hours: 6, minutes: 35)),
          observedAt: now.subtract(const Duration(minutes: 2)),
          source: DataSource.usageEndpoint,
        ),
        now,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('16%'), findsWidgets);
    expect(find.text('used'), findsOneWidget);
    expect(find.text('Closed'), findsNothing);
    expect(find.textContaining('closed'), findsNothing);
    expect(find.text('Unavailable'), findsNothing);
    // The reset time itself is the part we cannot vouch for, so it, and only
    // it, goes blank.
    expect(find.text('Resets at'), findsOneWidget);
    expect(find.textContaining('Resets in'), findsNothing);
  });

  testWidgets('an open window is untouched by any of it', (tester) async {
    await tester.pumpWidget(_host(five(resetsAt: now.add(const Duration(hours: 2)), observedAt: now), now));
    await tester.pumpAndSettle();

    expect(find.text('8%'), findsWidgets);
    expect(find.text('used'), findsOneWidget);
    expect(find.text('Closed'), findsNothing);
    expect(find.text('Resets at'), findsOneWidget);
    expect(find.text('Remaining'), findsOneWidget);
    expect(find.textContaining('closed'), findsNothing);
  });

  testWidgets('a window with no figure at all still reads Unavailable', (tester) async {
    await tester.pumpWidget(
      _host(
        LimitWindow.unavailable(
          id: LimitWindow.fiveHourId,
          label: LimitWindow.labelFor(LimitWindow.fiveHourId),
          reason: 'Not signed in to Claude Code — run `claude` and use /login',
        ),
        now,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('Closed'), findsNothing);
  });
}
