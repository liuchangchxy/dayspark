// Device registration contract.
//
// The client mints a stable `deviceId` per install and reports it; the server
// keeps one row per device so ops can be attributed and, later, a wake-up
// channel can be addressed per device.

T _requireField<T>(Map<String, dynamic> json, String field) {
  if (!json.containsKey(field)) {
    throw FormatException('missing required field: $field');
  }
  final value = json[field];
  if (value is! T) {
    throw FormatException('invalid field: $field');
  }
  return value;
}

DateTime _parseUtcDateTime(Object value, String field) {
  if (value is! String) {
    throw FormatException('invalid field: $field');
  }
  try {
    return DateTime.parse(value).toUtc();
  } on FormatException {
    throw FormatException('invalid field: $field');
  }
}

class DeviceDto {
  const DeviceDto({
    required this.deviceId,
    required this.lastSeen,
    this.name,
  });

  factory DeviceDto.fromJson(Map<String, dynamic> json) => DeviceDto(
        deviceId: _requireField<String>(json, 'deviceId'),
        name: json['name'] as String?,
        // _requireField first: handing a missing key straight to a
        // non-nullable Object parameter throws a raw _TypeError, not the
        // FormatException this package promises callers.
        lastSeen: _parseUtcDateTime(
          _requireField<String>(json, 'lastSeen'),
          'lastSeen',
        ),
      );

  final String deviceId;
  final String? name;
  final DateTime lastSeen;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'deviceId': deviceId,
        'name': name,
        'lastSeen': lastSeen.toUtc().toIso8601String(),
      };
}

class DeviceListResponse {
  const DeviceListResponse({required this.devices});

  factory DeviceListResponse.fromJson(Map<String, dynamic> json) {
    final list = _requireField<List<Object?>>(json, 'devices');
    return DeviceListResponse(
      devices: [
        for (final item in list)
          DeviceDto.fromJson(Map<String, dynamic>.from(item! as Map)),
      ],
    );
  }

  final List<DeviceDto> devices;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'devices': [for (final d in devices) d.toJson()],
      };
}
