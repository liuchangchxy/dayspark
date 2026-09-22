import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/infrastructure/platform/notification_service.dart';

void main() {
  group('NotificationPayload', () {
    test('encode carries reminderId', () {
      const payload = NotificationPayload(
        parentType: 'todo',
        parentId: 7,
        reminderId: 42,
      );
      expect(payload.encode(), 'todo:7:42');
    });

    test('roundtrip preserves reminderId', () {
      const original = NotificationPayload(
        parentType: 'event',
        parentId: 3,
        reminderId: 99,
      );
      final parsed = NotificationPayload.tryParse(original.encode());
      expect(parsed, isNotNull);
      expect(parsed!.parentType, 'event');
      expect(parsed.parentId, 3);
      expect(parsed.reminderId, 99);
    });

    test('legacy two-part payload parses with null reminderId', () {
      final parsed = NotificationPayload.tryParse('todo:5');
      expect(parsed, isNotNull);
      expect(parsed!.parentId, 5);
      expect(parsed.reminderId, isNull);
    });

    test('rejects malformed payloads', () {
      expect(NotificationPayload.tryParse('todo'), isNull);
      expect(NotificationPayload.tryParse('todo:abc'), isNull);
      expect(NotificationPayload.tryParse(''), isNull);
    });

    test('encode without reminderId stays two-part', () {
      const payload = NotificationPayload(parentType: 'todo', parentId: 7);
      expect(payload.encode(), 'todo:7');
    });
  });
}
