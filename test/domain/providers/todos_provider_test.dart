import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calendar_todo_app/data/local/database/app_database.dart';
import 'package:calendar_todo_app/domain/providers/database_provider.dart';
import 'package:calendar_todo_app/domain/providers/todos_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  late ProviderContainer container;
  late AppDatabase testDb;

  setUp(() {
    testDb = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(testDb)],
    );
  });

  tearDown(() async {
    container.dispose();
    await testDb.close();
  });

  group('todosProvider', () {
    test('pendingTodosProvider returns only non-completed todos', () async {
      final calId = await testDb.into(testDb.calendars).insert(
            CalendarsCompanion.insert(
              caldavHref: '/cal/',
              name: 'Test',
            ),
          );

      await testDb.into(testDb.todos).insert(
            TodosCompanion.insert(
              calendarId: calId,
              uid: 't1',
              summary: 'Pending task',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
            ),
          );
      await testDb.into(testDb.todos).insert(
            TodosCompanion.insert(
              calendarId: calId,
              uid: 't2',
              summary: 'Done task',
              priority: const Value(5),
              status: const Value('COMPLETED'),
            ),
          );

      final todos = await container.read(pendingTodosProvider.future);
      expect(todos!.length, 1);
      expect(todos.first.summary, 'Pending task');
    });

    test('createTodoProvider inserts a new todo', () async {
      final calId = await testDb.into(testDb.calendars).insert(
            CalendarsCompanion.insert(
              caldavHref: '/cal/',
              name: 'Test',
            ),
          );

      final id = await container.read(createTodoProvider).call(
            calendarId: calId,
            uid: 'new-uid',
            summary: 'New Todo',
            priority: 3,
            status: 'NEEDS-ACTION',
          );

      expect(id, greaterThan(0));

      final todo = await (testDb.select(testDb.todos)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      expect(todo.summary, 'New Todo');
    });

    test('todosByDueDateProvider returns todos for a specific date',
        () async {
      final calId = await testDb.into(testDb.calendars).insert(
            CalendarsCompanion.insert(
              caldavHref: '/cal/',
              name: 'Test',
            ),
          );

      final dueDate = DateTime(2026, 4, 20);
      await testDb.into(testDb.todos).insert(
            TodosCompanion.insert(
              calendarId: calId,
              uid: 't4',
              summary: 'Due today',
              priority: const Value(5),
              status: const Value('NEEDS-ACTION'),
              dueDate: Value(dueDate),
            ),
          );
      await testDb.into(testDb.todos).insert(
            TodosCompanion.insert(
              calendarId: calId,
              uid: 't5',
              summary: 'Other day',
              priority: const Value(5),
              status: const Value('NEEDS-ACTION'),
              dueDate: Value(DateTime(2026, 5, 1)),
            ),
          );

      final todos = await container
          .read(todosByDueDateProvider(DateTime(2026, 4, 20)).future);
      expect(todos!.length, 1);
      expect(todos.first.summary, 'Due today');
    });

    test('completeTodoProvider marks a todo as completed', () async {
      final calId = await testDb.into(testDb.calendars).insert(
            CalendarsCompanion.insert(
              caldavHref: '/cal/',
              name: 'Test',
            ),
          );

      final todoId = await testDb.into(testDb.todos).insert(
            TodosCompanion.insert(
              calendarId: calId,
              uid: 't3',
              summary: 'To complete',
              priority: const Value(5),
              status: const Value('NEEDS-ACTION'),
            ),
          );

      await container.read(completeTodoProvider).call(todoId);

      final todo = await (testDb.select(testDb.todos)
            ..where((t) => t.id.equals(todoId)))
          .getSingle();
      expect(todo.status, 'COMPLETED');
    });

    test('deleteTodoProvider removes a todo', () async {
      final calId = await testDb.into(testDb.calendars).insert(
            CalendarsCompanion.insert(
              caldavHref: '/cal/',
              name: 'Test',
            ),
          );

      final todoId = await testDb.into(testDb.todos).insert(
            TodosCompanion.insert(
              calendarId: calId,
              uid: 't-del',
              summary: 'To delete',
              priority: const Value(5),
              status: const Value('NEEDS-ACTION'),
            ),
          );

      await container.read(deleteTodoProvider).call(todoId);

      final remaining =
          await (testDb.select(testDb.todos)).get();
      expect(remaining.where((t) => t.id == todoId).isEmpty, true);
    });
  });
}
