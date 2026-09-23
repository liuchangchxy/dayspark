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
  // OAuth-track rows carry the issuing client and the granted scope;
  // /auth login rows keep both null (CLI/device session track).
  TextColumn get clientId => text().nullable()();
  TextColumn get scope => text().nullable()();
  DateTimeColumn get expiresAt => dateTime()();
  DateTimeColumn get revokedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('OauthClient')
class OauthClients extends Table {
  TextColumn get id => text()();
  TextColumn get clientSecretHash => text().nullable()();
  TextColumn get clientName => text()();
  TextColumn get redirectUris => text()();
  TextColumn get authMethod => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('OauthCode')
class OauthCodes extends Table {
  TextColumn get codeHash => text()();
  TextColumn get clientId => text()();
  TextColumn get userId => text()();
  TextColumn get redirectUri => text()();
  TextColumn get codeChallenge => text()();
  TextColumn get scopes => text()();
  DateTimeColumn get expiresAt => dateTime()();
  DateTimeColumn get usedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {codeHash};
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
  // Per-write sequence in the user's monotonic change feed; pull and
  // piggyback both page on seq > cursor.
  IntColumn get seq => integer().withDefault(Constant(0))();
  // Op that last wrote this record — the tombstone side of the same-second
  // opId lexicographic tie-break in LWW.
  TextColumn get lastOpId => text().withDefault(Constant(''))();

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
