import 'package:drift/drift.dart';

import 'todos_table.dart';
import 'tags_table.dart';

@DataClassName('TodoTag')
class TodoTags extends Table {
  IntColumn get todoId => integer().references(Todos, #id)();
  IntColumn get tagId => integer().references(Tags, #id)();
  TextColumn get syncId => text().nullable()();
  IntColumn get serverRev => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {todoId, tagId};
}
