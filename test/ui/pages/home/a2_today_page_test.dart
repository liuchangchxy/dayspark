import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/action_projection_provider.dart';
import 'package:dayspark/domain/providers/calendar_view_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/home/today_page.dart';

Widget _app({required List<Override> overrides}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: A2TodayPage(
          now: DateTime(2026, 10, 6, 15),
          onOpenTodo: (_) {},
          onOpenEvent: (_) {},
          onToggleTodo: (_, __, ___) async {},
          onOpenUnplanned: () {},
          onScheduleTodo: (_) {},
        ),
      ),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late int calendarId;
  final day = DateTime(2026, 10, 6);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    calendarId = await db
        .into(db.calendars)
        .insert(
          CalendarsCompanion.insert(
            name: 'Work',
            color: const Value('#2196F3'),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('empty day shows the empty box and keeps the capture row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDateProvider.overrideWith((ref) => day),
        ],
      ),
    );
    await _settle(tester);

    expect(find.text('Nothing scheduled today'), findsOneWidget);
    expect(find.byKey(const ValueKey('today-capture-field')), findsOneWidget);
    expect(find.text('Now'), findsNothing);
    expect(find.text('Overdue'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('today is sectioned and a planned todo appears once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            calendarId: calendarId,
            summary: 'Dentist',
            startDt: DateTime(2026, 10, 6, 14, 30),
            endDt: DateTime(2026, 10, 6, 15, 15),
            isAllDay: const Value(false),
          ),
        );
    final plannedId = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Weekly notes',
            dueDate: Value(DateTime(2026, 10, 6, 18)),
          ),
        );
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    await container.read(createTaskAllocationProvider)(
      todoId: plannedId,
      startAt: DateTime(2026, 10, 6, 16),
      endAt: DateTime(2026, 10, 6, 17),
    );
    container.dispose();
    await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Submit report',
            dueDate: Value(DateTime(2026, 10, 6, 18)),
          ),
        );
    await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Pay rent',
            dueDate: Value(DateTime(2026, 10, 2, 10)),
          ),
        );

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDateProvider.overrideWith((ref) => day),
        ],
      ),
    );
    await _settle(tester);

    expect(find.text('Now'), findsOneWidget);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Due today'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);

    expect(find.text('Dentist'), findsOneWidget);
    // Allocation leads, the deadline is secondary metadata: one row, not two.
    expect(find.text('Weekly notes'), findsOneWidget);
    expect(find.text('Submit report'), findsOneWidget);
    expect(find.text('Pay rent'), findsOneWidget);
    expect(find.textContaining('Planned 16:00–17:00'), findsOneWidget);
    expect(find.textContaining('4 days late'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('capture writes a bare todo and nothing else', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDateProvider.overrideWith((ref) => day),
        ],
      ),
    );
    await _settle(tester);

    await tester.enterText(
      find.byKey(const ValueKey('today-capture-field')),
      'Buy milk',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _settle(tester);

    final todos = await db.select(db.todos).get();
    expect(todos, hasLength(1));
    expect(todos.single.summary, 'Buy milk');
    expect(todos.single.dueDate, isNull);
    expect(await db.select(db.taskAllocations).get(), isEmpty);
    expect(find.text('Buy milk'), findsWidgets);

    await _unmount(tester);
  });

  testWidgets('browsing another date never moves today', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            calendarId: calendarId,
            // After the page clock (15:00), so the item is Upcoming rather
            // than Ended; the test is about dates, not about sectioning.
            summary: 'Standup',
            startDt: DateTime(2026, 10, 6, 16),
            endDt: DateTime(2026, 10, 6, 17),
            isAllDay: const Value(false),
          ),
        );

    await db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            calendarId: calendarId,
            summary: 'Other day',
            startDt: DateTime(2026, 10, 9, 9),
            endDt: DateTime(2026, 10, 9, 10),
            isAllDay: const Value(false),
          ),
        );

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDateProvider.overrideWith((ref) => day),
          viewedDateProvider.overrideWith((ref) => DateTime(2026, 10, 9)),
        ],
      ),
    );
    await _settle(tester);

    expect(find.text('Standup'), findsOneWidget);
    expect(find.text('Other day'), findsNothing);
    expect(find.text('Upcoming'), findsOneWidget);
    await _unmount(tester);
  });
}
