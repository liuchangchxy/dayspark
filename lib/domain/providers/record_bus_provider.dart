import 'dart:async';

import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/domain/records/record_bus.dart';
import 'package:dayspark/domain/records/reminder_reconciler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final recordBusProvider = Provider<RecordBus>(
  (ref) => RecordBus.of(ref.watch(databaseProvider)),
);

final reminderReconcilerProvider = Provider<ReminderReconciler>((ref) {
  final reconciler = ReminderReconciler(
    db: ref.watch(databaseProvider),
    notifications: ref.watch(notificationServiceProvider),
  );
  // Cold start: the only fallback for writers the bus cannot see (an external
  // process opening the same database file) — the sweep is idempotent and
  // conservative, so replaying it on every launch is safe.
  unawaited(reconciler.reconcileAll());
  // Batches and the resume recompute share one serial queue inside the
  // reconciler, so an interleaved pair can never diff a parent twice.
  final subscription = ref.watch(recordBusProvider).changes.listen((batch) {
    unawaited(reconciler.handle(batch));
  });
  ref.onDispose(subscription.cancel);
  return reconciler;
});
