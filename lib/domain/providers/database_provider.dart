import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/data/local/database/app_database.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());

  // Ensure a default calendar exists for existing installs where onCreate didn't seed
  _ensureDefaultCalendar(db);

  return db;
});

void _ensureDefaultCalendar(AppDatabase db) {
  // Fire-and-forget: check async and insert if empty
  (() async {
    try {
      final calendars = await (db.select(db.calendars)).get();
      if (calendars.isEmpty) {
        await db.into(db.calendars).insert(
              CalendarsCompanion.insert(
                caldavHref: 'local://default',
                name: 'Personal',
                color: const Value('#2563EB'),
              ),
            );
      }
    } catch (_) {}
  })();
}
