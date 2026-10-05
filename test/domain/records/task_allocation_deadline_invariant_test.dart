import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/records/writers/todo_writer.dart';
import 'package:dayspark/domain/records/record_scope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.calendars).insert(
          CalendarsCompanion.insert(
            name: 'Default Calendar',
            color: const Value('#2196F3'),
          ),
        );
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<Todo> getTodo(int id) async {
    return (db.select(db.todos)..where((t) => t.id.equals(id))).getSingle();
  }

  group('TaskAllocation lifecycle operations must not mutate Todo.dueDate', () {
    test('lifecycle operations with non-null dueDate preserve exact deadline', () async {
      final originalDeadline = DateTime(2026, 10, 15, 18, 0);

      // 1. Create ordinary Todo with explicit deadline
      final todoId = await RecordScope.run(
        db,
        (tx) => TodoWriter.create(
          db,
          tx,
          TodosCompanion.insert(
            calendarId: 1,
            summary: 'Review Q3 report',
            dueDate: Value(originalDeadline),
            status: const Value('PENDING'),
          ),
        ),
      );

      var todo = await getTodo(todoId);
      expect(todo.dueDate, equals(originalDeadline));

      // 2. Create TaskAllocation for this Todo
      final startAt = DateTime.utc(2026, 10, 6, 9, 0);
      final endAt = DateTime.utc(2026, 10, 6, 10, 0);
      final allocationId = await container.read(createTaskAllocationProvider)(
        todoId: todoId,
        startAt: startAt,
        endAt: endAt,
      );

      todo = await getTodo(todoId);
      expect(
        todo.dueDate,
        equals(originalDeadline),
        reason: 'TaskAllocation creation must not mutate Todo.dueDate',
      );

      // 3. Reschedule TaskAllocation
      final newStartAt = DateTime.utc(2026, 10, 6, 14, 0);
      final newEndAt = DateTime.utc(2026, 10, 6, 15, 30);
      await container.read(rescheduleTaskAllocationProvider)(
        id: allocationId,
        startAt: newStartAt,
        endAt: newEndAt,
      );

      todo = await getTodo(todoId);
      expect(
        todo.dueDate,
        equals(originalDeadline),
        reason: 'TaskAllocation rescheduling must not mutate Todo.dueDate',
      );

      // 4. Cancel TaskAllocation
      await container.read(cancelTaskAllocationProvider)(allocationId);

      todo = await getTodo(todoId);
      expect(
        todo.dueDate,
        equals(originalDeadline),
        reason: 'TaskAllocation cancellation must not mutate Todo.dueDate',
      );

      // 5. Create a second allocation and complete Todo
      final allocationId2 = await container.read(createTaskAllocationProvider)(
        todoId: todoId,
        startAt: DateTime.utc(2026, 10, 7, 10, 0),
        endAt: DateTime.utc(2026, 10, 7, 11, 0),
      );

      await container.read(toggleTodoProvider)(id: todoId, isCompleted: true);

      todo = await getTodo(todoId);
      expect(
        todo.dueDate,
        equals(originalDeadline),
        reason: 'Todo completion must not mutate Todo.dueDate',
      );

      final allocation2 = await (db.select(db.taskAllocations)
            ..where((a) => a.id.equals(allocationId2)))
          .getSingle();
      expect(allocation2.state, equals('invalidatedByCompletion'));
    });

    test('lifecycle operations with null dueDate preserve null deadline', () async {
      // 1. Create ordinary Todo without deadline (dueDate = null)
      final todoId = await RecordScope.run(
        db,
        (tx) => TodoWriter.create(
          db,
          tx,
          TodosCompanion.insert(
            calendarId: 1,
            summary: 'Inbox task without deadline',
            status: const Value('PENDING'),
          ),
        ),
      );

      var todo = await getTodo(todoId);
      expect(todo.dueDate, isNull);

      // 2. Create TaskAllocation
      final startAt = DateTime.utc(2026, 10, 6, 11, 0);
      final endAt = DateTime.utc(2026, 10, 6, 12, 0);
      final allocationId = await container.read(createTaskAllocationProvider)(
        todoId: todoId,
        startAt: startAt,
        endAt: endAt,
      );

      todo = await getTodo(todoId);
      expect(
        todo.dueDate,
        isNull,
        reason: 'Scheduling an undated Todo must not invent a dueDate',
      );

      // 3. Reschedule TaskAllocation
      await container.read(rescheduleTaskAllocationProvider)(
        id: allocationId,
        startAt: DateTime.utc(2026, 10, 6, 16, 0),
        endAt: DateTime.utc(2026, 10, 6, 17, 0),
      );

      todo = await getTodo(todoId);
      expect(todo.dueDate, isNull);

      // 4. Complete Todo
      await container.read(toggleTodoProvider)(id: todoId, isCompleted: true);

      todo = await getTodo(todoId);
      expect(todo.dueDate, isNull);
    });
  });
}
