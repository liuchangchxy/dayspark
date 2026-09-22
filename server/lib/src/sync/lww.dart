// LWW ruling (Task 3, reconciled from the brief's 协议实现要点):
//
// - Field-level upsert: incoming op's fields always win for the keys they
//   SET (op arrival order is server order — no per-field timestamps exist in
//   this data model); keys the op does not set keep the server's values;
//   rev+1, server_ts=now, status 'applied' with the merged serverRecord.
//   baseRev equality takes the same merge path — clients send dirty fields
//   only, so "apply all fields" and per-field merge converge.
// - Delete-vs-upsert (record currently a tombstone): compare the tombstone's
//   server_ts against the op's server-assigned opTs (server receive time,
//   client clocks never participate). Second granularity: tombstone later →
//   conflict; op later → apply (resurrect); same second → incoming opId wins
//   the lexicographic tie iff it is strictly greater than the opId that last
//   wrote the record (stored as records.last_op_id), else conflict.
// - Delete ops always apply by arrival (tombstone, server_ts=now).

enum TombstoneUpsertDecision { apply, conflict }

DateTime truncateToSecond(DateTime value) {
  final utc = value.toUtc();
  return DateTime.utc(
    utc.year,
    utc.month,
    utc.day,
    utc.hour,
    utc.minute,
    utc.second,
  );
}

TombstoneUpsertDecision decideTombstoneVsUpsert({
  required DateTime recordServerTs,
  required DateTime opTs,
  required String recordLastOpId,
  required String incomingOpId,
}) {
  final recordSecond = truncateToSecond(recordServerTs);
  final opSecond = truncateToSecond(opTs);
  if (recordSecond.isAfter(opSecond)) {
    return TombstoneUpsertDecision.conflict;
  }
  if (recordSecond.isBefore(opSecond)) {
    return TombstoneUpsertDecision.apply;
  }
  return incomingOpId.compareTo(recordLastOpId) > 0
      ? TombstoneUpsertDecision.apply
      : TombstoneUpsertDecision.conflict;
}

Map<String, dynamic> mergeFields(
  Map<String, dynamic> current,
  Map<String, dynamic>? fields,
) {
  final merged = Map<String, dynamic>.from(current);
  if (fields != null) {
    merged.addAll(fields);
  }
  return merged;
}
