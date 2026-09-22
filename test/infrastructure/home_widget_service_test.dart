import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/infrastructure/platform/home_widget_service.dart';

import '../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late int calId;

  setUp(() async {
    db = createTestDatabase();
    calId = await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(name: 'Test'));
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertTodo({
    required String summary,
    DateTime? dueDate,
    int? parentId,
    String status = 'NEEDS-ACTION',
    DateTime? deletedAt,
  }) {
    return db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calId,
            summary: summary,
            status: Value(status),
            dueDate: dueDate != null ? Value(dueDate) : const Value.absent(),
            parentId: parentId != null ? Value(parentId) : const Value.absent(),
            deletedAt:
                deletedAt != null ? Value(deletedAt) : const Value.absent(),
          ),
        );
  }

  group('HomeWidgetService.pendingTodos', () {
    test('orders todos with NULL due dates last', () async {
      await insertTodo(summary: 'No due', dueDate: null);
      await insertTodo(summary: 'Due later', dueDate: DateTime(2026, 10, 1));
      await insertTodo(
        summary: 'Due sooner',
        dueDate: DateTime(2026, 9, 20),
      );

      final todos = await HomeWidgetService.pendingTodos(db, limit: 10);

      expect(
        todos.map((t) => t.summary).toList(),
        ['Due sooner', 'Due later', 'No due'],
      );
    });

    test('excludes subtasks so they never occupy widget slots', () async {
      final parentId = await insertTodo(summary: 'Parent', dueDate: null);
      await insertTodo(
        summary: 'Subtask',
        dueDate: DateTime(2026, 9, 19),
        parentId: parentId,
      );
      await insertTodo(summary: 'Top level', dueDate: DateTime(2026, 9, 21));

      final todos = await HomeWidgetService.pendingTodos(db, limit: 10);

      expect(todos.map((t) => t.summary).toList(), [
        'Top level',
        'Parent',
      ]);
      expect(todos.any((t) => t.summary == 'Subtask'), isFalse);
    });

    test('returns at most limit top-level pending todos', () async {
      for (var i = 0; i < 5; i++) {
        await insertTodo(summary: 'Todo $i', dueDate: DateTime(2026, 9, 20));
      }
      await insertTodo(
        summary: 'Done',
        dueDate: DateTime(2026, 9, 20),
        status: 'COMPLETED',
      );
      await insertTodo(
        summary: 'Deleted',
        dueDate: DateTime(2026, 9, 20),
        deletedAt: DateTime(2026, 9, 21),
      );

      final todos = await HomeWidgetService.pendingTodos(db);

      expect(todos.length, 3);
    });
  });

  group('HomeWidgetService snapshot', () {
    test('versioned JSON schema matches the SP-style contract', () async {
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'Standup',
              startDt: todayStart.add(const Duration(hours: 10)),
              endDt: todayStart.add(const Duration(hours: 11)),
            ),
          );
      await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'Conference',
              startDt: todayStart,
              endDt: todayStart.add(const Duration(days: 1)),
              isAllDay: const Value(true),
            ),
          );
      await insertTodo(summary: 'With due', dueDate: DateTime(2026, 9, 25));
      await insertTodo(summary: 'Without due', dueDate: null);

      final events = await HomeWidgetService.todayEvents(db);
      final todos = await HomeWidgetService.pendingTodos(db);
      final todoCount = await HomeWidgetService.pendingTodoCount(db);

      final snapshot = HomeWidgetService.buildSnapshot(
        events: events,
        todos: todos,
        todoCount: todoCount,
        generatedAt: DateTime.utc(2026, 9, 22, 4, 5, 6),
      );
      final decoded =
          jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;

      expect(decoded.keys.toSet(), {
        'version',
        'generatedAt',
        'todayEvents',
        'pendingTodos',
        'todoCount',
      });
      expect(decoded['version'], 1);
      expect(decoded['version'], isA<int>());
      expect(decoded['generatedAt'], isA<String>());
      expect(DateTime.tryParse(decoded['generatedAt'] as String), isNotNull);

      final todayEvents = decoded['todayEvents'] as List;
      expect(todayEvents, hasLength(2));
      for (final item in todayEvents.cast<Map<String, dynamic>>()) {
        expect(item.keys.toSet(), {'summary', 'start', 'isAllDay'});
        expect(item['summary'], isA<String>());
        expect(item['start'], matches(RegExp(r'^\d{2}:\d{2}$')));
        expect(item['isAllDay'], isA<bool>());
      }
      // startDt ASC: all-day event starts at 00:00, standup at 10:00.
      expect((todayEvents.first as Map)['summary'], 'Conference');

      final pendingTodos = decoded['pendingTodos'] as List;
      expect(pendingTodos, hasLength(2));
      for (final item in pendingTodos.cast<Map<String, dynamic>>()) {
        expect(item.keys.toSet(), {'summary', 'dueDate'});
        expect(item['summary'], isA<String>());
        expect(item['dueDate'], isA<String>());
      }

      expect(decoded['todoCount'], 2);
      expect(decoded['todoCount'], isA<int>());
    });

    test('legacy encoders keep payloads native readers parse', () async {
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'Standup',
              startDt: todayStart.add(const Duration(hours: 9, minutes: 30)),
              endDt: todayStart.add(const Duration(hours: 10)),
            ),
          );
      await insertTodo(summary: 'Legacy todo', dueDate: DateTime(2026, 9, 30));

      final events = await HomeWidgetService.todayEvents(db);
      final todos = await HomeWidgetService.pendingTodos(db);

      final eventsJson =
          jsonDecode(HomeWidgetService.encodeTodayEvents(events))
              as List<dynamic>;
      expect(eventsJson, hasLength(1));
      final legacyEvent = (eventsJson.first as Map).cast<String, dynamic>();
      expect(legacyEvent.keys.toSet(), {'summary', 'start', 'isAllDay'});
      expect(legacyEvent['summary'], 'Standup');
      expect(legacyEvent['start'], '09:30');
      // iOS casts today_events as [[String: String]] — every value must be
      // a String or the whole array cast fails and the widget renders empty.
      expect(legacyEvent['isAllDay'], isA<String>());
      expect(legacyEvent['isAllDay'], 'false');
      for (final item in eventsJson.cast<Map<String, dynamic>>()) {
        expect(item.values.every((v) => v is String), isTrue);
      }

      final todosJson =
          jsonDecode(HomeWidgetService.encodePendingTodos(todos))
              as List<dynamic>;
      expect(todosJson, hasLength(1));
      final legacyTodo = (todosJson.first as Map).cast<String, dynamic>();
      expect(legacyTodo.keys.toSet(), {'summary', 'dueDate'});
      expect(legacyTodo['summary'], 'Legacy todo');
      expect(legacyTodo['dueDate'], '9/30');
      for (final item in todosJson.cast<Map<String, dynamic>>()) {
        expect(item.values.every((v) => v is String), isTrue);
      }
    });
  });
}
