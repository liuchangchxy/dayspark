import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/action_projection_provider.dart';
import 'package:dayspark/domain/providers/calendar_view_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/default_tab_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/home_widget_provider.dart';
import 'package:dayspark/domain/providers/locale_provider.dart';
import 'package:dayspark/domain/providers/record_bus_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/providers/theme_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/providers/todos_ui_prefs_provider.dart';
import 'package:dayspark/domain/utils/recurring_event_helper.dart';
import 'package:dayspark/infrastructure/platform/notification_service.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/a2.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/pages/calendar/a2_calendar_page.dart';
import 'package:dayspark/ui/pages/home/day_agenda.dart';
import 'package:dayspark/ui/pages/home/today_page.dart';
import 'package:dayspark/ui/pages/todo/a2_composer.dart';
import 'package:dayspark/ui/pages/todo/a2_todo_page.dart';
import 'package:dayspark/ui/pages/todo/todo_detail_page.dart';
import 'package:dayspark/ui/pages/event/event_detail_page.dart';
import 'package:dayspark/ui/shell/workspace_navigation.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_deadline_lane.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_slot_sheet.dart';
import 'package:dayspark/ui/widgets/calendar/view_switcher.dart';
import 'package:dayspark/ui/widgets/todo/todo_completion.dart';

/// A todo belongs in the calendar deadline lane only when it is an ordinary
/// (non-series) open todo with a due date.
///
/// Both recurrence columns count: `rrule` is the legacy projection and
/// `recurrenceRule` the spec one, and the DAO's "ordinary" predicate tests
/// both. Reading only `rrule` let a spec-only series leak in as a deadline.
bool isCalendarDeadlineCandidate(Todo todo) =>
    todo.rrule == null &&
    todo.recurrenceRule == null &&
    todo.dueDate != null &&
    todo.status != 'COMPLETED' &&
    todo.status != 'CANCELLED';

/// The three primary destinations and the chrome they share.
///
/// Today is the clock's day and nothing else; the Todo dated view and the
/// Calendar read one `viewedDateProvider` between them, so switching tabs can
/// never move the browsed date.
class HomePage extends ConsumerStatefulWidget {
  final int initialTab;
  final DateTime? initialDate;
  final String? initialTodoView;
  final DateTime Function()? clock;
  const HomePage({
    super.key,
    this.initialTab = -1,
    this.initialDate,
    this.initialTodoView,
    this.clock,
  });

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with WidgetsBindingObserver {
  bool _userChangedTab = false;
  bool _calendarTabWasActive = false;
  bool _urlSyncScheduled = false;
  Timer? _dayCheckTimer;
  DateTime? _lastCheckedDay;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  static DateTimeRange _calendarRange() {
    return DateTimeRange(
      start: DateTime(2000, 1, 1),
      end: DateTime(2100, 12, 31),
    );
  }

  static String _rangeKey(DateTimeRange range) =>
      '${range.start.millisecondsSinceEpoch}-'
      '${range.end.millisecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    _initCurrentTab();
    _applyInitialTodoView();
    final initialDate = widget.initialDate;
    if (initialDate != null) {
      Future.microtask(() {
        if (!mounted) return;
        ref.read(viewedDateProvider.notifier).state = DateTime(
          initialDate.year,
          initialDate.month,
          initialDate.day,
        );
      });
    }
    WidgetsBinding.instance.addObserver(this);
    _listenForDefaultTabChanges();
    _listenForWidgetRefreshTriggers();
    _listenForUrlStateChanges();
    Future.microtask(_runStartupSideEffects);
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTodoView != oldWidget.initialTodoView) {
      _applyInitialTodoView();
    }
    if (widget.initialTab >= 0 && widget.initialTab != oldWidget.initialTab) {
      Future.microtask(() {
        if (mounted) {
          ref
              .read(workspaceTabProvider.notifier)
              .setTab(AppTab.values[widget.initialTab.clamp(0, 2)]);
        }
      });
    }
    final initialDate = widget.initialDate;
    if (initialDate != null && initialDate != oldWidget.initialDate) {
      Future.microtask(() {
        if (!mounted) return;
        ref.read(viewedDateProvider.notifier).state = DateTime(
          initialDate.year,
          initialDate.month,
          initialDate.day,
        );
      });
    }
  }

  int _tabIndexFor(AppTab tab) {
    switch (tab) {
      case AppTab.action:
        return 0;
      case AppTab.calendar:
        return 1;
      case AppTab.todos:
        return 2;
    }
  }

  int get _currentTab => _tabIndexFor(ref.watch(workspaceTabProvider));

  void _initCurrentTab() {
    final index = widget.initialTab >= 0
        ? widget.initialTab.clamp(0, 2)
        : _tabIndexFor(ref.read(defaultTabProvider));
    Future.microtask(() {
      if (mounted) {
        ref.read(workspaceTabProvider.notifier).setTab(AppTab.values[index]);
      }
    });
  }

  void _applyInitialTodoView() {
    final raw = widget.initialTodoView;
    if (raw == null || raw.isEmpty) return;
    final view = switch (raw) {
      'inbox' || 'unplanned' => const TodosInboxView(),
      'all' => const TodosAllView(),
      'today' || 'date' => const TodosDayView(),
      _ => null,
    };
    if (view == null) return;
    Future.microtask(() {
      if (mounted) ref.read(todosViewProvider.notifier).state = view;
    });
  }

  void _listenForDefaultTabChanges() {
    if (widget.initialTab >= 0) return;
    Future.microtask(() {
      if (!mounted) return;
      ref.listenManual(defaultTabProvider, (prev, next) {
        if (!_userChangedTab && prev != null && mounted) {
          _setTab(_tabIndexFor(next));
        }
      });
    });
  }

  void _setTab(int index) {
    _userChangedTab = true;
    ref
        .read(workspaceTabProvider.notifier)
        .setTab(AppTab.values[index.clamp(0, 2)]);
    _scheduleUrlSync();
  }

  Future<void> _runStartupSideEffects() async {
    try {
      await _localizeDefaultCalendarName();
      final notifService = NotificationService();
      notifService
          .onNotificationAction = (actionId, parentId, parentType, reminderId) {
        unawaited(
          _handleNotificationAction(actionId, parentId, parentType, reminderId),
        );
      };
      _startDayCheckTimer();
      _checkVersionChangelog();
      _refreshHomeWidget();
    } catch (e) {
      debugPrint('initState microtask error: $e');
    }
  }

  Future<void> _localizeDefaultCalendarName() async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    if (l == null) return;
    final calendars = await ref.read(calendarsProvider.future);
    if (!mounted ||
        calendars.length != 1 ||
        calendars.single.name != 'Personal' ||
        !const {'#2563EB', '#5F7183'}.contains(calendars.single.color) ||
        calendars.single.name == l.defaultCalendarName) {
      return;
    }
    await ref.read(updateCalendarProvider)(
      id: calendars.single.id,
      name: l.defaultCalendarName,
    );
  }

  /// Today is the clock, and the projection is pinned to it. This is the only
  /// writer of the projection's date: navigation never touches it.
  void _syncActionDateIfDayChanged() {
    final current = _now();
    final today = DateTime(current.year, current.month, current.day);
    if (today != _lastCheckedDay) {
      _lastCheckedDay = today;
      ref.read(actionDateProvider.notifier).state = today;
    }
  }

  void _startDayCheckTimer() {
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    _lastCheckedDay = today;
    if (ref.read(actionDateProvider) != today) {
      ref.read(actionDateProvider.notifier).state = today;
    }
    _scheduleNextMidnightCheck();
  }

  void _scheduleNextMidnightCheck() {
    final now = _now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    _dayCheckTimer = Timer(midnight.difference(now), () {
      if (!mounted) return;
      _handleDayRollover();
    });
  }

  void _handleDayRollover() {
    _refreshHomeWidget();
    _syncActionDateIfDayChanged();
    if (mounted) setState(() {});
    _scheduleNextMidnightCheck();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _handleResumed();
  }

  void _handleResumed() {
    _syncActionDateIfDayChanged();
    _refreshHomeWidget();
    unawaited(ref.read(reminderReconcilerProvider).reconcileAll());
    if (mounted) setState(() {});
    _dayCheckTimer?.cancel();
    _scheduleNextMidnightCheck();
  }

  void _refreshHomeWidget() {
    unawaited(ref.read(updateHomeWidgetProvider)());
  }

  void _listenForWidgetRefreshTriggers() {
    Future.microtask(() {
      if (!mounted) return;
      ref.listenManual(localeProvider, (_, __) => _refreshHomeWidget());
      ref.listenManual(themeModeProvider, (_, __) => _refreshHomeWidget());
      ref.listenManual(themeColorProvider, (_, __) => _refreshHomeWidget());
    });
  }

  /// On the web the address bar is the shareable state: a reload or a pasted
  /// link has to land on the tab and day the reader was looking at.
  void _listenForUrlStateChanges() {
    if (!kIsWeb) return;
    Future.microtask(() {
      if (!mounted) return;
      ref.listenManual(viewedDateProvider, (_, __) => _scheduleUrlSync());
    });
  }

  void _scheduleUrlSync() {
    if (!kIsWeb || _urlSyncScheduled) return;
    _urlSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _urlSyncScheduled = false;
      if (!mounted) return;
      _syncHomeUrl();
    });
  }

  void _syncHomeUrl() {
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    final current = router.routerDelegate.currentConfiguration.uri;
    // A pushed page owns the address bar; the home state is only written while
    // home is what is on screen.
    if (current.path != '/') return;
    final tab = ref.read(workspaceTabProvider);
    final target = Uri(
      path: '/',
      queryParameters: {
        'tab': '${_tabIndexFor(tab)}',
        // Today is the clock's day: writing a browsable date there would
        // promise a navigation the page does not offer.
        if (tab != AppTab.action)
          'date': DateFormat('yyyy-MM-dd').format(ref.read(viewedDateProvider)),
      },
    );
    final same =
        current.queryParameters.length == target.queryParameters.length &&
        target.queryParameters.entries.every(
          (entry) => current.queryParameters[entry.key] == entry.value,
        );
    if (same) return;
    router.go(target.toString());
  }

  Future<void> _checkVersionChangelog() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final info = await PackageInfo.fromPlatform();
      final current = info.version;
      final lastSeen = prefs.getString('last_seen_version');
      if (lastSeen != null && lastSeen != current) {
        if (!mounted) return;
        final l = AppLocalizations.of(context)!;
        await showDialog<void>(
          animationStyle: AnimationStyle.noAnimation,
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l.whatsNew),
            content: SingleChildScrollView(child: Text('v$current')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l.changelogDismiss),
              ),
            ],
          ),
        );
      }
      prefs.setString('last_seen_version', current);
    } catch (e) {
      debugPrint('home: checkVersionChangelog error: $e');
    }
  }

  Future<void> _handleNotificationAction(
    String actionId,
    int parentId,
    String parentType,
    int? reminderId,
  ) async {
    if (!mounted) return;
    if (actionId == NotificationActions.markComplete && parentType == 'todo') {
      final todo =
          await (ref
                  .read(databaseProvider)
                  .select(ref.read(databaseProvider).todos)
                ..where((row) => row.id.equals(parentId)))
              .getSingleOrNull();
      if (!mounted || todo == null) return;
      if (todo.rrule != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.selectTodoOccurrence),
          ),
        );
        context.push('/todo/detail', extra: todo);
        return;
      }
      await ref.read(toggleTodoProvider)(id: parentId, isCompleted: true);
    } else if (actionId == NotificationActions.snooze) {
      if (reminderId == null) return;
      final l = AppLocalizations.of(context)!;
      final newTime = DateTime.now().add(const Duration(hours: 1));
      NotificationService().snooze(
        id: reminderId,
        title: parentType == 'event' ? l.eventReminder : l.todoReminder,
        body: l.snoozedReminder,
        scheduledTime: newTime,
        payload: NotificationPayload(
          parentType: parentType,
          parentId: parentId,
          reminderId: reminderId,
        ).encode(),
      );
    }
  }

  @override
  void dispose() {
    _dayCheckTimer?.cancel();
    NotificationService().onNotificationAction = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(workspaceTabProvider);
    final desktop = isWorkspaceLayout(context);

    if (tab == AppTab.calendar && !_calendarTabWasActive) {
      _calendarTabWasActive = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.invalidate(eventsInDateRangeProvider(_rangeKey(_calendarRange())));
      });
    } else if (tab != AppTab.calendar) {
      _calendarTabWasActive = false;
    }

    final page = KeyedSubtree(
      key: ValueKey('workspace-content-$_currentTab'),
      child: switch (tab) {
        AppTab.action => _todayPage(),
        AppTab.todos => _todoPage(desktop),
        AppTab.calendar => _calendarPage(),
      },
    );

    if (desktop) {
      final body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DesktopBar(
            current: tab,
            now: _now(),
            onSelect: (index) => _setTab(index),
            onCapture: _openComposer,
          ),
          Expanded(child: page),
        ],
      );
      // Ctrl K is the habit the old rail taught and the bar keeps a search
      // entry for; both must reach the same page.
      return _withSystemBack(
        tab,
        CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyK, control: true):
                _openSearch,
            const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
                _openSearch,
          },
          child: Focus(
            autofocus: true,
            onKeyEvent: _handleEscape,
            child: Scaffold(backgroundColor: context.ds.bg, body: body),
          ),
        ),
      );
    }

    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return _withSystemBack(
      tab,
      Scaffold(
        backgroundColor: context.ds.bg,
        resizeToAvoidBottomInset: true,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: SafeArea(bottom: false, child: page)),
            if (!keyboardOpen)
              _MobileDock(
                current: tab,
                onSelect: (index) => _setTab(index),
              ),
          ],
        ),
      ),
    );
  }

  /// Android's back button belongs to navigation, not to the process: on a
  /// destination other than Today it returns to Today first.
  Widget _withSystemBack(AppTab tab, Widget child) {
    return PopScope(
      canPop: tab == AppTab.action,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _setTab(0);
      },
      child: child,
    );
  }

  /// Escape closes the detail pane. Pushed pages own their own Escape path,
  /// and the pane is a selection rather than a route, so this is its only
  /// keyboard exit.
  KeyEventResult _handleEscape(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    if (ref.read(workspaceSelectionProvider) == null) {
      return KeyEventResult.ignored;
    }
    _clearSelection();
    return KeyEventResult.handled;
  }

  Widget _todayPage() {
    return A2TodayPage(
      now: _now(),
      onOpenTodo: _openTodo,
      onOpenEvent: _openEvent,
      onToggleTodo: _toggleTodo,
      onOpenUnplanned: () {
        ref.read(todosViewProvider.notifier).state = const TodosInboxView();
        _setTab(2);
      },
      onScheduleTodo: (todo) => _openComposer(todo: todo),
    );
  }

  Widget _todoPage(bool desktop) {
    final browseDate = ref.watch(viewedDateProvider);
    final selection = ref.watch(workspaceSelectionProvider);
    return A2TodoPage(
      now: _now(),
      dayAgenda: _dayAgenda(browseDate),
      detail: desktop && isMasterDetailLayout(context) && selection != null
          ? _buildDetailPane(selection)
          : null,
      onOpenTodo: _openTodo,
      onToggleTodo: _toggleTodo,
      onCapture: (text) => _captureOnTodoPage(text),
      onPlanDay: (day) => _openComposer(contextDate: day),
      onScheduleTodo: (todo) => _openComposer(todo: todo),
      onOpenEvent: _openEvent,
      onOpenUnplanned: () {
        ref.read(todosViewProvider.notifier).state = const TodosInboxView();
      },
      trailingActions: [
        _filterButton(context),
      ],
    );
  }

  Widget _calendarPage() {
    final range = _calendarRange();
    final key = _rangeKey(range);
    final eventsAsync = ref.watch(eventsInDateRangeProvider(key));
    final allocationsAsync = ref.watch(
      taskAllocationsInDateRangeProvider(key),
    );
    final browseDate = ref.watch(viewedDateProvider);
    final calendarColors = {
      for (final calendar in ref.watch(calendarsProvider).valueOrNull ?? const [])
        calendar.id: ColorUtils.parseHex(calendar.color),
    };
    final deadlineTodos = (ref.watch(allTodosProvider).valueOrNull ?? <Todo>[])
        .where(isCalendarDeadlineCandidate)
        .toList();

    // The grid draws what it has; a day with nothing to show is still a day,
    // and the toolbar must never wait on a query to appear.
    if (eventsAsync.hasError) {
      debugPrint('calendar: events error: ${eventsAsync.error}');
    }
    if (allocationsAsync.hasError) {
      debugPrint('calendar: allocations error: ${allocationsAsync.error}');
    }
    final adapters = expandRecurringEvents(
      eventsAsync.valueOrNull ?? const <Event>[],
      before: browseDate.subtract(const Duration(days: 60)),
      after: browseDate.add(const Duration(days: 60)),
      colorForCalendar: (id) => calendarColors[id],
    );
    return A2CalendarPage(
      events: adapters,
      allocations:
          allocationsAsync.valueOrNull ??
          const <TaskAllocationCalendarItem>[],
      deadlines: [
        for (final todo in deadlineTodos)
          CalendarDeadline(
            todoId: todo.id,
            title: todo.summary,
            due: todo.dueDate!,
          ),
      ],
      onEventTapped: _openEvent,
      onAllocationTapped: (item) => _openTodo(item.todo),
      onDeadlineTapped: (deadline) {
        for (final todo in deadlineTodos) {
          if (todo.id == deadline.todoId) {
            _openTodo(todo);
            return;
          }
        }
      },
      onTimeSlotTapped: (slot) => _openSlotSheet(slot, key),
      onCreateAtDay: (day) {
        // Calendar creation is an event, not a task: the day is the context,
        // and the form shows the time it starts with so nothing is silent.
        // The clock is the calendar's own, not a second reading of the wall.
        final clock = ref.read(calendarNowProvider)();
        final sameDay =
            day.year == clock.year &&
            day.month == clock.month &&
            day.day == clock.day;
        final start = DateTime(
          day.year,
          day.month,
          day.day,
          sameDay ? (clock.hour + 1).clamp(0, 23) : 9,
        );
        final end = start.add(const Duration(hours: 1));
        context.push(
          '/event/new?start=${start.millisecondsSinceEpoch}'
          '&end=${end.millisecondsSinceEpoch}',
        );
      },
      onEventChanged: (event) async {
        await ref.read(updateEventProvider)(
          event.drifId,
          event.toUpdateCompanion(),
        );
      },
      onAllocationChanged: (allocation) async {
        try {
          await ref.read(rescheduleTaskAllocationProvider)(
            id: allocation.allocation.id,
            startAt: allocation.allocation.startAt.toLocal(),
            endAt: allocation.allocation.endAt.toLocal(),
          );
        } catch (error) {
          ref.invalidate(taskAllocationsInDateRangeProvider(key));
          rethrow;
        }
      },
    );
  }

  void _openSlotSheet(DateTimeRange range, String rangeKey) {
    final l = AppLocalizations.of(context)!;
    CalendarSlotSheet.show(
      context: context,
      range: range,
      onCreateEvent: () {
        context.push(
          '/event/new?start=${range.start.millisecondsSinceEpoch}'
          '&end=${range.end.millisecondsSinceEpoch}',
        );
      },
      loadSchedulableTodos: () =>
          ref.read(databaseProvider).todosDao.getSchedulableTodos(),
      onCreateTodoHere: () => _openComposer(
        contextDate: DateTime(
          range.start.year,
          range.start.month,
          range.start.day,
        ),
        initialStart: range.start,
        initialEnd: range.end,
      ),
      onScheduleTodo: (todo, [occurrenceId]) async {
        try {
          await ref.read(createTaskAllocationProvider)(
            todoId: todo.id,
            startAt: range.start,
            endAt: range.end,
            occurrenceId: occurrenceId,
          );
          ref.invalidate(taskAllocationsInDateRangeProvider(rangeKey));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l.scheduledTodoSuccess(todo.summary))),
            );
          }
        } catch (e) {
          debugPrint('calendar: schedule todo failed: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l.schedulingFailed)),
            );
          }
        }
      },
    );
  }

  DayAgenda _dayAgenda(DateTime browseDate) {
    final range = _calendarRange();
    final key = _rangeKey(range);
    final calendars = ref.watch(calendarsProvider).valueOrNull ?? const [];
    final names = {for (final c in calendars) c.id: c.name};
    final colors = {
      for (final c in calendars) c.id: ColorUtils.parseHex(c.color),
    };
    final events = ref.watch(eventsInDateRangeProvider(key)).valueOrNull ??
        const <Event>[];
    final allocations =
        ref.watch(taskAllocationsInDateRangeProvider(key)).valueOrNull ??
        const [];
    final day = DateTime(browseDate.year, browseDate.month, browseDate.day);
    final adapted = expandRecurringEvents(
      events,
      before: day.subtract(const Duration(days: 2)),
      after: day.add(const Duration(days: 2)),
      colorForCalendar: (id) => colors[id],
    );
    final due = [
      for (final todo in ref.watch(allTodosProvider).valueOrNull ?? <Todo>[])
        if (todo.dueDate != null &&
            todo.dueDate!.year == day.year &&
            todo.dueDate!.month == day.month &&
            todo.dueDate!.day == day.day)
          todo,
    ];
    return DayAgenda.build(
      day: day,
      events: adapted,
      allocations: allocations,
      dueTodos: due,
      calendarNames: names,
      calendarColors: colors,
    );
  }

  Future<void> _captureOnTodoPage(String text) async {
    final l = AppLocalizations.of(context)!;
    final calendars = await ref.read(calendarsProvider.future);
    if (calendars.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.noCalendar)),
        );
      }
      return;
    }
    try {
      await ref.read(createTodoProvider)(
        calendarId: calendars.first.id,
        summary: text,
        priority: 0,
        status: 'NEEDS-ACTION',
      );
    } catch (error) {
      debugPrint('todo: capture failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.actionFailedRetry)),
        );
      }
    }
  }

  void _openComposer({
    DateTime? contextDate,
    Todo? todo,
    DateTime? initialStart,
    DateTime? initialEnd,
  }) {
    showA2Composer(
      context,
      contextDate: contextDate ?? ref.read(viewedDateProvider),
      todo: todo,
      initialStart: initialStart,
      initialEnd: initialEnd,
    );
  }

  /// The occurrence each series was last completed on, so the Undo the list
  /// offers can reopen that instance instead of asking which one again — the
  /// page only knows the row it ticked, and that row is the series.
  final Map<int, String> _completedOccurrenceByTodo = {};

  Future<bool> _toggleTodo(
    Todo todo,
    String? occurrenceId,
    bool completed,
  ) async {
    // The single completion entry point: a recurring series row has no one
    // occurrence to tick, so this asks which one instead of calling the
    // writer and surface its "requires an occurrenceId" StateError.
    // A completed series reopens as a series, not as one occurrence: the
    // remembered id only answers an undo of an instance completion.
    final canReuseOccurrence =
        !completed && occurrenceId == null && todo.status != 'COMPLETED';
    final undoOccurrence = canReuseOccurrence
        ? _completedOccurrenceByTodo[todo.id]
        : null;
    final result = await toggleTodoCompletion(
      context,
      ref,
      todo: todo,
      completed: completed,
      occurrenceId: occurrenceId ?? undoOccurrence,
    );
    if (!result.changed) return false;
    final resolved = result.occurrenceId;
    if (completed && resolved != null) {
      _completedOccurrenceByTodo[todo.id] = resolved;
    } else {
      _completedOccurrenceByTodo.remove(todo.id);
    }
    return true;
  }

  Widget _buildDetailPane(WorkspaceSelection selection) {
    return switch (selection) {
      TodoSelection(:final todo) => TodoDetailPane(
        key: ValueKey('pane-todo-${todo.id}'),
        todo: todo,
        embedded: true,
        onClose: _clearSelection,
        onDeleted: _clearSelection,
      ),
      EventSelection(:final event) => EventDetailPane(
        key: ValueKey('pane-event-${event.drifId}'),
        event: event,
        embedded: true,
        onClose: _clearSelection,
        onDeleted: _clearSelection,
      ),
    };
  }

  void _clearSelection() {
    ref.read(workspaceSelectionProvider.notifier).state = null;
  }

  void _openSearch() {
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    if (router.routerDelegate.currentConfiguration.uri.path == '/search') {
      return;
    }
    router.push('/search');
  }

  /// Whether a tap can be answered in place. The pane only exists on the Todo
  /// destination at the master-detail width; every other destination has to
  /// navigate, or the tap is silently lost.
  bool _rendersSelectionHere(AppTab tab) =>
      tab == AppTab.todos && isMasterDetailLayout(context);

  void _openTodo(Todo todo) {
    if (_rendersSelectionHere(ref.read(workspaceTabProvider))) {
      ref.read(workspaceSelectionProvider.notifier).state = TodoSelection(todo);
      return;
    }
    context.push('/todo/detail', extra: todo);
  }

  void _openEvent(CalendaEventAdapter event) {
    if (_rendersSelectionHere(ref.read(workspaceTabProvider))) {
      ref.read(workspaceSelectionProvider.notifier).state = EventSelection(
        event,
      );
      return;
    }
    context.push('/event/detail', extra: event);
  }

  int get _filterCount {
    var count = 0;
    if (ref.watch(todoCalendarFilterProvider) != null) count++;
    if (ref.watch(todoTagFilterProvider).isNotEmpty) count++;
    if (ref.watch(todoPriorityFilterProvider) != null) count++;
    return count;
  }

  Widget _filterButton(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final count = _filterCount;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        A2IconAction(
          icon: CupertinoIcons.slider_horizontal_3,
          tooltip: l.filterAndDisplay,
          onPressed: () => _showFilterSheet(context),
        ),
        if (count > 0)
          Positioned(
            right: 10,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: ds.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 9.5,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: ds.onPrimary,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _showFilterSheet(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final calendars =
        ref.read(calendarsProvider).valueOrNull ?? const <Calendar>[];
    final tags = ref.read(tagsProvider).valueOrNull ?? const <Tag>[];
    return showDsSheet<void>(
      context: context,
      title: l.filterAndDisplay,
      body: Consumer(
        builder: (ctx, r, _) {
          final ds = ctx.ds;
          final calFilter = r.watch(todoCalendarFilterProvider);
          final tagFilter = r.watch(todoTagFilterProvider);
          final prioFilter = r.watch(todoPriorityFilterProvider);
          final hideCompleted =
              r.watch(hideCompletedProvider).valueOrNull ?? false;
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DsGroupLabel(l.calendar),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final calendar in calendars)
                      DsChip(
                        label: calendar.name,
                        selected: calFilter == calendar.id,
                        leading: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: ColorUtils.parseHex(calendar.color),
                            shape: BoxShape.circle,
                          ),
                        ),
                        onTap: () =>
                            r.read(todoCalendarFilterProvider.notifier).state =
                                calFilter == calendar.id ? null : calendar.id,
                      ),
                  ],
                ),
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  DsGroupLabel(l.tags),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in tags)
                        DsChip(
                          label: tag.name,
                          selected: tagFilter.contains(tag.id),
                          leading: Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: ColorUtils.parseHex(tag.color),
                              shape: BoxShape.circle,
                            ),
                          ),
                          onTap: () {
                            final next = {...tagFilter};
                            if (!next.remove(tag.id)) next.add(tag.id);
                            r.read(todoTagFilterProvider.notifier).state = next;
                          },
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                DsGroupLabel(l.priority),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    DsChip(
                      label: l.priorityNone,
                      selected: prioFilter == null,
                      onTap: () =>
                          r.read(todoPriorityFilterProvider.notifier).state =
                              null,
                    ),
                    for (final entry in [
                      (1, l.priorityHigh),
                      (5, l.priorityMedium),
                      (9, l.priorityLow),
                    ])
                      DsChip(
                        label: entry.$2,
                        selected: prioFilter == entry.$1,
                        onTap: () =>
                            r.read(todoPriorityFilterProvider.notifier).state =
                                prioFilter == entry.$1 ? null : entry.$1,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: ds.lineSoft)),
                  ),
                  child: DsSettingRow(
                    label: hideCompleted ? l.hideCompleted : l.showCompleted,
                    trailing: Switch.adaptive(
                      value: !hideCompleted,
                      activeTrackColor: ds.primary,
                      onChanged: (show) =>
                          r.read(setHideCompletedProvider)(!show),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      actions: [
        DsButton(
          label: l.clearFilters,
          tone: DsButtonTone.ghost,
          small: true,
          onPressed: () {
            ref.read(todoCalendarFilterProvider.notifier).state = null;
            ref.read(todoTagFilterProvider.notifier).state = const {};
            ref.read(todoPriorityFilterProvider.notifier).state = null;
          },
        ),
        DsButton(
          label: l.done,
          small: true,
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
        ),
      ],
    );
  }
}

/// 56-high desktop bar: brand, date navigation, the clock, the three
/// destinations, capture and search. There is no sidebar in this product.
class _DesktopBar extends ConsumerWidget {
  const _DesktopBar({
    required this.current,
    required this.now,
    required this.onSelect,
    required this.onCapture,
  });

  final AppTab current;
  final DateTime now;
  final ValueChanged<int> onSelect;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final browseDate = ref.watch(viewedDateProvider);
    final locale = Localizations.localeOf(context).toString();
    final items = [
      (l.today, CupertinoIcons.house, AppTab.action),
      (l.todos, CupertinoIcons.checkmark_circle, AppTab.todos),
      (l.calendar, CupertinoIcons.calendar, AppTab.calendar),
    ];
    // Today answers to the clock, so its date is a read-out rather than a
    // browsable day: the arrows would move a date the page ignores.
    final isTodayTab = current == AppTab.action;
    final monthMode =
        current == AppTab.calendar &&
        ref.watch(calendarViewModeProvider) == CalendarViewMode.month;
    final shownDate = isTodayTab ? now : browseDate;
    // A wide face in a half-screen window cannot hold the wordmark, the date
    // and three labelled destinations; below the design's own width the
    // destinations keep their icons and drop their words.
    final iconOnly = !isMasterDetailLayout(context);
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: ds.bg,
        border: Border(bottom: BorderSide(color: ds.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ds.primary,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              'D',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1,
                color: ds.onPrimary,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'DaySpark',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              color: ds.ink,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 20, color: ds.line),
          const SizedBox(width: 8),
          if (!isTodayTab)
            _NavStep(
              icon: CupertinoIcons.chevron_left,
              tooltip: monthMode ? l.previousPeriod : l.previousDay,
              onTap: () => _step(ref, browseDate, monthMode, -1),
            ),
          Flexible(
            child: Text(
              '${DateFormat.MMMMd(locale).format(shownDate)} · '
              '${DateFormat.E(locale).format(shownDate)}',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: ds.ink,
                fontFeatures: AppTypography.tabular,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
          ),
          if (!isTodayTab)
            _NavStep(
              icon: CupertinoIcons.chevron_right,
              tooltip: monthMode ? l.nextPeriod : l.nextDay,
              onTap: () => _step(ref, browseDate, monthMode, 1),
            ),
          const SizedBox(width: 4),
          A2Clock(label: DateFormatters.formatTime(now)),
          const Spacer(),
          Row(
            children: [
              for (final item in items)
                _DesktopNavItem(
                  label: item.$1,
                  icon: item.$2,
                  iconOnly: iconOnly,
                  selected: current == item.$3,
                  onTap: () => onSelect(switch (item.$3) {
                    AppTab.action => 0,
                    AppTab.calendar => 1,
                    AppTab.todos => 2,
                  }),
                ),
            ],
          ),
          const SizedBox(width: 8),
          _QuickCapture(buttonLabel: l.captureQuickAddLabel, onTap: onCapture),
          const SizedBox(width: 4),
          SizedBox(
            width: 36,
            height: 36,
            child: IconButton(
              onPressed: () => context.push('/search'),
              tooltip: l.search,
              icon: Icon(CupertinoIcons.search, size: 17, color: ds.ink2),
            ),
          ),
        ],
      ),
    );
  }

  /// A day step barely moves the month grid, so on that surface the bar's
  /// arrows page the month and keep the browsed day (clamped) — the same
  /// contract the calendar page's own month header uses.
  void _step(WidgetRef ref, DateTime from, bool monthMode, int direction) {
    if (!monthMode) {
      ref.read(viewedDateProvider.notifier).state = from.add(
        Duration(days: direction),
      );
      return;
    }
    final first = DateTime(from.year, from.month + direction, 1);
    final lastDay = DateTime(first.year, first.month + 1, 0).day;
    ref.read(viewedDateProvider.notifier).state = DateTime(
      first.year,
      first.month,
      from.day.clamp(1, lastDay),
    );
  }
}

class _NavStep extends StatelessWidget {
  const _NavStep({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(icon, size: 14, color: ds.ink3),
        ),
      ),
    );
  }
}

class _DesktopNavItem extends StatelessWidget {
  const _DesktopNavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.iconOnly = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final color = selected ? ds.primary : ds.ink2;
    final item = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? ds.primarySoft : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: selected ? ds.primary : ds.ink3),
              if (!iconOnly) ...[
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: color,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    final padded = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: item,
    );
    if (!iconOnly) return padded;
    return Tooltip(message: label, child: padded);
  }
}

class _QuickCapture extends StatelessWidget {
  const _QuickCapture({required this.buttonLabel, required this.onTap});

  final String buttonLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: ds.surface,
            border: Border.all(color: ds.line),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(CupertinoIcons.plus, size: 12, color: ds.primary),
              const SizedBox(width: 5),
              Text(
                buttonLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: ds.ink,
                  fontFamilyFallback: AppTypography.fallback,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 56-high phone dock: 21px glyph, 11/500 label, primary when selected, no
/// badge. It is part of the body rather than `bottomNavigationBar` so the
/// keyboard can replace it instead of stacking above it.
class _MobileDock extends StatelessWidget {
  const _MobileDock({required this.current, required this.onSelect});

  final AppTab current;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final items = [
      (l.today, CupertinoIcons.house, AppTab.action),
      (l.calendar, CupertinoIcons.calendar, AppTab.calendar),
      (l.todos, CupertinoIcons.checkmark_circle, AppTab.todos),
    ];
    return Container(
      key: const ValueKey('mobile-tab-bar'),
      color: ds.navBg,
      child: SafeArea(
        top: false,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: ds.line)),
          ),
          child: Row(
            children: [
              for (final item in items)
                Expanded(
                  child: _MobileDockSlot(
                    label: item.$1,
                    icon: item.$2,
                    selected: current == item.$3,
                    onTap: () => onSelect(switch (item.$3) {
                      AppTab.action => 0,
                      AppTab.calendar => 1,
                      AppTab.todos => 2,
                    }),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileDockSlot extends StatelessWidget {
  const _MobileDockSlot({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final tint = selected ? ds.primary : ds.ink3;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          onTap: onTap,
          splashFactory: NoSplash.splashFactory,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(height: 26, child: Icon(icon, size: 21, color: tint)),
              Text(
                label,
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                  color: tint,
                  fontFamilyFallback: AppTypography.fallback,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
