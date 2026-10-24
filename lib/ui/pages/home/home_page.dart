import 'dart:async';
import 'package:intl/intl.dart';
import 'package:lunar/lunar.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/shell/workspace_navigation.dart';
import 'package:flutter/foundation.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/models/task_allocation_calendar_adapter.dart';
import 'package:dayspark/domain/providers/feature_flags_provider.dart';
import 'package:dayspark/domain/providers/default_tab_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/providers/todos_ui_prefs_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/home_widget_provider.dart';
import 'package:dayspark/domain/providers/locale_provider.dart';
import 'package:dayspark/domain/providers/record_bus_provider.dart';
import 'package:dayspark/domain/providers/theme_provider.dart';
import 'package:dayspark/infrastructure/platform/notification_service.dart';
import 'package:dayspark/domain/utils/recurring_event_helper.dart';
import 'package:dayspark/domain/providers/calendar_view_provider.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_section.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_deadline_lane.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_slot_sheet.dart';
import 'package:dayspark/ui/pages/home/action_section.dart';
import 'package:dayspark/domain/providers/action_projection_provider.dart';
import 'package:dayspark/ui/widgets/todo/date_strip.dart';
import 'package:dayspark/ui/widgets/todo/todo_list_tile.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';

/// The three primary destinations and their shared chrome.
///
/// Home owns navigation state; the sidebar (desktop) and the navigation bar
/// (mobile) are two presentations of the same three destinations, so neither
/// platform gains a navigation concept the other lacks.
class HomePage extends ConsumerStatefulWidget {
  final int initialTab;
  final DateTime Function()? clock;
  const HomePage({super.key, this.initialTab = -1, this.clock});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with WidgetsBindingObserver {
  bool _userChangedTab = false;
  // Expanding the six-things fold row is ephemeral: it collapses again when
  // the user leaves the date or turns the mode off.
  bool _sixThingsExpanded = false;
  final Set<int> _selectedTagIds = {};
  bool _calendarTabWasActive = false;
  // Page header title, pushed up from CalendarSection so it sits in the AppBar.
  // Kept as state rather than read in build(): the calendar owns its anchor.
  String? _calendarTitle;
  String? _calendarSubtitle;
  Timer? _dayCheckTimer;
  DateTime? _lastCheckedDay;

  DateTime _now() => (widget.clock ?? DateTime.now)();

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
    WidgetsBinding.instance.addObserver(this);
    _listenForDefaultTabChanges();
    _listenForWidgetRefreshTriggers();
    Future.microtask(_runStartupSideEffects);
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

  /// The active destination has exactly one owner — [workspaceTabProvider] —
  /// so the sidebar (which lives outside this page) and the in-page tab bar
  /// can never disagree about which pane is showing.
  int get _currentTab => _tabIndexFor(ref.watch(workspaceTabProvider));

  void _initCurrentTab() {
    final index = widget.initialTab >= 0
        ? widget.initialTab.clamp(0, 2)
        : _tabIndexFor(ref.read(defaultTabProvider));
    // Deferred: initState runs inside the build phase, and Riverpod forbids
    // mutating a provider while the tree is building.
    Future.microtask(() {
      if (mounted) {
        ref.read(workspaceTabProvider.notifier).state = AppTab.values[index];
      }
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

  /// Single writer for the active destination: the in-page tab bar, the
  /// sidebar and the persisted preference all funnel through here, so the
  /// sidebar highlight can never disagree with the content pane.
  void _setTab(int index) {
    _userChangedTab = true;
    ref.read(workspaceTabProvider.notifier).state =
        AppTab.values[index.clamp(0, 2)];
  }

  // Side effects run once after first frame: notification wiring, overdue
  // prompt, midnight day rollover check, changelog popup, cold-start widget
  // snapshot (ongoing refresh is write-driven via homeWidgetAutoRefreshProvider).
  Future<void> _runStartupSideEffects() async {
    try {
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
    final delay = midnight.difference(now);
    _dayCheckTimer = Timer(delay, () {
      if (!mounted) return;
      _handleDayRollover();
    });
  }

  // The widget snapshot and the reminder schedules both go stale across a day
  // boundary (today/upcoming buckets, reminders that fell due), so the
  // rollover refreshes both even when the calendar day itself did not change.
  void _handleDayRollover() {
    _refreshHomeWidget();
    _syncActionDateIfDayChanged();
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
    // The bus only carries in-process writes; the conservative full recompute
    // is what catches an external process (CLI) editing the same file, plus
    // any write path not yet migrated to the seam.
    unawaited(ref.read(reminderReconcilerProvider).reconcileAll());
    _dayCheckTimer?.cancel();
    _scheduleNextMidnightCheck();
  }

  void _refreshHomeWidget() {
    unawaited(ref.read(updateHomeWidgetProvider)());
  }

  void _listenForWidgetRefreshTriggers() {
    Future.microtask(() {
      if (!mounted) return;
      // Widget copy and colors are baked into the snapshot at build time, so
      // a language or theme change must rebuild it through this same entry
      // point — a listener per setting would eventually miss one.
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
      // Route through the toggle provider so completing from a notification
      // also cancels the todo's remaining reminder notifications.
      await ref.read(toggleTodoProvider)(id: parentId, isCompleted: true);
    } else if (actionId == NotificationActions.snooze) {
      if (reminderId == null) return;
      final l = AppLocalizations.of(context)!;
      final newTime = DateTime.now().add(const Duration(hours: 1));
      // Snooze addresses the reminder row id, not the parent id, so it
      // lands in the same notification id space cancel() can reach.
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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final desktop = isWorkspaceLayout(context);
    final isActionTab = _currentTab == 0;
    final isCalendarTab = _currentTab == 1;
    final pageLabel = isActionTab
        ? l.action
        : isCalendarTab
        ? l.calendar
        : l.todos;

    // Refresh events stream when switching to calendar tab
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

    final content = Scaffold(
      backgroundColor: desktop ? Theme.of(context).colorScheme.surface : null,
      appBar: desktop
          ? null
          : AppBar(
              titleSpacing: AppSpacing.lg,
              centerTitle: false,
              title: Text(
                l.appName,
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Container(height: 1, color: context.semantic.separator),
              ),
              actions: [
                Semantics(
                  button: true,
                  label: l.search,
                  child: IconButton(
                    icon: const Icon(CupertinoIcons.search),
                    tooltip: l.search,
                    onPressed: () => context.push('/search'),
                  ),
                ),
                if (ref
                        .watch(featureFlagsProvider)
                        .valueOrNull
                        ?.isEnabled(FeatureFlag.aiAssistant) ??
                    true)
                  Semantics(
                    button: true,
                    label: l.aiAssistant,
                    child: IconButton(
                      icon: const Icon(CupertinoIcons.sparkles),
                      tooltip: l.aiAssistant,
                      onPressed: () => context.push('/ai-chat'),
                    ),
                  ),
                Semantics(
                  button: true,
                  label: l.settings,
                  child: IconButton(
                    icon: const Icon(CupertinoIcons.settings),
                    tooltip: l.settings,
                    onPressed: () => context.push('/settings'),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                _buildCreateEntry(context, isCalendarTab: isCalendarTab),
                const SizedBox(width: AppSpacing.xs),
              ],
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPageHeader(
            context,
            l,
            desktop,
            isActionTab,
            isCalendarTab,
            pageLabel,
          ),
          Expanded(
            child: KeyedSubtree(
              key: ValueKey('workspace-content-$_currentTab'),
              child: isActionTab
                  ? _buildActionTab()
                  : isCalendarTab
                  ? Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: desktop ? 28 : 0,
                      ),
                      child: _buildCalendarTab(),
                    )
                  : Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: desktop ? 28 : 0,
                      ),
                      child: _buildTodoTab(),
                    ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: desktop
          ? null
          : NavigationBar(
              selectedIndex: _currentTab,
              onDestinationSelected: _setTab,
              destinations: [
                NavigationDestination(
                  icon: const Icon(CupertinoIcons.bolt),
                  label: l.action,
                ),
                NavigationDestination(
                  icon: const Icon(CupertinoIcons.calendar),
                  label: l.calendar,
                ),
                NavigationDestination(
                  icon: const Icon(CupertinoIcons.checkmark_rectangle),
                  label: l.todos,
                ),
              ],
            ),
    );
    if (!desktop) return content;
    return WorkspaceScaffold(child: content);
  }

  Widget _buildPageHeader(
    BuildContext context,
    AppLocalizations l,
    bool desktop,
    bool isActionTab,
    bool isCalendarTab,
    String pageLabel,
  ) {
    final horizontal = desktop ? 28.0 : AppSpacing.lg;
    final (title, subtitle) = isCalendarTab
        ? (_calendarTitle ?? pageLabel, _calendarSubtitle ?? '')
        : isActionTab
        ? (l.today, _actionDateNote(ref.watch(actionDateProvider)))
        : (l.todos, '');
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontal,
        desktop ? AppSpacing.lg : AppSpacing.md,
        horizontal,
        AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: desktop
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.display,
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitle,
                    style: AppTypography.overline.copyWith(
                      color: context.semantic.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (desktop) ...[
            const SizedBox(width: AppSpacing.md),
            _buildCreateEntry(context, isCalendarTab: isCalendarTab),
          ],
        ],
      ),
    );
  }

  String _actionDateNote(DateTime date) {
    final locale = Localizations.localeOf(context);
    final weekday = DateFormat.EEEE(locale.toString()).format(date);
    if (locale.languageCode != 'zh') return weekday;
    final lunar = Lunar.fromDate(date);
    final l = AppLocalizations.of(context)!;
    return '$weekday · ${lunar.getMonthInChinese()}${l.month}${lunar.getDayInChinese()}';
  }

  Widget _buildActionTab() {
    return ActionSection(
      onNavigateToCalendar: () => _setTab(1),
      onEventTap: (event) => context.push('/event/detail', extra: event),
      onTodoTap: (todo) => context.push('/todo/detail', extra: todo),
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
    final viewed = ref.watch(viewedDateProvider);
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
          // Visible-window expansion: month grid reaches ~6 weeks around the
          // anchor ([-7, +34] days); ±45d covers it with margin.
          // Event tiles carry the calendar's colour, so the colour a user
          // picks in Manage Calendars is the one they see on the grid.
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
              context.push('/todo/detail', extra: todo);
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
            onEventTapped: (event) =>
                context.push('/event/detail', extra: event),
            onTaskAllocationTapped: (allocation) async {
              final db = ref.read(databaseProvider);
              final todo =
                  await (db.select(db.todos)
                        ..where((row) => row.id.equals(allocation.todoId)))
                      .getSingleOrNull();
              if (mounted && todo != null) {
                context.push('/todo/detail', extra: todo);
              }
            },
            onTimeSlotTapped: (range) {
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
                      taskAllocationsInDateRangeProvider(rangeKey),
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
            },
            // 拖拽改期只走 provider：重排提醒由提交后的领域事件接管
            // （旧的内联补丁与重排器并存会互相争抢）。
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

  Widget _buildCreateEntry(
    BuildContext context, {
    required bool isCalendarTab,
  }) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final label = isCalendarTab ? l.newEvent : l.newTodo;
    void onPressed() {
      if (isCalendarTab) {
        // Creating from the calendar means "on the day I am looking at", not
        // "at midnight": a new event should start at a plausible hour.
        final viewed = ref.read(viewedDateProvider);
        final now = DateTime.now();
        final isToday =
            viewed.year == now.year &&
            viewed.month == now.month &&
            viewed.day == now.day;
        final start = isToday
            ? DateTime(now.year, now.month, now.day, now.hour + 1)
            : DateTime(viewed.year, viewed.month, viewed.day, 9);
        context.push(
          '/event/new?start=${start.millisecondsSinceEpoch}'
          '&end=${start.add(const Duration(hours: 1)).millisecondsSinceEpoch}',
        );
      } else {
        context.push('/todo/new');
      }
    }

    return TextButton.icon(
      key: const ValueKey('workspace-create'),
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: AppTypography.caption.copyWith(fontWeight: FontWeight.w600),
      ),
      icon: const Icon(CupertinoIcons.add, size: 15),
      label: Text(label),
    );
  }

  Widget _tagFilterChip(BuildContext context, Tag tag) {
    final selected = _selectedTagIds.contains(tag.id);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: FilterChip(
        label: Text(tag.name),
        selected: selected,
        selectedColor: ColorUtils.parseHex(tag.color).withValues(alpha: 0.3),
        checkmarkColor: ColorUtils.parseHex(tag.color),
        onSelected: (v) {
          setState(() {
            if (v) {
              _selectedTagIds.add(tag.id);
            } else {
              _selectedTagIds.remove(tag.id);
            }
          });
        },
      ),
    );
  }

  Widget _buildTodoTab() {
    final l = AppLocalizations.of(context)!;
    final desktop = isWorkspaceLayout(context);
    final view = ref.watch(todosViewProvider);
    final tagsAsync = ref.watch(tagsProvider);
    final six = ref.watch(sixThingsModeProvider);

    return Column(
      children: [
        if (desktop)
          TodoDesktopToolbar(
            view: view,
            sixThingsMode: six,
            onViewSelected: (next) =>
                ref.read(todosViewProvider.notifier).state = next,
            onSixThingsToggle: _toggleSixThings,
            trailing: [_manageTagsButton(context, l), _trashButton(context, l)],
          )
        else
          DateStrip(
            view: view,
            sixThingsMode: six,
            onViewSelected: (next) =>
                ref.read(todosViewProvider.notifier).state = next,
            onSixThingsToggle: _toggleSixThings,
          ),
        tagsAsync.when(
          data: (tags) {
            if (desktop) {
              if (tags.isEmpty) return const SizedBox.shrink();
              return SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(right: AppSpacing.md),
                  children: tags
                      .map((tag) => _tagFilterChip(context, tag))
                      .toList(),
                ),
              );
            }
            return SizedBox(
              height: 48,
              child: Row(
                children: [
                  Expanded(
                    child: tags.isEmpty
                        ? const SizedBox.shrink()
                        : ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                            ),
                            children: tags
                                .map((tag) => _tagFilterChip(context, tag))
                                .toList(),
                          ),
                  ),
                  _manageTagsButton(context, l),
                  _trashButton(context, l),
                ],
              ),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
        Expanded(child: _buildTodoList(view)),
      ],
    );
  }

  void _toggleSixThings() {
    setState(() => _sixThingsExpanded = false);
    ref
        .read(sixThingsModeProvider.notifier)
        .setEnabled(!ref.read(sixThingsModeProvider));
  }

  Widget _manageTagsButton(BuildContext context, AppLocalizations l) {
    return Semantics(
      button: true,
      label: l.manageTags,
      child: IconButton(
        icon: const Icon(CupertinoIcons.tag, size: 18),
        tooltip: l.manageTags,
        onPressed: () => context.push('/tags'),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _trashButton(BuildContext context, AppLocalizations l) {
    return Semantics(
      button: true,
      label: l.trash,
      child: IconButton(
        icon: const Icon(CupertinoIcons.trash, size: 18),
        tooltip: l.trash,
        onPressed: () => context.push('/trash'),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildTodoList(TodosView view) {
    final l = AppLocalizations.of(context)!;
    final hideCompleted = ref.watch(hideCompletedProvider).valueOrNull ?? false;
    final sixThingsOn = ref.watch(sixThingsModeProvider);
    final todoTagMap = ref.watch(todoTagIdsMapProvider).valueOrNull ?? const {};
    final hasTagFilter = _selectedTagIds.isNotEmpty;
    bool matchesTags(Todo t) {
      if (!hasTagFilter) return true;
      final tags = todoTagMap[t.id];
      if (tags == null) return false;
      return _selectedTagIds.any((id) => tags.contains(id));
    }

    final tagKey = _selectedTagIds.isEmpty
        ? ''
        : (_selectedTagIds.toList()..sort()).join(',');

    if (view is TodosAllView) {
      final allAsync = ref.watch(allTodosProvider);
      return allAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l.error)),
        data: (todos) {
          final pending = todos
              .where((t) => t.status != 'COMPLETED' && t.status != 'CANCELLED')
              .where(matchesTags)
              .toList();
          final completed = hideCompleted
              ? <Todo>[]
              : todos
                    .where((t) => t.status == 'COMPLETED')
                    .where(matchesTags)
                    .toList();
          if (pending.isEmpty && completed.isEmpty) return _emptyState(l);
          return CustomScrollView(
            slivers: [
              if (pending.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _sectionHeader(l.allTasks, pending.length, null),
                ),
                SliverReorderableList(
                  itemCount: pending.length,
                  onReorderItem: (oldIndex, newIndex) =>
                      _onReorderItem(pending, oldIndex, newIndex),
                  itemBuilder: (context, index) {
                    final t = pending[index];
                    return _reorderableTodoTile(
                      t,
                      Key('all-${t.id}'),
                      index: index,
                    );
                  },
                ),
              ],
              if (completed.isNotEmpty) ..._completedSliverGroups(completed),
            ],
          );
        },
      );
    }

    if (view is TodosInboxView) {
      final inboxAsync = ref.watch(inboxTodosProvider);
      final completedAsync = ref.watch(completedTodosProvider);
      return inboxAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l.error)),
        data: (inboxTodos) {
          final filteredInbox = inboxTodos.where(matchesTags).toList();
          final completed = hideCompleted
              ? <Todo>[]
              : (completedAsync.valueOrNull ?? []).where(matchesTags).toList();
          if (filteredInbox.isEmpty && completed.isEmpty) {
            return _emptyState(l);
          }
          return CustomScrollView(
            slivers: [
              if (filteredInbox.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _sectionHeader(l.inbox, filteredInbox.length, null),
                ),
                SliverReorderableList(
                  itemCount: filteredInbox.length,
                  onReorderItem: (oldIndex, newIndex) =>
                      _onReorderItem(filteredInbox, oldIndex, newIndex),
                  itemBuilder: (context, index) {
                    final t = filteredInbox[index];
                    return _reorderableTodoTile(
                      t,
                      Key('inbox-${t.id}'),
                      index: index,
                    );
                  },
                ),
              ],
              if (completed.isNotEmpty) ..._completedSliverGroups(completed),
            ],
          );
        },
      );
    }

    final date = (view as TodosDayView).day;
    final tagFilteredAsync = ref.watch(pendingTodosByTagsProvider(tagKey));
    final completedAsync = ref.watch(completedTodosProvider);

    return tagFilteredAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(l.error)),
      data: (allPending) {
        final completed = completedAsync.valueOrNull ?? [];
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);

        final overdue = <Todo>[];
        final dateTodos = <Todo>[];

        for (final t in allPending) {
          if (t.dueDate == null) continue;
          final due = DateTime(
            t.dueDate!.year,
            t.dueDate!.month,
            t.dueDate!.day,
          );
          if (due.isBefore(today) && date.isAtSameMomentAs(today)) {
            overdue.add(t);
          } else if (due == date) {
            dateTodos.add(t);
          }
        }

        final dateCompleted = hideCompleted
            ? <Todo>[]
            : completed.where(matchesTags).where((t) {
                if (t.completedAt == null) return false;
                final c = DateTime(
                  t.completedAt!.year,
                  t.completedAt!.month,
                  t.completedAt!.day,
                );
                return c == date;
              }).toList();

        if (overdue.isEmpty && dateTodos.isEmpty && dateCompleted.isEmpty) {
          return _emptyState(l);
        }

        // Six-things convergence (Ivy Lee): on today only, the ordered list
        // collapses to 6 slots plus a "More" fold; the full list reappears
        // after expanding. The visible items are always a prefix of the
        // drag-ordered list, so reorder indices map 1:1 onto the full list.
        final capActive = sixThingsOn && date == today && !_sixThingsExpanded;
        final visibleTodos = capActive && dateTodos.length > 6
            ? dateTodos.sublist(0, 6)
            : dateTodos;
        final hiddenCount = dateTodos.length - visibleTodos.length;

        return CustomScrollView(
          slivers: [
            if (overdue.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _sectionHeader(
                  l.overdue,
                  overdue.length,
                  Theme.of(context).colorScheme.error,
                ),
              ),
              SliverList(
                delegate: SliverChildListDelegate(
                  overdue
                      .asMap()
                      .entries
                      .map((e) => _todoTile(e.value, index: e.key))
                      .toList(),
                ),
              ),
            ],
            if (dateTodos.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _sectionHeader(
                  date == today ? l.today : l.dateLabel(date.month, date.day),
                  dateTodos.length,
                  Theme.of(context).colorScheme.primary,
                ),
              ),
              SliverReorderableList(
                itemCount: visibleTodos.length,
                onReorderItem: (oldIndex, newIndex) =>
                    _onReorderItem(dateTodos, oldIndex, newIndex),
                itemBuilder: (context, index) {
                  final t = visibleTodos[index];
                  return _reorderableTodoTile(
                    t,
                    Key('date-${t.id}'),
                    index: index,
                  );
                },
              ),
              if (hiddenCount > 0)
                SliverToBoxAdapter(
                  child: _foldRow(
                    l.moreItems(hiddenCount),
                    CupertinoIcons.chevron_down,
                    () {
                      setState(() => _sixThingsExpanded = true);
                    },
                  ),
                ),
              if (_sixThingsExpanded && sixThingsOn && date == today)
                SliverToBoxAdapter(
                  child: _foldRow(
                    l.collapseList,
                    CupertinoIcons.chevron_up,
                    () {
                      setState(() => _sixThingsExpanded = false);
                    },
                  ),
                ),
            ],
            if (dateCompleted.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Divider(height: 1),
                ),
              ),
              SliverToBoxAdapter(
                child: _sectionHeader(l.completed, dateCompleted.length, null),
              ),
              SliverList(
                delegate: SliverChildListDelegate(
                  dateCompleted
                      .map((t) => _todoTile(t, isCompleted: true))
                      .toList(),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  void _onReorderItem(List<Todo> todos, int oldIndex, int newIndex) {
    final list = [...todos];
    // onReorderItem already reports newIndex adjusted for the removed item.
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    ref.read(reorderTodosProvider)(list.map((t) => t.id).toList());
  }

  /// Numbers that describe a position in an order only mean something when
  /// the order is the feature — that is Six Things on today.
  bool get _showsSequenceNumber {
    if (!ref.read(sixThingsModeProvider)) return false;
    final view = ref.read(todosViewProvider);
    if (view is! TodosDayView) return false;
    final now = DateTime.now();
    return view.day.year == now.year &&
        view.day.month == now.month &&
        view.day.day == now.day;
  }

  Widget _reorderableTodoTile(Todo todo, Key key, {required int index}) {
    final sixThingsNumber = _showsSequenceNumber ? index : null;
    final desktopDrag =
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows;
    // Per-tile Material: during a reorder drag the tile is reparented into
    // the drag overlay, where the Scaffold Material may already be defunct.
    final tile = Material(
      type: MaterialType.transparency,
      child: _todoTile(
        todo,
        index: sixThingsNumber,
        dragHandle: desktopDrag
            ? ReorderableDragStartListener(
                index: index,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(
                      CupertinoIcons.line_horizontal_3,
                      size: 16,
                      color: context.semantic.textTertiary,
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
    if (desktopDrag) return KeyedSubtree(key: key, child: tile);
    return ReorderableDelayedDragStartListener(
      key: key,
      index: index,
      child: tile,
    );
  }

  List<Widget> _completedSliverGroups(List<Todo> completed) {
    final groups = <DateTime, List<Todo>>{};
    for (final t in completed) {
      final date = t.completedAt != null
          ? DateTime(
              t.completedAt!.year,
              t.completedAt!.month,
              t.completedAt!.day,
            )
          : DateTime(1970, 1, 1);
      groups.putIfAbsent(date, () => []).add(t);
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final slivers = <Widget>[
      const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Divider(height: 1),
        ),
      ),
    ];

    final sortedDates = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final date in sortedDates) {
      final todos = groups[date]!;
      String label;
      if (date == today) {
        label = AppLocalizations.of(context)!.today;
      } else if (date == yesterday) {
        label = AppLocalizations.of(context)!.yesterday;
      } else {
        label = AppLocalizations.of(context)!.dateLabel(date.month, date.day);
      }
      slivers.add(
        SliverToBoxAdapter(
          child: ExpansionTile(
            title: Row(
              children: [
                Text(label, style: AppTypography.title),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${todos.length}',
                  style: AppTypography.caption.copyWith(
                    color: context.semantic.textSecondary,
                  ),
                ),
              ],
            ),
            initiallyExpanded: date == today,
            tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            children: todos
                .map((t) => _todoTile(t, isCompleted: true))
                .toList(),
          ),
        ),
      );
    }
    return slivers;
  }

  Widget _emptyState(AppLocalizations l) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Icon(
              CupertinoIcons.checkmark_rectangle,
              size: 56,
              color: context.semantic.textTertiary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            l.noPendingTodos,
            style: AppTypography.title.copyWith(
              color: context.semantic.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _foldRow(String label, IconData icon, VoidCallback onTap) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, int count, Color? accentColor) {
    return Padding(
      // Keeps the Todo section headers on the shared 28dp desktop content
      // origin that Action and Calendar already use.
      padding: EdgeInsets.fromLTRB(
        isWorkspaceLayout(context) ? 0 : AppSpacing.lg,
        AppSpacing.md,
        isWorkspaceLayout(context) ? 0 : AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Text(
            title,
            style: AppTypography.overline.copyWith(
              fontWeight: FontWeight.w600,
              color: accentColor ?? context.semantic.textSecondary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '$count',
            style: AppTypography.caption.copyWith(
              color: context.semantic.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _todoTile(
    Todo todo, {
    bool isCompleted = false,
    int? index,
    Widget? dragHandle,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: TodoListTile(
        dragHandle: dragHandle,
        summary: todo.summary,
        isCompleted: isCompleted,
        priority: todo.priority,
        todoId: todo.id,
        todo: todo,
        dueDate: todo.dueDate,
        startDate: todo.startDate,
        onToggle: (occurrenceId, nextCompleted) => ref.read(toggleTodoProvider)(
          id: todo.id,
          isCompleted: nextCompleted,
          occurrenceId: occurrenceId,
        ),
        onTap: () => context.push('/todo/detail', extra: todo),
      ),
    );
  }
}
