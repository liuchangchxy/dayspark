import 'dart:convert';

import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:drift/drift.dart' show Value;

import '../db.dart';

Future<SyncOp?> findSyncOp(AppDatabase db, String opId) =>
    (db.select(db.syncOps)..where((t) => t.opId.equals(opId)))
        .getSingleOrNull();

// Replays return the OpResult stored at FIRST processing — including its
// original status — so a client retry always gets the same answer.
OpResult decodeStoredOpResult(SyncOp row) =>
    OpResult.fromJson(jsonDecode(row.resultJson) as Map<String, dynamic>);

Future<void> storeOpResult(
  AppDatabase db, {
  required String opId,
  required String userId,
  required OpResult result,
  String deviceId = '',
}) {
  return db
      .into(db.syncOps)
      .insert(
        SyncOpsCompanion.insert(
          opId: opId,
          userId: userId,
          // Empty for internal (MCP / migration) writes - they have no device.
          deviceId: Value(deviceId),
          resultJson: jsonEncode(result.toJson()),
          createdAt: DateTime.now().toUtc(),
        ),
      );
}
