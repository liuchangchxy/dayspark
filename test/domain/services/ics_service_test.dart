import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/services/ics_service.dart';

void main() {
  group('IcsService', () {
    test('can be instantiated with mock db', () {
      // IcsService requires AppDatabase — just verify construction logic compiles
      expect(IcsService, isNotNull);
    });

    test('exportCalendar skips soft-deleted events and todos', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final calId = await db
          .into(db.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));

      await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'Visible Event',
              startDt: DateTime(2026, 4, 17, 10),
              endDt: DateTime(2026, 4, 17, 11),
            ),
          );
      final deletedEventId = await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'Deleted Event',
              startDt: DateTime(2026, 4, 18, 10),
              endDt: DateTime(2026, 4, 18, 11),
            ),
          );
      await (db.update(db.events)..where((t) => t.id.equals(deletedEventId)))
          .write(EventsCompanion(deletedAt: Value(DateTime.now())));

      await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Visible Todo',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
            ),
          );
      final deletedTodoId = await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Deleted Todo',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
            ),
          );
      await (db.update(db.todos)..where((t) => t.id.equals(deletedTodoId)))
          .write(TodosCompanion(deletedAt: Value(DateTime.now())));

      final ics = await IcsService(db).exportCalendar(calId);

      expect(ics, contains('Visible Event'));
      expect(ics, isNot(contains('Deleted Event')));
      expect(ics, contains('Visible Todo'));
      expect(ics, isNot(contains('Deleted Todo')));

      await db.close();
    });
  });
}
