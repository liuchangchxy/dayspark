import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('CalendarsDao', () {
    test('watchAll returns stream of calendars', () async {
      await db
          .into(db.calendars)
          .insert(
            CalendarsCompanion.insert(
              caldavHref: '/cal/1',
              name: 'Work',
              color: const Value('#2563EB'),
              timezone: const Value('Asia/Shanghai'),
            ),
          );
      await db
          .into(db.calendars)
          .insert(
            CalendarsCompanion.insert(
              caldavHref: '/cal/2',
              name: 'Personal',
              color: const Value('#16A34A'),
              timezone: const Value('UTC'),
            ),
          );

      final calendars = await db.calendarsDao.watchAll().first;
      // 1 default seed + 2 manually inserted = 3
      expect(calendars.length, 3);
      expect(calendars.any((c) => c.name == 'Work'), true);
      expect(calendars.any((c) => c.name == 'Personal'), true);
    });
  });
}
