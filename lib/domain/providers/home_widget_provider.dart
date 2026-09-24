import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/record_bus_provider.dart';
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

// Lands widget-checkbox taps through the normal complete path
// (`toggleTodoProvider`): reminder cancellation, `markComplete`, and the
// sync outbox enqueue all stay in one place — the widget never gets a
// second write path into the database.
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

// The record bus is the single choke point for migrated writes: published
// after commit, so a refresh never sees pre-commit rows, and one
// transaction batch collapses into one trailing refresh instead of a
// platform-channel storm. Batch contents are ignored on purpose — the
// snapshot is a full recompute from the two tables, and the upcoming bucket
// reads the same tables at build time. Only in-process seam writes reach the
// bus, so home_page also refreshes on resume and the cold-start snapshot;
// pendingTaps consumption rides along inside every flush (updateWidget
// consumes before writing).
final homeWidgetAutoRefreshProvider = Provider<void>((ref) {
  final db = ref.watch(databaseProvider);
  final bus = ref.watch(recordBusProvider);
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

  final subscription = bus.changes.listen((_) => unawaited(refresh()));
  ref.onDispose(subscription.cancel);
});
