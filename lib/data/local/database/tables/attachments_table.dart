import 'package:drift/drift.dart';

@DataClassName('Attachment')
class Attachments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get parentType => text()();
  IntColumn get parentId => integer()();
  TextColumn get filePath => text()();
  TextColumn get fileName => text()();
  IntColumn get fileSize => integer().withDefault(const Constant(0))();
  TextColumn get mimeType => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
