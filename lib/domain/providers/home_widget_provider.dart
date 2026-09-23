import 'dart:async';

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/infrastructure/platform/home_widget_service.dart';

final updateHomeWidgetProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    final db = ref.read(databaseProvider);
    await HomeWidgetService.updateWidget(
      db,
      onPendingTaps: ref.read(consumeWidgetPendingTapsProvider),
    );
  };
});

/// Lands widget-checkbox taps through the normal complete path
/// (`toggleTodoProvider`): reminder cancellation, `markComplete`, and the
/// sync outbox enqueue all stay in one place — the widget never gets a
/// second write path into the database.
final consumeWidgetPendingTapsProvider =
    Provider<Future<void> Function(List<WidgetPendingTap>)>((ref) {
      // toggleTodoProvider is read at call time, not build time: consuming
      // is rare (only after a widget tap), and building it eagerly would
      // spin up the notification service on every app launch.
      return (taps) async {
        final toggleTodo = ref.read(toggleTodoProvider);
        for (final tap in taps) {
          if (tap.action == 'complete') {
            await toggleTodo(id: tap.todoId, isCompleted: true);
          }
        }
      };
    });

// Every mutation path (providers, edit pages, drag-resize) writes through
// Drift, so listening to todos/events table updates is the single choke
// point that covers all of them — sprinkling calls across mutation exits
// would silently miss future write sites. tableUpdates only fires on
// writes, so initial query loads never trigger a refresh; consecutive
// writes coalesce into one trailing refresh instead of a platform-channel
// storm. The upcoming bucket reads the same two tables at snapshot build
// time, so this listener covers it too; pendingTaps consumption rides
// along inside every flush (updateWidget consumes before writing).
final homeWidgetAutoRefreshProvider = Provider<void>((ref) {
  final db = ref.watch(databaseProvider);
  final onPendingTaps = ref.read(consumeWidgetPendingTapsProvider);
  var running = false;
  var queued = false;

  Future<void> refresh() async {
    if (running) {
      queued = true;
      return;
    }
    running = true;
    try {
      do {
        queued = false;
        await HomeWidgetService.updateWidget(db, onPendingTaps: onPendingTaps);
      } while (queued);
    } finally {
      running = false;
    }
  }

  final subscription = db
      .tableUpdates(
        TableUpdateQuery.allOf([
          TableUpdateQuery.onTable(db.todos),
          TableUpdateQuery.onTable(db.events),
        ]),
      )
      .listen((_) => unawaited(refresh()));
  ref.onDispose(subscription.cancel);
});
