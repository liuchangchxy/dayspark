import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';

class SearchResults {
  final List<Event> events;
  final List<Todo> todos;
  final bool hasMoreEvents;
  final bool hasMoreTodos;

  SearchResults(
    this.events,
    this.todos, {
    this.hasMoreEvents = false,
    this.hasMoreTodos = false,
  });

  bool get isEmpty => events.isEmpty && todos.isEmpty;
  bool get hasMore => hasMoreEvents || hasMoreTodos;
}

const int kSearchPageSize = 50;

class SearchQueryState {
  final String query;
  final int eventPage;
  final int todoPage;

  const SearchQueryState({
    required this.query,
    this.eventPage = 1,
    this.todoPage = 1,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchQueryState &&
          runtimeType == other.runtimeType &&
          query == other.query &&
          eventPage == other.eventPage &&
          todoPage == other.todoPage;

  @override
  int get hashCode => Object.hash(query, eventPage, todoPage);
}

final searchResultsProvider =
    FutureProvider.autoDispose.family<SearchResults, String>((
      ref,
      query,
    ) async {
      if (query.trim().isEmpty) return SearchResults([], []);
      var disposed = false;
      ref.onDispose(() => disposed = true);
      if (disposed) return SearchResults([], []);
      if (ref.state.hasError && ref.state.error != null) {
        return SearchResults([], []);
      }
      final db = ref.read(databaseProvider);
      final events = await db.eventsDao.searchEvents(
        query.trim(),
        limit: kSearchPageSize + 1,
      );
      final todos = await db.todosDao.searchTodos(
        query.trim(),
        limit: kSearchPageSize + 1,
      );
      final hasMoreEvents = events.length > kSearchPageSize;
      final hasMoreTodos = todos.length > kSearchPageSize;
      return SearchResults(
        hasMoreEvents ? events.sublist(0, kSearchPageSize) : events,
        hasMoreTodos ? todos.sublist(0, kSearchPageSize) : todos,
        hasMoreEvents: hasMoreEvents,
        hasMoreTodos: hasMoreTodos,
      );
    });

final pagedSearchResultsProvider =
    FutureProvider.autoDispose.family<SearchResults, SearchQueryState>((
      ref,
      state,
    ) async {
      if (state.query.trim().isEmpty) return SearchResults([], []);
      // If someone overridden searchResultsProvider, delegate to it for page 1
      if (state.eventPage == 1 && state.todoPage == 1) {
        return ref.watch(searchResultsProvider(state.query).future);
      }
      var disposed = false;
      ref.onDispose(() => disposed = true);
      if (disposed) return SearchResults([], []);
      if (ref.state.hasError && ref.state.error != null) {
        return SearchResults([], []);
      }
      final db = ref.read(databaseProvider);
      final eventLimit = state.eventPage * kSearchPageSize;
      final todoLimit = state.todoPage * kSearchPageSize;
      final events = await db.eventsDao.searchEvents(
        state.query.trim(),
        limit: eventLimit + 1,
      );
      final todos = await db.todosDao.searchTodos(
        state.query.trim(),
        limit: todoLimit + 1,
      );
      final hasMoreEvents = events.length > eventLimit;
      final hasMoreTodos = todos.length > todoLimit;
      return SearchResults(
        hasMoreEvents ? events.sublist(0, eventLimit) : events,
        hasMoreTodos ? todos.sublist(0, todoLimit) : todos,
        hasMoreEvents: hasMoreEvents,
        hasMoreTodos: hasMoreTodos,
      );
    });
