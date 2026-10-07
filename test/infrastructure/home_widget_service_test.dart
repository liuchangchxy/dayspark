import 'dart:convert';

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
            deletedAt:
                deletedAt != null ? Value(deletedAt) : const Value.absent(),
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
            deletedAt: deletedAt != null ? Value(deletedAt) : const Value.absent(),
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
            todoSyncId: todoSyncId != null ? Value(todoSyncId) : const Value.absent(),
            occurrenceId: occurrenceId != null ? Value(occurrenceId) : const Value.absent(),
            startAt: startAt,
            endAt: endAt,
          ),
        );
  }

  group('HomeWidgetService v3 snapshot contract', () {
    test('v3 snapshot schema keys and types match the contract', () async {
      final now = DateTime(2026, 10, 7, 10, 0);

      // 1. Insert Event for today
      await insertEvent(
        summary: 'Team Sync',
        startDt: DateTime(2026, 10, 7, 10, 0),
        endDt: DateTime(2026, 10, 7, 11, 0),
      );

      // 2. Insert Todo with allocation for today
      final allocatedTodoId = await insertTodo(
        summary: 'Deep Work',
        syncId: 'todo_sync_allocated',
      );
      await insertAllocation(
        todoId: allocatedTodoId,
        todoSyncId: 'todo_sync_allocated',
        startAt: DateTime(2026, 10, 7, 14, 0),
        endAt: DateTime(2026, 10, 7, 15, 0),
      );

      // 3. Insert Action Todo due today
      await insertTodo(
        summary: 'Quarterly Taxes',
        syncId: 'todo_sync_taxes',
        dueDate: DateTime(2026, 10, 7),
      );

      // 4. Insert Recurring habit
      final habitSpec = RecurrenceSpec.parse(
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
            rrule: Value(habitSpec.rule.canonical),
          ),
          recurrenceSpec: habitSpec,
        ),
      );

      // 5. Query and build v3 components
      final projectionData = await ActionProjectionQuery.fetch(db, date: now);
      final timeline = HomeWidgetService.todayTimeline(projectionData);
      final actions = HomeWidgetService.todayActions(projectionData);
      final status = HomeWidgetService.todayStatus(projectionData);
      final upcoming = await HomeWidgetService.upcomingItems(db, now: now);
      final monthDots = await HomeWidgetService.monthDots(db, now: now);

      final ui = await HomeWidgetService.loadWidgetUiStrings(
        locale: const Locale('en'),
        todoCount: actions.length + status['unplannedCount']!,
      );
      final theme = HomeWidgetService.buildThemeBlock(dark: true);

      final snapshot = HomeWidgetService.buildSnapshot(
        todayTimeline: timeline,
        todayActions: actions,
        todayStatus: status,
        upcomingItems: upcoming,
        monthDots: monthDots,
        ui: ui,
        theme: theme,
        generatedAt: now,
      );

      final decoded = jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;

      expect(decoded.keys.toSet(), {
        'version',
        'generatedAt',
        'today',
        'upcoming',
        'monthDots',
        'todayEvents',
        'pendingTodos',
        'todoCount',
        'pendingTaps',
        'ui',
        'theme',
      });

      expect(decoded['version'], 3);
      expect(decoded['generatedAt'], isA<String>());

      final today = decoded['today'] as Map<String, dynamic>;
      expect(today.keys.toSet(), {'timeline', 'actions', 'status'});

      final timelineRows = today['timeline'] as List;
      expect(timelineRows.length, 2);
      expect(timelineRows[0]['kind'], 'eventOccurrence');
      expect(timelineRows[0]['summary'], 'Team Sync');
      expect(timelineRows[0]['start'], '10:00');
      expect(timelineRows[0]['end'], '11:00');

      expect(timelineRows[1]['kind'], 'taskAllocation');
      expect(timelineRows[1]['summary'], 'Deep Work');
      expect(timelineRows[1]['start'], '14:00');
      expect(timelineRows[1]['end'], '15:00');

      final actionRows = today['actions'] as List;
      expect(actionRows.any((a) => a['summary'] == 'Quarterly Taxes'), isTrue);
      expect(actionRows.any((a) => a['summary'] == 'Daily Standup Notes'), isTrue);

      final statusMap = today['status'] as Map<String, dynamic>;
      expect(statusMap.keys.toSet(), {'overdueCount', 'missedCount', 'unplannedCount'});

      // Downlevel compatibility fields
      expect(decoded['todayEvents'], isA<List>());
      expect(decoded['pendingTodos'], isA<List>());
      expect(decoded['todoCount'], isA<int>());
      expect(decoded['pendingTaps'], isEmpty);
    });

    test('upcomingItems covers 7-civil-day hybrid projection', () async {
      final now = DateTime(2026, 10, 7, 10, 0);

      // Tomorrow event
      await insertEvent(
        summary: 'Tomorrow Meeting',
        startDt: DateTime(2026, 10, 8, 9, 0),
        endDt: DateTime(2026, 10, 8, 10, 0),
      );

      // Day 3 Task Allocation
      final todoDay3 = await insertTodo(summary: 'Project Sprint');
      await insertAllocation(
        todoId: todoDay3,
        startAt: DateTime(2026, 10, 10, 14, 0),
        endAt: DateTime(2026, 10, 10, 16, 0),
      );

      // Day 5 Todo Deadline
      await insertTodo(
        summary: 'Submit Invoice',
        dueDate: DateTime(2026, 10, 12),
      );

      // Day 8 event (out of 7-day window)
      await insertEvent(
        summary: 'Far Future Meeting',
        startDt: DateTime(2026, 10, 16, 9, 0),
        endDt: DateTime(2026, 10, 16, 10, 0),
      );

      final items = await HomeWidgetService.upcomingItems(db, now: now);

      expect(items.any((i) => i['summary'] == 'Tomorrow Meeting'), isTrue);
      expect(items.any((i) => i['summary'] == 'Project Sprint'), isTrue);
      expect(items.any((i) => i['summary'] == 'Submit Invoice'), isTrue);
      expect(items.any((i) => i['summary'] == 'Far Future Meeting'), isFalse);
    });

    test('civil-day arithmetic prevents DST drift', () async {
      // Simulating a date around autumn daylight saving transition (e.g. October 25)
      final dstDate = DateTime(2026, 10, 25, 12, 0);

      // Insert event on the exact day after DST transition
      await insertEvent(
        summary: 'Post-DST Sync',
        startDt: DateTime(2026, 10, 26, 10, 0),
        endDt: DateTime(2026, 10, 26, 11, 0),
      );

      final upcoming = await HomeWidgetService.upcomingItems(db, now: dstDate);
      expect(upcoming, isA<List>());
      final syncItem = upcoming.firstWhere((i) => i['summary'] == 'Post-DST Sync');
      // Must not drift to previous or next day due to 24h duration arithmetic
      expect(syncItem['date'], '10/26');
      expect(syncItem['time'], '10:00');

      final dots = await HomeWidgetService.monthDots(db, now: dstDate);
      expect(dots, isA<List>());
      // October 26 must have a marked dot [26, true]
      expect(dots.any((d) => d[0] == 26 && d[1] == true), isTrue);
    });

    test('expands recurring events started >90 days ago', () async {
      final now = DateTime(2026, 10, 7, 10, 0);

      // Recurring event started 120 days ago (June 9, 2026) with daily recurrence
      await insertEvent(
        summary: 'Daily Standup Recurrence',
        startDt: DateTime(2026, 6, 9, 9, 0),
        endDt: DateTime(2026, 6, 9, 9, 30),
        rrule: 'RRULE:FREQ=DAILY',
      );

      final projectionData = await ActionProjectionQuery.fetch(db, date: now);
      final timeline = HomeWidgetService.todayTimeline(projectionData);

      // The >90d daily recurring event must appear in today's timeline!
      expect(
        timeline.any((item) => item['summary'] == 'Daily Standup Recurrence'),
        isTrue,
        reason: '>90d daily recurring event must expand into today',
      );

      // And also appears in upcoming items
      final upcoming = await HomeWidgetService.upcomingItems(db, now: now);
      expect(
        upcoming.any((item) => item['summary'] == 'Daily Standup Recurrence'),
        isTrue,
        reason: '>90d daily recurring event must expand into upcoming window',
      );
    });

    test('monthDots marks commitment days from both events and allocations', () async {
      final now = DateTime(2026, 10, 7, 10, 0);

      // Event on October 5
      await insertEvent(
        summary: 'Event Oct 5',
        startDt: DateTime(2026, 10, 5, 10, 0),
        endDt: DateTime(2026, 10, 5, 11, 0),
      );

      // Allocation on October 18
      final todo = await insertTodo(summary: 'Allocated Todo Oct 18');
      await insertAllocation(
        todoId: todo,
        startAt: DateTime(2026, 10, 18, 14, 0),
        endAt: DateTime(2026, 10, 18, 15, 0),
      );

      final dots = await HomeWidgetService.monthDots(db, now: now);

      final markedDays = dots.where((pair) => pair[1] == true).map((pair) => pair[0]).toSet();
      expect(markedDays.contains(5), isTrue, reason: 'October 5 had an event');
      expect(markedDays.contains(18), isTrue, reason: 'October 18 had a task allocation');
    });
  });

  group('HomeWidgetService legacy pendingTaps codec', () {
    test('decodes legacy pendingTaps correctly', () {
      final jsonStr = jsonEncode({
        'version': 2,
        'pendingTaps': [
          {
            'todoId': 42,
            'action': 'complete',
            'at': '2026-10-07T10:00:00.000Z',
          },
          {
            'todoId': 'invalid',
            'action': 'complete',
          },
        ],
      });

      final taps = HomeWidgetService.decodePendingTaps(jsonStr);
      expect(taps.length, 1);
      expect(taps.first.todoId, 42);
      expect(taps.first.action, 'complete');
    });

    test('handles null and invalid json gracefully', () {
      expect(HomeWidgetService.decodePendingTaps(null), isEmpty);
      expect(HomeWidgetService.decodePendingTaps(''), isEmpty);
      expect(HomeWidgetService.decodePendingTaps('not json'), isEmpty);
    });
  });

  group('HomeWidgetService UI and Theme', () {
    test('ui strings load and switch locale', () async {
      final en = await HomeWidgetService.loadWidgetUiStrings(
        locale: const Locale('en'),
        todoCount: 5,
      );
      expect(en.locale, 'en');
      expect(en.today, 'Today');
      expect(en.pendingCount, '5 pending');
      expect(en.overdue, 'Overdue');
      expect(en.missed, 'Missed');
      expect(en.unplanned, 'Inbox');

      final zh = await HomeWidgetService.loadWidgetUiStrings(
        locale: const Locale('zh'),
        todoCount: 5,
      );
      expect(zh.locale, 'zh');
      expect(zh.today, '今天');
      expect(zh.pendingCount, '5 项待办');
      expect(zh.overdue, '已逾期');
      expect(zh.missed, '已遗漏');
      expect(zh.unplanned, '收件箱');
    });

    test('theme block contains valid hex tokens and mode', () {
      final light = HomeWidgetService.buildThemeBlock(dark: false);
      expect(light['dark'], false);
      expect((light['colors'] as Map)['accent'], '#007AFF');

      final dark = HomeWidgetService.buildThemeBlock(dark: true);
      expect(dark['dark'], true);
      expect((dark['colors'] as Map)['accent'], '#0A84FF');
    });
  });
}
