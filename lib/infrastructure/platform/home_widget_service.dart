import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/core/utils/platform_target.dart';
import 'package:dayspark/core/theme/app_colors.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/action_projection_provider.dart';
import 'package:dayspark/domain/providers/locale_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/providers/theme_provider.dart';
import 'package:dayspark/domain/records/todo_occurrence.dart';
import 'package:dayspark/domain/services/action_projection_query.dart';
import 'package:dayspark/domain/utils/recurring_event_helper.dart';
import 'package:dayspark/infrastructure/platform/widget_command.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';

// Legacy v2 tap format kept strictly for backward-compatible migration.
class WidgetPendingTap {
  const WidgetPendingTap({
    required this.todoId,
    required this.action,
    required this.at,
  });

  final int todoId;
  final String action;
  final DateTime at;

  Map<String, Object?> toJson() => {
    'todoId': todoId,
    'action': action,
    'at': at.toUtc().toIso8601String(),
  };

  factory WidgetPendingTap.fromJson(Map<String, dynamic> json) {
    final todoId = json['todoId'];
    final action = json['action'];
    final at = json['at'];
    if (todoId is! int || action is! String) {
      throw FormatException('bad pendingTap: $json');
    }
    return WidgetPendingTap(
      todoId: todoId,
      action: action,
      at: at is String
          ? (DateTime.tryParse(at) ?? DateTime.now())
          : DateTime.now(),
    );
  }
}

// Pre-localized widget labels for the locale in effect at snapshot build time.
class WidgetUiStrings {
  const WidgetUiStrings({
    required this.locale,
    required this.today,
    required this.inbox,
    required this.all,
    required this.noTodos,
    required this.allTodosDone,
    required this.noPlans,
    required this.allPlansDone,
    required this.now,
    required this.later,
    required this.dueToday,
    required this.overdue,
    required this.completedCount,
    required this.moreCount,
    required this.overdueCount,
    required this.selectedDayEmpty,
    required this.backToMonth,
    required this.openToUpdate,
    required this.stale,
    required this.addTodo,
    required this.addEvent,
    required this.quickAddHint,
    required this.quickAddToday,
    required this.quickAddInbox,
    required this.save,
    required this.saveFailed,
    required this.allDay,
  });

  final String locale;
  final String today;
  final String inbox;
  final String all;
  final String noTodos;
  final String allTodosDone;
  final String noPlans;
  final String allPlansDone;
  final String now;
  final String later;
  final String dueToday;
  final String overdue;
  final String completedCount;
  final String moreCount;
  final String overdueCount;
  final String selectedDayEmpty;
  final String backToMonth;
  final String openToUpdate;
  final String stale;
  final String addTodo;
  final String addEvent;
  final String quickAddHint;
  final String quickAddToday;
  final String quickAddInbox;
  final String save;
  final String saveFailed;
  final String allDay;

  Map<String, Object?> toBlock() => {
    'locale': locale,
    'today': today,
    'inbox': inbox,
    'all': all,
    'noTodos': noTodos,
    'allTodosDone': allTodosDone,
    'noPlans': noPlans,
    'allPlansDone': allPlansDone,
    'now': now,
    'later': later,
    'dueToday': dueToday,
    'overdue': overdue,
    'completedCount': completedCount,
    'moreCount': moreCount,
    'overdueCount': overdueCount,
    'selectedDayEmpty': selectedDayEmpty,
    'backToMonth': backToMonth,
    'openToUpdate': openToUpdate,
    'stale': stale,
    'addTodo': addTodo,
    'addEvent': addEvent,
    'quickAddHint': quickAddHint,
    'quickAddToday': quickAddToday,
    'quickAddInbox': quickAddInbox,
    'save': save,
    'saveFailed': saveFailed,
    'allDay': allDay,
  };
}

class HomeWidgetService {
  static const String snapshotKey = 'widget_snapshot';
  static const int snapshotVersion = 5;

  static const String androidProviderName =
      'com.dayspark.app.TodayWidgetProvider';
  static const String androidMonthProviderName =
      'com.dayspark.app.CalendarWidgetProvider';
  static const String androidTodoProviderName =
      'com.dayspark.app.TodoWidgetProvider';

  static const List<String> appleWidgetKinds = [
    'CalendarTodoWidget',
    'CalendarMonthWidget',
    'CalendarTodosWidget',
  ];

  static const int _actionCap = 30;
  static const int _todosTodayCap = 30;
  static const int _todosInboxCap = 30;
  static const int _todosAllCap = 50;
  static const int _monthItemsCap = 8;

  /// Updates the authoritative v5 widget snapshot and drains pending commands.
  static Future<void> updateWidget(
    AppDatabase db, {
    DateTime? now,
    WidgetCommandTransport? commandTransport,
    ToggleTodoFunction? toggleTodo,
    Future<void> Function(List<WidgetPendingTap> taps)? onLegacyPendingTaps,
  }) async {
    if (!supportsHomeWidget) return;

    try {
      final effectiveNow = now ?? DateTime.now();

      final transport =
          commandTransport ?? const PlatformWidgetCommandTransport();
      if (toggleTodo != null) {
        await consumeWidgetCommands(
          db: db,
          transport: transport,
          toggleTodo: toggleTodo,
        );
      }

      final storedRaw = await HomeWidget.getWidgetData<String>(snapshotKey);
      final legacyTaps = decodePendingTaps(storedRaw);
      if (legacyTaps.isNotEmpty) {
        if (onLegacyPendingTaps != null) {
          await onLegacyPendingTaps(legacyTaps);
        } else if (toggleTodo != null) {
          for (final tap in legacyTaps) {
            if (tap.action != 'complete') continue;
            final row =
                await (db.select(db.todos)..where(
                      (t) => t.id.equals(tap.todoId) & t.deletedAt.isNull(),
                    ))
                    .getSingleOrNull();
            if (row == null) continue;
            final isRecurring =
                (row.rrule != null && row.rrule!.isNotEmpty) ||
                (row.recurrenceRule != null && row.recurrenceRule!.isNotEmpty);
            if (isRecurring) continue;
            if (row.status != 'COMPLETED') {
              try {
                await toggleTodo(id: row.id, isCompleted: true);
              } catch (_) {}
            }
          }
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final sixThingsEnabled = prefs.getBool('six_things_mode') ?? false;
      final calendarColors = {
        for (final row in await db.select(db.calendars).get())
          row.id: row.color,
      };

      final projection = await ActionProjectionQuery.fetch(
        db,
        date: effectiveNow,
      );
      final action = buildActionBlock(
        projection,
        calendarColors: calendarColors,
      );
      final completedCount =
          projection.completedTodayTodos.length +
          projection.completedTodayTaskInstances.length;
      final todos = await buildTodosBlock(
        db,
        now: effectiveNow,
        sixThingsEnabled: sixThingsEnabled,
        completedCount: completedCount,
      );
      final month = await monthCalendar(
        db,
        now: effectiveNow,
        calendarColors: calendarColors,
      );
      final ui = await loadWidgetUiStrings();
      final theme = await resolveWidgetTheme();

      final snapshot = buildSnapshot(
        generatedAt: effectiveNow,
        action: action,
        todos: todos,
        month: month,
        ui: ui,
        theme: theme,
      );

      await HomeWidget.saveWidgetData(snapshotKey, jsonEncode(snapshot));
      await refreshNativeWidgets();
    } catch (e) {
      debugPrint('home_widget: update error: $e');
    }
  }

  static Future<void> refreshNativeWidgets() async {
    switch (homeWidgetPlatform) {
      case TargetPlatform.android:
        for (final name in [
          androidProviderName,
          androidMonthProviderName,
          androidTodoProviderName,
        ]) {
          await HomeWidget.updateWidget(qualifiedAndroidName: name);
        }
      case TargetPlatform.iOS:
        for (final kind in appleWidgetKinds) {
          await HomeWidget.updateWidget(iOSName: kind);
        }
      case TargetPlatform.macOS:
        await HomeWidget.updateWidget();
      default:
        return;
    }
  }

  static Map<String, Object?> buildSnapshot({
    required DateTime generatedAt,
    required Map<String, Object?> action,
    required Map<String, Object?> todos,
    required Map<String, Object?> month,
    required WidgetUiStrings ui,
    required Map<String, Object?> theme,
  }) {
    return {
      'version': snapshotVersion,
      'generatedAt': generatedAt.toUtc().toIso8601String(),
      'today': _isoDate(generatedAt.toLocal()),
      'action': action,
      'todos': todos,
      'month': month,
      'ui': ui.toBlock(),
      'theme': theme,
    };
  }

  static Map<String, Object?> buildActionBlock(
    ActionProjectionData data, {
    Map<int, String>? calendarColors,
  }) {
    final timeline = <({int sortMs, Map<String, dynamic> row})>[];
    for (final e in data.events) {
      final localStart = e.start.toLocal();
      final localEnd = e.end.toLocal();
      timeline.add((
        sortMs: localStart.millisecondsSinceEpoch,
        row: {
          'kind': 'eventOccurrence',
          'eventId': e.drifId,
          'calendarId': e.calendarId,
          'summary': e.title,
          'start': _formatTime(localStart),
          'end': _formatTime(localEnd),
          'startEpochMs': localStart.millisecondsSinceEpoch,
          'endEpochMs': localEnd.millisecondsSinceEpoch,
          'isAllDay': e.isAllDay,
          if (calendarColors?[e.calendarId] != null)
            'color': calendarColors![e.calendarId],
        },
      ));
    }
    for (final a in data.allocations) {
      final localStart = a.allocation.startAt.toLocal();
      final localEnd = a.allocation.endAt.toLocal();
      timeline.add((
        sortMs: localStart.millisecondsSinceEpoch,
        row: {
          'kind': 'taskAllocation',
          'todoId': a.todo.id,
          'todoSyncId': a.todo.syncId,
          'occurrenceId': a.allocation.occurrenceId,
          'allocationId': a.allocation.id.toString(),
          'summary': a.todo.summary,
          'start': _formatTime(localStart),
          'end': _formatTime(localEnd),
          'startEpochMs': localStart.millisecondsSinceEpoch,
          'endEpochMs': localEnd.millisecondsSinceEpoch,
          'isAllDay': false,
          if (calendarColors?[a.todo.calendarId] != null)
            'color': calendarColors![a.todo.calendarId],
        },
      ));
    }
    timeline.sort((a, b) => a.sortMs.compareTo(b.sortMs));
    final timelineRows = timeline
        .take(_actionCap)
        .map((entry) => entry.row)
        .toList();

    final dueToday = <Map<String, dynamic>>[];
    for (final instance in data.todayTaskInstances) {
      dueToday.add(_instanceRow(instance));
    }
    final dueTodos = List<Todo>.of(data.dueTodayTodos)
      ..sort((a, b) {
        final order = a.sortOrder.compareTo(b.sortOrder);
        if (order != 0) return order;
        final priority = a.priority.compareTo(b.priority);
        if (priority != 0) return priority;
        return a.id.compareTo(b.id);
      });
    for (final todo in dueTodos) {
      dueToday.add(_todoActionRow(todo));
    }

    final overdue = <Map<String, dynamic>>[];
    final overdueTodos = List<Todo>.of(data.overdueTodos)
      ..sort((a, b) {
        final due = (a.dueDate ?? a.updatedAt).compareTo(
          b.dueDate ?? b.updatedAt,
        );
        if (due != 0) return due;
        return a.priority.compareTo(b.priority);
      });
    for (final todo in overdueTodos) {
      overdue.add(_todoActionRow(todo));
    }
    for (final instance in data.missedTaskInstances) {
      overdue.add(_instanceRow(instance));
    }

    return {
      'timeline': timelineRows,
      'dueToday': dueToday.take(_actionCap).toList(),
      'overdue': overdue.take(_actionCap).toList(),
      'counts': {
        'dueToday': data.todayTaskInstances.length + data.dueTodayTodos.length,
        'overdue': data.overdueTodos.length + data.missedTaskInstances.length,
        'completedToday':
            data.completedTodayTodos.length +
            data.completedTodayTaskInstances.length,
      },
    };
  }

  static Map<String, dynamic> _todoActionRow(Todo todo) {
    final due = todo.dueDate;
    final local = due?.toLocal();
    final hasTime = local != null && (local.hour != 0 || local.minute != 0);
    return {
      'kind': 'todoDeadline',
      'target': 'todo',
      'todoId': todo.id,
      'todoSyncId': todo.syncId,
      'occurrenceId': null,
      'summary': todo.summary,
      'priority': todo.priority,
      if (due != null) 'dueEpochMs': due.millisecondsSinceEpoch,
      if (local != null) 'dueDate': _isoDate(local),
      'displayTime': hasTime ? _formatTime(local) : '',
    };
  }

  static Map<String, dynamic> _instanceRow(ProjectedTaskInstance instance) {
    final anchor = instance.occurrence.nominalAnchor;
    final resolved = instance.occurrence.resolvedStartInstant;
    final localAnchor = anchor is LocalDateTime ? anchor : null;
    return {
      'kind': 'taskInstance',
      'target': 'taskInstance',
      'todoId': instance.todo.id,
      'todoSyncId': instance.todo.syncId,
      'occurrenceId': instance.occurrenceId,
      'summary': instance.todo.summary,
      'priority': instance.todo.priority,
      if (resolved != null)
        'startEpochMs': resolved.toLocal().millisecondsSinceEpoch,
      if (localAnchor != null)
        'displayTime':
            '${localAnchor.hour.toString().padLeft(2, '0')}:${localAnchor.minute.toString().padLeft(2, '0')}',
      if (localAnchor == null) 'displayTime': '',
    };
  }

  static Future<Map<String, Object?>> buildTodosBlock(
    AppDatabase db, {
    required DateTime now,
    required bool sixThingsEnabled,
    required int completedCount,
  }) async {
    final today = DateTime(now.year, now.month, now.day);
    final rows =
        await (db.select(db.todos)
              ..where(
                (t) =>
                    t.deletedAt.isNull() &
                    t.status.isNotIn(const ['COMPLETED', 'CANCELLED']) &
                    t.parentId.isNull(),
              )
              ..orderBy([
                (t) => OrderingTerm.asc(t.sortOrder),
                (t) => OrderingTerm.asc(t.priority),
                (t) => OrderingTerm.asc(t.dueDate),
              ]))
            .get();

    final tagColors = <int, List<String>>{};
    final tagRows =
        await (db.select(db.todoTags).join([
              innerJoin(db.tags, db.tags.id.equalsExp(db.todoTags.tagId)),
            ])..orderBy([
              OrderingTerm.asc(db.todoTags.todoId),
              OrderingTerm.asc(db.tags.id),
            ]))
            .get();
    for (final row in tagRows) {
      final todoId = row.readTable(db.todoTags).todoId;
      final color = row.readTable(db.tags).color;
      final list = tagColors.putIfAbsent(todoId, () => []);
      if (list.length < 3) list.add(color);
    }

    final todayItems = <Todo>[];
    final overdueItems = <Todo>[];
    final inboxItems = <Todo>[];
    for (final todo in rows) {
      final due = todo.dueDate;
      if (due == null) {
        inboxItems.add(todo);
        continue;
      }
      final civil = DateTime(due.toLocal().year, due.toLocal().month, due.toLocal().day);
      if (civil == today) {
        todayItems.add(todo);
      } else if (civil.isBefore(today)) {
        overdueItems.add(todo);
      }
    }
    overdueItems.sort((a, b) {
      final due = a.dueDate!.compareTo(b.dueDate!);
      if (due != 0) return due;
      return a.priority.compareTo(b.priority);
    });

    Map<String, Object?> item(Todo todo) {
      final due = todo.dueDate;
      final local = due?.toLocal();
      final hasTime = local != null && (local.hour != 0 || local.minute != 0);
      final recurring =
          (todo.rrule != null && todo.rrule!.isNotEmpty) ||
          (todo.recurrenceRule != null && todo.recurrenceRule!.isNotEmpty);
      return {
        'todoId': todo.id,
        'todoSyncId': todo.syncId,
        'summary': todo.summary,
        'priority': todo.priority,
        if (due != null) 'dueDate': _isoDate(local!),
        if (due != null) 'dueEpochMs': due.millisecondsSinceEpoch,
        'hasTime': hasTime,
        'recurring': recurring,
        'tagColors': tagColors[todo.id] ?? const <String>[],
      };
    }

    final sixThingsCap = sixThingsEnabled ? 6 : 0;
    final todayEmitted = sixThingsCap > 0
        ? todayItems.take(sixThingsCap)
        : todayItems.take(_todosTodayCap);
    return {
      'today': {
        'sixThingsCap': sixThingsCap,
        'items': todayEmitted.map(item).toList(),
        'overdue': overdueItems.take(_todosTodayCap).map(item).toList(),
        'completedCount': completedCount,
        'total': todayItems.length,
      },
      'inbox': {
        'items': inboxItems.take(_todosInboxCap).map(item).toList(),
        'total': inboxItems.length,
      },
      'all': {
        'items': rows.take(_todosAllCap).map(item).toList(),
        'total': rows.length,
      },
    };
  }

  /// Month grid data for the Calendar widget, including a bounded item list
  /// per day so native code can render the selected day without the database.
  static Future<Map<String, Object?>> monthCalendar(
    AppDatabase db, {
    DateTime? now,
    Map<int, String>? calendarColors,
  }) async {
    final ref = now ?? DateTime.now();
    final monthStart = DateTime(ref.year, ref.month, 1);
    final monthEnd = DateTime(ref.year, ref.month + 1, 1);
    final daysInMonth = DateTime(ref.year, ref.month + 1, 0).day;

    final eventCandidates = await db.eventsDao.getEventCandidates(
      monthStart,
      monthEnd,
    );
    final expandedEvents =
        expandRecurringEvents(
              eventCandidates,
              before: monthStart,
              after: monthEnd,
              colorForCalendar: (id) => _parseColor(calendarColors?[id]),
            )
            .where(
              (e) => e.start.isBefore(monthEnd) && e.end.isAfter(monthStart),
            )
            .toList();

    final allocations = await fetchTaskAllocationsInDateRange(
      db,
      monthStart,
      monthEnd,
    );

    final dueTodos =
        await (db.select(db.todos)..where(
              (t) =>
                  t.deletedAt.isNull() &
                  t.status.isNotIn(const ['COMPLETED', 'CANCELLED']) &
                  t.rrule.isNull() &
                  t.recurrenceRule.isNull() &
                  t.dueDate.isBiggerOrEqualValue(monthStart) &
                  t.dueDate.isSmallerThanValue(monthEnd),
            ))
            .get();

    final days = <Map<String, Object?>>[];
    for (var d = 1; d <= daysInMonth; d++) {
      final dayStart = DateTime(ref.year, ref.month, d);
      final dayEnd = DateTime(ref.year, ref.month, d + 1);
      final dayEvents = expandedEvents
          .where((e) => e.start.isBefore(dayEnd) && e.end.isAfter(dayStart))
          .toList();
      final dayAllocations = allocations
          .where(
            (a) =>
                a.allocation.startAt.isBefore(dayEnd) &&
                a.allocation.endAt.isAfter(dayStart),
          )
          .toList();
      final dayDeadlines = dueTodos
          .where(
            (t) =>
                !t.dueDate!.isBefore(dayStart) && t.dueDate!.isBefore(dayEnd),
          )
          .toList();

      final items = <({int rank, int sortMs, int tie, Map<String, dynamic> row})>[];
      var tie = 0;
      for (final e in dayEvents) {
        final localStart = e.start.toLocal();
        final localEnd = e.end.toLocal();
        items.add((
          rank: e.isAllDay ? 0 : 1,
          sortMs: localStart.millisecondsSinceEpoch,
          tie: tie++,
          row: {
            'kind': 'eventOccurrence',
            'eventId': e.drifId,
            'calendarId': e.calendarId,
            'summary': e.title,
            'start': _formatTime(localStart),
            'end': _formatTime(localEnd),
            'startEpochMs': localStart.millisecondsSinceEpoch,
            'endEpochMs': localEnd.millisecondsSinceEpoch,
            'isAllDay': e.isAllDay,
            if (calendarColors?[e.calendarId] != null)
              'color': calendarColors![e.calendarId],
          },
        ));
      }
      for (final a in dayAllocations) {
        final localStart = a.allocation.startAt.toLocal();
        final localEnd = a.allocation.endAt.toLocal();
        items.add((
          rank: 1,
          sortMs: localStart.millisecondsSinceEpoch,
          tie: tie++,
          row: {
            'kind': 'taskAllocation',
            'todoId': a.todo.id,
            'todoSyncId': a.todo.syncId,
            'occurrenceId': a.allocation.occurrenceId,
            'allocationId': a.allocation.id.toString(),
            'summary': a.todo.summary,
            'start': _formatTime(localStart),
            'end': _formatTime(localEnd),
            'startEpochMs': localStart.millisecondsSinceEpoch,
            'endEpochMs': localEnd.millisecondsSinceEpoch,
            'isAllDay': false,
            if (calendarColors?[a.todo.calendarId] != null)
              'color': calendarColors![a.todo.calendarId],
          },
        ));
      }
      for (final todo in dayDeadlines) {
        final due = todo.dueDate!.toLocal();
        final hasTime = due.hour != 0 || due.minute != 0;
        items.add((
          rank: hasTime ? 2 : 3,
          sortMs: hasTime
              ? due.millisecondsSinceEpoch
              : dayStart.millisecondsSinceEpoch,
          tie: tie++,
          row: {
            'kind': 'todoDeadline',
            'todoId': todo.id,
            'todoSyncId': todo.syncId,
            'summary': todo.summary,
            'start': hasTime ? _formatTime(due) : '',
            'hasTime': hasTime,
            'startEpochMs': due.millisecondsSinceEpoch,
          },
        ));
      }
      items.sort((a, b) {
        final rank = a.rank.compareTo(b.rank);
        if (rank != 0) return rank;
        final time = a.sortMs.compareTo(b.sortMs);
        if (time != 0) return time;
        return a.tie.compareTo(b.tie);
      });

      final colors = _dayColors(dayEvents, dayAllocations, calendarColors);
      days.add({
        'day': d,
        'hasEvent': dayEvents.isNotEmpty,
        'hasTodo': dayDeadlines.isNotEmpty,
        'hasAllocation': dayAllocations.isNotEmpty,
        'colors': colors,
        'itemCount': items.length,
        'items': items
            .take(_monthItemsCap)
            .map((entry) => entry.row)
            .toList(),
      });
    }

    return {
      'year': ref.year,
      'month': ref.month,
      'firstWeekday': DateTime(ref.year, ref.month, 1).weekday,
      'today': ref.day,
      'days': days,
    };
  }

  static List<String> _dayColors(
    List<CalendaEventAdapter> events,
    List<TaskAllocationCalendarItem> allocations,
    Map<int, String>? calendarColors,
  ) {
    final colors = <String>[];
    for (final e in events) {
      final hex = calendarColors?[e.calendarId];
      if (hex != null && !colors.contains(hex)) colors.add(hex);
      if (colors.length == 3) return colors;
    }
    for (final a in allocations) {
      final hex = calendarColors?[a.todo.calendarId];
      if (hex != null && !colors.contains(hex)) colors.add(hex);
      if (colors.length == 3) return colors;
    }
    return colors;
  }

  static List<WidgetPendingTap> decodePendingTaps(String? rawSnapshot) {
    if (rawSnapshot == null || rawSnapshot.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(rawSnapshot);
      if (decoded is! Map<String, dynamic>) return const [];
      final rawTaps = decoded['pendingTaps'];
      if (rawTaps is! List) return const [];
      final taps = <WidgetPendingTap>[];
      for (final raw in rawTaps) {
        if (raw is! Map<String, dynamic>) continue;
        try {
          taps.add(WidgetPendingTap.fromJson(raw));
        } on FormatException {
          continue;
        }
      }
      return taps;
    } on FormatException {
      return const [];
    } on TypeError {
      return const [];
    }
  }

  static Future<WidgetUiStrings> loadWidgetUiStrings({Locale? locale}) async {
    var resolved = locale ?? const Locale('en');
    if (locale == null) {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(appLocalePrefKey);
      resolved = code != null
          ? Locale(code)
          : WidgetsBinding.instance.platformDispatcher.locale;
    }
    final l = await AppLocalizations.delegate.load(resolved);
    String template(String raw) => raw.replaceAll('%n', '{n}');
    return WidgetUiStrings(
      locale: resolved.toLanguageTag(),
      today: l.today,
      inbox: l.inbox,
      all: l.widgetAll,
      noTodos: l.widgetNoTodos,
      allTodosDone: l.widgetAllTodosDone,
      noPlans: l.widgetNoPlans,
      allPlansDone: l.widgetAllPlansDone,
      now: l.actionNow,
      later: l.widgetLater,
      dueToday: l.widgetDueToday,
      overdue: l.overdue,
      completedCount: template(l.widgetCompletedCountTemplate),
      moreCount: template(l.widgetMoreCountTemplate),
      overdueCount: template(l.widgetOverdueCountTemplate),
      selectedDayEmpty: l.widgetSelectedDayEmpty,
      backToMonth: l.widgetBackToMonth,
      openToUpdate: l.widgetOpenToUpdate,
      stale: l.widgetStale,
      addTodo: l.widgetAddTodo,
      addEvent: l.widgetAddEvent,
      quickAddHint: l.widgetQuickAddHint,
      quickAddToday: l.today,
      quickAddInbox: l.inbox,
      save: l.save,
      saveFailed: l.widgetSaveFailed,
      allDay: l.allDay,
    );
  }

  static Future<Map<String, Object?>> resolveWidgetTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(themeModePrefKey);
    final mode = ThemeMode.values.firstWhere(
      (m) => m.name == saved,
      orElse: () => ThemeMode.system,
    );
    final platformDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
    final dark =
        mode == ThemeMode.dark || (mode == ThemeMode.system && platformDark);
    return buildThemeBlock(dark: dark);
  }

  static Map<String, Object?> buildThemeBlock({required bool dark}) {
    return {
      'dark': dark,
      'colors': {
        'background': _hex(
          dark ? AppColors.darkBackground : AppColors.lightBackground,
        ),
        'surface': _hex(dark ? AppColors.darkSurface : AppColors.lightSurface),
        'textPrimary': _hex(
          dark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
        ),
        'textSecondary': _hex(
          dark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
        ),
        'accent': _hex(dark ? AppColors.darkAccent : AppColors.lightAccent),
        'border': _hex(dark ? AppColors.darkBorder : AppColors.lightBorder),
        'error': _hex(dark ? AppColors.darkError : AppColors.lightError),
        'warning': _hex(dark ? AppColors.darkWarning : AppColors.lightWarning),
      },
    };
  }

  static Color? _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    try {
      return ColorUtils.parseHex(hex);
    } catch (_) {
      return null;
    }
  }

  static String _isoDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String _hex(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  static String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
