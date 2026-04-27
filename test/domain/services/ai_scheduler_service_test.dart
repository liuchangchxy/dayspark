import 'package:flutter_test/flutter_test.dart';
import 'package:calendar_todo_app/domain/services/ai_scheduler_service.dart';

void main() {
  group('AiSchedulerService', () {
    test('can be instantiated', () {
      final service = AiSchedulerService();
      expect(service, isNotNull);
    });
  });
}
