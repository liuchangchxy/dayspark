import 'dart:async';

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/infrastructure/platform/home_widget_service.dart';

final updateHomeWidgetProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    final db = ref.read(databaseProvider);
    await HomeWidgetService.updateWidget(db);
  };
});

// Every mutation path (providers, edit pages, drag-resize) writes through
// Drift, so listening to todos/events table updates is the single choke
// point that covers all of them — sprinkling calls across mutation exits
// would silently miss future write sites. tableUpdates only fires on
// writes, so initial query loads never trigger a refresh; consecutive
// writes coalesce into one trailing refresh instead of a platform-channel
// storm.
final homeWidgetAutoRefreshProvider = Provider<void>((ref) {
  final db = ref.watch(databaseProvider);
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
        await HomeWidgetService.updateWidget(db);
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
