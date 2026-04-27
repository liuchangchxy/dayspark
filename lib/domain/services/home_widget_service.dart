import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:dayspark/data/local/database/app_database.dart';

class HomeWidgetService {
  static Future<void> updateWidgets({
    required List<Event> todayEvents,
    required List<Todo> pendingTodos,
  }) async {
    // home_widget only works on Android, iOS, and macOS with proper WidgetKit setup.
    // Skip on unsupported platforms (e.g. macOS debug without WidgetKit target).
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;

    try {
      final eventsJson = jsonEncode(todayEvents.take(3).map((e) => {
            'summary': e.summary,
            'start':
                '${e.startDt.hour.toString().padLeft(2, '0')}:${e.startDt.minute.toString().padLeft(2, '0')}',
            'isAllDay': e.isAllDay,
          }).toList());

      final todosJson = jsonEncode(pendingTodos.take(3).map((t) => {
            'summary': t.summary,
            'dueDate': t.dueDate?.toIso8601String().substring(0, 10),
            'priority': t.priority,
          }).toList());

      await HomeWidget.saveWidgetData('today_events', eventsJson);
      await HomeWidget.saveWidgetData('pending_todos', todosJson);
      await HomeWidget.saveWidgetData(
          'todo_count', pendingTodos.length.toString());

      if (Platform.isAndroid) {
        await HomeWidget.updateWidget(
            androidName: 'CalendarTodoWidgetProvider');
      } else if (Platform.isIOS) {
        await HomeWidget.updateWidget(iOSName: 'CalendarTodoWidget');
      }
    } catch (_) {
      // Silently fail — widget updates are not critical
    }
  }
}
