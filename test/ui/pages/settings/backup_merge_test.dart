import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/services/backup_service.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // The schema seeds one calendar with id 1.
  });

  tearDown(() async {
    await db.close();
  });

  Map<String, dynamic> backup() => {
        'version': 1,
        'calendars': [
          {
            'id': 1,
            'name': 'Work',
            'color': '#4f7bbf',
            'timezone': 'UTC',
            'isActive': true,
            'sortOrder': 0,
            'syncId': null,
          },
        ],
        'events': <Object>[],
        'todos': <Object>[],
        'reminders': <Object>[],
        'tags': <Object>[],
        'eventTags': <Object>[],
        'todoTags': <Object>[],
        'attachments': <Object>[],
      };

  test('merge keeps both calendars instead of inventing a field merge', () async {
    // The backup's id-1 calendar collides with the seeded local one.
    await BackupService(db).restoreFromJson(
      jsonEncode(backup()),
      resolutions: {'calendars:1': BackupConflictResolution.merge},
    );

    final calendars = await db.select(db.calendars).get();
    expect(calendars.map((c) => c.name), containsAll(['Personal', 'Work']));
    final imported = calendars.firstWhere((c) => c.name == 'Work');
    // The copy is local-only: a merge never pretends two rows share one
    // remote identity.
    expect(imported.syncId, isNull);
  });

  test('keep local skips the conflicting backup row', () async {
    await BackupService(db).restoreFromJson(
      jsonEncode(backup()),
      resolutions: {'calendars:1': BackupConflictResolution.keepLocal},
    );

    final calendars = await db.select(db.calendars).get();
    expect(calendars.map((c) => c.name), ['Personal']);
  });
}
