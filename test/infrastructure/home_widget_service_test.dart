import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/infrastructure/platform/home_widget_service.dart';

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

  Future<int> insertEvent({
    required String summary,
    required DateTime startDt,
    required DateTime endDt,
    bool isAllDay = false,
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
            deletedAt: deletedAt != null ? Value(deletedAt) : const Value.absent(),
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

  group('HomeWidgetService v2 snapshot', () {
    test('v2 snapshot schema keys and types match the contract', () async {
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      await insertEvent(
        summary: 'Standup',
        startDt: todayStart.add(const Duration(hours: 10)),
        endDt: todayStart.add(const Duration(hours: 11)),
      );
      await insertEvent(
        summary: 'Conference',
        startDt: todayStart,
        endDt: todayStart.add(const Duration(days: 1)),
        isAllDay: true,
      );
      await insertTodo(summary: 'With due', dueDate: DateTime(2026, 9, 25));
      await insertTodo(summary: 'Without due', dueDate: null);

      final events = await HomeWidgetService.todayEvents(db);
      final todos = await HomeWidgetService.pendingTodos(db);
      final todoCount = await HomeWidgetService.pendingTodoCount(db);
      final ui = await HomeWidgetService.loadWidgetUiStrings(
        locale: const Locale('en'),
        todoCount: todoCount,
      );
      final theme = HomeWidgetService.buildThemeBlock(dark: false);

      final snapshot = HomeWidgetService.buildSnapshot(
        events: events,
        todos: todos,
        todoCount: todoCount,
        upcomingEvents: const [],
        upcomingTodos: const [],
        monthEventDays: await HomeWidgetService.monthEventDaysOfCurrentMonth(
          db,
        ),
        ui: ui,
        theme: theme,
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
        'upcoming',
        'pendingTaps',
        'monthDots',
        'ui',
        'theme',
      });
      expect(decoded['version'], 2);
      expect(decoded['version'], isA<int>());
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
        // `id` is the handle native checkbox taps append into pendingTaps.
        expect(item.keys.toSet(), {'id', 'summary', 'dueDate'});
        expect(item['id'], isA<int>());
        expect(item['summary'], isA<String>());
        expect(item['dueDate'], isA<String>());
      }

      expect(decoded['todoCount'], 2);
      expect(decoded['todoCount'], isA<int>());

      final upcoming = decoded['upcoming'] as Map<String, dynamic>;
      expect(upcoming.keys.toSet(), {'events', 'todos'});
      expect(upcoming['events'], isA<List>());
      expect(upcoming['todos'], isA<List>());

      // App side of the native→app channel always writes it empty; native
      // appends between flushes, the next flush with a consumer clears it.
      expect(decoded['pendingTaps'], isA<List>());
      expect(decoded['pendingTaps'], isEmpty);

      // monthDots: [[dayNumber, hasEvent]] pairs for the current month; the
      // golden inserts an all-day event covering today, so today's day shows.
      final monthDots = decoded['monthDots'] as List;
      expect(monthDots, isA<List>());
      for (final pair in monthDots) {
        expect(pair, isA<List>());
        final parts = (pair as List);
        expect(parts, hasLength(2));
        expect(parts[0], isA<int>());
        expect(parts[1], true);
      }
      final todayDot = monthDots.firstWhere(
        (pair) => (pair as List)[0] == today.day,
        orElse: () => null,
      );
      expect(todayDot, isNotNull, reason: 'today must carry a month dot');

      final uiBlock = decoded['ui'] as Map<String, dynamic>;
      expect(uiBlock.keys.toSet(), {
        'locale',
        'title',
        'today',
        'events',
        'todos',
        'allDay',
        'todayEventsHeader',
        'noEvents',
        'allDone',
        'pendingCount',
        'quickAdd',
        'upcoming',
      });
      expect(uiBlock['locale'], 'en');
      expect(uiBlock['pendingCount'], '2 pending');
      for (final key in uiBlock.keys) {
        expect(uiBlock[key], isA<String>(), reason: 'ui.$key');
      }

      final themeBlock = decoded['theme'] as Map<String, dynamic>;
      expect(themeBlock.keys.toSet(), {'dark', 'colors'});
      expect(themeBlock['dark'], isA<bool>());
      expect(themeBlock['dark'], false);
      final colors = themeBlock['colors'] as Map<String, dynamic>;
      expect(colors.keys.toSet(), {
        'background',
        'surface',
        'textPrimary',
        'textSecondary',
        'accent',
        'border',
      });
      for (final key in colors.keys) {
        expect(colors[key], matches(RegExp(r'^#[0-9A-F]{6}$')));
      }
    });

    test('upcoming bucket covers tomorrow through day 7 only', () async {
      final now = DateTime(2026, 9, 24, 15);
      final window = HomeWidgetService.upcomingWindow(now);
      expect(window.start, DateTime(2026, 9, 25));
      expect(window.end, DateTime(2026, 10, 2));

      await insertEvent(
        summary: 'Today event',
        startDt: DateTime(2026, 9, 24, 10),
        endDt: DateTime(2026, 9, 24, 11),
      );
      await insertEvent(
        summary: 'Tomorrow event',
        startDt: DateTime(2026, 9, 25, 9),
        endDt: DateTime(2026, 9, 25, 10),
      );
      await insertEvent(
        summary: 'Day7 event',
        startDt: DateTime(2026, 10, 1, 18),
        endDt: DateTime(2026, 10, 1, 19),
      );
      await insertEvent(
        summary: 'Day8 event',
        startDt: DateTime(2026, 10, 2, 9),
        endDt: DateTime(2026, 10, 2, 10),
      );
      await insertEvent(
        summary: 'Spilling multi-day',
        startDt: DateTime(2026, 9, 24, 8),
        endDt: DateTime(2026, 9, 26, 8),
      );

      await insertTodo(summary: 'Due tomorrow', dueDate: DateTime(2026, 9, 25));
      await insertTodo(summary: 'Due day7', dueDate: DateTime(2026, 10, 1));
      await insertTodo(summary: 'Due day8', dueDate: DateTime(2026, 10, 2));
      await insertTodo(summary: 'Due today', dueDate: DateTime(2026, 9, 24));
      await insertTodo(summary: 'No due', dueDate: null);
      final parentId = await insertTodo(summary: 'Parent', dueDate: null);
      await insertTodo(
        summary: 'Due subtask',
        dueDate: DateTime(2026, 9, 26),
        parentId: parentId,
      );
      await insertTodo(
        summary: 'Done soon',
        dueDate: DateTime(2026, 9, 26),
        status: 'COMPLETED',
      );

      final events = await HomeWidgetService.upcomingEvents(db, now: now);
      final todos = await HomeWidgetService.upcomingTodos(db, now: now);

      expect(events.map((e) => e.summary).toSet(), {
        'Tomorrow event',
        'Day7 event',
        'Spilling multi-day',
      });
      expect(todos.map((t) => t.summary).toSet(), {
        'Due tomorrow',
        'Due day7',
      });

      final snapshot = HomeWidgetService.buildSnapshot(
        events: const [],
        todos: const [],
        todoCount: 0,
        upcomingEvents: events,
        upcomingTodos: todos,
        ui: await HomeWidgetService.loadWidgetUiStrings(
          locale: const Locale('en'),
        ),
        theme: HomeWidgetService.buildThemeBlock(dark: false),
        generatedAt: now,
      );
      final upcoming = snapshot['upcoming'] as Map<String, Object?>;
      final upcomingEventItems = upcoming['events'] as List;
      expect(upcomingEventItems, hasLength(3));
      for (final item in upcomingEventItems.cast<Map<String, Object?>>()) {
        expect(
          item.keys.toSet(),
          {'summary', 'date', 'start', 'isAllDay'},
        );
        expect(item['date'], matches(RegExp(r'^\d{1,2}/\d{1,2}$')));
      }
      final upcomingTodoItems = upcoming['todos'] as List;
      expect(upcomingTodoItems, hasLength(2));
      for (final item in upcomingTodoItems.cast<Map<String, Object?>>()) {
        expect(item.keys.toSet(), {'summary', 'dueDate'});
      }
    });

    test('month dots cover every day an event touches in the month',
        () async {
      final now = DateTime(2026, 9, 15, 12);
      await insertEvent(
        summary: 'Single day',
        startDt: DateTime(2026, 9, 3, 9),
        endDt: DateTime(2026, 9, 3, 10),
      );
      await insertEvent(
        summary: 'Multi day',
        startDt: DateTime(2026, 9, 28, 10),
        endDt: DateTime(2026, 9, 30, 11),
      );
      await insertEvent(
        summary: 'Crosses into month',
        startDt: DateTime(2026, 8, 31, 8),
        endDt: DateTime(2026, 9, 1, 8),
      );
      await insertEvent(
        summary: 'Next month',
        startDt: DateTime(2026, 10, 5, 9),
        endDt: DateTime(2026, 10, 5, 10),
      );
      await insertEvent(
        summary: 'Previous month only',
        startDt: DateTime(2026, 8, 10, 9),
        endDt: DateTime(2026, 8, 10, 10),
      );
      await insertEvent(
        summary: 'Deleted',
        startDt: DateTime(2026, 9, 10, 9),
        endDt: DateTime(2026, 9, 10, 10),
        deletedAt: DateTime(2026, 9, 11),
      );

      final days = await HomeWidgetService.monthEventDaysOfCurrentMonth(
        db,
        now: now,
      );

      // Boundary-crossing event occupies Aug 31 (outside) + Sep 1 (inside);
      // multi-day marks each touched September day; out-of-month and
      // deleted events stay out.
      expect(days, [1, 3, 28, 29, 30]);
    });

    test('legacy encoders keep payloads native readers parse', () async {
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      await insertEvent(
        summary: 'Standup',
        startDt: todayStart.add(const Duration(hours: 9, minutes: 30)),
        endDt: todayStart.add(const Duration(hours: 10)),
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

  group('HomeWidgetService pendingTaps codec', () {
    test('app-written snapshot carries an empty pendingTaps array', () {
      final snapshot = HomeWidgetService.buildSnapshot(
        events: const [],
        todos: const [],
        todoCount: 0,
        upcomingEvents: const [],
        upcomingTodos: const [],
        ui: const WidgetUiStrings(
          locale: 'en',
          title: 'DaySpark',
          today: 'Today',
          events: 'Events',
          todos: 'Todos',
          allDay: 'All day',
          todayEventsHeader: "Today's Events",
          noEvents: 'No events today',
          allDone: 'All done!',
          pendingCount: '0 pending',
          quickAdd: 'Quick add',
          upcoming: 'Upcoming',
        ),
        theme: HomeWidgetService.buildThemeBlock(dark: false),
        generatedAt: DateTime.utc(2026, 9, 22),
      );

      expect(snapshot['pendingTaps'], isEmpty);
      expect(
        HomeWidgetService.decodePendingTaps(jsonEncode(snapshot)),
        isEmpty,
      );
    });

    test('decodes native-appended entries and skips malformed ones', () {
      final appended = jsonEncode({
        'version': 2,
        'pendingTaps': [
          {
            'todoId': 7,
            'action': 'complete',
            'at': '2026-09-24T01:02:03.000Z',
          },
          {'todoId': 'bad', 'action': 'complete'},
          42,
          {
            'todoId': 8,
            'action': 'complete',
            'at': 'not-a-date',
          },
        ],
      });

      final taps = HomeWidgetService.decodePendingTaps(appended);

      expect(taps, hasLength(2));
      expect(taps.first.todoId, 7);
      expect(taps.first.action, 'complete');
      expect(taps.first.at, DateTime.utc(2026, 9, 24, 1, 2, 3));
      expect(taps.last.todoId, 8);

      expect(HomeWidgetService.decodePendingTaps(null), isEmpty);
      expect(HomeWidgetService.decodePendingTaps(''), isEmpty);
      expect(HomeWidgetService.decodePendingTaps('not json'), isEmpty);
      expect(
        HomeWidgetService.decodePendingTaps('{"pendingTaps": "nope"}'),
        isEmpty,
      );
      expect(
        HomeWidgetService.decodePendingTaps('[]'),
        isEmpty,
      );
    });
  });

  group('HomeWidgetService ui strings', () {
    test('ui strings follow locale switch', () async {
      final en = await HomeWidgetService.loadWidgetUiStrings(
        locale: const Locale('en'),
        todoCount: 3,
      );
      expect(en.locale, 'en');
      expect(en.today, 'Today');
      expect(en.events, 'Events');
      expect(en.todos, 'Todos');
      expect(en.allDay, 'All day');
      expect(en.todayEventsHeader, "Today's Events");
      expect(en.noEvents, 'No events today');
      expect(en.allDone, 'All done!');
      expect(en.pendingCount, '3 pending');
      expect(en.quickAdd, 'Quick add');
      expect(en.upcoming, 'Upcoming');

      final zh = await HomeWidgetService.loadWidgetUiStrings(
        locale: const Locale('zh'),
        todoCount: 3,
      );
      expect(zh.locale, 'zh');
      expect(zh.today, '今天');
      expect(zh.events, '日程');
      expect(zh.todos, '待办');
      expect(zh.allDay, '全天');
      expect(zh.todayEventsHeader, '今日日程');
      expect(zh.noEvents, '今天没有日程');
      expect(zh.allDone, '全部完成');
      expect(zh.pendingCount, '3 项待办');
      expect(zh.quickAdd, '快速添加');
      expect(zh.upcoming, '接下来');

      expect(zh.toBlock()['locale'], 'zh');
      expect(zh.toBlock()['todos'], '待办');
    });
  });

  group('HomeWidgetService theme block', () {
    test('exposes dark flag and hex tokens per mode', () {
      final light = HomeWidgetService.buildThemeBlock(dark: false);
      expect(light['dark'], false);
      final lightColors = light['colors'] as Map<String, Object?>;
      expect(lightColors['accent'], '#2563EB');
      expect(lightColors['background'], '#FAFAFA');

      final dark = HomeWidgetService.buildThemeBlock(dark: true);
      expect(dark['dark'], true);
      final darkColors = dark['colors'] as Map<String, Object?>;
      expect(darkColors['accent'], '#60A5FA');
      expect(darkColors['background'], '#0F0F14');
    });
  });
}
