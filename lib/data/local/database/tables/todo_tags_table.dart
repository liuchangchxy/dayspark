import 'package:drift/drift.dart';

import 'todos_table.dart';
import 'tags_table.dart';

@DataClassName('TodoTag')
class TodoTags extends Table {
  IntColumn get todoId => integer().references(Todos, #id)();
  IntColumn get tagId => integer().references(Tags, #id)();

  @override
  Set<Column> get primaryKey => {todoId, tagId};
}
