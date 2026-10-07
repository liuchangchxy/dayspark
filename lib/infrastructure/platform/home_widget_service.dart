import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dayspark/core/utils/platform_target.dart';
import 'package:dayspark/core/theme/app_colors.dart';
import 'package:dayspark/data/local/database/app_database.dart';
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

// Legacy v2 tap format kept strictly for backward-compatible migration (Ruling I/P).
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
    required this.title,
    required this.today,
    required this.events,
    required this.todos,
    required this.allDay,
    required this.todayEventsHeader,
    required this.noEvents,
    required this.allDone,
    required this.pendingCount,
    required this.quickAdd,
    required this.upcoming,
    this.overdue = 'Overdue',
    this.missed = 'Missed',
    this.unplanned = 'Inbox',
  });

  final String locale;
  final String title;
  final String today;
  final String events;
  final String todos;
  final String allDay;
  final String todayEventsHeader;
  final String noEvents;
  final String allDone;
  final String pendingCount;
  final String quickAdd;
  final String upcoming;
  final String overdue;
  final String missed;
  final String unplanned;

  Map<String, Object?> toBlock() => {
    'locale': locale,
    'title': title,
    'today': today,
    'events': events,
    'todos': todos,
    'allDay': allDay,
    'todayEventsHeader': todayEventsHeader,
    'noEvents': noEvents,
    'allDone': allDone,
    'pendingCount': pendingCount,
    'quickAdd': quickAdd,
    'upcoming': upcoming,
    'overdue': overdue,
    'missed': missed,
    'unplanned': unplanned,
  };
}

class HomeWidgetService {
  static const String snapshotKey = 'widget_snapshot';
  static const int snapshotVersion = 3;

  static const String androidProviderName =
      'com.dayspark.app.CalendarTodoWidgetProvider';
  static const String androidUpcomingProviderName =
      'com.dayspark.app.UpcomingWidgetProvider';
  static const String androidMonthProviderName =
      'com.dayspark.app.MonthDotsWidgetProvider';

  static const List<String> appleWidgetKinds = [
    'CalendarTodoWidget',
    'CalendarUpcomingWidget',
    'CalendarMonthWidget',
  ];

  static const String legacyEventsKey = 'today_events';
  static const String legacyTodosKey = 'pending_todos';
  static const String legacyCountKey = 'todo_count';

  /// Updates the authoritative v3 widget snapshot and drains any pending commands.
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

      // 1. Drain typed commands from independent command transport (Ruling O)
      final transport = commandTransport ?? const PlatformWidgetCommandTransport();
      if (toggleTodo != null) {
        await consumeWidgetCommands(
          db: db,
          transport: transport,
          toggleTodo: toggleTodo,
        );
      }

      // 2. Backward compatibility: Drain any legacy v2 pendingTaps if found (Ruling I / P)
      final storedRaw = await HomeWidget.getWidgetData<String>(snapshotKey);
      final legacyTaps = decodePendingTaps(storedRaw);
      if (legacyTaps.isNotEmpty) {
        if (onLegacyPendingTaps != null) {
          await onLegacyPendingTaps(legacyTaps);
        } else if (toggleTodo != null) {
          for (final tap in legacyTaps) {
            if (tap.action == 'complete') {
              final row = await (db.select(db.todos)
                    ..where((t) => t.id.equals(tap.todoId) & t.deletedAt.isNull()))
                  .getSingleOrNull();
              if (row != null) {
                final isRecurring = (row.rrule != null && row.rrule!.isNotEmpty) ||
                    (row.recurrenceRule != null && row.recurrenceRule!.isNotEmpty);
                if (isRecurring) {
                  // Ruling I: Missing occurrenceId fails closed; do not guess
                  continue;
                }
                if (row.status != 'COMPLETED') {
                  try {
                    await toggleTodo(id: row.id, isCompleted: true);
                  } catch (_) {}
                }
              }
            }
          }
        }
      }

      // 3. Compute unified deterministic projections
      final todayData = await ActionProjectionQuery.fetch(db, date: effectiveNow);
      final timeline = todayTimeline(todayData);
      final actions = todayActions(todayData);
      final status = todayStatus(todayData);
      final upcoming = await upcomingItems(db, now: effectiveNow);
      final dots = await monthDots(db, now: effectiveNow);

      final ui = await loadWidgetUiStrings(
        todoCount: actions.length + status['unplannedCount']!,
      );
      final theme = await resolveWidgetTheme();

      final preservedTaps =
          (onLegacyPendingTaps == null && toggleTodo == null)
              ? legacyTaps
              : const <WidgetPendingTap>[];

      // 4. Build authoritative v3 snapshot
      final snapshot = buildSnapshot(
        todayTimeline: timeline,
        todayActions: actions,
        todayStatus: status,
        upcomingItems: upcoming,
        monthDots: dots,
        ui: ui,
        theme: theme,
        generatedAt: effectiveNow,
        preservedPendingTaps: preservedTaps,
      );

      // Save v3 snapshot (Native only reads this; never writes to it)
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
          androidUpcomingProviderName,
          androidMonthProviderName,
        ]) {
          await HomeWidget.updateWidget(qualifiedAndroidName: name);
        }
      case TargetPlatform.iOS:
        for (final kind in appleWidgetKinds) {
          await HomeWidget.updateWidget(iOSName: kind);
        }
      default:
        return;
    }
  }

  /// Builds the timeline rows for Today Widget (EventOccurrence + TaskAllocation).
  static List<Map<String, dynamic>> todayTimeline(ActionProjectionData data) {
    final list = <Map<String, dynamic>>[];

    for (final e in data.events) {
      list.add({
        'kind': 'eventOccurrence',
        'id': e.drifId,
        'summary': e.title,
        'start': _formatTime(e.start),
        'end': _formatTime(e.end),
        'isAllDay': e.isAllDay,
        'startMs': e.start.millisecondsSinceEpoch,
      });
    }

    for (final a in data.allocations) {
      list.add({
        'kind': 'taskAllocation',
        'allocationId': a.allocation.id,
        'todoId': a.todo.id,
        'todoSyncId': a.todo.syncId,
        'occurrenceId': a.allocation.occurrenceId,
        'summary': a.todo.summary,
        'start': _formatTime(a.allocation.startAt),
        'end': _formatTime(a.allocation.endAt),
        'isAllDay': false,
        'startMs': a.allocation.startAt.millisecondsSinceEpoch,
      });
    }

    list.sort((a, b) => (a['startMs'] as int).compareTo(b['startMs'] as int));
    for (final item in list) {
      item.remove('startMs');
    }
    return list;
  }

  /// Builds the action rows for Today Widget (TodoDeadline + TaskInstance).
  static List<Map<String, dynamic>> todayActions(ActionProjectionData data) {
    final list = <Map<String, dynamic>>[];

    for (final t in data.dueTodayTodos) {
      list.add({
        'kind': 'todoDeadline',
        'todoId': t.id,
        'todoSyncId': t.syncId,
        'summary': t.summary,
        'deadline': t.dueDate != null ? '${t.dueDate!.month}/${t.dueDate!.day}' : '',
        'target': 'todo',
      });
    }

    for (final inst in data.todayTaskInstances) {
      list.add({
        'kind': 'taskInstance',
        'todoId': inst.todo.id,
        'todoSyncId': inst.todo.syncId,
        'occurrenceId': inst.occurrence.occurrenceId,
        'summary': inst.todo.summary,
        'displayTime': _formatOccurrenceTime(inst.occurrence),
        'target': 'taskInstance',
      });
    }

    return list;
  }

  /// Computes status counts for Today Widget.
  static Map<String, int> todayStatus(ActionProjectionData data) {
    return {
      'overdueCount': data.overdueTodos.length,
      'missedCount': data.missedTaskInstances.length,
      'unplannedCount': data.unplannedCount,
    };
  }

  /// Upcoming items for the next 7 full civil days [tomorrow 00:00, tomorrow+7d 00:00).
  static Future<List<Map<String, dynamic>>> upcomingItems(
    AppDatabase db, {
    DateTime? now,
  }) async {
    final ref = now ?? DateTime.now();
    final tomorrowStart = DateTime(ref.year, ref.month, ref.day + 1);
    final windowEnd = DateTime(ref.year, ref.month, ref.day + 8);

    final eventCandidates = await db.eventsDao.getEventCandidates(
      tomorrowStart,
      windowEnd,
    );
    final expandedEvents = expandRecurringEvents(
      eventCandidates,
      before: tomorrowStart,
      after: windowEnd,
    ).where((e) => e.start.isBefore(windowEnd) && e.end.isAfter(tomorrowStart)).toList();

    final allocations = await fetchTaskAllocationsInDateRange(
      db,
      tomorrowStart,
      windowEnd,
    );

    final dueTodos = await (db.select(db.todos)
          ..where(
            (t) =>
                t.deletedAt.isNull() &
                t.status.isNotIn(const ['COMPLETED', 'CANCELLED']) &
                t.rrule.isNull() &
                t.recurrenceRule.isNull() &
                t.dueDate.isBiggerOrEqualValue(tomorrowStart) &
                t.dueDate.isSmallerThanValue(windowEnd),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.dueDate)]))
        .get();

    final rows = <({DateTime sortTime, Map<String, dynamic> item})>[];

    for (final e in expandedEvents) {
      final localStart = e.start.toLocal();
      rows.add((
        sortTime: localStart,
        item: {
          'kind': 'eventOccurrence',
          'summary': e.title,
          'date': '${localStart.month}/${localStart.day}',
          'time': e.isAllDay ? 'All day' : _formatTime(localStart),
          'isAllDay': e.isAllDay,
        },
      ));
    }

    for (final a in allocations) {
      final localStart = a.allocation.startAt.toLocal();
      rows.add((
        sortTime: localStart,
        item: {
          'kind': 'taskAllocation',
          'summary': a.todo.summary,
          'date': '${localStart.month}/${localStart.day}',
          'time': '${_formatTime(a.allocation.startAt)} - ${_formatTime(a.allocation.endAt)}',
          'isAllDay': false,
        },
      ));
    }

    for (final t in dueTodos) {
      final due = t.dueDate!;
      rows.add((
        sortTime: due,
        item: {
          'kind': 'todoDeadline',
          'summary': t.summary,
          'date': '${due.month}/${due.day}',
          'time': 'Deadline',
          'isAllDay': false,
        },
      ));
    }

    rows.sort((a, b) => a.sortTime.compareTo(b.sortTime));
    return rows.map((r) => r.item).toList();
  }

  /// Month dots for current civil calendar month.
  /// Points on dates with at least one EventOccurrence or TaskAllocation (Ruling G).
  static Future<List<List<dynamic>>> monthDots(
    AppDatabase db, {
    DateTime? now,
  }) async {
    final ref = now ?? DateTime.now();
    final monthStart = DateTime(ref.year, ref.month, 1);
    final monthEnd = DateTime(ref.year, ref.month + 1, 1);
    final daysInMonth = DateTime(ref.year, ref.month + 1, 0).day;

    final eventCandidates = await db.eventsDao.getEventCandidates(
      monthStart,
      monthEnd,
    );
    final expandedEvents = expandRecurringEvents(
      eventCandidates,
      before: monthStart,
      after: monthEnd,
    ).where((e) => e.start.isBefore(monthEnd) && e.end.isAfter(monthStart)).toList();

    final allocations = await fetchTaskAllocationsInDateRange(
      db,
      monthStart,
      monthEnd,
    );

    final markedDays = <int>{};

    for (var d = 1; d <= daysInMonth; d++) {
      final dayStart = DateTime(ref.year, ref.month, d);
      final dayEnd = DateTime(ref.year, ref.month, d + 1);

      final hasEvent = expandedEvents.any(
        (e) => e.start.isBefore(dayEnd) && e.end.isAfter(dayStart),
      );
      if (hasEvent) {
        markedDays.add(d);
        continue;
      }

      final hasAlloc = allocations.any(
        (a) =>
            a.allocation.startAt.isBefore(dayEnd) &&
            a.allocation.endAt.isAfter(dayStart),
      );
      if (hasAlloc) {
        markedDays.add(d);
      }
    }

    final sorted = markedDays.toList()..sort();
    return [for (final day in sorted) [day, true]];
  }

  /// Builds the complete authoritative v3 snapshot dictionary.
  static Map<String, Object?> buildSnapshot({
    required List<Map<String, dynamic>> todayTimeline,
    required List<Map<String, dynamic>> todayActions,
    required Map<String, int> todayStatus,
    required List<Map<String, dynamic>> upcomingItems,
    required List<List<dynamic>> monthDots,
    required WidgetUiStrings ui,
    required Map<String, Object?> theme,
    required DateTime generatedAt,
    List<WidgetPendingTap> preservedPendingTaps = const [],
  }) {
    // Legacy fallback items for smooth downlevel reader compatibility
    final legacyEvents = todayTimeline
        .where((t) => t['kind'] == 'eventOccurrence')
        .map((e) => {
          'summary': e['summary'] as String,
          'start': e['start'] as String,
          'isAllDay': e['isAllDay'] as bool,
        })
        .toList();

    final legacyTodos = todayActions
        .map((a) => {
          'id': a['todoId'],
          'summary': a['summary'] as String,
          'dueDate': a['deadline'] ?? '',
        })
        .toList();

    final legacyUpcomingEvents = upcomingItems
        .where((i) => i['kind'] == 'eventOccurrence')
        .map((e) => {
          'summary': e['summary'] as String,
          'date': e['date'] as String,
          'start': e['time'] as String,
          'isAllDay': e['isAllDay'] as bool,
        })
        .toList();

    final legacyUpcomingTodos = upcomingItems
        .where((i) => i['kind'] != 'eventOccurrence')
        .map((t) => {
          'summary': t['summary'] as String,
          'dueDate': t['date'] as String,
        })
        .toList();

    return {
      'version': snapshotVersion,
      'generatedAt': generatedAt.toUtc().toIso8601String(),
      'today': {
        'timeline': todayTimeline,
        'actions': todayActions,
        'status': todayStatus,
      },
      'upcoming': {
        'items': upcomingItems,
        'events': legacyUpcomingEvents,
        'todos': legacyUpcomingTodos,
      },
      'monthDots': monthDots,
      'todayEvents': legacyEvents,
      'pendingTodos': legacyTodos,
      'todoCount': todayActions.length + (todayStatus['unplannedCount'] ?? 0),
      'pendingTaps': [
        for (final tap in preservedPendingTaps) tap.toJson(),
      ],
      'ui': ui.toBlock(),
      'theme': theme,
    };
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

  static Future<WidgetUiStrings> loadWidgetUiStrings({
    Locale? locale,
    int todoCount = 0,
  }) async {
    var resolved = locale ?? const Locale('en');
    if (locale == null) {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(appLocalePrefKey);
      resolved = code != null
          ? Locale(code)
          : WidgetsBinding.instance.platformDispatcher.locale;
    }
    final l = await AppLocalizations.delegate.load(resolved);
    return WidgetUiStrings(
      locale: resolved.toLanguageTag(),
      title: l.appName,
      today: l.today,
      events: l.events,
      todos: l.todos,
      allDay: l.allDay,
      todayEventsHeader: l.todayEventsHeader,
      noEvents: l.widgetNoEvents,
      allDone: l.widgetAllDone,
      pendingCount: l.widgetPendingCount(todoCount),
      quickAdd: l.quickAdd,
      upcoming: l.upcoming,
      overdue: l.overdue,
      missed: l.missed,
      unplanned: l.unplannedInbox,
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
        'background': _hex(dark ? AppColors.darkBackground : AppColors.lightBackground),
        'surface': _hex(dark ? AppColors.darkSurface : AppColors.lightSurface),
        'textPrimary': _hex(
          dark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
        ),
        'textSecondary': _hex(
          dark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
        ),
        'accent': _hex(dark ? AppColors.darkAccent : AppColors.lightAccent),
        'border': _hex(dark ? AppColors.darkBorder : AppColors.lightBorder),
      },
    };
  }

  static String _hex(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  static String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  static String _formatOccurrenceTime(TodoOccurrence occ) {
    final anchor = occ.nominalAnchor;
    if (anchor is LocalDateTime) {
      return '${anchor.hour.toString().padLeft(2, '0')}:${anchor.minute.toString().padLeft(2, '0')}';
    }
    return '';
  }
}
