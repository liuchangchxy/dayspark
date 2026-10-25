import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/schedule/repeat_editor.dart';

/// The rule string is a machine format and never reaches the user; every part
/// that changes what the series does must be spelled out. "Every week" for a
/// Mon/Wed/Fri series would be a lie the user cannot see through.
Future<String> _describe(WidgetTester tester, String? rrule) async {
  late String text;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Builder(
        builder: (context) {
          text = describeRepeat(context, rrule);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return text;
}

void main() {
  testWidgets('a rule with no end reads as its frequency alone', (tester) async {
    expect(await _describe(tester, 'FREQ=DAILY'), 'Every day');
  });

  testWidgets('an interval is not hidden behind the frequency', (tester) async {
    expect(await _describe(tester, 'FREQ=DAILY;INTERVAL=3'), 'Every 3 days');
    expect(
      await _describe(tester, 'FREQ=WEEKLY;INTERVAL=2'),
      'Every 2 weeks',
    );
  });

  testWidgets('weekly rules name the weekdays they run on', (tester) async {
    final text = await _describe(tester, 'FREQ=WEEKLY;BYDAY=MO,WE,FR');
    expect(text, startsWith('Every week on '));
    expect(text, contains('Mon'));
    expect(text, contains('Wed'));
    expect(text, contains('Fri'));
  });

  testWidgets('an end is stated as a count or a date, never as the rule', (
    tester,
  ) async {
    final counted = await _describe(tester, 'FREQ=DAILY;COUNT=5');
    expect(counted, 'Every day · Ends after 5 times');

    final dated = await _describe(tester, 'FREQ=WEEKLY;UNTIL=20261231');
    expect(dated, startsWith('Every week · until '));
    expect(dated, contains('2026'));
    expect(dated, isNot(contains('UNTIL')));
  });

  testWidgets('an unknown frequency degrades to custom, not to raw RRULE', (
    tester,
  ) async {
    final text = await _describe(tester, 'FREQ=HOURLY');
    expect(text, 'Custom repeat…');
    expect(text, isNot(contains('FREQ')));
  });

  testWidgets('no rule reads as never repeating', (tester) async {
    expect(await _describe(tester, null), 'Does not repeat');
  });
}
