import 'package:drift/drift.dart';

@DataClassName('Tag')
class Tags extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 50)();
  TextColumn get color => text().withDefault(const Constant('#6B7280'))();
  TextColumn get syncId => text().nullable()();
  IntColumn get serverRev => integer().withDefault(const Constant(0))();
}
