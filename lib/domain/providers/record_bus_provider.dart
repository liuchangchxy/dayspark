import 'dart:async';

import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/locale_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/domain/records/record_bus.dart';
import 'package:dayspark/domain/records/reminder_reconciler.dart';
import 'package:flutter/material.dart' show Locale;
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

  // 通知是「字典之外的出口」：文案在排期时写死进 OS，UI 层任何 i18n 检查都
  // 看不见它。locale 一变就交给重排器判断要不要重排——判据是「上次排期实际
  // 用的语言」，所以这里不需要关心自己是先于还是后于 localeProvider.load()。
  ref.listen<Locale?>(localeProvider, (previous, next) {
    if (previous == next) return;
    unawaited(reconciler.onLocaleChanged());
  });
  return reconciler;
});
