import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/domain/sync/sync_payload.dart';

void main() {
  test('sync timestamps serialize as canonical UTC ISO-8601', () {
    final local = DateTime(2026, 10, 4, 9, 30);

    final serialized = isoOf(local);

    expect(serialized, local.toUtc().toIso8601String());
    expect(serialized, endsWith('Z'));
  });
}
