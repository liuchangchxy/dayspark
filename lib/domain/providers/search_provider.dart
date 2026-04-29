import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';

class SearchResults {
  final List<Event> events;
  final List<Todo> todos;
  SearchResults(this.events, this.todos);
  bool get isEmpty => events.isEmpty && todos.isEmpty;
}

final searchResultsProvider = FutureProvider.family<SearchResults, String>((
  ref,
  query,
) async {
  if (query.trim().isEmpty) return SearchResults([], []);
  // Debounce: wait 300ms before executing the query
  await Future.delayed(const Duration(milliseconds: 300));
  if (ref.state.hasError && ref.state.error != null)
    return SearchResults([], []);
  final db = ref.read(databaseProvider);
  final events = await db.eventsDao.searchEvents(query.trim());
  final todos = await db.todosDao.searchTodos(query.trim());
  return SearchResults(events, todos);
});
