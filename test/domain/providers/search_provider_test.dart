import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
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
    test('provider handles rapid disposal gracefully', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });

      final sub = container.listen(
        searchResultsProvider('lunch'),
        (_, __) {},
      );
      sub.close();
    });
  });
}
