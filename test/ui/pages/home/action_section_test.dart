import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/action_projection_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/home/action_section.dart';

Widget _wrapWithApp({
  required Widget child,
  required List<Override> overrides,
}) {
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
      home: Scaffold(body: child),
    ),
  );
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late int calendarId;
  final fixedDate = DateTime(2026, 10, 6);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    calendarId = await db.into(db.calendars).insert(
          CalendarsCompanion.insert(
            name: 'Default',
            color: const Value('#2196F3'),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('renders empty state when projection is empty', (tester) async {
    await tester.pumpWidget(
      _wrapWithApp(
        child: const ActionSection(),
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDateProvider.overrideWith((ref) => fixedDate),
        ],
      ),
    );

    // Pump to settle drift stream providers
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      find.text('No events, scheduled tasks, or deadlines for today.'),
      findsOneWidget,
    );
    expect(find.text('Inbox'), findsOneWidget);
    expect(find.text('0 unplanned'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('visually distinguishes Event, Planned Allocation, and Deadline', (
    tester,
  ) async {
    // 1. Event
    await db.into(db.events).insert(
          EventsCompanion.insert(
            calendarId: calendarId,
            summary: 'Client Call',
            startDt: DateTime(2026, 10, 6, 10, 0),
            endDt: DateTime(2026, 10, 6, 11, 0),
            isAllDay: const Value(false),
          ),
        );

    // 2. Ordinary Todo with TaskAllocation
    final scheduledTodoId = await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Write Spec',
          ),
        );
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    await container.read(createTaskAllocationProvider)(
      todoId: scheduledTodoId,
      startAt: DateTime(2026, 10, 6, 14, 0),
      endAt: DateTime(2026, 10, 6, 15, 30),
    );
    container.dispose();

    // 3. Ordinary Todo due today
    await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Submit Invoice',
            dueDate: Value(DateTime(2026, 10, 6, 18, 0)),
          ),
        );

    // 4. Overdue Todo with past deadline
    await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Fix Bug',
            dueDate: Value(DateTime(2026, 10, 2, 9, 0)),
          ),
        );

    await tester.pumpWidget(
      _wrapWithApp(
        child: const ActionSection(),
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDateProvider.overrideWith((ref) => fixedDate),
        ],
      ),
    );

    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Overdue section
    expect(find.text('Overdue (1)'), findsOneWidget);
    expect(find.text('Fix Bug'), findsOneWidget);
    expect(find.text('Deadline: 2026-10-02'), findsOneWidget);

    // Today's schedule section
    expect(find.text("Today's Schedule"), findsOneWidget);
    expect(find.text('Client Call'), findsOneWidget);
    expect(find.text('10:00 – 11:00 · Event'), findsOneWidget);

    expect(find.text('Write Spec'), findsOneWidget);
    expect(find.text('14:00 – 15:30 · Planned'), findsOneWidget);

    // Due Today section
    expect(find.text('Due Today (1)'), findsOneWidget);
    expect(find.text('Submit Invoice'), findsOneWidget);
    expect(find.text('Due today'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('checking allocation checkbox completes ordinary todo without mutating dueDate', (
    tester,
  ) async {
    final originalDueDate = DateTime(2026, 10, 6, 23, 59);
    final todoId = await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Ship Feature',
            dueDate: Value(originalDueDate),
          ),
        );

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    await container.read(createTaskAllocationProvider)(
      todoId: todoId,
      startAt: DateTime(2026, 10, 6, 9, 0),
      endAt: DateTime(2026, 10, 6, 10, 0),
    );
    container.dispose();

    await tester.pumpWidget(
      _wrapWithApp(
        child: const ActionSection(),
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDateProvider.overrideWith((ref) => fixedDate),
        ],
      ),
    );

    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Find checkbox in today's schedule for Ship Feature and tap it
    final checkboxes = find.byType(Checkbox);
    expect(checkboxes, findsWidgets);

    // Tap the first checkbox (Ship Feature in timeline)
    await tester.tap(checkboxes.first);
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Verify in DB that the todo is COMPLETED and dueDate is UNMUTED
    final updatedTodo = await (db.select(db.todos)
          ..where((t) => t.id.equals(todoId)))
        .getSingle();
    expect(updatedTodo.status, 'COMPLETED');
    expect(updatedTodo.dueDate, originalDueDate);

    await _unmount(tester);
  });

  testWidgets('tapping Inbox card invokes onNavigateToTodos callback', (
    tester,
  ) async {
    var navigated = false;
    await tester.pumpWidget(
      _wrapWithApp(
        child: ActionSection(
          onNavigateToTodos: () => navigated = true,
        ),
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDateProvider.overrideWith((ref) => fixedDate),
        ],
      ),
    );

    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(find.text('Inbox'));
    await tester.pump();

    expect(navigated, isTrue);

    await _unmount(tester);
  });
}
