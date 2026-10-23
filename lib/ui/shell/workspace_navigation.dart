import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/domain/providers/default_tab_provider.dart';

/// The live workspace tab, as opposed to [defaultTabProvider] which is the
/// persisted launch preference. Secondary pages (Settings, Search, a pushed
/// detail) read this to keep the desktop sidebar highlighting the destination
/// the user actually came from, and to name the tab they are returning to.
final workspaceTabProvider = StateProvider<AppTab>((ref) => AppTab.action);

/// Which list the Todo destination is showing. Today and Inbox are views of
/// Todo, not destinations of their own, so the sidebar selects a tab *and* a
/// view — one place owns both, and the sidebar can drive them from anywhere.
sealed class TodosView {
  const TodosView();
}

/// A single day's list. `date == null` is not a case here: that is [TodosInbox].
class TodosDayView extends TodosView {
  const TodosDayView(this.date);

  final DateTime date;

  DateTime get day => DateTime(date.year, date.month, date.day);
}

/// Undated todos.
class TodosInboxView extends TodosView {
  const TodosInboxView();
}

/// Every pending todo, regardless of date.
class TodosAllView extends TodosView {
  const TodosAllView();
}

final todosViewProvider = StateProvider<TodosView>((ref) {
  final now = DateTime.now();
  return TodosDayView(DateTime(now.year, now.month, now.day));
});
