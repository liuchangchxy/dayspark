import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dayspark/core/theme/app_colors.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/locale_provider.dart';
import 'package:dayspark/domain/providers/theme_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';

// One widget-checkbox tap pushed from native code to the app.
//
// Native widgets never write the database directly (single-writer rule):
// they append entries to `widget_snapshot.pendingTaps` in the shared
// store; the app consumes them on the next flush and lands the completes
// through the normal `toggleTodoProvider` path.
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

// Pre-localized widget labels for the locale in effect at snapshot build
// time. Native readers render these verbatim — Kotlin/Swift must never
// hardcode English (or Chinese) widget copy again; locale switches reach
// the widget only through the next snapshot write.
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
  };
}

class HomeWidgetService {
  static const String snapshotKey = 'widget_snapshot';
  static const int snapshotVersion = 2;
  static const String androidProviderName =
      'com.dayspark.app.CalendarTodoWidgetProvider';
  static const String androidUpcomingProviderName =
      'com.dayspark.app.UpcomingWidgetProvider';
  static const String androidMonthProviderName =
      'com.dayspark.app.MonthDotsWidgetProvider';
  // WidgetKit kind names — home_widget reloads one kind per updateWidget
  // call, so a flush must fan out over all three or the variants go stale.
  static const List<String> appleWidgetKinds = [
    'CalendarTodoWidget',
    'CalendarUpcomingWidget',
    'CalendarMonthWidget',
  ];
  static const String legacyEventsKey = 'today_events';
  static const String legacyTodosKey = 'pending_todos';
  static const String legacyCountKey = 'todo_count';

  // Snapshot contract (v2) — single blob every native widget reads.
  //
  // WHY v2 with dual-written legacy keys still present: the three legacy
  // keys stay for one more task so live widgets never blank out, while
  // `widget_snapshot` becomes the only contract native readers migrate to
  // (T3). `upcoming` feeds the next-7-days variant; `pendingTaps` is the
  // native→app command channel (app writes `[]` on every flush after
  // consumption — native appends, app consumes, never the reverse);
  // `ui` carries pre-localized labels so Kotlin/Swift hold zero hardcoded
  // copy; `theme` hands native the resolved dark flag + hex tokens so its
  // styling matches the app without re-deriving theme logic.
  static Future<void> updateWidget(
    AppDatabase db, {
    Future<void> Function(List<WidgetPendingTap> taps)? onPendingTaps,
  }) async {
    try {
      final events = await todayEvents(db);
      final todos = await pendingTodos(db);
      final todoCount = await pendingTodoCount(db);
      final upcomingEventsList = await upcomingEvents(db);
      final upcomingTodosList = await upcomingTodos(db);
      final monthEventDays = await monthEventDaysOfCurrentMonth(db);

      // Native→app channel: read taps appended since the last flush, land
      // them through the caller's complete path, then write a fresh
      // snapshot whose pendingTaps is empty. Reading before building the
      // snapshot (and only clearing on a successful consume) keeps a tap
      // from being wiped by a flush that has no consumer attached.
      final storedRaw = await HomeWidget.getWidgetData<String>(snapshotKey);
      final storedTaps = decodePendingTaps(storedRaw);
      var pendingTaps = const <WidgetPendingTap>[];
      if (storedTaps.isNotEmpty) {
        if (onPendingTaps != null) {
          await onPendingTaps(storedTaps);
        } else {
          pendingTaps = storedTaps;
        }
      }

      final ui = await loadWidgetUiStrings(todoCount: todoCount);
      final theme = await resolveWidgetTheme();
      final snapshot = buildSnapshot(
        events: events,
        todos: todos,
        todoCount: todoCount,
        upcomingEvents: upcomingEventsList,
        upcomingTodos: upcomingTodosList,
        monthEventDays: monthEventDays,
        pendingTaps: pendingTaps,
        ui: ui,
        theme: theme,
        generatedAt: DateTime.now(),
      );

      // Dual-write kept for the retirement window: legacy three keys stay
      // one more release as a downlevel fallback; `widget_snapshot` v2 is
      // now the contract every native reader (T3) consumes.
      await HomeWidget.saveWidgetData(
        legacyEventsKey,
        encodeTodayEvents(events),
      );
      await HomeWidget.saveWidgetData(legacyTodosKey, encodePendingTodos(todos));
      await HomeWidget.saveWidgetData(legacyCountKey, '$todoCount');
      await HomeWidget.saveWidgetData(snapshotKey, jsonEncode(snapshot));
      await refreshNativeWidgets();
    } catch (e) {
      debugPrint('home_widget: update error: $e');
    }
  }

  // Fans the refresh out over every registered widget: Android needs one
  // APPWIDGET_UPDATE broadcast per provider class, iOS one reloadTimelines
  // per WidgetKit kind (home_widget reloads a single kind per call), and
  // the macOS shim treats any call as reloadAllTimelines. Branching by
  // platform keeps each call valid there — a name unknown to a platform
  // completes with an error that would abort the remaining fan-out.
  static Future<void> refreshNativeWidgets() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      for (final name in [
        androidProviderName,
        androidUpcomingProviderName,
        androidMonthProviderName,
      ]) {
        await HomeWidget.updateWidget(qualifiedAndroidName: name);
      }
      return;
    }
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      for (final kind in appleWidgetKinds) {
        await HomeWidget.updateWidget(iOSName: kind);
      }
      return;
    }
    await HomeWidget.updateWidget(qualifiedAndroidName: androidProviderName);
  }

  static Future<List<Event>> todayEvents(AppDatabase db) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    return (db.select(db.events)
          ..where((t) => t.deletedAt.isNull())
          ..where(
            (t) =>
                t.startDt.isSmallerThanValue(todayEnd) &
                t.endDt.isBiggerThanValue(todayStart),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.startDt)])
          ..limit(3))
        .get();
  }

  static Future<List<Todo>> pendingTodos(AppDatabase db, {int limit = 3}) {
    return (db.select(db.todos)
          ..where((t) => t.deletedAt.isNull())
          ..where((t) => t.status.isNotIn(['COMPLETED', 'CANCELLED']))
          // Subtasks must not occupy widget slots — only top-level todos.
          ..where((t) => t.parentId.isNull())
          ..orderBy([
            // SQLite ASC puts NULLs first; ordering by `due_date IS NULL`
            // (0/1) first sinks NULL due dates to the end of the list.
            (t) => OrderingTerm(
              expression: t.dueDate.isNull(),
              mode: OrderingMode.asc,
            ),
            (t) => OrderingTerm.asc(t.dueDate),
          ])
          ..limit(limit))
        .get();
  }

  static Future<int> pendingTodoCount(AppDatabase db) async {
    final rows = await (db.select(db.todos)
          ..where((t) => t.deletedAt.isNull())
          ..where((t) => t.status.isNotIn(['COMPLETED', 'CANCELLED'])))
        .get();
    return rows.length;
  }

  // Upcoming bucket window: the 7 full days after today — [tomorrow
  // 00:00, tomorrow+7d 00:00). Today is excluded on purpose: the legacy
  // bucket already covers it and the Upcoming variant sits next to the
  // today widget on the home screen.
  static ({DateTime start, DateTime end}) upcomingWindow(DateTime now) {
    final todayStart = DateTime(now.year, now.month, now.day);
    final start = todayStart.add(const Duration(days: 1));
    return (start: start, end: start.add(const Duration(days: 7)));
  }

  static Future<List<Event>> upcomingEvents(
    AppDatabase db, {
    int limit = 10,
    DateTime? now,
  }) {
    final window = upcomingWindow(now ?? DateTime.now());
    return (db.select(db.events)
          ..where((t) => t.deletedAt.isNull())
          ..where(
            (t) =>
                t.startDt.isSmallerThanValue(window.end) &
                t.endDt.isBiggerThanValue(window.start),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.startDt)])
          ..limit(limit))
        .get();
  }

  static Future<List<Todo>> upcomingTodos(
    AppDatabase db, {
    int limit = 10,
    DateTime? now,
  }) {
    final window = upcomingWindow(now ?? DateTime.now());
    return (db.select(db.todos)
          ..where((t) => t.deletedAt.isNull())
          ..where((t) => t.status.isNotIn(['COMPLETED', 'CANCELLED']))
          ..where((t) => t.parentId.isNull())
          ..where((t) => t.dueDate.isBiggerOrEqualValue(window.start))
          ..where((t) => t.dueDate.isSmallerThanValue(window.end))
          ..orderBy([(t) => OrderingTerm.asc(t.dueDate)])
          ..limit(limit))
        .get();
  }

  // Days-of-month (1..31) inside the current calendar month that overlap at
  // least one event — feeds the month-dots widget variant. Derived here in
  // one bounded query rather than by native code: todayEvents carries no
  // date and the upcoming bucket only spans 7 days, so the snapshot alone
  // cannot reconstruct a month grid (T3 brief's allowed minimal Dart
  // addition).
  static Future<List<int>> monthEventDaysOfCurrentMonth(
    AppDatabase db, {
    DateTime? now,
  }) async {
    final ref = now ?? DateTime.now();
    final monthStart = DateTime(ref.year, ref.month, 1);
    final monthEnd = DateTime(ref.year, ref.month + 1, 1);
    final rows = await (db.select(db.events)
          ..where((t) => t.deletedAt.isNull())
          ..where(
            (t) =>
                t.startDt.isSmallerThanValue(monthEnd) &
                t.endDt.isBiggerOrEqualValue(monthStart),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.startDt)])
          ..limit(200))
        .get();
    final days = <int>{};
    for (final e in rows) {
      if (!e.endDt.isAfter(e.startDt)) {
        // Zero-length events still occupy their start day.
        final s = DateTime(e.startDt.year, e.startDt.month, e.startDt.day);
        if (!s.isBefore(monthStart) && s.isBefore(monthEnd)) {
          days.add(s.day);
        }
        continue;
      }
      var cursor = DateTime(e.startDt.year, e.startDt.month, e.startDt.day);
      if (cursor.isBefore(monthStart)) cursor = monthStart;
      while (cursor.isBefore(monthEnd) && cursor.isBefore(e.endDt)) {
        days.add(cursor.day);
        cursor = cursor.add(const Duration(days: 1));
      }
    }
    final sorted = days.toList()..sort();
    return sorted;
  }

  static Map<String, Object?> buildSnapshot({
    required List<Event> events,
    required List<Todo> todos,
    required int todoCount,
    required List<Event> upcomingEvents,
    required List<Todo> upcomingTodos,
    required WidgetUiStrings ui,
    required Map<String, Object?> theme,
    required DateTime generatedAt,
    List<WidgetPendingTap> pendingTaps = const [],
    List<int> monthEventDays = const [],
  }) {
    return {
      'version': snapshotVersion,
      'generatedAt': generatedAt.toUtc().toIso8601String(),
      'todayEvents': events.map(eventItem).toList(),
      'pendingTodos': todos.map(todoItem).toList(),
      'todoCount': todoCount,
      'upcoming': {
        'events': upcomingEvents.map(upcomingEventItem).toList(),
        'todos': upcomingTodos.map(upcomingTodoItem).toList(),
      },
      'pendingTaps': pendingTaps.map((t) => t.toJson()).toList(),
      // Additive on top of the frozen v2 shape: [[dayNumber, hasEvent]]
      // pairs for the current month — presence of the pair is what marks
      // the day, `hasEvent` is carried for contract-shape stability.
      'monthDots': [
        for (final day in monthEventDays) [day, true],
      ],
      'ui': ui.toBlock(),
      'theme': theme,
    };
  }

  // Parses `pendingTaps` out of a stored snapshot. Malformed JSON or
  // malformed entries degrade to "no taps" instead of throwing — a corrupt
  // channel must never block a widget refresh.
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

  // Resolution order: explicit locale param → persisted app locale →
  // platform locale (mirrors loadNotificationStrings — no BuildContext).
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
    );
  }

  // `system` falls back to platform brightness; emits the native-ready
  // dark flag + hex color tokens.
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

  static String encodeTodayEvents(List<Event> events) =>
      jsonEncode(events.map(legacyEventItem).toList());

  static String encodePendingTodos(List<Todo> todos) =>
      jsonEncode(todos.map(legacyTodoItem).toList());

  static Map<String, Object?> eventItem(Event e) => {
        'summary': e.summary,
        'start':
            '${e.startDt.hour.toString().padLeft(2, '0')}:${e.startDt.minute.toString().padLeft(2, '0')}',
        'isAllDay': e.isAllDay,
      };

  // `id` rides along so native checkbox taps can address the todo in
  // pendingTaps (native never writes the DB — it only appends the id).
  static Map<String, Object?> todoItem(Todo t) => {
        'id': t.id,
        'summary': t.summary,
        'dueDate':
            t.dueDate != null ? '${t.dueDate!.month}/${t.dueDate!.day}' : '',
      };

  static Map<String, Object?> upcomingEventItem(Event e) => {
        'summary': e.summary,
        'date': '${e.startDt.month}/${e.startDt.day}',
        'start':
            '${e.startDt.hour.toString().padLeft(2, '0')}:${e.startDt.minute.toString().padLeft(2, '0')}',
        'isAllDay': e.isAllDay,
      };

  static Map<String, Object?> upcomingTodoItem(Todo t) => {
        'summary': t.summary,
        'dueDate':
            t.dueDate != null ? '${t.dueDate!.month}/${t.dueDate!.day}' : '',
      };

  // Legacy payloads must be [[String: String]]: iOS CalendarTodoWidget.swift
  // casts today_events/pending_todos with `as? [[String: String]]`, and one
  // non-string value (the bool isAllDay) fails the whole array cast, leaving
  // the widget empty. macOS Swift reads isAllDay as `as? Bool` — it cannot
  // coexist with the iOS all-string contract, so legacy degrades macOS to
  // "All Day" labels until P4 retargets the Swift readers at widget_snapshot.
  static Map<String, String> legacyEventItem(Event e) => {
        'summary': e.summary,
        'start':
            '${e.startDt.hour.toString().padLeft(2, '0')}:${e.startDt.minute.toString().padLeft(2, '0')}',
        'isAllDay': '${e.isAllDay}',
      };

  static Map<String, String> legacyTodoItem(Todo t) => {
        'summary': t.summary,
        'dueDate':
            t.dueDate != null ? '${t.dueDate!.month}/${t.dueDate!.day}' : '',
      };
}
