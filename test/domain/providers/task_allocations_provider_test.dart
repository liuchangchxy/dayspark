import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late int calendarId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    calendarId = await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(name: 'Test'));
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test(
    'creates multiple allocations without changing Todo dueDate and cancellation retains history',
    () async {
      final dueDate = DateTime(2026, 10, 9, 17);
      final todoId = await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Write report',
              dueDate: Value(dueDate),
              description: const Value('Keep this description'),
              priority: const Value(4),
            ),
          );
      final eventId = await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calendarId,
              summary: 'Unchanged event',
              startDt: DateTime(2026, 10, 8, 10),
              endDt: DateTime(2026, 10, 8, 11),
            ),
          );
      final eventBefore = await (db.select(
        db.events,
      )..where((row) => row.id.equals(eventId))).getSingle();
      final create = container.read(createTaskAllocationProvider);
      final firstId = await create(
        todoId: todoId,
        startAt: DateTime(2026, 10, 7, 10),
        endAt: DateTime(2026, 10, 7, 11),
      );
      final secondId = await create(
        todoId: todoId,
        startAt: DateTime(2026, 10, 8, 14),
        endAt: DateTime(2026, 10, 8, 15),
      );

      await container.read(rescheduleTaskAllocationProvider)(
        id: secondId,
        startAt: DateTime(2026, 10, 8, 15),
        endAt: DateTime(2026, 10, 8, 16),
      );
      await container.read(cancelTaskAllocationProvider)(firstId);

      final allocations =
          await (db.select(db.taskAllocations)
                ..where((row) => row.todoId.equals(todoId))
                ..orderBy([(row) => OrderingTerm.asc(row.id)]))
              .get();
      final todo = await (db.select(
        db.todos,
      )..where((row) => row.id.equals(todoId))).getSingle();

      expect(allocations, hasLength(2));
      expect(allocations.last.id, secondId);
      expect(allocations.first.state, 'cancelledByUser');
      expect(
        allocations.first.startAt.millisecondsSinceEpoch,
        DateTime(2026, 10, 7, 10).toUtc().millisecondsSinceEpoch,
      );
      expect(
        allocations.last.startAt.millisecondsSinceEpoch,
        DateTime(2026, 10, 8, 15).toUtc().millisecondsSinceEpoch,
      );
      expect(
        todo.dueDate!.millisecondsSinceEpoch,
        dueDate.millisecondsSinceEpoch,
      );
      expect(todo.summary, 'Write report');
      expect(todo.description, 'Keep this description');
      expect(todo.priority, 4);
      expect(todo.status, 'NEEDS-ACTION');
      final eventAfter = await (db.select(
        db.events,
      )..where((row) => row.id.equals(eventId))).getSingle();
      expect(eventAfter, eventBefore);
    },
  );

  test(
    'rejects recurring Todo allocation rather than guessing an occurrence',
    () async {
      final todoId = await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Weekly review',
              rrule: const Value('FREQ=WEEKLY;BYDAY=MO'),
            ),
          );

      await expectLater(
        container.read(createTaskAllocationProvider)(
          todoId: todoId,
          startAt: DateTime(2026, 10, 5, 9),
          endAt: DateTime(2026, 10, 5, 10),
        ),
        throwsA(isA<StateError>()),
      );
      expect(await db.select(db.taskAllocations).get(), isEmpty);
    },
  );

  test(
    'Todo soft delete retains allocations; permanent delete and emptyTrash remove them',
    () async {
      Future<int> createTodo(String summary) => db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(calendarId: calendarId, summary: summary),
          );
      Future<int> allocate(int todoId) =>
          container.read(createTaskAllocationProvider)(
            todoId: todoId,
            startAt: DateTime.utc(2026, 10, 7, 9),
            endAt: DateTime.utc(2026, 10, 7, 10),
          );
      final permanentTodoId = await createTodo('Permanent');
      final permanentAllocationId = await allocate(permanentTodoId);
      await container.read(permanentDeleteTodoProvider)(permanentTodoId);
      expect(
        await (db.select(
          db.taskAllocations,
        )..where((row) => row.id.equals(permanentAllocationId))).get(),
        isEmpty,
      );

      final trashedTodoId = await createTodo('Trash');
      final trashedAllocationId = await allocate(trashedTodoId);
      await container.read(deleteTodoProvider)(trashedTodoId);
      expect(
        await (db.select(
          db.taskAllocations,
        )..where((row) => row.id.equals(trashedAllocationId))).get(),
        hasLength(1),
      );
      await container.read(emptyTrashProvider)();
      expect(
        await (db.select(
          db.taskAllocations,
        )..where((row) => row.id.equals(trashedAllocationId))).get(),
        isEmpty,
      );
    },
  );

  test('restoring a Todo projects only allocations that remain active', () async {
    final todoId = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(calendarId: calendarId, summary: 'Restore'),
        );
    final create = container.read(createTaskAllocationProvider);
    final activeId = await create(
      todoId: todoId,
      startAt: DateTime.utc(2026, 10, 7, 8),
      endAt: DateTime.utc(2026, 10, 7, 9),
    );
    final cancelledId = await create(
      todoId: todoId,
      startAt: DateTime.utc(2026, 10, 7, 10),
      endAt: DateTime.utc(2026, 10, 7, 11),
    );
    final invalidatedId = await create(
      todoId: todoId,
      startAt: DateTime.utc(2026, 10, 7, 12),
      endAt: DateTime.utc(2026, 10, 7, 13),
    );
    await container.read(cancelTaskAllocationProvider)(cancelledId);
    await container.read(updateTodoProvider)(
      todoId,
      TodosCompanion(
        status: const Value('COMPLETED'),
        completedAt: Value(DateTime.utc(2026, 10, 7, 11)),
      ),
    );
    await container.read(updateTodoProvider)(
      todoId,
      const TodosCompanion(
        status: Value('NEEDS-ACTION'),
        completedAt: Value(null),
      ),
    );

    final rangeStart = DateTime.utc(2026, 10, 7).millisecondsSinceEpoch;
    final rangeEnd = DateTime.utc(2026, 10, 8).millisecondsSinceEpoch;
    final rangeKey = '$rangeStart-$rangeEnd';
    Future<Set<int>> projectedIds() async {
      container.invalidate(taskAllocationsInDateRangeProvider(rangeKey));
      final items = await container.read(
        taskAllocationsInDateRangeProvider(rangeKey).future,
      );
      return items.map((item) => item.allocation.id).toSet();
    }

    await container.read(deleteTodoProvider)(todoId);
    expect(await projectedIds(), isEmpty);
    final retained = await (db.select(
      db.taskAllocations,
    )..where((row) => row.todoId.equals(todoId))).get();
    expect(retained, hasLength(3));

    await container.read(restoreTodoProvider)(todoId);
    expect(await projectedIds(), {activeId});
    final restored = await (db.select(
      db.taskAllocations,
    )..where((row) => row.todoId.equals(todoId))).get();
    final byId = {for (final row in restored) row.id: row};
    expect(byId[activeId]!.state, 'active');
    expect(byId[cancelledId]!.state, 'cancelledByUser');
    expect(byId[invalidatedId]!.state, 'invalidatedByCompletion');
  });

  test(
    'stores allocation bounds as UTC instants at millisecond precision',
    () async {
      final todoId = await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(calendarId: calendarId, summary: 'Precise'),
          );
      final inputStart = DateTime(2026, 10, 7, 10, 0, 0, 123, 987);
      final inputEnd = DateTime(2026, 10, 7, 11, 0, 0, 456, 789);

      final id = await container.read(createTaskAllocationProvider)(
        todoId: todoId,
        startAt: inputStart,
        endAt: inputEnd,
      );
      final saved = await (db.select(
        db.taskAllocations,
      )..where((row) => row.id.equals(id))).getSingle();

      expect(saved.startAt.isUtc, isTrue);
      expect(saved.endAt.isUtc, isTrue);
      expect(
        saved.startAt.millisecondsSinceEpoch,
        inputStart.toUtc().millisecondsSinceEpoch,
      );
      expect(
        saved.endAt.millisecondsSinceEpoch,
        inputEnd.toUtc().millisecondsSinceEpoch,
      );
      expect(saved.startAt.microsecond, 0);
      expect(saved.endAt.microsecond, 0);
    },
  );

  test(
    'create and reschedule reject ranges equal after millisecond truncation',
    () async {
      final todoId = await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(calendarId: calendarId, summary: 'Range'),
          );
      final create = container.read(createTaskAllocationProvider);
      final start = DateTime.utc(2026, 10, 7, 10, 0, 0, 10, 100);
      final collapsedEnd = DateTime.utc(2026, 10, 7, 10, 0, 0, 10, 900);
      await expectLater(
        create(todoId: todoId, startAt: start, endAt: collapsedEnd),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        create(todoId: todoId, startAt: start, endAt: start),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        create(todoId: todoId, startAt: collapsedEnd, endAt: start),
        throwsA(isA<ArgumentError>()),
      );

      final id = await create(
        todoId: todoId,
        startAt: start,
        endAt: DateTime.utc(2026, 10, 7, 10, 0, 0, 11, 100),
      );
      final before = await (db.select(
        db.taskAllocations,
      )..where((row) => row.id.equals(id))).getSingle();
      await expectLater(
        container.read(rescheduleTaskAllocationProvider)(
          id: id,
          startAt: start,
          endAt: collapsedEnd,
        ),
        throwsA(isA<ArgumentError>()),
      );
      final unchanged = await (db.select(
        db.taskAllocations,
      )..where((row) => row.id.equals(id))).getSingle();
      expect(unchanged, before);
    },
  );

  test(
    'canonicalizes equivalent UTC and local instants for create and reschedule',
    () async {
      final todoId = await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(calendarId: calendarId, summary: 'UTC'),
          );
      final localStart = DateTime(2026, 10, 7, 10, 0, 0, 123, 456);
      final localEnd = DateTime(2026, 10, 7, 11, 0, 0, 123, 456);
      final id = await container.read(createTaskAllocationProvider)(
        todoId: todoId,
        startAt: localStart,
        endAt: localEnd,
      );
      final canonicalStart = DateTime.fromMillisecondsSinceEpoch(
        localStart.toUtc().millisecondsSinceEpoch,
        isUtc: true,
      );
      final canonicalEnd = DateTime.fromMillisecondsSinceEpoch(
        localEnd.toUtc().millisecondsSinceEpoch,
        isUtc: true,
      );
      await container.read(rescheduleTaskAllocationProvider)(
        id: id,
        startAt: canonicalStart,
        endAt: canonicalEnd,
      );
      final stored = await (db.select(
        db.taskAllocations,
      )..where((row) => row.id.equals(id))).getSingle();
      expect(stored.startAt, canonicalStart);
      expect(stored.endAt, canonicalEnd);
    },
  );

  test(
    'completion preserves history and ongoing allocation, invalidates future active only',
    () async {
      final dueDate = DateTime.utc(2026, 10, 9, 17);
      final todoId = await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Completion boundaries',
              dueDate: Value(dueDate),
            ),
          );
      final create = container.read(createTaskAllocationProvider);
      final ended = await create(
        todoId: todoId,
        startAt: DateTime.utc(2026, 10, 7, 8),
        endAt: DateTime.utc(2026, 10, 7, 9),
      );
      final ongoing = await create(
        todoId: todoId,
        startAt: DateTime.utc(2026, 10, 7, 9),
        endAt: DateTime.utc(2026, 10, 7, 11),
      );
      final equalBoundary = await create(
        todoId: todoId,
        startAt: DateTime.utc(2026, 10, 7, 10),
        endAt: DateTime.utc(2026, 10, 7, 11),
      );
      final future = await create(
        todoId: todoId,
        startAt: DateTime.utc(2026, 10, 7, 12),
        endAt: DateTime.utc(2026, 10, 7, 13),
      );
      final cancelled = await create(
        todoId: todoId,
        startAt: DateTime.utc(2026, 10, 7, 14),
        endAt: DateTime.utc(2026, 10, 7, 15),
      );
      await container.read(cancelTaskAllocationProvider)(cancelled);

      final completedAt = DateTime.utc(2026, 10, 7, 10);
      await container.read(updateTodoProvider)(
        todoId,
        TodosCompanion(
          status: const Value('COMPLETED'),
          completedAt: Value(completedAt),
        ),
      );
      final rows = await (db.select(
        db.taskAllocations,
      )..where((row) => row.todoId.equals(todoId))).get();
      final byId = {for (final row in rows) row.id: row};
      expect(byId[ended]!.state, 'active');
      expect(byId[ongoing]!.state, 'active');
      expect(byId[equalBoundary]!.state, 'invalidatedByCompletion');
      expect(byId[future]!.state, 'invalidatedByCompletion');
      expect(byId[cancelled]!.state, 'cancelledByUser');
      await container.read(cancelTaskAllocationProvider)(cancelled);
      await expectLater(
        container.read(rescheduleTaskAllocationProvider)(
          id: equalBoundary,
          startAt: DateTime.utc(2026, 10, 8, 12),
          endAt: DateTime.utc(2026, 10, 8, 13),
        ),
        throwsA(isA<StateError>()),
      );
      final todo = await (db.select(
        db.todos,
      )..where((row) => row.id.equals(todoId))).getSingle();
      expect(
        todo.dueDate!.millisecondsSinceEpoch,
        dueDate.millisecondsSinceEpoch,
      );

      final rangeStart = DateTime.utc(2026, 10, 7).millisecondsSinceEpoch;
      final rangeEnd = DateTime.utc(2026, 10, 8).millisecondsSinceEpoch;
      final projected = await container.read(
        taskAllocationsInDateRangeProvider('$rangeStart-$rangeEnd').future,
      );
      expect(projected.map((item) => item.allocation.id).toSet(), {
        ended,
        ongoing,
      });

      await container.read(updateTodoProvider)(
        todoId,
        const TodosCompanion(
          status: Value('NEEDS-ACTION'),
          completedAt: Value(null),
        ),
      );
      final afterUncomplete = await container.read(
        taskAllocationsInDateRangeProvider('$rangeStart-$rangeEnd').future,
      );
      expect(afterUncomplete.map((item) => item.allocation.id).toSet(), {
        ended,
        ongoing,
      });
    },
  );

  test(
    'calendar projection includes active allocations and hides cancelled ones',
    () async {
      final todoId = await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Prepare slides',
            ),
          );
      final create = container.read(createTaskAllocationProvider);
      final activeId = await create(
        todoId: todoId,
        startAt: DateTime(2026, 10, 7, 10),
        endAt: DateTime(2026, 10, 7, 11),
      );
      final cancelledId = await create(
        todoId: todoId,
        startAt: DateTime(2026, 10, 7, 12),
        endAt: DateTime(2026, 10, 7, 13),
      );
      await container.read(cancelTaskAllocationProvider)(cancelledId);

      final start = DateTime(2026, 10, 7).millisecondsSinceEpoch;
      final end = DateTime(2026, 10, 8).millisecondsSinceEpoch;
      final items = await container.read(
        taskAllocationsInDateRangeProvider('$start-$end').future,
      );

      expect(items, hasLength(1));
      expect(items.single.allocation.id, activeId);
      expect(items.single.todo.summary, 'Prepare slides');
    },
  );
}
