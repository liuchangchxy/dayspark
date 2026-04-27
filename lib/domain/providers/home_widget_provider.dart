import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/services/home_widget_service.dart';

final updateHomeWidgetProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    final db = ref.read(databaseProvider);
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));

    // Use DAOs which provide properly typed column accessors
    final events = await db.eventsDao.watchByDateRange(start, end).first;
    final todos = await db.todosDao.watchPending().first;

    await HomeWidgetService.updateWidgets(
      todayEvents: events,
      pendingTodos: todos,
    );
  };
});
