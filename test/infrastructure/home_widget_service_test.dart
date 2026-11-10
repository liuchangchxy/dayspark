import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/writers/todo_writer.dart';
import 'package:dayspark/domain/services/action_projection_query.dart';
import 'package:dayspark/infrastructure/platform/home_widget_service.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';

import '../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
    String? syncId,
    String? rrule,
    int priority = 0,
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
            syncId: syncId != null ? Value(syncId) : const Value.absent(),
            rrule: rrule != null ? Value(rrule) : const Value.absent(),
            priority: Value(priority),
            deletedAt: deletedAt != null
                ? Value(deletedAt)
                : const Value.absent(),
          ),
        );
  }

  Future<int> insertEvent({
    required String summary,
    required DateTime startDt,
    required DateTime endDt,
    bool isAllDay = false,
    String? rrule,
    DateTime? deletedAt,
  }) {
    return db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            calendarId: calId,
            summary: summary,
            startDt: startDt,
            endDt: endDt,
            isAllDay: Value(isAllDay),
            rrule: rrule != null ? Value(rrule) : const Value.absent(),
            deletedAt: deletedAt != null
                ? Value(deletedAt)
                : const Value.absent(),
          ),
        );
  }

  Future<int> insertAllocation({
    required int todoId,
    String? todoSyncId,
    String? occurrenceId,
    required DateTime startAt,
    required DateTime endAt,
  }) {
    return db
        .into(db.taskAllocations)
        .insert(
          TaskAllocationsCompanion.insert(
            todoId: Value(todoId),
            todoSyncId: todoSyncId != null
                ? Value(todoSyncId)
                : const Value.absent(),
            occurrenceId: occurrenceId != null
                ? Value(occurrenceId)
                : const Value.absent(),
            startAt: startAt,
            endAt: endAt,
          ),
        );
  }

  group('v5 snapshot contract', () {
    test('top-level keys, version and today string', () async {
      final now = DateTime(2026, 10, 7, 10, 0);
      final projection = await ActionProjectionQuery.fetch(db, date: now);
      final action = HomeWidgetService.buildActionBlock(projection);
      final todos = await HomeWidgetService.buildTodosBlock(
        db,
        now: now,
        sixThingsEnabled: false,
        completedCount: 0,
      );
      final month = await HomeWidgetService.monthCalendar(db, now: now);
      final ui = await HomeWidgetService.loadWidgetUiStrings(
        locale: const Locale('en'),
      );

      final snapshot = HomeWidgetService.buildSnapshot(
        generatedAt: now,
        action: action,
        todos: todos,
        month: month,
        ui: ui,
        theme: HomeWidgetService.buildThemeBlock(dark: false),
      );
      final decoded = jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;

      expect(decoded.keys.toSet(), {
        'version',
        'generatedAt',
        'today',
        'action',
        'todos',
        'month',
        'ui',
        'theme',
      });
      expect(decoded['version'], 5);
      expect(decoded['generatedAt'], isA<String>());
      expect(decoded['today'], '2026-10-07');
      expect(decoded['today'], isA<String>());

      final actionBlock = decoded['action'] as Map<String, dynamic>;
      expect(actionBlock.keys.toSet(), {
        'timeline',
        'dueToday',
        'overdue',
        'counts',
      });
      expect(
        (actionBlock['counts'] as Map).keys.toSet(),
        {'dueToday', 'overdue', 'completedToday'},
      );

      final todosBlock = decoded['todos'] as Map<String, dynamic>;
      expect(todosBlock.keys.toSet(), {'today', 'inbox', 'all'});
      expect(
        (todosBlock['today'] as Map).keys.toSet(),
        {'sixThingsCap', 'items', 'overdue', 'completedCount', 'total'},
      );

      final monthBlock = decoded['month'] as Map<String, dynamic>;
      final days = monthBlock['days'] as List;
      expect(days.length, 31);
      final day = days.first as Map<String, dynamic>;
      expect(
        day.keys.toSet(),
        {
          'day',
          'hasEvent',
          'hasTodo',
          'hasAllocation',
          'colors',
          'itemCount',
          'items',
        },
      );
    });

    test('v4 payload is not a valid v5 input', () async {
      final fixture = File('test/fixtures/widget/widget_snapshot_v3.json');
      final legacy =
          jsonDecode(await fixture.readAsString()) as Map<String, dynamic>;

      expect(legacy.containsKey('action'), isFalse);
      expect(legacy.containsKey('todos'), isFalse);
      expect(legacy['version'], isNot(HomeWidgetService.snapshotVersion));
      expect(HomeWidgetService.snapshotVersion, 5);
    });

    test('only the three product widgets are registered', () {
      expect(HomeWidgetService.appleWidgetKinds, [
        'CalendarTodoWidget',
        'CalendarMonthWidget',
        'CalendarTodosWidget',
      ]);
      expect(
        HomeWidgetService.androidProviderName,
        'com.dayspark.app.TodayWidgetProvider',
      );
      expect(
        HomeWidgetService.androidMonthProviderName,
        'com.dayspark.app.CalendarWidgetProvider',
      );
      expect(
        HomeWidgetService.androidTodoProviderName,
        'com.dayspark.app.TodoWidgetProvider',
      );
      expect(
        HomeWidgetService.appleWidgetKinds.any(
          (kind) => kind.toLowerCase().contains('upcoming'),
        ),
        isFalse,
      );
      expect(
        HomeWidgetService.appleWidgetKinds.any(
          (kind) => kind.toLowerCase().contains('quick'),
        ),
        isFalse,
      );
    });
  });

  group('Action block', () {
    test('timeline, due today, overdue and counts', () async {
      final now = DateTime(2026, 10, 7, 10, 0);
      final eventId = await insertEvent(
        summary: 'Team Sync',
        startDt: DateTime(2026, 10, 7, 10, 0),
        endDt: DateTime(2026, 10, 7, 11, 0),
      );
      final allocatedTodoId = await insertTodo(
        summary: 'Deep Work',
        syncId: 'todo_sync_allocated',
      );
      final allocationId = await insertAllocation(
        todoId: allocatedTodoId,
        todoSyncId: 'todo_sync_allocated',
        startAt: DateTime(2026, 10, 7, 14, 0),
        endAt: DateTime(2026, 10, 7, 15, 0),
      );
      final dueTodoId = await insertTodo(
        summary: 'Quarterly Taxes',
        dueDate: DateTime(2026, 10, 7),
      );
      final overdueTodoId = await insertTodo(
        summary: 'Late Report',
        dueDate: DateTime(2026, 10, 5),
      );

      final projection = await ActionProjectionQuery.fetch(db, date: now);
      final action = HomeWidgetService.buildActionBlock(
        projection,
        calendarColors: {calId: '#2457D6'},
      );
      final decoded = jsonDecode(jsonEncode(action)) as Map<String, dynamic>;

      final timeline = decoded['timeline'] as List;
      expect(timeline.length, 2);
      expect(timeline[0]['kind'], 'eventOccurrence');
      expect(timeline[0]['summary'], 'Team Sync');
      expect(timeline[0]['eventId'], eventId);
      expect(timeline[0]['start'], '10:00');
      expect(timeline[0]['end'], '11:00');
      expect(timeline[0]['startEpochMs'], isA<int>());
      expect(timeline[0]['color'], '#2457D6');

      expect(timeline[1]['kind'], 'taskAllocation');
      expect(timeline[1]['summary'], 'Deep Work');
      expect(timeline[1]['allocationId'], allocationId.toString());
      expect(timeline[1]['todoId'], allocatedTodoId);

      final due = decoded['dueToday'] as List;
      expect(due.any((row) => row['todoId'] == dueTodoId), isTrue);
      expect(
        due.any((row) => row['target'] == 'todo' && row['kind'] == 'todoDeadline'),
        isTrue,
      );

      final overdue = decoded['overdue'] as List;
      expect(overdue.single['todoId'], overdueTodoId);
      expect(overdue.single['displayTime'], '');

      final counts = decoded['counts'] as Map<String, dynamic>;
      expect(counts['dueToday'], 1);
      expect(counts['overdue'], 1);
      expect(counts['completedToday'], 0);
    });

    test('recurring todo contributes task instances with occurrence ids', () async {
      final now = DateTime(2026, 10, 7, 10, 0);
      final spec = RecurrenceSpec.parse(
        anchor: RecurrenceAnchor(
          source: RecurrenceAnchorSource.due,
          value: LocalDate(2026, 10, 7),
        ),
        timeZone: 'Asia/Shanghai',
        rrule: 'FREQ=DAILY',
      );
      await RecordScope.run(
        db,
        (tx) => TodoWriter.create(
          db,
          tx,
          TodosCompanion.insert(
            calendarId: calId,
            summary: 'Daily Standup Notes',
            rrule: Value(spec.rule.canonical),
          ),
          recurrenceSpec: spec,
        ),
      );

      final projection = await ActionProjectionQuery.fetch(db, date: now);
      final action = HomeWidgetService.buildActionBlock(projection);
      final instances = [
        ...(action['dueToday'] as List),
        ...(action['overdue'] as List),
      ].where((row) => row['kind'] == 'taskInstance').toList();
      expect(instances, isNotEmpty);
      expect(instances.first['target'], 'taskInstance');
      expect(instances.first['occurrenceId'], isNotEmpty);
      expect(instances.first['todoId'], isA<int>());
    });

    test('expands recurring events started more than 90 days ago', () async {
      final now = DateTime(2026, 10, 7, 10, 0);
      await insertEvent(
        summary: 'Daily Standup Recurrence',
        startDt: DateTime(2026, 6, 9, 9, 0),
        endDt: DateTime(2026, 6, 9, 9, 30),
        rrule: 'RRULE:FREQ=DAILY',
      );

      final projection = await ActionProjectionQuery.fetch(db, date: now);
      final action = HomeWidgetService.buildActionBlock(projection);
      final timeline = action['timeline'] as List;
      expect(
        timeline.any((item) => item['summary'] == 'Daily Standup Recurrence'),
        isTrue,
      );
    });
  });

  group('Todos block', () {
    test('today, overdue, inbox and all groups', () async {
      final now = DateTime(2026, 10, 7, 10, 0);
      final todayId = await insertTodo(
        summary: 'Today Task',
        dueDate: DateTime(2026, 10, 7),
        priority: 2,
      );
      final overdueId = await insertTodo(
        summary: 'Overdue Task',
        dueDate: DateTime(2026, 10, 3),
      );
      final inboxId = await insertTodo(summary: 'No Date Task');
      final futureId = await insertTodo(
        summary: 'Future Task',
        dueDate: DateTime(2026, 10, 20),
      );
      await insertTodo(
        summary: 'Done Task',
        dueDate: DateTime(2026, 10, 7),
        status: 'COMPLETED',
      );
      await insertTodo(
        summary: 'Deleted Task',
        dueDate: DateTime(2026, 10, 7),
        deletedAt: DateTime(2026, 10, 6),
      );

      final block = await HomeWidgetService.buildTodosBlock(
        db,
        now: now,
        sixThingsEnabled: false,
        completedCount: 1,
      );
      final decoded = jsonDecode(jsonEncode(block)) as Map<String, dynamic>;
      final today = decoded['today'] as Map<String, dynamic>;
      final inbox = decoded['inbox'] as Map<String, dynamic>;
      final all = decoded['all'] as Map<String, dynamic>;

      final todayIds = (today['items'] as List).map((i) => i['todoId']).toSet();
      expect(todayIds, contains(todayId));
      expect(todayIds, isNot(contains(overdueId)));
      expect(todayIds, isNot(contains(futureId)));
      expect(today['total'], 1);
      expect(today['completedCount'], 1);
      expect(today['sixThingsCap'], 0);

      final overdueIds =
          (today['overdue'] as List).map((i) => i['todoId']).toSet();
      expect(overdueIds, contains(overdueId));

      final inboxIds =
          (inbox['items'] as List).map((i) => i['todoId']).toSet();
      expect(inboxIds, contains(inboxId));
      expect(inboxIds, isNot(contains(todayId)));

      final allIds = (all['items'] as List).map((i) => i['todoId']).toSet();
      expect(allIds, containsAll([todayId, overdueId, inboxId, futureId]));
      expect(allIds, isNot(contains('Done Task')));
      expect(all['total'], 4);

      final item =
          (today['items'] as List).firstWhere((i) => i['todoId'] == todayId)
              as Map<String, dynamic>;
      expect(item['summary'], 'Today Task');
      expect(item['priority'], 2);
      expect(item['hasTime'], isFalse);
      expect(item['recurring'], isFalse);
      expect(item['tagColors'], isEmpty);
    });

    test('six things caps emitted items but keeps the real total', () async {
      final now = DateTime(2026, 10, 7, 10, 0);
      for (var i = 0; i < 8; i++) {
        await insertTodo(
          summary: 'Task $i',
          dueDate: DateTime(2026, 10, 7),
        );
      }
      final block = await HomeWidgetService.buildTodosBlock(
        db,
        now: now,
        sixThingsEnabled: true,
        completedCount: 0,
      );
      final today = block['today'] as Map<String, dynamic>;
      expect((today['items'] as List).length, 6);
      expect(today['total'], 8);
      expect(today['sixThingsCap'], 6);
    });

    test('recurring parent stays pending and is flagged', () async {
      final now = DateTime(2026, 10, 7, 10, 0);
      final spec = RecurrenceSpec.parse(
        anchor: RecurrenceAnchor(
          source: RecurrenceAnchorSource.due,
          value: LocalDate(2026, 10, 7),
        ),
        timeZone: 'Asia/Shanghai',
        rrule: 'FREQ=DAILY',
      );
      await RecordScope.run(
        db,
        (tx) => TodoWriter.create(
          db,
          tx,
          TodosCompanion.insert(
            calendarId: calId,
            summary: 'Recurring Parent',
            rrule: Value(spec.rule.canonical),
          ),
          recurrenceSpec: spec,
        ),
      );
      final block = await HomeWidgetService.buildTodosBlock(
        db,
        now: now,
        sixThingsEnabled: false,
        completedCount: 0,
      );
      final inbox = block['inbox'] as Map<String, dynamic>;
      final item =
          (inbox['items'] as List).firstWhere(
                (i) => i['summary'] == 'Recurring Parent',
              )
              as Map<String, dynamic>;
      expect(item['recurring'], isTrue);
      expect(item['dueDate'], isNull);
      expect(item['status'], isNull);
    });
  });

  group('Month block', () {
    test('days carry marks, item lists and ordered kinds', () async {
      final now = DateTime(2026, 10, 7, 10, 0);
      final eventId = await insertEvent(
        summary: 'Event Oct 5',
        startDt: DateTime(2026, 10, 5, 10, 0),
        endDt: DateTime(2026, 10, 5, 11, 0),
      );
      final todoId = await insertTodo(summary: 'Allocated Todo Oct 18');
      final allocationId = await insertAllocation(
        todoId: todoId,
        startAt: DateTime(2026, 10, 18, 14, 0),
        endAt: DateTime(2026, 10, 18, 15, 0),
      );
      final deadlineId = await insertTodo(
        summary: 'Deadline Oct 9',
        dueDate: DateTime(2026, 10, 9),
      );

      final month = await HomeWidgetService.monthCalendar(
        db,
        now: now,
        calendarColors: {calId: '#2457D6'},
      );
      expect(month['year'], 2026);
      expect(month['month'], 10);
      expect(month['today'], 7);
      expect(month['firstWeekday'], inInclusiveRange(1, 7));

      final days = month['days'] as List;
      final day5 = days.firstWhere((d) => d['day'] == 5) as Map;
      final day18 = days.firstWhere((d) => d['day'] == 18) as Map;
      final day9 = days.firstWhere((d) => d['day'] == 9) as Map;

      expect(day5['hasEvent'], isTrue);
      expect((day5['items'] as List).single['eventId'], eventId);
      expect((day5['items'] as List).single['kind'], 'eventOccurrence');
      expect(day5['colors'], ['#2457D6']);

      expect(day18['hasAllocation'], isTrue);
      final allocationRow = (day18['items'] as List).single as Map;
      expect(allocationRow['kind'], 'taskAllocation');
      expect(allocationRow['todoId'], todoId);
      expect(allocationRow['allocationId'], allocationId.toString());

      expect(day9['hasTodo'], isTrue);
      final deadlineRow = (day9['items'] as List).single as Map;
      expect(deadlineRow['kind'], 'todoDeadline');
      expect(deadlineRow['todoId'], deadlineId);
      expect(deadlineRow['hasTime'], isFalse);
      expect(deadlineRow['start'], '');
    });

    test('per-day items are capped at eight', () async {
      final now = DateTime(2026, 10, 7, 10, 0);
      for (var i = 0; i < 10; i++) {
        await insertEvent(
          summary: 'Event $i',
          startDt: DateTime(2026, 10, 12, 8 + i, 0),
          endDt: DateTime(2026, 10, 12, 9 + i, 0),
        );
      }
      final month = await HomeWidgetService.monthCalendar(db, now: now);
      final days = month['days'] as List;
      final day12 = days.firstWhere((d) => d['day'] == 12) as Map;
      expect(day12['itemCount'], 10);
      expect((day12['items'] as List).length, 8);
    });

    test('all-day events sort before timed items', () async {
      final now = DateTime(2026, 10, 7, 10, 0);
      await insertEvent(
        summary: 'Timed',
        startDt: DateTime(2026, 10, 12, 9, 0),
        endDt: DateTime(2026, 10, 12, 10, 0),
      );
      await insertEvent(
        summary: 'All day',
        startDt: DateTime(2026, 10, 12),
        endDt: DateTime(2026, 10, 13),
        isAllDay: true,
      );
      final month = await HomeWidgetService.monthCalendar(db, now: now);
      final day12 = (month['days'] as List).firstWhere(
        (d) => d['day'] == 12,
      ) as Map;
      final items = day12['items'] as List;
      expect(items.first['summary'], 'All day');
      expect(items[1]['summary'], 'Timed');
    });
  });

  group('UI and theme', () {
    test('localized labels and count templates', () async {
      final en = await HomeWidgetService.loadWidgetUiStrings(
        locale: const Locale('en'),
      );
      expect(en.locale, 'en');
      expect(en.today, 'Today');
      expect(en.inbox, 'Unplanned');
      expect(en.all, 'All');
      expect(en.completedCount, '{n} completed');
      expect(en.moreCount, '{n} more');
      expect(en.overdueCount, '{n} overdue');

      final zh = await HomeWidgetService.loadWidgetUiStrings(
        locale: const Locale('zh'),
      );
      expect(zh.locale, 'zh');
      expect(zh.today, '今天');
      expect(zh.inbox, '未安排');
      expect(zh.all, '全部');
      expect(zh.completedCount, '已完成 {n}');
      expect(zh.moreCount, '还有 {n} 项');
      expect(zh.overdueCount, '{n} 项逾期');
    });

    test('theme includes error and warning tokens', () {
      final light = HomeWidgetService.buildThemeBlock(dark: false);
      expect(light['dark'], false);
      final lightColors = light['colors'] as Map;
      expect(lightColors['accent'], '#2D4F7C');
      expect(lightColors['error'], isA<String>());
      expect(lightColors['warning'], isA<String>());

      final dark = HomeWidgetService.buildThemeBlock(dark: true);
      expect(dark['dark'], true);
      final darkColors = dark['colors'] as Map;
      expect(darkColors['accent'], '#8FB0D9');
      expect(darkColors['error'], isA<String>());
      expect(darkColors['warning'], isA<String>());
    });
  });

  group('legacy pendingTaps decoder', () {
    test('decodes valid legacy rows', () {
      final jsonStr = jsonEncode({
        'version': 2,
        'pendingTaps': [
          {
            'todoId': 42,
            'action': 'complete',
            'at': '2026-10-07T10:00:00.000Z',
          },
          {'todoId': 'invalid', 'action': 'complete'},
        ],
      });
      final taps = HomeWidgetService.decodePendingTaps(jsonStr);
      expect(taps.length, 1);
      expect(taps.first.todoId, 42);
      expect(taps.first.action, 'complete');
    });

    test('handles null and invalid json', () {
      expect(HomeWidgetService.decodePendingTaps(null), isEmpty);
      expect(HomeWidgetService.decodePendingTaps(''), isEmpty);
      expect(HomeWidgetService.decodePendingTaps('not json'), isEmpty);
    });
  });
}
