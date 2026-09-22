import 'package:drift/drift.dart';

/// Local mutation queue for the sync engine: one row per pending op.
///
/// Merge semantics (enforced by `SyncOutbox.enqueue*`, see
/// `lib/domain/sync/sync_outbox.dart`): rows for the same `recordId`
/// collapse into a single entry, so `recordId` is not unique here —
/// `opId` (UUIDv7, the server's idempotency key) is the primary key.
@DataClassName('SyncOutboxEntry')
class SyncOutbox extends Table {
  TextColumn get opId => text()();
  TextColumn get recordId => text()();
  TextColumn get type => text()();
  TextColumn get op => text()();
  TextColumn get payloadJson => text().nullable()();
  IntColumn get baseRev => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {opId};
}
