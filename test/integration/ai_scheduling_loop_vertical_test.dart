import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/action_projection_provider.dart';
import 'package:dayspark/domain/providers/ai_scheduler_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/writers/event_writer.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ProviderContainer container;
  late int calendarId;

  setUpAll(tzdata.initializeTimeZones);

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
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

  testWidgets('Vertical Integration: Availability seam -> TaskAllocation scheduling -> Calendar & Action projection -> Complete', (tester) async {
    final targetDay = DateTime(2026, 10, 20);
    final rangeStart = DateTime(2026, 10, 20, 9, 0);
    final rangeEnd = DateTime(2026, 10, 20, 18, 0);

    // 1. Long-running recurring Event whose master startDt was 100 days ago (2026-07-12)
    //    Occurs daily from 09:00 to 10:00
    await RecordScope.run(
      db,
      (tx) => EventWriter.create(
        db,
        tx,
        EventsCompanion.insert(
          calendarId: calendarId,
          summary: 'Long-running Daily Standup',
          startDt: DateTime(2026, 7, 12, 9, 0),
          endDt: DateTime(2026, 7, 12, 10, 0),
          isAllDay: const Value(false),
          rrule: const Value('RRULE:FREQ=DAILY'),
        ),
      ),
    );

    // 2. An existing task allocation for another task from 14:00 to 15:00
    final otherTodoId = await db.into(db.todos).insert(
      TodosCompanion.insert(
        calendarId: calendarId,
        summary: 'Other Task',
      ),
    );
    await container.read(createTaskAllocationProvider)(
      todoId: otherTodoId,
      startAt: DateTime(2026, 10, 20, 14, 0),
      endAt: DateTime(2026, 10, 20, 15, 0),
    );

    // 3. New Todo obligation to be scheduled
    final due = DateTime.utc(2026, 10, 25, 18, 0);
    final mainTodoId = await db.into(db.todos).insert(
      TodosCompanion.insert(
        calendarId: calendarId,
        summary: 'Deliver Architecture Proposal',
        dueDate: Value(due),
        priority: const Value(2),
      ),
    );

    // 4. Compute availability deterministically via suggestTimeSlotsProvider
    final suggestions = await container.read(suggestTimeSlotsProvider)(
      taskDescription: 'Deliver Architecture Proposal',
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      slotDuration: const Duration(hours: 1),
    );

    expect(suggestions, isNotEmpty);
    // Verified invariant: No suggestion overlaps 09:00 - 10:00 (long-running recurring event)
    for (final s in suggestions) {
      final sStart = DateTime.parse(s['start'] as String);
      final sEnd = DateTime.parse(s['end'] as String);
      final overlapsStandup = sStart.isBefore(DateTime(2026, 10, 20, 10, 0)) &&
          sEnd.isAfter(DateTime(2026, 10, 20, 9, 0));
      expect(overlapsStandup, isFalse, reason: 'Must not overlap long-running recurring event');

      final overlapsOtherAlloc = sStart.isBefore(DateTime(2026, 10, 20, 15, 0)) &&
          sEnd.isAfter(DateTime(2026, 10, 20, 14, 0));
      expect(overlapsOtherAlloc, isFalse, reason: 'Must not overlap existing task allocation');
    }

    // 5. Select free slot 10:00 - 11:00 and schedule TaskAllocation
    final chosenStart = DateTime(2026, 10, 20, 10, 0);
    final chosenEnd = DateTime(2026, 10, 20, 11, 0);
    await container.read(createTaskAllocationProvider)(
      todoId: mainTodoId,
      startAt: chosenStart,
      endAt: chosenEnd,
    );

    // Invariant: Zero Events created, dueDate untouched
    final allEvents = await db.select(db.events).get();
    expect(allEvents, hasLength(1), reason: 'Only the initial recurring event exists');

    final mainTodo = await (db.select(db.todos)..where((t) => t.id.equals(mainTodoId))).getSingle();
    expect(mainTodo.dueDate!.toUtc(), due, reason: 'dueDate is zero-touch');

    // 6. Action and Calendar projections
    container.read(actionDateProvider.notifier).state = targetDay;
    final rangeKey = '${rangeStart.millisecondsSinceEpoch}-${rangeEnd.millisecondsSinceEpoch}';

    final calSub = container.listen(taskAllocationsInDateRangeProvider(rangeKey), (_, __) {});
    final actSub = container.listen(actionProjectionProvider, (_, __) {});

    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final allocationItems = container.read(taskAllocationsInDateRangeProvider(rangeKey)).valueOrNull ?? [];
    expect(
      allocationItems.any((item) => item.todo.id == mainTodoId && item.allocation.startAt.isAtSameMomentAs(chosenStart)),
      isTrue,
      reason: 'Visible in calendar allocation range provider',
    );

    final actionData = container.read(actionProjectionProvider).valueOrNull;
    expect(actionData, isNotNull);
    expect(
      actionData!.allocations.any((item) => item.todo.id == mainTodoId && item.allocation.startAt.isAtSameMomentAs(chosenStart)),
      isTrue,
      reason: 'Visible in action projection',
    );

    calSub.close();
    actSub.close();

    // 7. Complete the Todo
    await container.read(toggleTodoProvider)(
      id: mainTodoId,
      isCompleted: true,
    );
    final completedTodo = await (db.select(db.todos)..where((t) => t.id.equals(mainTodoId))).getSingle();
    expect(completedTodo.status, 'COMPLETED');

    await tester.pump(const Duration(milliseconds: 100));
  });
}
