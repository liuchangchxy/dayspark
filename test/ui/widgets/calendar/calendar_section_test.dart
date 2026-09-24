import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_section.dart';
import 'package:dayspark/ui/widgets/calendar/view_switcher.dart';

Future<void> _pumpCalendar(
  WidgetTester tester, {
  required List<CalendaEventAdapter> events,
  void Function(DateTimeRange range)? onTimeSlotTapped,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CalendarSection(
            events: events,
            onTimeSlotTapped: onTimeSlotTapped,
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders header controls and view switcher', (tester) async {
    await _pumpCalendar(tester, events: []);

    expect(find.byType(ViewSwitcher), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.chevron_left), findsWidgets);
    expect(find.byIcon(CupertinoIcons.chevron_right), findsWidgets);
  });

  testWidgets('renders a timed event tile', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await _pumpCalendar(
      tester,
      events: [
        CalendaEventAdapter(
          drifId: 1,
          calendarId: 10,
          title: 'Timed meeting',
          start: today.add(const Duration(hours: 10)),
          end: today.add(const Duration(hours: 11)),
        ),
      ],
    );

    expect(find.text('Timed meeting'), findsWidgets);
  });

  testWidgets('renders all-day event (all-day bar shows every event)',
      (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await _pumpCalendar(
      tester,
      events: [
        CalendaEventAdapter(
          drifId: 2,
          calendarId: 10,
          title: 'All day one',
          start: today,
          end: today.add(const Duration(days: 1)),
          isAllDay: true,
        ),
        CalendaEventAdapter(
          drifId: 3,
          calendarId: 10,
          title: 'All day two',
          start: today,
          end: today.add(const Duration(days: 1)),
          isAllDay: true,
        ),
      ],
    );

    expect(find.text('All day one'), findsWidgets);
    expect(find.text('All day two'), findsWidgets);
  });

  testWidgets('slot tap uses the viewed (navigated) week, not today',
      (tester) async {
    DateTimeRange? tapped;
    await _pumpCalendar(
      tester,
      events: [],
      onTimeSlotTapped: (range) => tapped = range,
    );

    await tester.tap(find.byIcon(CupertinoIcons.chevron_right));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tapAt(const Offset(400, 400));
    await tester.pump();

    expect(tapped, isNotNull);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thisWeekStart = today.subtract(Duration(days: today.weekday - 1));
    final nextWeekStart = thisWeekStart.add(const Duration(days: 7));
    final nextWeekEnd = nextWeekStart.add(const Duration(days: 7));
    final start = tapped!.start;
    expect(
      !start.isBefore(nextWeekStart) && start.isBefore(nextWeekEnd),
      isTrue,
      reason: 'slot tap must land in the viewed week, got $start',
    );
    expect(
      tapped!.end.difference(tapped!.start),
      const Duration(hours: 1),
    );
    // Regression (C1): wall-clock, not fake-UTC — the router encodes
    // millisecondsSinceEpoch and decodes as local; a shifted value would
    // land hours off (or next day) in the create prefill.
    expect(start.isUtc, isFalse);
    expect(
      DateTime.fromMillisecondsSinceEpoch(start.millisecondsSinceEpoch),
      start,
    );
  });

  testWidgets('month view slot tap routes to event creation with a range', (
    tester,
  ) async {
    DateTimeRange? tapped;
    await _pumpCalendar(
      tester,
      events: [],
      onTimeSlotTapped: (range) => tapped = range,
    );

    await tester.tap(find.text('Month'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));

    // Tap inside the month grid body (below the weekday header row).
    await tester.tapAt(const Offset(400, 400));
    await tester.pump();

    expect(tapped, isNotNull);
    expect(
      tapped!.end.difference(tapped!.start),
      const Duration(hours: 1),
    );
    expect(tapped!.start.isUtc, isFalse);
  });

  testWidgets('title-only event update refreshes rendered tiles',
      (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    CalendaEventAdapter build(String title) => CalendaEventAdapter(
          drifId: 7,
          calendarId: 10,
          title: title,
          start: today.add(const Duration(hours: 9)),
          end: today.add(const Duration(hours: 10)),
        );

    await _pumpCalendar(tester, events: [build('First title')]);
    expect(find.text('First title'), findsWidgets);

    await _pumpCalendar(tester, events: [build('Second title')]);
    expect(find.text('Second title'), findsWidgets);
    expect(find.text('First title'), findsNothing);
  });

  testWidgets('zero-hour all-day event renders in the all-day area',
      (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await _pumpCalendar(
      tester,
      events: [
        CalendaEventAdapter(
          drifId: 8,
          calendarId: 10,
          title: 'Zero hour day',
          start: today,
          end: today,
          isAllDay: true,
        ),
      ],
    );

    expect(find.text('Zero hour day'), findsWidgets);
  });
}
