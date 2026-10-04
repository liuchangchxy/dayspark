export 'src/device_dto.dart' show DeviceDto, DeviceListResponse;
export 'src/errors.dart';
export 'src/record_dto.dart'
    show
        RecordType,
        RecordTypeWireName,
        recordTypeFromJson,
        SyncRecord,
        TaskAllocationPayload,
        TaskAllocationState,
        TaskAllocationStateWireName;
export 'src/sync_api.dart'
    show
        OpResult,
        OpStatus,
        OpType,
        PushOp,
        PushRequest,
        PushResponse,
        PullResponse,
        SyncCapability,
        SyncCapabilitiesResponse;

// Unknown JSON keys are ignored on purpose: newer server/app versions can add
// fields without breaking older peers (forward compatibility).
