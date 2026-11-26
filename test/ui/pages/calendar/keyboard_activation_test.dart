import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/calendar_view_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/a2.dart' show FocusableTap;
import 'package:dayspark/ui/pages/calendar/a2_calendar_page.dart';
import 'package:dayspark/ui/pages/calendar/a2_calendar_views.dart';
import 'package:dayspark/ui/widgets/calendar/view_switcher.dart';

final _day = DateTime(2026, 11, 15);

Todo _todo(int id, int calendarId, String summary) => Todo(
  id: id,
  calendarId: calendarId,
  summary: summary,
  priority: 0,
  status: 'NEEDS-ACTION',
  dueDate: DateTime(2026, 11, 15, 18),
  sortOrder: 0,
  recurrenceRevision: 0,
  percentComplete: 0,
  createdAt: _day,
  updatedAt: _day,
  serverRev: 0,
);

TaskAllocationCalendarItem _allocation({
  required DateTime start,
  required DateTime end,
}) => TaskAllocationCalendarItem(
  allocation: TaskAllocation(
    id: 1,
    todoId: 1,
    startAt: start.toUtc(),
    endAt: end.toUtc(),
    state: 'active',
    createdAt: _day.toUtc(),
    updatedAt: _day.toUtc(),
    serverRev: 0,
  ),
  todo: _todo(1, 1, 'Work block'),
);

Widget _app(Widget page, {required AppDatabase db}) => ProviderScope(
  overrides: [
    databaseProvider.overrideWithValue(db),
    calendarNowProvider.overrideWithValue(() => DateTime(2026, 11, 15, 15)),
    viewedDateProvider.overrideWith((ref) => _day),
  ],
  child: MaterialApp(
    localizationsDelegates: const [
      ...AppLocalizations.localizationsDelegates,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: page),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

void _focus(WidgetTester tester, Finder control) {
  final gesture = find
      .descendant(of: control, matching: find.byType(GestureDetector))
      .first;
  Focus.of(tester.element(gesture)).requestFocus();
}

Future<void> _switchView(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('calendar-view-menu')));
  await _settle(tester);
  await tester.tap(find.text(label).last);
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'calendar_view_mode': 'week'});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db
        .into(db.calendars)
        .insert(
          CalendarsCompanion.insert(
            name: 'Work',
            color: const Value('#5F7183'),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('Enter on a phone month day opens the day view like a tap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final page = A2CalendarPage(
      events: const <CalendaEventAdapter>[],
      allocations: [
        _allocation(
          start: DateTime(2026, 11, 15, 16),
          end: DateTime(2026, 11, 15, 17),
        ),
      ],
      deadlines: const [],
    );
    await tester.pumpWidget(_app(page, db: db));
    await _settle(tester);
    await _switchView(tester, 'Month');
    await _settle(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(A2CalendarPage)),
    );

    final cell = find.byKey(const ValueKey('month-day-2026-11-15'));
    _focus(tester, cell);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester);

    expect(container.read(calendarViewModeProvider), CalendarViewMode.day);
    expect(find.byType(A2PhoneDayList), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('Enter on a desktop month cell opens that day', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final page = A2CalendarPage(
      events: const <CalendaEventAdapter>[],
      allocations: const [],
      deadlines: const [],
    );
    await tester.pumpWidget(_app(page, db: db));
    await _settle(tester);
    await tester.tap(find.text('Month'));
    await _settle(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(A2CalendarPage)),
    );

    final cell = find.byKey(const ValueKey('desktop-month-day-2026-11-16'));
    _focus(tester, cell);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester);

    expect(container.read(calendarViewModeProvider), CalendarViewMode.day);
    expect(container.read(viewedDateProvider), DateTime(2026, 11, 16));
    expect(find.byType(A2TimeGridView), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('Enter on the week/day view switch reaches the day view', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final page = A2CalendarPage(
      events: const <CalendaEventAdapter>[],
      allocations: const [],
      deadlines: const [],
    );
    await tester.pumpWidget(_app(page, db: db));
    await _settle(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(A2CalendarPage)),
    );

    final dayButton = find
        .ancestor(
          of: find.text('Day'),
          matching: find.byType(FocusableTap),
        )
        .first;
    _focus(tester, dayButton);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester);

    expect(container.read(calendarViewModeProvider), CalendarViewMode.day);

    await _unmount(tester);
  });
}
