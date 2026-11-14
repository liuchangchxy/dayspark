// Re-exported from dayspark_contracts so the client-side cloud transport and
// the DaySpark server run the exact same arbitration rules (see the file's
// header for the ruling and for why it is shared).
export 'package:dayspark_contracts/dayspark_contracts.dart'
    show
        TombstoneUpsertDecision,
        decideTombstoneVsUpsert,
        mergeFields,
        truncateToSecond;
