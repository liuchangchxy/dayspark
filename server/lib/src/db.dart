import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'schema.dart';

part 'db.g.dart';

LazyDatabase openDatabase(String dbPath) {
  return LazyDatabase(() async {
    if (dbPath == ':memory:') {
      return NativeDatabase.memory();
    }
    final file = File(dbPath);
    await file.parent.create(recursive: true);
    return NativeDatabase(file);
  });
}

@DriftDatabase(
  tables: [Users, RefreshTokens, Devices, Records, SyncOps, Revisions],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(records, records.seq);
        await m.addColumn(records, records.lastOpId);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await _createSeqIndex();
    },
  );

  Future<void> _createSeqIndex() => customStatement(
    'CREATE INDEX IF NOT EXISTS records_user_seq_idx '
    'ON records (user_id, seq)',
  );

  // WHY takes an explicit [tx]: Task 3 must bump seq inside its push
  // transaction. Drift 2.x binds transactions to a Zone instead of passing a
  // Transaction handle, so any DatabaseConnectionUser issued inside the
  // caller's db.transaction block runs on that transaction. One
  // UPDATE...RETURNING statement then locks and increments atomically, and
  // SQLite's single-writer model keeps seq strictly monotonic per user.
  // A missing row bootstraps the user's cursor at seq 1.
  Future<int> nextSeq(DatabaseConnectionUser tx, String userId) async {
    final rows = await tx
        .customSelect(
          'UPDATE revisions SET seq = seq + 1 WHERE user_id = ? RETURNING seq',
          variables: [Variable.withString(userId)],
        )
        .get();
    if (rows.isNotEmpty) {
      return rows.first.read<int>('seq');
    }
    await tx
        .into(revisions)
        .insert(RevisionsCompanion.insert(userId: userId, seq: 1));
    return 1;
  }

  Future<int> nextSeqForUser(String userId) =>
      transaction(() => nextSeq(this, userId));
}
