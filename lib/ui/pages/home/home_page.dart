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

import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/theme/spec_tokens.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/action_projection_provider.dart';
import 'package:dayspark/domain/providers/calendar_view_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/default_calendar_provider.dart';
import 'package:dayspark/domain/providers/default_tab_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/home_widget_provider.dart';
import 'package:dayspark/domain/providers/locale_provider.dart';
import 'package:dayspark/domain/providers/record_bus_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/providers/theme_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/utils/recurring_event_helper.dart';
import 'package:dayspark/infrastructure/platform/notification_service.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/spec_drawer_overlay.dart';
import 'package:dayspark/ui/pages/calendar/a2_calendar_page.dart';
import 'package:dayspark/ui/pages/home/day_agenda.dart';
import 'package:dayspark/ui/pages/home/today_page.dart';
import 'package:dayspark/ui/pages/todo/a2_composer.dart';
import 'package:dayspark/ui/pages/todo/a2_todo_page.dart';
import 'package:dayspark/ui/pages/todo/todo_detail_page.dart';
import 'package:dayspark/ui/pages/event/event_detail_page.dart';
import 'package:dayspark/ui/shell/spark_top_bar.dart';
import 'package:dayspark/ui/shell/sync_status_banner.dart';
import 'package:dayspark/ui/shell/workspace_navigation.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_deadline_lane.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_slot_sheet.dart';
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

bool _initialLoading(AsyncValue<Object?> value) =>
    value.isLoading && !value.hasValue;

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
  Timer? _todayTicker;
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
    _startTodayTicker();
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

  /// The Today page paints "now" from the clock at build time, and group
  /// membership is derived from it. A minute that elapses while the page sits
  /// open must move both, so tick on the minute boundary instead of leaving
  /// the page frozen on the moment it was built.
  void _startTodayTicker() {
    _todayTicker?.cancel();
    final now = _now();
    final nextMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    );
    _todayTicker = Timer(nextMinute.difference(now), () {
      _refreshTodayClock();
      if (!mounted) return;
      _todayTicker = Timer.periodic(
        const Duration(minutes: 1),
        (_) => _refreshTodayClock(),
      );
    });
  }

  /// A tick is only worth a rebuild when Today is the visible destination;
  /// the other tabs read their own clocks when they are built.
  void _refreshTodayClock() {
    if (!mounted) return;
    if (ref.read(workspaceTabProvider) != AppTab.action) return;
    setState(() {});
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
    _startTodayTicker();
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
    _todayTicker?.cancel();
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

    final selection = ref.watch(workspaceSelectionProvider);
    final isDrawerOpen =
        desktop && canShowDesktopDrawer(context) && selection != null;
    final inlineDetail = isDrawerOpen && _usesInlineDetail(tab);

    if (desktop) {
      final body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SparkTopBar(
            clock: widget.clock,
            onSelect: (index) => _setTab(index),
          ),
          const SyncStatusBanner(),
          Expanded(
            child: inlineDetail
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: page),
                      _InlineDetailPane(child: _buildDetailPane(selection)),
                    ],
                  )
                : Stack(
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: isDrawerOpen ? _clearSelection : null,
                          child: page,
                        ),
                      ),
                      if (isDrawerOpen)
                        SpecDrawerOverlay(
                          width: specDrawerWidth(context),
                          child: _buildDetailPane(selection),
                        ),
                    ],
                  ),
          ),
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
            child: Scaffold(backgroundColor: SpecTokens.paper, body: body),
          ),
        ),
      );
    }

    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return _withSystemBack(
      tab,
      Scaffold(
        backgroundColor: SpecTokens.paper,
        resizeToAvoidBottomInset: true,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SyncStatusBanner(),
                    Expanded(child: page),
                  ],
                ),
              ),
            ),
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

  void _openInboxNoDate() {
    ref.read(todosInboxNoDateOnlyProvider.notifier).state = true;
    ref.read(todosViewProvider.notifier).state = const TodosInboxView();
    _setTab(2);
  }

  Widget _todayPage() {
    return A2TodayPage(
      now: _now(),
      onOpenTodo: _openTodo,
      onOpenEvent: _openEvent,
      onToggleTodo: _toggleTodo,
      onOpenUnplanned: _openInboxNoDate,
      onScheduleTodo: (todo) => _openComposer(todo: todo),
    );
  }

  Widget _todoPage(bool desktop) {
    final browseDate = ref.watch(viewedDateProvider);
    final dayView = ref.watch(todosViewProvider) is TodosDayView;
    final key = _rangeKey(_calendarRange());
    final eventsAsync = ref.watch(eventsInDateRangeProvider(key));
    final allocationsAsync = ref.watch(
      taskAllocationsInDateRangeProvider(key),
    );
    final todosAsync = ref.watch(allTodosProvider);
    final unplannedAsync = ref.watch(unplannedTodosProvider);
    final dayAgendaLoading = [
      eventsAsync,
      allocationsAsync,
      todosAsync,
      unplannedAsync,
    ].any(_initialLoading);
    final dayAgendaFailed = [
      eventsAsync,
      allocationsAsync,
      todosAsync,
      unplannedAsync,
    ].any((value) => value.hasError);
    return A2TodoPage(
      now: _now(),
      dayAgenda: _dayAgenda(browseDate),
      dayAgendaLoading: dayAgendaLoading,
      dayAgendaFailed: dayAgendaFailed,
      onRetryDayAgenda: () {
        ref.invalidate(eventsInDateRangeProvider(key));
        ref.invalidate(taskAllocationsInDateRangeProvider(key));
        ref.invalidate(allTodosProvider);
        ref.invalidate(unplannedTodosProvider);
        ref.invalidate(pendingTodosProvider);
        ref.invalidate(allActiveTaskAllocationsProvider);
      },
      onOpenTodo: _openTodo,
      onToggleTodo: _toggleTodo,
      onCapture: (text) => _captureOnTodoPage(text),
      onPlanDay: (day) => _openComposer(contextDate: day),
      onScheduleTodo: (todo) => _openComposer(
        todo: todo,
        contextDate: dayView ? browseDate : null,
      ),
      onOpenEvent: _openEvent,
      onOpenUnplanned: () {
        ref.read(todosInboxNoDateOnlyProvider.notifier).state = false;
        ref.read(todosViewProvider.notifier).state = const TodosInboxView();
      },
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
    final adaptedEvents = eventsAsync.whenData(
      (events) => expandRecurringEvents(
        events,
        before: browseDate.subtract(const Duration(days: 60)),
        after: browseDate.add(const Duration(days: 60)),
        colorForCalendar: (id) => calendarColors[id],
      ),
    );
    return A2CalendarPage(
      events: adaptedEvents.valueOrNull ?? const <CalendaEventAdapter>[],
      allocations:
          allocationsAsync.valueOrNull ??
          const <TaskAllocationCalendarItem>[],
      eventsAsync: adaptedEvents,
      allocationsAsync: allocationsAsync,
      onRetry: () {
        ref.invalidate(eventsInDateRangeProvider(key));
        ref.invalidate(taskAllocationsInDateRangeProvider(key));
      },
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
        calendarId:
            resolveNewEntryCalendarId(
              calendars: calendars,
              preferredId: ref.read(defaultCalendarIdProvider),
            ) ??
            calendars.first.id,
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
    final fallback = todo == null
        ? ref.read(viewedDateProvider)
        : DateTime(_now().year, _now().month, _now().day);
    showA2Composer(
      context,
      contextDate: contextDate ?? fallback,
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

  /// Todos reads detail as a column beside the list once the window is wide
  /// enough; Today stays an overlay, and a narrow desktop keeps the 360
  /// overlay rather than squeezing the list.
  bool _usesInlineDetail(AppTab tab) =>
      tab == AppTab.todos &&
      MediaQuery.sizeOf(context).width >= kWideDesktopBreakpoint;

  /// Whether a tap can be answered in place via the desktop drawer overlay.
  /// On wide layouts (>= 1000) Today, Calendar, and Todos destinations show
  /// the overlay drawer; on narrow layouts (< 1000) and mobile (< 720) it navigates.
  bool _rendersSelectionHere(AppTab tab) =>
      (tab == AppTab.action ||
          tab == AppTab.calendar ||
          tab == AppTab.todos) &&
      canShowDesktopDrawer(context);

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



}

class _InlineDetailPane extends StatelessWidget {
  const _InlineDetailPane({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return SizedBox(
      key: const ValueKey('spec-drawer-inline'),
      width: width >= kWideDesktopBreakpoint
          ? kDrawerWidthWide
          : kDrawerWidthNarrow,
      child: Container(
        decoration: const BoxDecoration(
          color: SpecTokens.paper,
          border: Border(left: BorderSide(color: SpecTokens.hair)),
        ),
        child: child,
      ),
    );
  }
}

class _MobileDock extends StatelessWidget {
  const _MobileDock({required this.current, required this.onSelect});

  final AppTab current;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final items = [
      (l.today, CupertinoIcons.sun_max, current == AppTab.action, () => onSelect(0)),
      (l.todos, CupertinoIcons.checkmark_alt, current == AppTab.todos, () => onSelect(2)),
      (l.calendar, CupertinoIcons.calendar, current == AppTab.calendar, () => onSelect(1)),
      (l.navMe, CupertinoIcons.person, false, () => context.push('/settings')),
    ];

    return Container(
      key: const ValueKey('mobile-tab-bar'),
      color: const Color(0xFFFBFBF8),
      child: SafeArea(
        top: false,
        child: Container(
          height: 56,
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: SpecTokens.hair, width: 1.0)),
          ),
          child: Row(
            children: [
              for (final item in items)
                Expanded(
                  child: _MobileDockSlot(
                    label: item.$1,
                    icon: item.$2,
                    selected: item.$3,
                    onTap: item.$4,
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
    final tint = selected ? SpecTokens.ink : SpecTokens.faint;
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
              SizedBox(height: 22, child: Icon(icon, size: 18, color: tint)),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  height: 1.2,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
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
