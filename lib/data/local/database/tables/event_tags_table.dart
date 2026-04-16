import 'package:drift/drift.dart';

import 'events_table.dart';
import 'tags_table.dart';

@DataClassName('EventTag')
class EventTags extends Table {
  IntColumn get eventId => integer().references(Events, #id)();
  IntColumn get tagId => integer().references(Tags, #id)();

  @override
  Set<Column> get primaryKey => {eventId, tagId};
}
