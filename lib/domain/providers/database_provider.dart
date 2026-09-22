import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/data/local/database/connect_flutter.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.forExecutor(openFlutterDatabase());
  ref.onDispose(() => db.close());

  _ensureDefaultCalendar(db);

  return db;
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
                color: const Value('#2563EB'),
              ),
            );
      }
    } catch (e) { debugPrint('database_provider: seed error: $e'); }
  })();
}
