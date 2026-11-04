import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/search_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';

/// Lets drift's broadcast stream and the provider rebuilds it triggers run
/// before the next read.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 100));

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
      // The answer now watches live todo/event queries, so the container needs
      // a database that can be opened without platform bindings.
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      final sub = container.listen(
        searchResultsProvider('lunch'),
        (_, __) {},
      );
      sub.close();
    });
  });

  group('search freshness', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('a todo edit and completion reach the open results', () async {
      final calId = await db
          .into(db.calendars)
          .insert(CalendarsCompanion.insert(name: 'Personal'));
      final todoId = await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(calendarId: calId, summary: 'Task one'),
          );
      final sub = container.listen(
        searchResultsProvider('Task'),
        (_, __) {},
      );
      addTearDown(sub.close);

      final before = await container
          .read(searchResultsProvider('Task').future);
      expect(before.todos.single.summary, 'Task one');
      expect(before.todos.single.status, 'NEEDS-ACTION');

      await container.read(updateTodoProvider)(
        todoId,
        const TodosCompanion(summary: Value('Task renamed')),
      );
      await _settle();
      final renamed = await container
          .read(searchResultsProvider('Task').future);
      expect(renamed.todos.single.summary, 'Task renamed');

      await container.read(toggleTodoProvider)(
        id: todoId,
        isCompleted: true,
      );
      await _settle();
      final completed = await container
          .read(searchResultsProvider('Task').future);
      expect(completed.todos.single.status, 'COMPLETED');
    });

    test('an event edit reaches the open results', () async {
      final calId = await db
          .into(db.calendars)
          .insert(CalendarsCompanion.insert(name: 'Personal'));
      final eventId = await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'Event one',
              startDt: DateTime(2026, 10, 5, 14),
              endDt: DateTime(2026, 10, 5, 15),
            ),
          );
      final sub = container.listen(
        searchResultsProvider('Event'),
        (_, __) {},
      );
      addTearDown(sub.close);

      final before = await container
          .read(searchResultsProvider('Event').future);
      expect(before.events.single.summary, 'Event one');

      await container.read(updateEventProvider)(
        eventId,
        const EventsCompanion(summary: Value('Event renamed')),
      );
      await _settle();
      final renamed = await container
          .read(searchResultsProvider('Event').future);
      expect(renamed.events.single.summary, 'Event renamed');
    });
  });
}
