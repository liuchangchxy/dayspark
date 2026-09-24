import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/feature_flags_provider.dart';
import 'package:dayspark/domain/providers/default_tab_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/providers/todos_ui_prefs_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/home_widget_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/infrastructure/platform/notification_service.dart';
import 'package:dayspark/domain/utils/recurring_event_helper.dart';
import 'package:dayspark/domain/providers/calendar_view_provider.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_section.dart';
import 'package:dayspark/ui/widgets/todo/date_strip.dart';
import 'package:dayspark/ui/widgets/todo/todo_list_tile.dart';
import 'package:dayspark/l10n/app_localizations.dart';

class HomePage extends ConsumerStatefulWidget {
  final int initialTab;
  const HomePage({super.key, this.initialTab = -1});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with WidgetsBindingObserver {
  late int _currentTab;
  bool _userChangedTab = false;
  DateTime? _selectedDate = DateTime.now();
  bool _showAllTodos = false;
  // Expanding the six-things fold row is ephemeral: it collapses again when
  // the user leaves the date or turns the mode off.
  bool _sixThingsExpanded = false;
  final Set<int> _selectedTagIds = {};
  bool _calendarTabWasActive = false;
  Timer? _dayCheckTimer;
  DateTime? _lastCheckedDay;

  static DateTimeRange _calendarRange() {
    return DateTimeRange(
      start: DateTime(2000, 1, 1),
      end: DateTime(2030, 12, 31),
    );
  }

  @override
  void initState() {
    super.initState();
    _initSelectedDate();
    _initCurrentTab();
    WidgetsBinding.instance.addObserver(this);
    _listenForDefaultTabChanges();
    Future.microtask(_runStartupSideEffects);
  }

  void _initSelectedDate() {
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
  }

  void _initCurrentTab() {
    _currentTab = widget.initialTab >= 0
        ? widget.initialTab.clamp(0, 1)
        : (ref.read(defaultTabProvider) == AppTab.todos ? 1 : 0);
  }

  void _listenForDefaultTabChanges() {
    if (widget.initialTab >= 0) return;
    Future.microtask(() {
      if (!mounted) return;
      ref.listenManual(defaultTabProvider, (prev, next) {
        if (!_userChangedTab && prev != null && mounted) {
          setState(() {
            _currentTab = next == AppTab.todos ? 1 : 0;
          });
        }
      });
    });
  }

  // Side effects run once after first frame: notification wiring, overdue
  // prompt, midnight day rollover check, changelog popup, cold-start widget
  // snapshot (ongoing refresh is write-driven via homeWidgetAutoRefreshProvider).
  Future<void> _runStartupSideEffects() async {
    try {
      final notifService = NotificationService();
      notifService.onNotificationAction =
          (actionId, parentId, parentType, reminderId) {
            _handleNotificationAction(
              actionId,
              parentId,
              parentType,
              reminderId,
            );
          };
      _checkOverdueTodos();
      _startDayCheckTimer();
      _checkVersionChangelog();
      ref.read(updateHomeWidgetProvider)();
    } catch (e) {
      debugPrint('initState microtask error: $e');
    }
  }

  void _startDayCheckTimer() {
    final now = DateTime.now();
    _lastCheckedDay = DateTime(now.year, now.month, now.day);
    _scheduleNextMidnightCheck();
  }

  void _scheduleNextMidnightCheck() {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    final delay = midnight.difference(now);
    _dayCheckTimer = Timer(delay, () {
      if (!mounted) return;
      final current = DateTime.now();
      final today = DateTime(current.year, current.month, current.day);
      if (today != _lastCheckedDay) {
        _lastCheckedDay = today;
        _checkOverdueTodos();
      }
      _scheduleNextMidnightCheck();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkOverdueTodos();
      _dayCheckTimer?.cancel();
      _scheduleNextMidnightCheck();
    }
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
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l.whatsNew),
            content: SingleChildScrollView(
              child: Text('v$current'),
            ),
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
    } catch (e) { debugPrint('home: checkVersionChangelog error: $e'); }
  }

  Future<void> _checkOverdueTodos() async {
    final db = ref.read(databaseProvider);
    final overdue = await db.todosDao.getOverduePending();
    if (overdue.isEmpty || !mounted) return;

    final l = AppLocalizations.of(context)!;
    final moved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.overdue),
        content: Text(l.moveToTodayPrompt(overdue.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.skip),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.moveToToday),
          ),
        ],
      ),
    );

    if (moved == true && mounted) {
      await ref.read(moveOverdueToTodayProvider)(
        overdue.map((t) => t.id).toList(),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.movedToToday(overdue.length))));
      }
    }
  }

  void _handleNotificationAction(
    String actionId,
    int parentId,
    String parentType,
    int? reminderId,
  ) {
    if (!mounted) return;
    if (actionId == NotificationActions.markComplete && parentType == 'todo') {
      // Route through the toggle provider so completing from a notification
      // also cancels the todo's remaining reminder notifications.
      ref.read(toggleTodoProvider)(id: parentId, isCompleted: true);
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

  bool get _todosFirst => ref.read(defaultTabProvider) == AppTab.todos;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final todosFirst = _todosFirst;
    final isCalendarTab = todosFirst ? _currentTab == 1 : _currentTab == 0;

    // Refresh events stream when switching to calendar tab
    if (isCalendarTab && !_calendarTabWasActive) {
      _calendarTabWasActive = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final r = _calendarRange();
        final k = '${r.start.millisecondsSinceEpoch}-${r.end.millisecondsSinceEpoch}';
        ref.invalidate(eventsInDateRangeProvider(k));
      });
    } else if (!isCalendarTab) {
      _calendarTabWasActive = false;
    }

    return Scaffold(
      appBar: AppBar(
        actions: [
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
            label: l.search,
            child: IconButton(
              icon: const Icon(CupertinoIcons.search),
              tooltip: l.search,
              onPressed: () => context.push('/search'),
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
        ],
      ),
      body: isCalendarTab ? _buildCalendarTab() : _buildTodoTab(),
      floatingActionButton: Semantics(
        button: true,
        label: isCalendarTab ? l.newEvent : l.newTodo,
        child: FloatingActionButton(
          onPressed: () {
            if (isCalendarTab) {
              // Prefill with the date the calendar is showing (week view:
              // Monday anchor) so creation lands on the browsed week, not today.
              final viewed = ref.read(viewedDateProvider);
              context.push(
                '/event/new?start=${viewed.millisecondsSinceEpoch}'
                '&end=${viewed.add(const Duration(hours: 1)).millisecondsSinceEpoch}',
              );
            } else {
              context.push('/todo/new');
            }
          },
          tooltip: isCalendarTab ? l.newEvent : l.newTodo,
          child: const Icon(CupertinoIcons.add),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: (i) => setState(() {
          _userChangedTab = true;
          _currentTab = i;
        }),
        destinations: todosFirst
            ? [
                NavigationDestination(
                  icon: const Icon(CupertinoIcons.checkmark_rectangle),
                  label: l.todos,
                ),
                NavigationDestination(
                  icon: const Icon(CupertinoIcons.calendar),
                  label: l.calendar,
                ),
              ]
            : [
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
  }

  Widget _buildCalendarTab() {
    final l = AppLocalizations.of(context)!;
    final range = _calendarRange();
    final rangeKey =
        '${range.start.millisecondsSinceEpoch}-${range.end.millisecondsSinceEpoch}';
    final eventsAsync = ref.watch(eventsInDateRangeProvider(rangeKey));
    final viewed = ref.watch(viewedDateProvider);

    return eventsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(l.error('$e'))),
      data: (events) {
        // Visible-window expansion: month grid reaches ~6 weeks around the
        // anchor ([-7, +34] days); ±45d covers it with margin.
        final adapters = expandRecurringEvents(
          events,
          before: viewed.subtract(const Duration(days: 45)),
          after: viewed.add(const Duration(days: 45)),
        );
        return CalendarSection(
          events: adapters,
          onEventTapped: (event) => context.push('/event/edit', extra: event),
          onTimeSlotTapped: (range) {
            context.push(
              '/event/new?start=${range.start.millisecondsSinceEpoch}'
              '&end=${range.end.millisecondsSinceEpoch}',
            );
          },
          onEventChanged: (event) async {
            final db = ref.read(databaseProvider);
            final previous = await (db.select(
                  db.events,
                )..where((t) => t.id.equals(event.drifId)))
                .getSingleOrNull();
            await ref.read(updateEventProvider)(
              event.drifId,
              event.toUpdateCompanion(),
            );
            // Without this, dragged events keep notifications at the old time.
            final oldStart = previous?.startDt;
            if (oldStart != null && oldStart != event.start) {
              try {
                await ref.read(rescheduleRemindersProvider)(
                  parentType: 'event',
                  parentId: event.drifId,
                  oldReferenceTime: oldStart,
                  newReferenceTime: event.start,
                );
              } catch (e) {
                debugPrint('home: rescheduleReminders error: $e');
              }
            }
          },
        );
      },
    );
  }

  Widget _buildTodoTab() {
    final l = AppLocalizations.of(context)!;
    final tagsAsync = ref.watch(tagsProvider);
    return Column(
      children: [
        // Date strip
        DateStrip(
          selectedDate: _selectedDate,
          showAllMode: _showAllTodos,
          sixThingsMode:
              ref.watch(sixThingsModeProvider).valueOrNull ?? false,
          onSixThingsToggle: () {
            final current =
                ref.read(sixThingsModeProvider).valueOrNull ?? false;
            setState(() => _sixThingsExpanded = false);
            ref.read(setSixThingsModeProvider)(!current);
          },
          onDateSelected: (date) => setState(() {
            _selectedDate = date;
            _showAllTodos = false;
            _sixThingsExpanded = false;
          }),
          onShowAll: () => setState(() => _showAllTodos = true),
          onCalendarTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _selectedDate ?? DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null) {
              setState(() {
                _selectedDate = DateTime(picked.year, picked.month, picked.day);
              });
            }
          },
        ),
        // Tag filter chips + manage button
        tagsAsync.when(
          data: (tags) {
            return SizedBox(
              height: 36,
              child: Row(
                children: [
                  Expanded(
                    child: tags.isEmpty
                        ? const SizedBox.shrink()
                        : ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            children: tags.map((tag) {
                              final selected = _selectedTagIds.contains(tag.id);
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                child: FilterChip(
                                  label: Text(tag.name),
                                  selected: selected,
                                  selectedColor: ColorUtils.parseHex(
                                    tag.color,
                                  ).withValues(alpha: 0.3),
                                  checkmarkColor: ColorUtils.parseHex(
                                    tag.color,
                                  ),
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
                            }).toList(),
                          ),
                  ),
                  Semantics(
                    button: true,
                    label: l.manageTags,
                    child: IconButton(
                      icon: const Icon(CupertinoIcons.tag, size: 18),
                      tooltip: l.manageTags,
                      onPressed: () => context.push('/tags'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: l.trash,
                    child: IconButton(
                      icon: const Icon(CupertinoIcons.trash, size: 18),
                      tooltip: l.trash,
                      onPressed: () => context.push('/trash'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
        Expanded(child: _buildTodoList()),
      ],
    );
  }

  Widget _buildTodoList() {
    final l = AppLocalizations.of(context)!;
    final hideCompleted = ref.watch(hideCompletedProvider).valueOrNull ?? false;
    final sixThingsOn = ref.watch(sixThingsModeProvider).valueOrNull ?? false;
    final tagKey = _selectedTagIds.isEmpty
        ? ''
        : (_selectedTagIds.toList()..sort()).join(',');

    if (_showAllTodos) {
      final allAsync = ref.watch(allTodosProvider);
      return allAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l.error('$e'))),
        data: (todos) {
          final pending = todos
              .where((t) => t.status != 'COMPLETED' && t.status != 'CANCELLED')
              .toList();
          final completed = hideCompleted
              ? <Todo>[]
              : todos.where((t) => t.status == 'COMPLETED').toList();
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

    if (_selectedDate == null) {
      // Inbox view — undated todos
      final inboxAsync = ref.watch(inboxTodosProvider);
      final completedAsync = ref.watch(completedTodosProvider);

      return inboxAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l.error('$e'))),
        data: (inboxTodos) {
          final completed = hideCompleted
              ? <Todo>[]
              : (completedAsync.valueOrNull ?? []);
          if (inboxTodos.isEmpty && completed.isEmpty) {
            return _emptyState(l);
          }
          return CustomScrollView(
            slivers: [
              if (inboxTodos.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _sectionHeader(l.inbox, inboxTodos.length, null),
                ),
                SliverReorderableList(
                  itemCount: inboxTodos.length,
                  onReorderItem: (oldIndex, newIndex) =>
                      _onReorderItem(inboxTodos, oldIndex, newIndex),
                  itemBuilder: (context, index) {
                    final t = inboxTodos[index];
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

    // Date-based view
    final tagFilteredAsync = ref.watch(pendingTodosByTagsProvider(tagKey));
    final completedAsync = ref.watch(completedTodosProvider);

    return tagFilteredAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(l.error('$e'))),
      data: (allPending) {
        final completed = completedAsync.valueOrNull ?? [];
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final date = _selectedDate!;

        // Filter pending todos for the selected date
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

        // Filter completed for the selected date
        final dateCompleted = hideCompleted
            ? <Todo>[]
            : completed.where((t) {
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
        final capActive =
            sixThingsOn && date == today && !_sixThingsExpanded;
        final visibleTodos = capActive && dateTodos.length > 6
            ? dateTodos.sublist(0, 6)
            : dateTodos;
        final hiddenCount = dateTodos.length - visibleTodos.length;

        return CustomScrollView(
          slivers: [
            if (overdue.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _sectionHeader(l.overdue, overdue.length, Theme.of(context).colorScheme.error),
              ),
              SliverList(
                delegate: SliverChildListDelegate(
                  overdue.asMap().entries.map(
                    (e) => _todoTile(e.value, index: e.key),
                  ).toList(),
                ),
              ),
            ],
            if (dateTodos.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _sectionHeader(
                  _selectedDate == today
                      ? l.today
                      : l.dateLabel(date.month, date.day),
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
                  child: _foldRow(l.moreItems(hiddenCount), CupertinoIcons.chevron_down, () {
                    setState(() => _sixThingsExpanded = true);
                  }),
                ),
              if (_sixThingsExpanded && sixThingsOn && date == today)
                SliverToBoxAdapter(
                  child: _foldRow(l.collapseList, CupertinoIcons.chevron_up, () {
                    setState(() => _sixThingsExpanded = false);
                  }),
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

  Widget _reorderableTodoTile(Todo todo, Key key, {required int index}) {
    // Per-tile Material: during a reorder drag the tile is reparented into
    // the drag overlay, where the Scaffold Material may already be defunct.
    final tile = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        type: MaterialType.transparency,
        child: _todoTile(todo, index: index),
      ),
    );
    if (defaultTargetPlatform == TargetPlatform.linux || defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.windows) {
      return ReorderableDragStartListener(
        key: key,
        index: index,
        child: tile,
      );
    }
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
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${todos.length}',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            initiallyExpanded: date == today,
            tilePadding: const EdgeInsets.symmetric(horizontal: 8),
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
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l.noPendingTodos,
            style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            l.tapToCreate,
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, int count, Color? accentColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: accentColor ?? Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _todoTile(Todo todo, {bool isCompleted = false, int? index}) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: TodoListTile(
      index: index,
      summary: todo.summary,
      isCompleted: isCompleted,
      priority: todo.priority,
      todoId: todo.id,
      dueDate: todo.dueDate,
      startDate: todo.startDate,
      onToggle: () =>
          ref.read(toggleTodoProvider)(id: todo.id, isCompleted: !isCompleted),
      onTap: () => context.push('/todo/edit', extra: todo),
      ),
    );
  }
}
