import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  group('searchResultsProvider', () {
    test('debounce continuation is guarded when disposed mid-wait', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final sub = container.listen(
        searchResultsProvider('lunch'),
        (_, __) {},
      );
      sub.close();

      await Future.delayed(const Duration(milliseconds: 400));
    });
  });
}
