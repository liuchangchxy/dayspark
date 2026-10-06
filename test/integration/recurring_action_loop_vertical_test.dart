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
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/writers/todo_writer.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/home/action_section.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_slot_sheet.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

Widget _wrapWithScope({
  required Widget child,
  required ProviderContainer container,
}) {
  return UncontrolledProviderScope(
    container: container,
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ProviderContainer container;
  late int calendarId;

  setUpAll(tzdata.initializeTimeZones);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    calendarId = await db.into(db.calendars).insert(
          CalendarsCompanion.insert(
            name: 'Default',
            color: const Value('#2196F3'),
          ),
        );
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  testWidgets(
    'Phase 2 vertical acceptance: TaskSeries -> Calendar slot -> pick concrete occurrenceId -> TaskAllocation -> visible in Calendar and Action -> exact-instance complete and reopen with dueDate invariant and series preservation',
    (tester) async {
      // -------------------------------------------------------------
      // Dynamic time setup:
      // Derive test allocation start strictly in the future (+2h)
      // so production completion (completedAt = DateTime.now()) always
      // satisfies startAt >= completedAt on any machine or time zone.
      // -------------------------------------------------------------
      final now = DateTime.now();
      final futureInstant = now.add(const Duration(hours: 2));
      final slotStart = DateTime(
        futureInstant.year,
        futureInstant.month,
        futureInstant.day,
        futureInstant.hour,
        futureInstant.minute,
      );
      final slotEnd = slotStart.add(const Duration(hours: 1));
      final slotRange = DateTimeRange(start: slotStart, end: slotEnd);

      // Derive Action day from the slot start date
      final actionDay = DateTime(slotStart.year, slotStart.month, slotStart.day);
      container.read(actionDateProvider.notifier).state = actionDay;

      // -------------------------------------------------------------
      // 1. TaskSeries: Create recurring Todo series
      //    dueDate must remain null throughout.
      // -------------------------------------------------------------
      final spec = RecurrenceSpec.parse(
        anchor: RecurrenceAnchor(
          source: RecurrenceAnchorSource.start,
          value: LocalDate(now.year, now.month, now.day),
        ),
        timeZone: 'Asia/Shanghai',
        rrule: 'FREQ=DAILY;COUNT=7',
      );

      final seriesId = await RecordScope.run(
        db,
        (tx) => TodoWriter.create(
          db,
          tx,
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Daily Sprint Standup',
            rrule: Value(spec.rule.canonical),
          ),
          recurrenceSpec: spec,
        ),
      );

      final initialSeries =
          await (db.select(db.todos)..where((t) => t.id.equals(seriesId))).getSingle();
      expect(initialSeries.dueDate, isNull, reason: 'Recurring series dueDate is null');
      expect(initialSeries.status, 'NEEDS-ACTION');
      expect(initialSeries.syncId, isNotNull);
      final seriesSyncId = initialSeries.syncId!;

      // Verify no events, allocations, or instance states exist yet
      expect(await db.select(db.events).get(), isEmpty);
      expect(await db.select(db.taskAllocations).get(), isEmpty);
      expect(await db.select(db.taskInstanceStates).get(), isEmpty);

      // -------------------------------------------------------------
      // 2. Calendar empty slot: Open CalendarSlotSheet
      // -------------------------------------------------------------
      await tester.pumpWidget(
        _wrapWithScope(
          container: container,
          child: Builder(
            builder: (ctx) {
              return ElevatedButton(
                onPressed: () {
                  CalendarSlotSheet.show(
                    context: ctx,
                    range: slotRange,
                    onCreateEvent: () {
                      fail('Should not trigger onCreateEvent during Schedule Todo flow');
                    },
                    loadSchedulableTodos: () =>
                        container.read(databaseProvider).todosDao.getSchedulableTodos(),
                    onScheduleTodo: (todo, [occurrenceId]) async {
                      await container.read(createTaskAllocationProvider)(
                        todoId: todo.id,
                        occurrenceId: occurrenceId,
                        startAt: slotRange.start,
                        endAt: slotRange.end,
                      );
                    },
                  );
                },
                child: const Text('Open Slot Sheet'),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Slot Sheet'));
      await tester.pumpAndSettle();

      // Tap Schedule Todo
      await tester.tap(find.text('Schedule Todo'));
      await tester.pumpAndSettle();

      // Should display candidate picker with recurring Todo and repeat icon/indicator
      expect(find.text('Daily Sprint Standup'), findsOneWidget);
      expect(find.text('Recurring'), findsOneWidget);

      // -------------------------------------------------------------
      // 3. Tap recurring series -> opens TodoOccurrencePickerSheet -> pick concrete occurrence
      // -------------------------------------------------------------
      await tester.tap(find.text('Daily Sprint Standup'));
      await tester.pumpAndSettle();

      expect(find.text('Select occurrence'), findsOneWidget);

      // Target the first occurrence list tile inside the dialog
      final occurrenceTile = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(ListTile),
      ).first;
      expect(occurrenceTile, findsOneWidget);

      await tester.tap(occurrenceTile);
      await tester.pumpAndSettle();

      // -------------------------------------------------------------
      // 4. Assert throughout right after scheduling:
      //    - TaskAllocation created with exact slot interval and non-null occurrenceId
      //    - No Event is created
      //    - Todo series dueDate is strictly unchanged (still null)
      //    - Visible in Calendar and Action projection
      // -------------------------------------------------------------
      final allocations = await db.select(db.taskAllocations).get();
      expect(allocations, hasLength(1), reason: 'Exactly one TaskAllocation created');
      final allocation = allocations.first;
      expect(allocation.todoId, seriesId);
      expect(allocation.occurrenceId, isNotNull, reason: 'Recurring allocation must have explicit occurrenceId');
      expect(allocation.occurrenceId, startsWith('v2:DATE:'));
      final chosenOccurrenceId = allocation.occurrenceId!;

      expect(allocation.startAt, slotRange.start.toUtc());
      expect(allocation.endAt, slotRange.end.toUtc());
      expect(allocation.state, 'active');

      // Assert no Event created
      final events = await db.select(db.events).get();
      expect(events, isEmpty, reason: 'Scheduling a Todo must NOT create an Event');

      // Assert Todo series dueDate is strictly untouched
      final seriesAfterSchedule =
          await (db.select(db.todos)..where((t) => t.id.equals(seriesId))).getSingle();
      expect(seriesAfterSchedule.dueDate, isNull, reason: 'Series dueDate must remain null');
      expect(seriesAfterSchedule.status, 'NEEDS-ACTION');

      // Assert visible in Calendar query
      final calendarRangeKey =
          '${actionDay.millisecondsSinceEpoch}-${actionDay.add(const Duration(days: 1)).millisecondsSinceEpoch}';
      final calSub = container.listen(
        taskAllocationsInDateRangeProvider(calendarRangeKey),
        (_, __) {},
      );
      final actSub = container.listen(actionProjectionProvider, (_, __) {});

      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final calendarItems =
          container.read(taskAllocationsInDateRangeProvider(calendarRangeKey)).valueOrNull ?? [];
      expect(calendarItems, hasLength(1), reason: 'Visible in Calendar allocation query');
      expect(calendarItems.first.todo.id, seriesId);
      expect(calendarItems.first.allocation.occurrenceId, chosenOccurrenceId);

      // Assert visible in Action projection
      final actionData = container.read(actionProjectionProvider).valueOrNull;
      expect(actionData, isNotNull);
      expect(actionData!.allocations, hasLength(1), reason: 'Allocation visible in Action timeline');
      expect(actionData.allocations.first.todo.id, seriesId);
      expect(actionData.allocations.first.allocation.occurrenceId, chosenOccurrenceId);

      calSub.close();
      actSub.close();

      // -------------------------------------------------------------
      // 5. Action projection UI execution: complete through Action UI
      // -------------------------------------------------------------
      await tester.pumpWidget(
        _wrapWithScope(
          container: container,
          child: const ActionSection(),
        ),
      );
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.text('Daily Sprint Standup'), findsWidgets);

      // Checkbox in todayTimeline for this allocation item
      final checkboxFinder = find.byType(Checkbox);
      expect(checkboxFinder, findsWidgets);
      await tester.tap(checkboxFinder.first);
      await tester.pumpAndSettle();

      // -------------------------------------------------------------
      // 6. Invariant check after completion:
      //    - Exact instance marked COMPLETED in TaskInstanceState
      //    - Parent Todo series status remains NEEDS-ACTION
      //    - Todo series dueDate remains null
      //    - Future allocation for this instance becomes invalidatedByCompletion
      //    - No Event created
      // -------------------------------------------------------------
      final states = await db.select(db.taskInstanceStates).get();
      expect(states, hasLength(1), reason: 'Only the exact chosen occurrence is recorded');
      expect(states.first.todoSyncId, seriesSyncId);
      expect(states.first.occurrenceId, chosenOccurrenceId);
      expect(states.first.status, 'completed');

      final seriesAfterInstanceComplete =
          await (db.select(db.todos)..where((t) => t.id.equals(seriesId))).getSingle();
      expect(seriesAfterInstanceComplete.status, 'NEEDS-ACTION',
          reason: 'Parent series must remain NEEDS-ACTION when completing single instance');
      expect(seriesAfterInstanceComplete.dueDate, isNull,
          reason: 'Parent series dueDate must remain null');

      final updatedAllocations = await db.select(db.taskAllocations).get();
      expect(updatedAllocations, hasLength(1));
      expect(
        updatedAllocations.first.state,
        'invalidatedByCompletion',
        reason: 'Future allocation invalidated on completion',
      );

      final finalEvents = await db.select(db.events).get();
      expect(finalEvents, isEmpty, reason: 'Zero Events created');

      // -------------------------------------------------------------
      // 7. Reopen exact instance
      // -------------------------------------------------------------
      await container.read(toggleTodoProvider)(
        id: seriesId,
        isCompleted: false,
        occurrenceId: chosenOccurrenceId,
      );

      final statesAfterReopen = await db.select(db.taskInstanceStates).get();
      expect(statesAfterReopen, hasLength(1));
      expect(statesAfterReopen.first.status, 'pending');
      expect(statesAfterReopen.first.completedAt, isNull);

      final seriesAfterReopen =
          await (db.select(db.todos)..where((t) => t.id.equals(seriesId))).getSingle();
      expect(seriesAfterReopen.status, 'NEEDS-ACTION');
      expect(seriesAfterReopen.dueDate, isNull);
    },
  );
}
