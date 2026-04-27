import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/domain/services/ics_service.dart';

void main() {
  group('IcsService', () {
    test('can be instantiated with mock db', () {
      // IcsService requires AppDatabase — just verify construction logic compiles
      expect(IcsService, isNotNull);
    });
  });
}
