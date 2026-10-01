import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:shelf_router/shelf_router.dart';

import '../auth.dart';
import '../db.dart';
import '../http.dart';

/// Device registration and listing.
///
/// Why this exists at all: the client has minted and persisted a `deviceId`
/// since P2, and the push request body has carried it — but nothing on the
/// server ever wrote it down, so the `devices` table stayed empty and
/// `AuthContext.deviceId` (read from the `x-device-id` header) was always
/// unbound. With a device row we can (a) attribute ops to a device, (b) show
/// the user which devices are connected, and (c) later address a wake-up
/// channel per device.
void registerDeviceRoutes(
  Router router, {
  required AppDatabase db,
  required Auth auth,
}) {
  router.post('/devices/register', auth.requireAuth((request, context) async {
    final body = await readJsonObject(request);
    final deviceId = body['deviceId'];
    if (deviceId is! String || deviceId.isEmpty) {
      throw ApiException(400, errValidation, 'deviceId is required');
    }
    final name = body['name'];
    if (name != null && name is! String) {
      throw ApiException(400, errValidation, 'name must be a string');
    }

    final userId = context.userId;
    final now = DateTime.now().toUtc();

    final existing =
        await (db.select(db.devices)..where((t) => t.deviceId.equals(deviceId)))
            .getSingleOrNull();

    if (existing != null && existing.userId != userId) {
      // A device id is minted per install and never reassigned. Rebinding it
      // silently would let one account claim another's device row — and once a
      // wake-up channel hangs off this row, that row is worth stealing.
      throw ApiException(
        409,
        errConflict,
        'deviceId is already bound to another account',
      );
    }

    if (existing == null) {
      await db.into(db.devices).insert(
            DevicesCompanion.insert(
              id: newId(),
              userId: userId,
              deviceId: deviceId,
              name: Value(name as String?),
              lastSeen: now,
            ),
          );
    } else {
      await (db.update(db.devices)..where((t) => t.deviceId.equals(deviceId)))
          .write(
        DevicesCompanion(
          // Absent name keeps the stored one: a plain re-register on cold start
          // must not wipe a name the user set earlier.
          name: name == null ? const Value.absent() : Value(name),
          lastSeen: Value(now),
        ),
      );
    }

    // Serialized through the shared DTO so both sides literally cannot drift.
    return jsonResponse(
      200,
      DeviceDto(deviceId: deviceId, name: name, lastSeen: now).toJson(),
    );
  }));

  router.get('/devices', auth.requireAuth((request, context) async {
    final rows = await (db.select(db.devices)
          ..where((t) => t.userId.equals(context.userId))
          ..orderBy([(t) => OrderingTerm.desc(t.lastSeen)]))
        .get();
    return jsonResponse(
      200,
      DeviceListResponse(
        devices: [
          for (final row in rows)
            DeviceDto(
              deviceId: row.deviceId,
              name: row.name,
              lastSeen: row.lastSeen.toUtc(),
            ),
        ],
      ).toJson(),
    );
  }));
}
