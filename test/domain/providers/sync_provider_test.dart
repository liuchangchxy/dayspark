import 'package:flutter_test/flutter_test.dart';
import 'package:calendar_todo_app/data/remote/caldav/sync_service.dart';

void main() {
  group('SyncStatus', () {
    test('has all expected values', () {
      expect(SyncStatus.values, containsAll([
        SyncStatus.idle,
        SyncStatus.syncing,
        SyncStatus.success,
        SyncStatus.error,
      ]));
    });
  });
}
