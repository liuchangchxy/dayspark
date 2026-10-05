import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/action_projection_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ProviderContainer container;
  late int calendarId;
  final fixedToday = DateTime(2026, 10, 6);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    calendarId = await db.into(db.calendars).insert(
          CalendarsCompanion.insert(
            name: 'Default Calendar',
            color: const Value('#2196F3'),
          ),
        );

    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        actionDateProvider.overrideWith((ref) => fixedToday),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<ActionProjectionData> getActionData() async {
    final sub = container.listen(actionProjectionProvider, (_, __) {});
    try {
      for (var i = 0; i < 30; i++) {
        await pumpEventQueue();
        final asyncVal = container.read(actionProjectionProvider);
        if (asyncVal.hasValue) {
          return asyncVal.value!;
        }
      }
      throw StateError('actionProjectionProvider did not resolve to data');
    } finally {
      sub.close();
    }
  }

  test('projects today events and excludes other days', () async {
    // Event today: 10:00 - 11:00
    await db.into(db.events).insert(
          EventsCompanion.insert(
            calendarId: calendarId,
            summary: 'Morning Standup',
            startDt: DateTime(2026, 10, 6, 10, 0),
            endDt: DateTime(2026, 10, 6, 11, 0),
            isAllDay: const Value(false),
          ),
        );
    // Event yesterday: 14:00 - 15:00
    await db.into(db.events).insert(
          EventsCompanion.insert(
            calendarId: calendarId,
            summary: 'Yesterday Meeting',
            startDt: DateTime(2026, 10, 5, 14, 0),
            endDt: DateTime(2026, 10, 5, 15, 0),
            isAllDay: const Value(false),
          ),
        );

    final data = await getActionData();
    expect(data.events.length, 1);
    expect(data.events.first.title, 'Morning Standup');
  });

  test('projects ordinary task allocation and excludes recurring allocation', () async {
    // 1. Ordinary todo with today allocation
    final ordinaryTodoId = await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Deep Work Session',
          ),
        );
    await container.read(createTaskAllocationProvider)(
      todoId: ordinaryTodoId,
      startAt: DateTime(2026, 10, 6, 14, 0),
      endAt: DateTime(2026, 10, 6, 16, 0),
    );

    // 2. Recurring todo with allocation (Phase 1 excludes recurring instances from Action)
    final recurringTodoId = await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Daily Review',
            rrule: const Value('RRULE:FREQ=DAILY'),
          ),
        );
    await db.into(db.taskAllocations).insert(
          TaskAllocationsCompanion.insert(
            todoId: Value(recurringTodoId),
            occurrenceId: const Value('2026-10-06T09:00:00Z'),
            startAt: DateTime(2026, 10, 6, 9, 0),
            endAt: DateTime(2026, 10, 6, 9, 30),
            state: const Value('active'),
          ),
        );

    final data = await getActionData();
    expect(data.allocations.length, 1);
    expect(data.allocations.first.todo.summary, 'Deep Work Session');
    expect(data.allocations.first.allocation.occurrenceId, isNull);
  });

  test('projects due today and overdue separately with original deadline preserved', () async {
    final originalOverdueDeadline = DateTime(2026, 10, 3, 18, 0);
    final todayDeadline = DateTime(2026, 10, 6, 17, 0);

    // Overdue todo
    await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Past Due Report',
            dueDate: Value(originalOverdueDeadline),
          ),
        );

    // Due today todo
    await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Deliver Slides',
            dueDate: Value(todayDeadline),
          ),
        );

    // Future todo (should NOT appear in due today or overdue)
    await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Next Week Planning',
            dueDate: Value(DateTime(2026, 10, 12)),
          ),
        );

    final data = await getActionData();

    expect(data.overdueTodos.length, 1);
    expect(data.overdueTodos.first.summary, 'Past Due Report');
    expect(data.overdueTodos.first.dueDate, originalOverdueDeadline);

    expect(data.dueTodayTodos.length, 1);
    expect(data.dueTodayTodos.first.summary, 'Deliver Slides');
    expect(data.dueTodayTodos.first.dueDate, todayDeadline);
  });

  test('preserves both facts when a Todo has both today allocation and today deadline', () async {
    final deadline = DateTime(2026, 10, 6, 20, 0);
    final todoId = await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Important Deliverable',
            dueDate: Value(deadline),
          ),
        );

    // Add allocation for today
    await container.read(createTaskAllocationProvider)(
      todoId: todoId,
      startAt: DateTime(2026, 10, 6, 10, 0),
      endAt: DateTime(2026, 10, 6, 12, 0),
    );

    final data = await getActionData();

    // Must appear in allocations
    expect(data.allocations.any((a) => a.todo.id == todoId), isTrue);
    // Must also appear in due today without losing either fact
    expect(data.dueTodayTodos.any((t) => t.id == todoId), isTrue);
    expect(data.dueTodayTodos.firstWhere((t) => t.id == todoId).dueDate, deadline);
  });

  test('unplannedCount counts only undated pending ordinary todos', () async {
    // 2 undated ordinary todos
    await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Idea 1',
          ),
        );
    await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Idea 2',
          ),
        );

    // 1 dated todo
    await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Dated',
            dueDate: Value(DateTime(2026, 10, 6)),
          ),
        );

    // 1 completed undated todo
    await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Completed idea',
            status: const Value('COMPLETED'),
          ),
        );

    final data = await getActionData();
    expect(data.unplannedCount, 2);
  });

  test('toggling todo completion moves it reactively to completedToday', () async {
    final todoId = await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Task To Complete',
            dueDate: Value(DateTime(2026, 10, 6, 15, 0)),
          ),
        );

    var data = await getActionData();
    expect(data.dueTodayTodos.length, 1);
    expect(data.completedTodayTodos.isEmpty, isTrue);

    // Complete the todo via existing toggle provider
    await container.read(toggleTodoProvider)(id: todoId, isCompleted: true);

    data = await getActionData();
    expect(data.dueTodayTodos.isEmpty, isTrue);
    expect(data.completedTodayTodos.length, 1);
    expect(data.completedTodayTodos.first.id, todoId);
    expect(data.completedTodayTodos.first.status, 'COMPLETED');
  });
}
