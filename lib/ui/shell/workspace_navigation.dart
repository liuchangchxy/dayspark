import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/default_tab_provider.dart';

/// The live workspace tab, as opposed to [defaultTabProvider] which is the
/// persisted launch preference. Secondary pages (Settings, Search, a pushed
/// detail) read this to keep the desktop sidebar highlighting the destination
/// the user actually came from, and to name the tab they are returning to.
final workspaceTabProvider = NotifierProvider<WorkspaceTabNotifier, AppTab>(
  WorkspaceTabNotifier.new,
);

class WorkspaceTabNotifier extends Notifier<AppTab> {
  @override
  AppTab build() => AppTab.action;

  /// Changing destination closes the detail pane. Whatever it holds belongs to
  /// the view that opened it: a todo editor left open beside the month grid cut
  /// 400px off the calendar to describe something no longer on screen.
  void setTab(AppTab tab) {
    ref.read(workspaceSelectionProvider.notifier).state = null;
    state = tab;
  }
}

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

/// The object currently shown in the desktop detail pane.
///
/// Selection is a workspace concept, not a route: on a wide window a list tap
/// chooses a row instead of pushing a page, so the list stays visible next to
/// the detail. On narrow windows the same tap pushes a full page and this
/// provider is never read.
sealed class WorkspaceSelection {
  const WorkspaceSelection();
}

class TodoSelection extends WorkspaceSelection {
  const TodoSelection(this.todo);

  final Todo todo;
}

class EventSelection extends WorkspaceSelection {
  const EventSelection(this.event);

  final CalendaEventAdapter event;
}

final workspaceSelectionProvider = StateProvider<WorkspaceSelection?>(
  (ref) => null,
);

/// The desktop sidebar's calendar / tag rows filter the Todo destination in
/// place rather than opening a management page. Two providers, because the
/// design lets a calendar and a tag narrow the same list independently.
final todoCalendarFilterProvider = StateProvider<int?>((ref) => null);
final todoTagFilterProvider = StateProvider<Set<int>>((ref) => const {});
final todoPriorityFilterProvider = StateProvider<int?>((ref) => null);

/// The width at which a right-hand detail pane can sit beside a list without
/// squeezing either. Narrower desktops keep single-column navigation.
const double kMasterDetailBreakpoint = 1180;

bool isMasterDetailLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kMasterDetailBreakpoint;
