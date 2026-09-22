import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/infrastructure/platform/notification_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';

class _MockNotificationService extends Mock implements NotificationService {}

void main() {
  late ProviderContainer container;
  late AppDatabase testDb;

  setUp(() {
    testDb = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(testDb),
        notificationServiceProvider.overrideWithValue(
          _MockNotificationService(),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await testDb.close();
  });

  group('todosProvider', () {
    test('allTodosProvider returns non-deleted todos', () async {
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));

      await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Pending task',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
            ),
          );
      await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Done task',
              priority: const Value(5),
              status: const Value('COMPLETED'),
            ),
          );

      final todos = await container.read(allTodosProvider.future);
      expect(todos.length, 2);
    });

    test('createTodoProvider inserts a new todo', () async {
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));

      final id = await container
          .read(createTodoProvider)
          .call(
            calendarId: calId,
            summary: 'New Todo',
            priority: 3,
            status: 'NEEDS-ACTION',
          );

      expect(id, greaterThan(0));

      final todo = await (testDb.select(
        testDb.todos,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(todo.summary, 'New Todo');
    });

    test('completeTodoProvider marks a todo as completed', () async {
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));

      final todoId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'To complete',
              priority: const Value(5),
              status: const Value('NEEDS-ACTION'),
            ),
          );

      await container
          .read(toggleTodoProvider)
          .call(id: todoId, isCompleted: true);

      final todo = await (testDb.select(
        testDb.todos,
      )..where((t) => t.id.equals(todoId))).getSingle();
      expect(todo.status, 'COMPLETED');
    });

    test('deleteTodoProvider soft-deletes a todo', () async {
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));

      final todoId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'To delete',
              priority: const Value(5),
              status: const Value('NEEDS-ACTION'),
            ),
          );

      await container.read(deleteTodoProvider).call(todoId);

      final todo = await (testDb.select(
        testDb.todos,
      )..where((t) => t.id.equals(todoId))).getSingle();
      expect(todo.deletedAt != null, true);
    });

    test('deleteTodoProvider cascades soft-delete to children', () async {
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));

      final parentId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Parent',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
            ),
          );
      final childId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Child',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
              parentId: Value(parentId),
            ),
          );
      final otherId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Unrelated',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
            ),
          );

      await container.read(deleteTodoProvider).call(parentId);

      final rows = await testDb.select(testDb.todos).get();
      final parent = rows.firstWhere((t) => t.id == parentId);
      final child = rows.firstWhere((t) => t.id == childId);
      final other = rows.firstWhere((t) => t.id == otherId);
      expect(parent.deletedAt != null, true);
      expect(child.deletedAt != null, true);
      expect(child.deletedAt, parent.deletedAt);
      expect(other.deletedAt == null, true);

      final trashed = await testDb.todosDao.watchDeleted().first;
      expect(trashed.map((t) => t.id), containsAll([parentId, childId]));
    });

    test('restoreTodoProvider clears deletedAt', () async {
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));
      final todoId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Trashed',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
              deletedAt: Value(DateTime.now()),
            ),
          );

      await container.read(restoreTodoProvider).call(todoId);

      final todo = await (testDb.select(
        testDb.todos,
      )..where((t) => t.id.equals(todoId))).getSingle();
      expect(todo.deletedAt == null, true);
    });
  });
}
