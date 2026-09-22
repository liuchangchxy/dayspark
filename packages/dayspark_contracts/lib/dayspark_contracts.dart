export 'src/errors.dart';
export 'src/record_dto.dart' show RecordType, SyncRecord;
export 'src/sync_api.dart'
    show OpResult, OpStatus, OpType, PushOp, PushRequest, PushResponse, PullResponse;

// Unknown JSON keys are ignored on purpose: newer server/app versions can add
// fields without breaking older peers (forward compatibility).
