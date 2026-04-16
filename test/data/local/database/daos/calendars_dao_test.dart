import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calendar_todo_app/data/local/database/app_database.dart';

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
      await db.into(db.calendars).insert(
            CalendarsCompanion.insert(
              caldavHref: '/cal/1',
              name: 'Work',
              color: const Value('#2563EB'),
              timezone: const Value('Asia/Shanghai'),
            ),
          );
      await db.into(db.calendars).insert(
            CalendarsCompanion.insert(
              caldavHref: '/cal/2',
              name: 'Personal',
              color: const Value('#16A34A'),
              timezone: const Value('UTC'),
            ),
          );

      final calendars = await db.calendarsDao.watchAll().first;
      expect(calendars.length, 2);
      expect(calendars[0].name, 'Work');
      expect(calendars[1].name, 'Personal');
    });

    test('getById returns single calendar', () async {
      final id = await db.into(db.calendars).insert(
            CalendarsCompanion.insert(
              caldavHref: '/cal/x',
              name: 'Test',
              color: const Value('#000'),
              timezone: const Value('UTC'),
            ),
          );
      final cal = await db.calendarsDao.getById(id);
      expect(cal?.name, 'Test');
    });

    test('getById returns null for non-existent id', () async {
      final cal = await db.calendarsDao.getById(9999);
      expect(cal, isNull);
    });

    test('setActive toggles active status', () async {
      final id = await db.into(db.calendars).insert(
            CalendarsCompanion.insert(
              caldavHref: '/cal/',
              name: 'Test',
              color: const Value('#000'),
              timezone: const Value('UTC'),
            ),
          );
      await db.calendarsDao.setActive(id, false);
      final cal = await db.calendarsDao.getById(id);
      expect(cal?.isActive, false);
    });
  });
}
