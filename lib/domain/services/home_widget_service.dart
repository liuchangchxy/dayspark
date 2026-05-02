import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:home_widget/home_widget.dart';
import 'package:dayspark/data/local/database/app_database.dart';

class HomeWidgetService {
  static Future<void> updateWidget(AppDatabase db) async {
    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = todayStart.add(const Duration(days: 1));

      final events = await (db.select(db.events)
            ..where((t) => t.deletedAt.isNull())
            ..where(
              (t) =>
                  t.startDt.isSmallerThanValue(todayEnd) &
                  t.endDt.isBiggerThanValue(todayStart),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.startDt)])
            ..limit(3))
          .get();

      final eventsJson = jsonEncode(
        events
            .map((e) => {
                  'summary': e.summary,
                  'start':
                      '${e.startDt.hour.toString().padLeft(2, '0')}:${e.startDt.minute.toString().padLeft(2, '0')}',
                  'isAllDay': e.isAllDay,
                })
            .toList(),
      );

      final todos = await (db.select(db.todos)
            ..where((t) => t.deletedAt.isNull())
            ..where((t) => t.status.isNotIn(['COMPLETED', 'CANCELLED']))
            ..orderBy([(t) => OrderingTerm.asc(t.dueDate)])
            ..limit(3))
          .get();

      final todosJson = jsonEncode(
        todos
            .map((t) => {
                  'summary': t.summary,
                  'dueDate': t.dueDate != null
                      ? '${t.dueDate!.month}/${t.dueDate!.day}'
                      : '',
                })
            .toList(),
      );

      final allPendingCount = await (db.select(db.todos)
            ..where((t) => t.deletedAt.isNull())
            ..where((t) => t.status.isNotIn(['COMPLETED', 'CANCELLED'])))
          .get()
          .then((list) => list.length);

      await HomeWidget.saveWidgetData('today_events', eventsJson);
      await HomeWidget.saveWidgetData('pending_todos', todosJson);
      await HomeWidget.saveWidgetData('todo_count', '$allPendingCount');
      await HomeWidget.updateWidget(
        qualifiedAndroidName: 'com.dayspark.app.CalendarTodoWidgetProvider',
      );
    } catch (_) {}
  }
}
