import 'dart:async';

import 'package:flutter/widgets.dart' show EditableTextState, FocusManager;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/record_bus_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/infrastructure/platform/home_widget_service.dart';
import 'package:dayspark/infrastructure/platform/widget_refresh_scheduler.dart';

final updateHomeWidgetProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    final db = ref.read(databaseProvider);
    final toggleTodo = ref.read(toggleTodoProvider);
    await HomeWidgetService.updateWidget(
      db,
      toggleTodo: toggleTodo,
      onLegacyPendingTaps: ref.read(consumeWidgetPendingTapsProvider),
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
            try {
              await toggleTodo(id: tap.todoId, isCompleted: true);
            } on StateError {
              continue;
            }
          }
        }
      };
    });

// The record bus is the single choke point for migrated writes: published
// after commit, so a refresh never sees pre-commit rows. Batch contents are
// ignored on purpose — the snapshot is a full recompute.
//
// Timing is not immediate: a commit lands exactly when the next keystroke
// arrives, and a full rebuild (projection queries + JSON + platform writes +
// native RemoteViews) on that boundary stalls the IME. [WidgetRefreshScheduler]
// coalesces bursts, holds the rebuild while a field owns focus, and caps the
// hold so widgets still refresh during a long typing session.
final homeWidgetAutoRefreshProvider = Provider<void>((ref) {
  final db = ref.watch(databaseProvider);
  final bus = ref.watch(recordBusProvider);
  final onLegacyPendingTaps = ref.read(consumeWidgetPendingTapsProvider);

  Future<void> refresh() async {
    final toggleTodo = ref.read(toggleTodoProvider);
    await HomeWidgetService.updateWidget(
      db,
      toggleTodo: toggleTodo,
      onLegacyPendingTaps: onLegacyPendingTaps,
    );
  }

  final scheduler = WidgetRefreshScheduler(
    onRun: refresh,
    isEditing: _hasEditingFocus,
  );
  final subscription = bus.changes.listen((_) => scheduler.request());
  ref.onDispose(() {
    subscription.cancel();
    scheduler.dispose();
  });
});

/// True while a text field owns the focus — i.e. the IME is live and the next
/// keystroke is inbound.
bool _hasEditingFocus() {
  final focus = FocusManager.instance.primaryFocus;
  return focus?.context?.findAncestorStateOfType<EditableTextState>() != null;
}
