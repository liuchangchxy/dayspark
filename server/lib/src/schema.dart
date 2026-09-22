import 'package:drift/drift.dart';

@DataClassName('User')
class Users extends Table {
  TextColumn get id => text()();
  TextColumn get email => text().unique()();
  TextColumn get passwordHash => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('RefreshToken')
class RefreshTokens extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get tokenHash => text().unique()();
  TextColumn get familyId => text()();
  DateTimeColumn get expiresAt => dateTime()();
  DateTimeColumn get revokedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Device')
class Devices extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get deviceId => text().unique()();
  TextColumn get name => text().nullable()();
  DateTimeColumn get lastSeen => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

// Data class is RecordRow, not Record: Dart 3's built-in Record type would
// otherwise collide in generated code and in every importing library.
@DataClassName('RecordRow')
class Records extends Table {
  TextColumn get userId => text()();
  TextColumn get id => text()();
  TextColumn get type => text()();
  TextColumn get payloadJson => text()();
  IntColumn get rev => integer()();
  BoolColumn get deleted => boolean()();
  DateTimeColumn get serverTs => dateTime()();

  @override
  Set<Column> get primaryKey => {userId, id};
}

@DataClassName('SyncOp')
class SyncOps extends Table {
  TextColumn get opId => text()();
  TextColumn get userId => text()();
  TextColumn get resultJson => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {opId};
}

@DataClassName('Revision')
class Revisions extends Table {
  TextColumn get userId => text()();
  IntColumn get seq => integer()();

  @override
  Set<Column> get primaryKey => {userId};
}
