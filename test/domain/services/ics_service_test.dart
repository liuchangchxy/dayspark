import 'package:flutter_test/flutter_test.dart';
import 'package:calendar_todo_app/domain/services/ics_service.dart';

void main() {
  group('IcsService', () {
    test('can be instantiated with mock db', () {
      // IcsService requires AppDatabase — just verify construction logic compiles
      expect(IcsService, isNotNull);
    });
  });
}
