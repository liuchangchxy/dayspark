import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/data/local/database/connect_flutter.dart';

/// Single owner of the database close.
///
/// Provider disposal and the macOS exit request both call [close]; memoizing
/// the future makes whichever runs second await the same close instead of
/// starting another one.
final class DatabaseShutdown {
  DatabaseShutdown(this._close);

  final Future<void> Function() _close;
  Future<void>? _closing;

  Future<void> close() => _closing ??= _close();
}

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.forExecutor(openFlutterDatabase());
  _ensureDefaultCalendar(db);
  return db;
});

final databaseShutdownProvider = Provider<DatabaseShutdown>((ref) {
  final shutdown = DatabaseShutdown(ref.watch(databaseProvider).close);
  ref.onDispose(shutdown.close);
  return shutdown;
});

void _ensureDefaultCalendar(AppDatabase db) {
  // Fire-and-forget: check async and insert if empty
  (() async {
    try {
      final calendars = await (db.select(db.calendars)).get();
      if (calendars.isEmpty) {
        await db
            .into(db.calendars)
            .insert(
              CalendarsCompanion.insert(
                name: 'Personal',
                color: const Value('#5F7183'),
              ),
            );
      }
    } catch (e) {
      debugPrint('database_provider: seed error: $e');
    }
  })();
}
