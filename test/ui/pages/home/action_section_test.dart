import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/date_context_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/writers/todo_writer.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/pages/home/action_section.dart';
import 'package:dayspark/ui/pages/todo/todo_detail_page.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

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
  setUpAll(tzdata.initializeTimeZones);

  late AppDatabase db;
  late int calendarId;
  final fixedDate = DateTime(2026, 10, 6);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    calendarId = await db
        .into(db.calendars)
        .insert(
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
          clockNowProvider.overrideWithValue(() => fixedDate),
        ],
      ),
    );

    // Pump to settle drift stream providers
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Nothing needs you right now'), findsOneWidget);
    // Today stays a read surface; the unplanned shortcut only appears when
    // something is actually sitting in 未安排.
    expect(find.text('Unplanned'), findsNothing);
    expect(find.textContaining('unplanned'), findsNothing);

    await _unmount(tester);
  });

  testWidgets(
    'visually distinguishes Event, Planned Allocation, and Deadline',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // 1. Event
      await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calendarId,
              summary: 'Client Call',
              startDt: DateTime(2026, 10, 6, 10, 0),
              endDt: DateTime(2026, 10, 6, 11, 0),
              isAllDay: const Value(false),
            ),
          );

      // 2. Ordinary Todo with TaskAllocation
      final scheduledTodoId = await db
          .into(db.todos)
          .insert(
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
      await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Submit Invoice',
              dueDate: Value(DateTime(2026, 10, 6, 18, 0)),
            ),
          );

      // 4. Overdue Todo with past deadline
      await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Fix Bug',
              dueDate: Value(DateTime(2026, 10, 2, 9, 0)),
            ),
          );

      await tester.pumpWidget(
        _wrapWithApp(
          child: ActionSection(date: fixedDate),
          overrides: [
            databaseProvider.overrideWithValue(db),
            clockNowProvider.overrideWithValue(() => fixedDate),
          ],
        ),
      );

      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // The day's plan is drawn to scale: the event and the planned
      // allocation are timeline blocks carrying their own titles.
      expect(find.text('Client Call'), findsOneWidget);
      expect(find.text('Write Spec'), findsOneWidget);

      // Todos live in the bottom sheet as rows: a due-today task carries its
      // due label, and an overdue task is marked overdue instead. Both are
      // also previewed in to-day's unplanned group, so assert presence.
      expect(find.text('Submit Invoice'), findsWidgets);
      expect(find.text('Fix Bug'), findsWidgets);
      expect(find.text('Overdue'), findsOneWidget);

      // The old rhythm strip, inspector and section counters are gone.
      expect(find.byKey(const ValueKey('action-rhythm')), findsNothing);
      expect(find.byKey(const ValueKey('action-inspector')), findsNothing);

      await _unmount(tester);
    },
  );

  testWidgets('planned Todo with a deadline keeps one row and both facts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final todoId = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Write Paper',
            dueDate: Value(DateTime(2026, 10, 6, 18)),
          ),
        );
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    await container.read(createTaskAllocationProvider)(
      todoId: todoId,
      startAt: DateTime(2026, 10, 6, 14),
      endAt: DateTime(2026, 10, 6, 15),
    );
    container.dispose();

    await tester.pumpWidget(
      _wrapWithApp(
        child: ActionSection(date: fixedDate),
        overrides: [
          databaseProvider.overrideWithValue(db),
          clockNowProvider.overrideWithValue(() => fixedDate),
        ],
      ),
    );
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // One obligation, one display: the allocation is the primary block and
    // the deadline rides on it as secondary metadata. The due row is gone, but
    // the block keeps its own completion control (rule 17).
    expect(find.text('Write Paper'), findsOneWidget);
    expect(find.byKey(ValueKey('action-complete-$todoId')), findsNothing);
    expect(find.textContaining('Deadline: Oct 6 · 18:00'), findsOneWidget);
    expect(find.text('Due today'), findsNothing);
    final check = find.byKey(ValueKey('timeline-complete-$todoId'));
    expect(check, findsOneWidget);

    await tester.tap(check);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final stored = await (db.select(
      db.todos,
    )..where((t) => t.id.equals(todoId))).getSingle();
    expect(stored.status, 'COMPLETED');
    await _unmount(tester);
  });

  testWidgets('every Action row opens the object detail, on desktop too', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final id = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Review a deliberately long bilingual title 设计评审与交付',
            dueDate: Value(fixedDate),
          ),
        );
    Todo? opened;
    await tester.pumpWidget(
      _wrapWithApp(
        child: ActionSection(onTodoTap: (todo) => opened = todo),
        overrides: [
          databaseProvider.overrideWithValue(db),
          clockNowProvider.overrideWithValue(() => fixedDate),
        ],
      ),
    );
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(
      find
          .text('Review a deliberately long bilingual title 设计评审与交付')
          .first,
    );
    await tester.pump();
    // One tap, straight to detail: there is no desktop side pane to select
    // into first.
    expect(opened?.id, id);
    expect(find.byKey(const ValueKey('action-inspector')), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('mobile Action has no date switcher: it stays on today', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _wrapWithApp(
        child: const ActionSection(),
        overrides: [
          databaseProvider.overrideWithValue(db),
          clockNowProvider.overrideWithValue(() => fixedDate),
        ],
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    for (var i = 0; i < 7; i++) {
      expect(
        find.byKey(ValueKey('action-week-$i')),
        findsNothing,
        reason:
            'Action answers "now", so browsing future days belongs to '
            'the Calendar',
      );
    }
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ActionSection)),
    );
    expect(container.read(clockDayProvider), fixedDate);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets(
    'completing a planned todo through its block leaves dueDate untouched',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final now = DateTime.now();
      final originalDueDate = DateTime(now.year, now.month, now.day, 23, 59);
      final todoId = await db
          .into(db.todos)
          .insert(
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
        startAt: now.subtract(const Duration(minutes: 30)),
        endAt: now.add(const Duration(minutes: 90)),
      );
      container.dispose();

      Todo? opened;
      await tester.pumpWidget(
        _wrapWithApp(
          child: ActionSection(onTodoTap: (todo) => opened = todo),
          overrides: [
            databaseProvider.overrideWithValue(db),
            clockNowProvider.overrideWithValue(
              () => DateTime(now.year, now.month, now.day),
            ),
          ],
        ),
      );

      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // A planned Todo is a timeline block now, not a sheet row: it opens the
      // detail on tap and carries its own completion control.
      expect(find.byKey(ValueKey('action-complete-$todoId')), findsNothing);
      expect(
        find.byKey(ValueKey('timeline-complete-$todoId')),
        findsOneWidget,
      );
      await tester.tap(find.text('Ship Feature'));
      await tester.pump();
      expect(opened?.id, todoId);

      await tester.pumpWidget(
        _wrapWithApp(
          child: TodoDetailPane(todo: opened!),
          overrides: [
            databaseProvider.overrideWithValue(db),
            clockNowProvider.overrideWithValue(
              () => DateTime(now.year, now.month, now.day),
            ),
          ],
        ),
      );
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final checks = find.byType(DsCheck);
      expect(checks, findsOneWidget);
      await tester.tap(checks);
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Verify in DB that the todo is COMPLETED and dueDate is UNMUTED
      final updatedTodo = await (db.select(
        db.todos,
      )..where((t) => t.id.equals(todoId))).getSingle();
      expect(updatedTodo.status, 'COMPLETED');
      expect(updatedTodo.dueDate, originalDueDate);

      await _unmount(tester);
    },
  );

  testWidgets(
    'Phase 2: renders today recurring instance and checkbox completes exact instance',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      final todayStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final occId = 'v2:DATE:$todayStr';

      final spec = RecurrenceSpec.parse(
        anchor: RecurrenceAnchor(
          source: RecurrenceAnchorSource.due,
          value: LocalDate(today.year, today.month, today.day),
        ),
        timeZone: 'Asia/Shanghai',
        rrule: 'FREQ=DAILY',
      );
      final seriesId = await RecordScope.run(
        db,
        (tx) => TodoWriter.create(
          db,
          tx,
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Daily Yoga',
            rrule: Value(spec.rule.canonical),
          ),
          recurrenceSpec: spec,
        ),
      );

      await tester.pumpWidget(
        _wrapWithApp(
          child: const ActionSection(),
          overrides: [
            databaseProvider.overrideWithValue(db),
            clockNowProvider.overrideWithValue(() => todayDate),
          ],
        ),
      );

      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // The instance is a sheet row and the series master is previewed in
      // today's unplanned group, so the title can appear more than once.
      expect(find.text('Daily Yoga'), findsWidgets);
      expect(find.text('1 still open today'), findsOneWidget);

      // Find and tap the completion circle for Daily Yoga
      final checkbox = find.byKey(ValueKey('action-complete-$seriesId'));
      expect(checkbox, findsOneWidget);
      await tester.tap(checkbox);

      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Verify parent series remains NEEDS-ACTION
      final parent = await (db.select(
        db.todos,
      )..where((t) => t.id.equals(seriesId))).getSingle();
      expect(parent.status, 'NEEDS-ACTION');

      // Verify taskInstanceState has completed
      final state =
          await (db.select(db.taskInstanceStates)..where(
                (s) =>
                    s.todoSyncId.equals(parent.syncId!) &
                    s.occurrenceId.equals(occId),
              ))
              .getSingle();
      expect(state.status, 'completed');

      // Verify UI no longer offers the completed instance as open today: the
      // actionable row is gone even though the series master can still be
      // previewed in the unplanned group.
      expect(find.byKey(ValueKey('action-complete-$seriesId')), findsNothing);
      expect(find.text('0 still open today'), findsOneWidget);

      await _unmount(tester);
    },
  );

  testWidgets('no rhythm strip and no side pane at any width', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _wrapWithApp(
        child: const ActionSection(),
        overrides: [
          databaseProvider.overrideWithValue(db),
          clockNowProvider.overrideWithValue(() => fixedDate),
        ],
      ),
    );
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const ValueKey('action-rhythm')), findsNothing);
    expect(find.byKey(const ValueKey('action-inspector')), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });
}
