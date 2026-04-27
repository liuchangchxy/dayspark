import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/domain/providers/search_provider.dart';

void main() {
  group('SearchResults', () {
    test('creates with empty lists', () {
      final results = SearchResults([], []);
      expect(results.isEmpty, true);
      expect(results.events, isEmpty);
      expect(results.todos, isEmpty);
    });

    test('isEmpty is false when events exist', () {
      final results = SearchResults([], []);
      expect(results.isEmpty, true);
    });
  });
}
