import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';

void main() {
  late AppDatabase db;
  late int calId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    calId = await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(caldavHref: '/cal/', name: 'Test'));
  });

  tearDown(() async {
    await db.close();
  });

  group('TodosDao', () {
    test('watchPending returns only non-completed todos', () async {
      await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              uid: 't1',
              summary: 'Pending task',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
            ),
          );
      await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              uid: 't2',
              summary: 'Done task',
              priority: const Value(5),
              status: const Value('COMPLETED'),
            ),
          );

      final todos = await db.todosDao.watchPending().first;
      expect(todos.length, 1);
      expect(todos.first.summary, 'Pending task');
    });

    test('markComplete sets status and completedAt', () async {
      final todoId = await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              uid: 't3',
              summary: 'To complete',
              priority: const Value(5),
              status: const Value('NEEDS-ACTION'),
            ),
          );
      await db.todosDao.markComplete(todoId);
      final todo = await (db.select(
        db.todos,
      )..where((t) => t.id.equals(todoId))).getSingle();
      expect(todo.status, 'COMPLETED');
      expect(todo.completedAt, isNotNull);
    });

    test('watchByDueDate returns todos due on specific date', () async {
      final dueDate = DateTime(2026, 4, 20);
      await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              uid: 't4',
              summary: 'Due today',
              priority: const Value(5),
              status: const Value('NEEDS-ACTION'),
              dueDate: Value(dueDate),
            ),
          );

      final todos = await db.todosDao
          .watchByDueDate(DateTime(2026, 4, 20))
          .first;
      expect(todos.length, 1);
      expect(todos.first.summary, 'Due today');
    });
  });
}
