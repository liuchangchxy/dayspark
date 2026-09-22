import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:dayspark/data/local/database/app_database.dart';

class HomeWidgetService {
  static const String snapshotKey = 'widget_snapshot';
  static const int snapshotVersion = 1;
  static const String androidProviderName =
      'com.dayspark.app.CalendarTodoWidgetProvider';
  static const String legacyEventsKey = 'today_events';
  static const String legacyTodosKey = 'pending_todos';
  static const String legacyCountKey = 'todo_count';

  static Future<void> updateWidget(AppDatabase db) async {
    try {
      final events = await todayEvents(db);
      final todos = await pendingTodos(db);
      final todoCount = await pendingTodoCount(db);
      final snapshot = buildSnapshot(
        events: events,
        todos: todos,
        todoCount: todoCount,
        generatedAt: DateTime.now(),
      );

      // Dual-write: CalendarTodoWidgetProvider.kt and both CalendarTodoWidget.swift
      // files still read the three legacy keys from their native stores, so they
      // keep working untouched; `widget_snapshot` is the forward contract for P4.
      await HomeWidget.saveWidgetData(
        legacyEventsKey,
        encodeTodayEvents(events),
      );
      await HomeWidget.saveWidgetData(legacyTodosKey, encodePendingTodos(todos));
      await HomeWidget.saveWidgetData(legacyCountKey, '$todoCount');
      await HomeWidget.saveWidgetData(snapshotKey, jsonEncode(snapshot));
      await HomeWidget.updateWidget(qualifiedAndroidName: androidProviderName);
    } catch (e) {
      debugPrint('home_widget: update error: $e');
    }
  }

  static Future<List<Event>> todayEvents(AppDatabase db) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    return (db.select(db.events)
          ..where((t) => t.deletedAt.isNull())
          ..where(
            (t) =>
                t.startDt.isSmallerThanValue(todayEnd) &
                t.endDt.isBiggerThanValue(todayStart),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.startDt)])
          ..limit(3))
        .get();
  }

  static Future<List<Todo>> pendingTodos(AppDatabase db, {int limit = 3}) {
    return (db.select(db.todos)
          ..where((t) => t.deletedAt.isNull())
          ..where((t) => t.status.isNotIn(['COMPLETED', 'CANCELLED']))
          // Subtasks must not occupy widget slots — only top-level todos.
          ..where((t) => t.parentId.isNull())
          ..orderBy([
            // SQLite ASC puts NULLs first; ordering by `due_date IS NULL`
            // (0/1) first sinks NULL due dates to the end of the list.
            (t) => OrderingTerm(
              expression: t.dueDate.isNull(),
              mode: OrderingMode.asc,
            ),
            (t) => OrderingTerm.asc(t.dueDate),
          ])
          ..limit(limit))
        .get();
  }

  static Future<int> pendingTodoCount(AppDatabase db) async {
    final rows = await (db.select(db.todos)
          ..where((t) => t.deletedAt.isNull())
          ..where((t) => t.status.isNotIn(['COMPLETED', 'CANCELLED'])))
        .get();
    return rows.length;
  }

  static Map<String, Object?> buildSnapshot({
    required List<Event> events,
    required List<Todo> todos,
    required int todoCount,
    required DateTime generatedAt,
  }) {
    return {
      'version': snapshotVersion,
      'generatedAt': generatedAt.toUtc().toIso8601String(),
      'todayEvents': events.map(eventItem).toList(),
      'pendingTodos': todos.map(todoItem).toList(),
      'todoCount': todoCount,
    };
  }

  static String encodeTodayEvents(List<Event> events) =>
      jsonEncode(events.map(eventItem).toList());

  static String encodePendingTodos(List<Todo> todos) =>
      jsonEncode(todos.map(todoItem).toList());

  static Map<String, Object?> eventItem(Event e) => {
        'summary': e.summary,
        'start':
            '${e.startDt.hour.toString().padLeft(2, '0')}:${e.startDt.minute.toString().padLeft(2, '0')}',
        'isAllDay': e.isAllDay,
      };

  static Map<String, Object?> todoItem(Todo t) => {
        'summary': t.summary,
        'dueDate':
            t.dueDate != null ? '${t.dueDate!.month}/${t.dueDate!.day}' : '',
      };
}
