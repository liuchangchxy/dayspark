import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/models/task_allocation_calendar_adapter.dart';
import 'package:dayspark/domain/providers/action_projection_provider.dart';
import 'package:dayspark/domain/providers/date_context_provider.dart';
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
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/pages/event/event_detail_page.dart';
import 'package:dayspark/ui/pages/home/action_section.dart';
import 'package:dayspark/ui/pages/home/c_day_timeline.dart';
import 'package:dayspark/ui/pages/todo/todo_detail_page.dart';
import 'package:dayspark/ui/shell/workspace_navigation.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_deadline_lane.dart';
import 'package:dayspark/ui/widgets/schedule/month_year_picker.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_section.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_slot_sheet.dart';
import 'package:dayspark/ui/widgets/todo/date_strip.dart';
import 'package:dayspark/ui/widgets/todo/todo_list_tile.dart';
import 'package:dayspark/ui/widgets/todo/todo_quick_add.dart';
import 'package:dayspark/ui/widgets/todo/todo_quick_create_sheet.dart';

/// The three primary destinations and their shared chrome.
///
/// Home owns navigation state; the sidebar (desktop) and the tab bar (mobile)
/// are two presentations of the same three destinations, so neither platform
/// gains a navigation concept the other lacks.
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
  // Subtitle pushed up from CalendarSection so it can sit in the chrome.
  String? _calendarTitle;
  String? _calendarSubtitle;
  Timer? _dayCheckTimer;
  DateTime? _lastCheckedDay;

  DateTime _now() {
    final clock = widget.clock;
    return clock != null ? clock() : ref.read(clockNowProvider)();
  }

  static DateTimeRange _calendarRange() {
    return DateTimeRange(
      start: DateTime(2000, 1, 1),
      end: DateTime(2100, 12, 31),
    );
  }

  @override
  void initState() {
    super.initState();
    _initCurrentTab();
    _applyInitialTodoView();
    final initialDate = widget.initialDate;
    if (initialDate != null) {
      Future.microtask(() {
        if (!mounted) return;
        ref.read(browseDateProvider.notifier).state = DateTime(
          initialDate.year,
          initialDate.month,
          initialDate.day,
        );
      });
    }
    WidgetsBinding.instance.addObserver(this);
    _listenForDefaultTabChanges();
    _listenForWidgetRefreshTriggers();
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
        ref.read(browseDateProvider.notifier).state = DateTime(
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
      'inbox' => const TodosInboxView(),
      'all' => const TodosAllView(),
      'today' || 'date' || 'bydate' => const TodosDayView(),
      _ => null,
    };
    if (view == null) return;
    Future.microtask(() {
      if (!mounted) return;
      if (view is TodosDayView) {
        if (raw == 'today') {
          ref.read(browseDateProvider.notifier).state = dayOf(_now());
        } else {
          final date = widget.initialDate;
          ref.read(browseDateProvider.notifier).state = dayOf(
            date ?? _now(),
          );
        }
      }
      ref.read(todosViewProvider.notifier).state = view;
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
  }

  void _openAssistant() {
    if (GoRouter.maybeOf(context) == null) return;
    context.push('/ai-chat');
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

  void _syncActionDateIfDayChanged() {
    final current = _now();
    final today = DateTime(current.year, current.month, current.day);
    if (today != _lastCheckedDay) {
      _lastCheckedDay = today;
      ref.read(clockDayProvider.notifier).refresh();
    }
  }

  void _startDayCheckTimer() {
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    _lastCheckedDay = today;
    ref.read(clockDayProvider.notifier).refresh();
    _scheduleNextMidnightCheck();
  }

  void _scheduleNextMidnightCheck() {
    final now = _now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    final delay = midnight.difference(now);
    _dayCheckTimer = Timer(delay, () {
      if (!mounted) return;
      _handleDayRollover();
    });
  }

  void _handleDayRollover() {
    _refreshHomeWidget();
    _syncActionDateIfDayChanged();
    // The page captured its clock when it was built, and the projection is
    // not the only reader of it: relative labels and the timeline's now-line
    // keep yesterday's instant until something rebuilds this widget.
    if (mounted) setState(() {});
    _scheduleNextMidnightCheck();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _handleResumed();
    }
  }

  void _handleResumed() {
    _syncActionDateIfDayChanged();
    _refreshHomeWidget();
    unawaited(ref.read(reminderReconcilerProvider).reconcileAll());
    // Coming back from the background is the other way the clock can have
    // moved under the page; the same rebuild applies.
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
    final l = AppLocalizations.of(context)!;
    final desktop = isWorkspaceLayout(context);
    final width = MediaQuery.sizeOf(context).width;
    final tab = ref.watch(workspaceTabProvider);
    final isActionTab = tab == AppTab.action;
    final isCalendarTab = tab == AppTab.calendar;
    final selection = ref.watch(workspaceSelectionProvider);

    if (isCalendarTab && !_calendarTabWasActive) {
      _calendarTabWasActive = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final r = _calendarRange();
        final k =
            '${r.start.millisecondsSinceEpoch}-${r.end.millisecondsSinceEpoch}';
        ref.invalidate(eventsInDateRangeProvider(k));
      });
    } else if (!isCalendarTab) {
      _calendarTabWasActive = false;
    }

    final body = KeyedSubtree(
      key: ValueKey('workspace-content-$_currentTab'),
      child: isActionTab
          ? _buildActionTab(
              selection != null && desktop && width >= 1180
                  ? _buildDetailPane(selection)
                  : null,
            )
          : isCalendarTab
          ? _buildCalendarArea(selection, width, desktop)
          : _buildTodoArea(selection, width, desktop),
    );

    if (!desktop) {
      return Scaffold(
        backgroundColor: context.ds.bg,
        appBar: _mobileTopBar(context, l, tab),
        body: body,
        floatingActionButton: isCalendarTab
            ? FloatingActionButton(
                key: const ValueKey('calendar-create'),
                backgroundColor: context.ds.primary,
                foregroundColor: context.ds.surface,
                tooltip: l.eventLabel,
                onPressed: _openCalendarCreate,
                child: const Icon(CupertinoIcons.add, size: 22),
              )
            : null,
        bottomNavigationBar: _MobileTabBar(
          current: _currentTab,
          onSelected: (index) => index == 3 ? _openAssistant() : _setTab(index),
        ),
      );
    }

    return WorkspaceScaffold(
      clock: widget.clock,
      child: Scaffold(backgroundColor: context.ds.bg, body: body),
    );
  }

  PreferredSizeWidget _mobileTopBar(
    BuildContext context,
    AppLocalizations l,
    AppTab tab,
  ) {
    final ds = context.ds;
    final view = ref.watch(todosViewProvider);
    final isAction = tab == AppTab.action;
    final isCalendar = tab == AppTab.calendar;
    final title = isAction
        ? l.today
        : isCalendar
        ? l.calendar
        : view is TodosInboxView
        ? l.inbox
        : view is TodosAllView
        ? l.allTasks
        : l.todos;
    final subtitle = isAction
        ? _clockContext()
        : isCalendar
        ? (_calendarSubtitle ?? _fallbackCalendarContext())
        : null;
    final now = _now();
    // Scaffold reserves the status bar on top of the preferred size, so the bar
    // fills that slot instead of sitting at its top; without the inset the title
    // rendered underneath the clock on a real phone.
    final inset = MediaQuery.paddingOf(context).top;
    return PreferredSize(
      preferredSize: const Size.fromHeight(54),
      child: Container(
        height: 54 + inset,
        padding: EdgeInsets.only(
          top: inset,
          left: AppSpacing.s4,
          right: 4,
        ),
        color: ds.bg,
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.headline.copyWith(
                      color: ds.ink,
                      fontSize: 20,
                      height: 26 / 20,
                      letterSpacing: 0.1,
                    ),
                  ),
                  if (subtitle != null)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: isAction ? _pickDayFromHeader : null,
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.small.copyWith(
                          color: ds.ink3,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: ds.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  DateFormatters.formatTime(now),
                  style: AppTypography.small.copyWith(
                    color: ds.primary,
                    fontWeight: FontWeight.w600,
                    fontFeatures: AppTypography.tabular,
                    height: 1,
                  ),
                ),
              ],
            ),
            _MobileBarAction(
              icon: CupertinoIcons.search,
              tooltip: l.search,
              onPressed: () => context.push('/search'),
            ),
            _MobileBarAction(
              icon: CupertinoIcons.settings,
              tooltip: l.settings,
              onPressed: () => context.push('/settings'),
            ),
            _MobileBarAction(
              key: const ValueKey('workspace-create'),
              icon: CupertinoIcons.add,
              tooltip: isAction
                  ? l.newItem
                  : isCalendar
                  ? l.eventLabel
                  : l.newTodo,
              boxed: true,
              onPressed: () {
                if (isAction) {
                  _showCreateChooser(context);
                } else if (isCalendar) {
                  _openNewEvent(context);
                } else {
                  final v = ref.read(todosViewProvider);
                  showTodoQuickCreateSheet(
                    context,
                    contextDate:
                        v is TodosDayView
                            ? ref.read(browseDateProvider)
                            : null,
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  String _clockContext() {
    final now = _now();
    final locale = Localizations.localeOf(context).toString();
    return '${DateFormat.MMMd(locale).format(now)} · '
        '${DateFormat.E(locale).format(now)}';
  }

  Future<void> _pickDayFromHeader() async {
    final picked = await showMonthYearPicker(
      context,
      initial: dayOf(_now()),
    );
    if (picked == null || !mounted) return;
    ref.read(browseDateProvider.notifier).state = dayOf(picked);
    ref.read(todosViewProvider.notifier).state = const TodosDayView();
    _setTab(2);
  }

  String _fallbackCalendarContext() {
    final viewed = ref.watch(browseDateProvider);
    final locale = Localizations.localeOf(context).toString();
    return '${DateFormat.MMMd(locale).format(viewed)} · '
        '${DateFormat.E(locale).format(viewed)}';
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

  void _openTodo(Todo todo) {
    final width = MediaQuery.sizeOf(context).width;
    final tab = ref.read(workspaceTabProvider);
    final minPane = tab == AppTab.action ? 1180.0 : 900.0;
    if (width >= minPane) {
      ref.read(workspaceSelectionProvider.notifier).state = TodoSelection(todo);
      return;
    }
    context.push('/todo/detail', extra: todo);
  }

  void _openEvent(CalendaEventAdapter event) {
    final width = MediaQuery.sizeOf(context).width;
    final tab = ref.read(workspaceTabProvider);
    final minPane = tab == AppTab.calendar ? 1180.0 : 980.0;
    if (width >= minPane) {
      ref.read(workspaceSelectionProvider.notifier).state = EventSelection(
        event,
      );
      return;
    }
    context.push('/event/detail', extra: event);
  }

  Widget _buildActionTab(Widget? detail) {
    return ActionSection(
      now: _now(),
      onNavigateToCalendar: () => _setTab(1),
      onNavigateToUnplanned: () {
        ref.read(todosViewProvider.notifier).state = const TodosInboxView();
        _setTab(2);
      },
      onEventTap: _openEvent,
      onTodoTap: _openTodo,
      detail: detail,
    );
  }

  // ---------------------------------------------------------------- calendar

  Widget _buildCalendarArea(
    WorkspaceSelection? selection,
    double width,
    bool desktop,
  ) {
    final calendar = Padding(
      padding: EdgeInsets.symmetric(horizontal: desktop ? 24 : 0),
      child: _buildCalendarTab(),
    );
    if (!desktop || selection == null || width < 1180) return calendar;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: calendar),
        Container(width: 1, color: context.ds.line),
        SizedBox(width: 400, child: _buildDetailPane(selection)),
      ],
    );
  }

  Widget _buildCalendarTab() {
    final l = AppLocalizations.of(context)!;
    final range = _calendarRange();
    final rangeKey =
        '${range.start.millisecondsSinceEpoch}-${range.end.millisecondsSinceEpoch}';
    final eventsAsync = ref.watch(eventsInDateRangeProvider(rangeKey));
    final allocationsAsync = ref.watch(
      taskAllocationsInDateRangeProvider(rangeKey),
    );
    final viewed = ref.watch(browseDateProvider);
    final deadlineTodos = (ref.watch(allTodosProvider).valueOrNull ?? <Todo>[])
        .where(
          (todo) =>
              todo.rrule == null &&
              todo.dueDate != null &&
              todo.status != 'COMPLETED' &&
              todo.status != 'CANCELLED',
        )
        .toList();

    return eventsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(l.error)),
      data: (events) => allocationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l.error)),
        data: (allocationItems) {
          final calendarColors = {
            for (final calendar
                in ref.watch(calendarsProvider).valueOrNull ?? const [])
              calendar.id: ColorUtils.parseHex(calendar.color),
          };
          final adapters = expandRecurringEvents(
            events,
            before: viewed.subtract(const Duration(days: 45)),
            after: viewed.add(const Duration(days: 45)),
            colorForCalendar: (id) => calendarColors[id],
          );
          return CalendarSection(
            events: adapters,
            deadlines: deadlineTodos
                .map(
                  (todo) => CalendarDeadline(
                    todoId: todo.id,
                    title: todo.summary,
                    due: todo.dueDate!,
                  ),
                )
                .toList(),
            onDeadlineTapped: (deadline) {
              final todo = deadlineTodos.firstWhere(
                (todo) => todo.id == deadline.todoId,
              );
              _openTodo(todo);
            },
            allocations: allocationItems
                .map(TaskAllocationCalendarAdapter.fromItem)
                .toList(),
            hideHeader: true,
            onHeaderChanged: (title, subtitle) {
              if (title == _calendarTitle && subtitle == _calendarSubtitle) {
                return;
              }
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() {
                  _calendarTitle = title;
                  _calendarSubtitle = subtitle;
                });
              });
            },
            onEventTapped: _openEvent,
            onTaskAllocationTapped: (allocation) async {
              final db = ref.read(databaseProvider);
              final todo =
                  await (db.select(db.todos)
                        ..where((row) => row.id.equals(allocation.todoId)))
                      .getSingleOrNull();
              if (mounted && todo != null) {
                _openTodo(todo);
              }
            },
            onTimeSlotTapped: _openCalendarSlot,
            onEventChanged: (event) async {
              await ref.read(updateEventProvider)(
                event.drifId,
                event.toUpdateCompanion(),
              );
            },
            onTaskAllocationChanged: (allocation) async {
              try {
                await ref.read(rescheduleTaskAllocationProvider)(
                  id: allocation.id,
                  startAt: allocation.start,
                  endAt: allocation.end,
                );
              } catch (error) {
                ref.invalidate(taskAllocationsInDateRangeProvider(rangeKey));
                rethrow;
              }
            },
          );
        },
      ),
    );
  }


  void _openCalendarSlot(DateTimeRange range) {
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
      onCreateTodoHere: () => context.push(
        '/todo/new?start=${range.start.millisecondsSinceEpoch}'
        '&end=${range.end.millisecondsSinceEpoch}',
      ),
      onScheduleTodo: (todo, [occurrenceId]) async {
        try {
          await ref.read(createTaskAllocationProvider)(
            todoId: todo.id,
            startAt: range.start,
            endAt: range.end,
            occurrenceId: occurrenceId,
          );
          ref.invalidate(
            taskAllocationsInDateRangeProvider(
              '${DateTime(range.start.year, range.start.month, range.start.day).millisecondsSinceEpoch}-'
              '${DateTime(range.start.year, range.start.month, range.start.day + 1).millisecondsSinceEpoch}',
            ),
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  AppLocalizations.of(
                    context,
                  )!.scheduledTodoSuccess(todo.summary),
                ),
              ),
            );
          }
        } catch (e) {
          debugPrint('calendar: schedule todo failed: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  AppLocalizations.of(context)!.schedulingFailed,
                ),
              ),
            );
          }
        }
      },
    );
  }

  void _openCalendarCreate() {
    final now = _now();
    final browse = ref.read(browseDateProvider);
    final start = isSameDay(browse, now)
        ? DateTime(now.year, now.month, now.day, now.hour + 1)
        : DateTime(browse.year, browse.month, browse.day, 9);
    _openCalendarSlot(
      DateTimeRange(start: start, end: start.add(const Duration(hours: 1))),
    );
  }

  // ---------------------------------------------------------------- todos

  bool _matchesFilters(
    Todo todo,
    Map<int, Set<int>> tagMap,
    int? calendarFilter,
    Set<int> tagFilter,
    int? priorityFilter,
  ) {
    if (calendarFilter != null && todo.calendarId != calendarFilter) {
      return false;
    }
    if (priorityFilter != null && todo.priority != priorityFilter) {
      return false;
    }
    if (tagFilter.isNotEmpty) {
      final ids = tagMap[todo.id];
      if (ids == null || !tagFilter.any(ids.contains)) return false;
    }
    return true;
  }

  bool get _todoPaneVisible {
    final width = MediaQuery.sizeOf(context).width;
    final tab = ref.read(workspaceTabProvider);
    return width >= (tab == AppTab.action ? 980 : 900);
  }

  int _countVisibleTodos(TodosView view) {
    final tagMap = ref.watch(todoTagIdsMapProvider).valueOrNull ?? const {};
    final calendarFilter = ref.watch(todoCalendarFilterProvider);
    final tagFilter = ref.watch(todoTagFilterProvider);
    final priorityFilter = ref.watch(todoPriorityFilterProvider);
    final todos = switch (view) {
      TodosInboxView() =>
        ref.watch(unplannedTodosProvider).valueOrNull ?? const <Todo>[],
      TodosAllView() =>
        ref.watch(allTodosProvider).valueOrNull ?? const <Todo>[],
      TodosDayView() => _dayTodos(ref.watch(browseDateProvider)).cast<Todo>(),
    };
    return todos
        .where((t) => t.status != 'COMPLETED' && t.status != 'CANCELLED')
        .where(
          (t) => _matchesFilters(
            t,
            tagMap,
            calendarFilter,
            tagFilter,
            priorityFilter,
          ),
        )
        .length;
  }

  List<Todo> _dayTodos(DateTime day) =>
      ref.watch(projectedDayTodosProvider(dayOf(day))).valueOrNull ??
      const <Todo>[];

  (int, int) _backlogCounts(TodosView view) {
    final tagMap = ref.watch(todoTagIdsMapProvider).valueOrNull ?? const {};
    final calendarFilter = ref.watch(todoCalendarFilterProvider);
    final tagFilter = ref.watch(todoTagFilterProvider);
    final priorityFilter = ref.watch(todoPriorityFilterProvider);
    bool visible(Todo t) =>
        _matchesFilters(t, tagMap, calendarFilter, tagFilter, priorityFilter);
    bool active(Todo t) => t.status != 'COMPLETED' && t.status != 'CANCELLED';
    final today = DateTime(_now().year, _now().month, _now().day);

    final all = ref.watch(allTodosProvider).valueOrNull ?? const <Todo>[];
    final Iterable<Todo> base;
    if (view is TodosDayView) {
      final day = dayOf(ref.watch(browseDateProvider));
      base =
          ref.watch(projectedDayTodosProvider(day)).valueOrNull ??
          const <Todo>[];
    } else if (view is TodosInboxView) {
      base =
          ref.watch(unplannedTodosProvider).valueOrNull ?? const <Todo>[];
    } else {
      base = all;
    }
    final pending = base.where(active).where(visible).toList();
    var overdue = 0;
    for (final todo in pending) {
      final due = todo.dueDate;
      if (due == null) continue;
      if (DateTime(due.year, due.month, due.day).isBefore(today)) overdue++;
    }
    return (pending.length, overdue);
  }

  Widget _arrangeToDayBar(BuildContext context, AppLocalizations l) {
    final browse = ref.watch(browseDateProvider);
    final locale = Localizations.localeOf(context).toString();
    final label = l.arrangeToDay(
      '${DateFormat.MMMd(locale).format(browse)} '
      '${DateFormat.E(locale).format(browse)}',
    );
    return Container(
      decoration: BoxDecoration(
        color: context.ds.surface,
        border: Border(top: BorderSide(color: context.ds.line)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s2,
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: DsButton(
            key: const ValueKey('arrange-to-day'),
            label: label,
            tone: DsButtonTone.secondary,
            icon: CupertinoIcons.calendar_badge_plus,
            onPressed: () => showTodoQuickCreateSheet(
              context,
              contextDate: browse,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTodoArea(
    WorkspaceSelection? selection,
    double width,
    bool desktop,
  ) {
    final l = AppLocalizations.of(context)!;
    final view = ref.watch(todosViewProvider);
    final filters = _filterButton(context);
    final dueDays = <DateTime>{
      for (final todo
          in ref.watch(allTodosProvider).valueOrNull ?? const <Todo>[])
        if (todo.dueDate != null)
          DateTime(todo.dueDate!.year, todo.dueDate!.month, todo.dueDate!.day),
    };
    final twoColumn = desktop && width >= 900;
    final (backlogCount, backlogOverdue) = twoColumn
        ? _backlogCounts(view)
        : (0, 0);
    final listPane = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (twoColumn)
          TodoBacklogHead(
            view: view,
            count: backlogCount,
            overdue: backlogOverdue,
            dueDays: dueDays,
            onViewSelected: (next) =>
                ref.read(todosViewProvider.notifier).state = next,
            trailing: [
              _createTodoButton(context),
              const SizedBox(width: 2),
              filters,
            ],
          )
        else if (desktop)
          TodoDesktopToolbar(
            view: view,
            dueDays: dueDays,
            onViewSelected: (next) =>
                ref.read(todosViewProvider.notifier).state = next,
            trailing: [filters],
          )
        else
          DateStrip(
            view: view,
            dueDays: dueDays,
            onViewSelected: (next) =>
                ref.read(todosViewProvider.notifier).state = next,
            trailing: [filters],
          ),
        Expanded(child: _buildTodoList(view, selection)),
        if (!twoColumn)
          view is TodosDayView
              ? _arrangeToDayBar(context, l)
              : Container(
                  decoration: BoxDecoration(
                    color: context.ds.surface,
                    border: Border(top: BorderSide(color: context.ds.line)),
                  ),
                  child: const TodoQuickAdd(),
                ),
      ],
    );

    if (!twoColumn) return listPane;

    final ds = context.ds;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1240),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s5,
            vertical: AppSpacing.s4,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 610,
                child: Container(
                  decoration: BoxDecoration(
                    color: ds.surface,
                    border: Border.all(color: ds.line),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: listPane,
                ),
              ),
              const SizedBox(width: AppSpacing.s5),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: ds.surface,
                    border: Border.all(color: ds.line),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: selection is TodoSelection
                      ? _buildDetailPane(selection)
                      : _todoTimelinePane(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _todoTimelinePane(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    final data = ref.watch(actionProjectionProvider).valueOrNull;
    final allEvents = data?.events ?? const <CalendaEventAdapter>[];
    final dayEvents = <CalendaEventAdapter>[
      for (final event in allEvents)
        if (_sameDay(event.start, today) || _sameDay(event.end, today)) event,
    ];
    final dayAllocations = <TaskAllocationCalendarItem>[
      for (final item in data?.allocations ?? const <TaskAllocationCalendarItem>[])
        if (_sameDay(item.allocation.startAt.toLocal(), today) ||
            _sameDay(item.allocation.endAt.toLocal(), today))
          item,
    ];

    var planned = 0;
    for (final event in dayEvents) {
      if (event.isAllDay) continue;
      planned += event.end.difference(event.start).inMinutes;
    }
    for (final item in dayAllocations) {
      planned += item.allocation.endAt
          .difference(item.allocation.startAt)
          .inMinutes;
    }
    final free = (15 * 60 - planned).clamp(0, 15 * 60);
    final locale = Localizations.localeOf(context).toLanguageTag();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s4,
            AppSpacing.s3,
            AppSpacing.s4,
            AppSpacing.s2,
          ),
          child: Row(
            children: [
              Text(
                l.today,
                style: AppTypography.bodyStrong.copyWith(color: ds.ink),
              ),
              const SizedBox(width: 6),
              Text(
                '${DateFormat.MMMd(locale).format(today)} \u00b7 '
                '${DateFormat.E(locale).format(today)}',
                style: AppTypography.small.copyWith(color: ds.ink3),
              ),
              const Spacer(),
              Text(
                '${l.scheduledLabel} ${_minutesLabel(l, planned)}',
                style: AppTypography.small.copyWith(
                  color: ds.ink3,
                  fontFeatures: AppTypography.tabular,
                ),
              ),
              const SizedBox(width: AppSpacing.s3),
              Text(
                '${l.freeLabel} ${_minutesLabel(l, free)}',
                style: AppTypography.small.copyWith(
                  color: ds.ink2,
                  fontFeatures: AppTypography.tabular,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s4,
              0,
              AppSpacing.s4,
              AppSpacing.s3,
            ),
            child: CDayTimeline(
              day: today,
              now: now,
              events: dayEvents,
              allocations: dayAllocations,
              onEventTap: _openEvent,
              onAllocationTap: (item) => _openTodo(item.todo),
            ),
          ),
        ),
      ],
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _minutesLabel(AppLocalizations l, int totalMinutes) {
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours == 0) return l.durationMinutes(minutes);
    if (minutes == 0) return l.durationHours(hours);
    return l.durationHoursMinutes(hours, minutes);
  }

  int get _filterCount {
    var count = 0;
    if (ref.watch(todoCalendarFilterProvider) != null) count++;
    if (ref.watch(todoTagFilterProvider).isNotEmpty) count++;
    if (ref.watch(todoPriorityFilterProvider) != null) count++;
    return count;
  }

  Widget _createTodoButton(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final view = ref.watch(todosViewProvider);
    return DsIconButton(
      key: const ValueKey('workspace-create-todo'),
      icon: CupertinoIcons.add,
      tooltip: l.addTodoShort,
      size: 17,
      compact: true,
      onPressed: () => showTodoQuickCreateSheet(
        context,
        contextDate:
            view is TodosDayView ? ref.read(browseDateProvider) : null,
      ),
    );
  }

  Widget _filterButton(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final count = _filterCount;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        DsIconButton(
          icon: CupertinoIcons.slider_horizontal_3,
          tooltip: l.filterAndDisplay,
          size: 17,
          compact: true,
          onPressed: () => _showFilterSheet(context),
        ),
        if (count > 0)
          Positioned(
            right: 2,
            top: 2,
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
            padding: const EdgeInsets.only(bottom: AppSpacing.s2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DsGroupLabel(l.calendar),
                Wrap(
                  spacing: AppSpacing.s2,
                  runSpacing: AppSpacing.s2,
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
                  const SizedBox(height: AppSpacing.s4),
                  DsGroupLabel(l.tags),
                  Wrap(
                    spacing: AppSpacing.s2,
                    runSpacing: AppSpacing.s2,
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
                const SizedBox(height: AppSpacing.s4),
                DsGroupLabel(l.priority),
                Wrap(
                  spacing: AppSpacing.s2,
                  runSpacing: AppSpacing.s2,
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
                const SizedBox(height: AppSpacing.s3),
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

  Widget _buildTodoList(TodosView view, WorkspaceSelection? selection) {
    final l = AppLocalizations.of(context)!;
    final hideCompleted = ref.watch(hideCompletedProvider).valueOrNull ?? false;
    final tagMap = ref.watch(todoTagIdsMapProvider).valueOrNull ?? const {};
    final calendarFilter = ref.watch(todoCalendarFilterProvider);
    final tagFilter = ref.watch(todoTagFilterProvider);
    final priorityFilter = ref.watch(todoPriorityFilterProvider);
    final selectedId = selection is TodoSelection ? selection.todo.id : null;

    bool visible(Todo t) =>
        _matchesFilters(t, tagMap, calendarFilter, tagFilter, priorityFilter);
    bool active(Todo t) => t.status != 'COMPLETED' && t.status != 'CANCELLED';

    Widget row(Todo todo, {bool completed = false, Widget? dragHandle}) {
      return TodoListTile(
        summary: todo.summary,
        isCompleted: completed || todo.status == 'COMPLETED',
        priority: todo.priority,
        todoId: todo.id,
        todo: todo,
        dueDate: todo.dueDate,
        startDate: todo.startDate,
        selected: _todoPaneVisible && selectedId == todo.id,
        dragHandle: dragHandle,
        onTap: () => _openTodo(todo),
        onToggle: (occurrenceId, next) => ref.read(toggleTodoProvider)(
          id: todo.id,
          isCompleted: next,
          occurrenceId: occurrenceId,
        ),
      );
    }

    final pendingCount = _countVisibleTodos(view);

    Widget reorderable(List<Todo> todos, String keyPrefix) {
      final showHandle = _desktopDrag && isWorkspaceLayout(context);
      return SliverReorderableList(
        itemCount: todos.length,
        onReorderItem: (oldIndex, newIndex) =>
            _onReorderItem(todos, oldIndex, newIndex),
        itemBuilder: (context, index) {
          final todo = todos[index];
          final key = ValueKey('$keyPrefix-${todo.id}');
          final tile = Material(
            type: MaterialType.transparency,
            child: row(
              todo,
              dragHandle: showHandle ? _dragHandle(index) : null,
            ),
          );
          if (showHandle) return KeyedSubtree(key: key, child: tile);
          return ReorderableDelayedDragStartListener(
            key: key,
            index: index,
            child: tile,
          );
        },
      );
    }

    List<Widget> completedSlivers(List<Todo> completed) {
      if (hideCompleted || completed.isEmpty) return const [];
      return [
        SliverToBoxAdapter(
          child: DsGroupHead(l.completed, count: completed.length),
        ),
        SliverList(
          delegate: SliverChildListDelegate([
            for (final todo in completed) row(todo, completed: true),
          ]),
        ),
      ];
    }

    List<Todo> completedFor(DateTime? day) {
      final base = ref.watch(completedTodosProvider).valueOrNull ?? const [];
      return base.where(visible).where((todo) {
        if (day == null) return true;
        final at = todo.completedAt;
        if (at == null) return false;
        return at.year == day.year &&
            at.month == day.month &&
            at.day == day.day;
      }).toList();
    }

    final slivers = <Widget>[];

    if (view is TodosAllView) {
      final async = ref.watch(allTodosProvider);
      if (async.isLoading && !async.hasValue) {
        return const Center(child: CircularProgressIndicator());
      }
      final pending = (async.valueOrNull ?? const <Todo>[])
          .where(active)
          .where(visible)
          .toList();
      final completed = completedFor(null);
      if (pending.isEmpty && completed.isEmpty) {
        return _todoEmpty(l, view);
      }
      if (pending.isNotEmpty) {
        slivers.add(
          SliverToBoxAdapter(
            child: DsGroupHead(l.allTasks, count: pendingCount),
          ),
        );
        slivers.add(reorderable(pending, 'all'));
      }
      slivers.addAll(completedSlivers(completed));
    } else if (view is TodosInboxView) {
      final async = ref.watch(unplannedTodosProvider);
      if (async.isLoading && !async.hasValue) {
        return const Center(child: CircularProgressIndicator());
      }
      final pending = (async.valueOrNull ?? const <Todo>[])
          .where(active)
          .where(visible)
          .toList();
      final completed = completedFor(null);
      if (pending.isEmpty && completed.isEmpty) {
        return _todoEmpty(l, view);
      }
      if (pending.isNotEmpty) {
        slivers.add(
          SliverToBoxAdapter(
            child: DsGroupHead(l.noPlannedExecution, count: pendingCount),
          ),
        );
        slivers.add(reorderable(pending, 'inbox'));
      }
      slivers.addAll(completedSlivers(completed));
    } else {
      final day = dayOf(ref.watch(browseDateProvider));
      final async = ref.watch(projectedDayTodosProvider(day));
      if (async.isLoading && !async.hasValue) {
        return const Center(child: CircularProgressIndicator());
      }
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final overdue = <Todo>[];
      final due = <Todo>[];
      for (final todo
          in (async.valueOrNull ?? const <Todo>[])
              .where(active)
              .where(visible)) {
        final when = todo.dueDate == null ? null : dayOf(todo.dueDate!);
        if (day == today && when != null && when.isBefore(today)) {
          overdue.add(todo);
        } else {
          due.add(todo);
        }
      }
      final completed = completedFor(day);
      if (overdue.isEmpty && due.isEmpty && completed.isEmpty) {
        return _todoEmpty(l, view);
      }
      if (overdue.isNotEmpty) {
        slivers.add(
          SliverToBoxAdapter(
            child: DsGroupHead(
              l.overdue,
              count: overdue.length,
              danger: true,
            ),
          ),
        );
        slivers.add(
          SliverList(
            delegate: SliverChildListDelegate([
              for (final todo in overdue) row(todo),
            ]),
          ),
        );
      }
      if (due.isNotEmpty) {
        slivers.add(
          SliverToBoxAdapter(
            child: DsGroupHead(
              l.dateLabel(day.month, day.day),
              count: due.length,
            ),
          ),
        );
        slivers.add(reorderable(due, 'date'));
      }
      slivers.addAll(completedSlivers(completed));
    }

    if (pendingCount == 0 && slivers.isEmpty) {
      return _todoEmpty(l, view);
    }

    slivers.add(
      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.s6)),
    );
    return CustomScrollView(slivers: slivers);
  }

  bool get _desktopDrag =>
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows;

  Widget _dragHandle(int index) {
    return ReorderableDragStartListener(
      index: index,
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(
            CupertinoIcons.line_horizontal_3,
            size: 16,
            color: context.ds.ink3,
          ),
        ),
      ),
    );
  }

  void _onReorderItem(List<Todo> todos, int oldIndex, int newIndex) {
    final list = [...todos];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    ref.read(reorderTodosProvider)(list.map((t) => t.id).toList());
  }

  Widget _todoEmpty(AppLocalizations l, TodosView view) {
    final inbox = view is TodosInboxView;
    return DsEmpty(
      icon: CupertinoIcons.checkmark_rectangle,
      title: inbox ? l.unplannedViewEmptyTitle : l.todosEmptyTitle,
      message: inbox ? l.unplannedViewEmptyHint : l.todosEmptyHint,
      action: DsButton(
        label: l.newTodo,
        tone: DsButtonTone.secondary,
        small: true,
        icon: CupertinoIcons.add,
        onPressed: () => showTodoQuickCreateSheet(
          context,
          contextDate:
              view is TodosDayView ? ref.read(browseDateProvider) : null,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- create

  void _openNewEvent(BuildContext context) {
    final viewed = ref.read(browseDateProvider);
    final now = DateTime.now();
    final isToday =
        viewed.year == now.year &&
        viewed.month == now.month &&
        viewed.day == now.day;
    final start = isToday
        ? DateTime(now.year, now.month, now.day, (now.hour + 1).clamp(0, 23))
        : DateTime(viewed.year, viewed.month, viewed.day, 9);
    context.push(
      '/event/new?start=${start.millisecondsSinceEpoch}'
      '&end=${start.add(const Duration(hours: 1)).millisecondsSinceEpoch}',
    );
  }

  Future<void> _showCreateChooser(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final now = DateTime.now();
    return showDsSheet<void>(
      context: context,
      title: l.newItem,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DsRow(
            title: l.todos,
            leading: Icon(
              CupertinoIcons.checkmark_rectangle,
              size: 18,
              color: context.ds.ink2,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 12),
            onTap: () {
              Navigator.of(context, rootNavigator: true).pop();
              showTodoQuickCreateSheet(context);
            },
          ),
          DsRow(
            title: l.newEvent,
            leading: Icon(
              CupertinoIcons.calendar_badge_plus,
              size: 18,
              color: context.ds.ink2,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 12),
            onTap: () {
              Navigator.of(context, rootNavigator: true).pop();
              final start = DateTime(
                now.year,
                now.month,
                now.day,
                (now.hour + 1).clamp(0, 23),
              );
              context.push(
                '/event/new?start=${start.millisecondsSinceEpoch}'
                '&end=${start.add(const Duration(hours: 1)).millisecondsSinceEpoch}',
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MobileTabBar extends StatelessWidget {
  const _MobileTabBar({required this.current, required this.onSelected});

  final int current;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    // The bar's left-to-right order is its own; each item names the destination
    // it opens so the two never drift apart. The last entry is not a tab: it
    // opens the assistant over whatever you were doing, so it is drawn as an
    // action on the end of the strip rather than a fourth destination.
    final items = [
      (l.today, CupertinoIcons.square_on_square, 0),
      (l.todos, CupertinoIcons.checkmark_circle, 2),
      (l.calendar, CupertinoIcons.calendar, 1),
      (l.aiAssistant, CupertinoIcons.sparkles, 3),
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
              for (var i = 0; i < items.length; i++) ...[
                if (items[i].$3 == 3)
                  Container(width: 1, height: 24, color: ds.line),
                Expanded(
                  child: _MobileTabSlot(
                    label: items[i].$1,
                    icon: items[i].$2,
                    // Three of these switch the workspace; the fourth opens the
                    // assistant and returns you here. Only a switcher can be the
                    // current page, so the action never draws a selected state.
                    isAction: items[i].$3 == 3,
                    selected: items[i].$3 != 3 && current == items[i].$3,
                    onTap: () => onSelected(items[i].$3),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One slot of the phone bar: a workspace tab, or the assistant action at the end.
class _MobileTabSlot extends StatelessWidget {
  const _MobileTabSlot({
    required this.label,
    required this.icon,
    required this.selected,
    required this.isAction,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool isAction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    // A tab's inactive label is tertiary; the assistant is a live action, so it
    // sits one step darker and reads as something to press rather than a place.
    final tint = selected ? ds.primary : (isAction ? ds.ink2 : ds.ink3);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      // InkWell rather than GestureDetector: a tab has to be reachable by
      // keyboard on a narrow desktop window, and a bare GestureDetector cannot
      // take focus or Enter.
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          onTap: onTap,
          splashFactory: NoSplash.splashFactory,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 26,
                child: Icon(icon, size: 21, color: tint),
              ),
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 48x48 touch target in the phone bar. [boxed] draws the create affordance
/// as a bordered square so it reads as the primary action.
class _MobileBarAction extends StatelessWidget {
  const _MobileBarAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.boxed = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool boxed;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        // InkWell, not GestureDetector: these are the only controls on a phone
        // bar and they have to answer Enter/Space on a narrow desktop window.
        child: InkWell(
          onTap: onPressed,
          splashFactory: NoSplash.splashFactory,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          child: Semantics(
            button: true,
            label: tooltip,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: boxed
                    ? Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: ds.surface,
                          border: Border.all(color: ds.line),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(icon, size: 15, color: ds.ink2),
                      )
                    : Icon(icon, size: 19, color: ds.ink3),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
