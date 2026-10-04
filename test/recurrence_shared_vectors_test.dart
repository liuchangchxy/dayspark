import 'package:dayspark_recurrence/dayspark_recurrence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import '../packages/dayspark_recurrence/test/shared_vectors.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  test('client output matches the shared recurrence golden vectors', () {
    const engine = RecurrenceEngine();
    for (final vector in recurrenceParityVectors()) {
      final occurrences = engine.expand(
        vector.spec,
        window: vector.window,
        limit: 100,
      );
      expect(
        occurrences.map(describeOccurrence).toList(),
        vector.expected,
        reason: vector.name,
      );
    }
  });
}
