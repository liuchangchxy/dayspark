import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/feature_flags_provider.dart';
import 'package:dayspark/domain/providers/default_tab_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/sync_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/background_sync_provider.dart';
import 'package:dayspark/domain/providers/home_widget_provider.dart';
import 'package:dayspark/domain/services/background_sync_service.dart';
import 'package:dayspark/domain/utils/recurring_event_helper.dart';
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
  final Set<int> _selectedTagIds = {};
  BackgroundSyncService? _syncService;

  // Cached date range — recalculated only when the current month changes.
  DateTimeRange? _cachedRange;
  int _cachedMonthKey = -1;

  DateTimeRange _calendarRange() {
    final now = DateTime.now();
    final monthKey = now.year * 100 + now.month;
    if (_cachedRange == null || _cachedMonthKey != monthKey) {
      _cachedMonthKey = monthKey;
      _cachedRange = DateTimeRange(
        start: DateTime(now.year, now.month - 1, 1),
        end: DateTime(now.year, now.month + 2, 1),
      );
    }
    return _cachedRange!;
  }

  @override
  void initState() {
    super.initState();
    // Default to today for the selected date
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);

    _currentTab = widget.initialTab >= 0
        ? widget.initialTab.clamp(0, 1)
        : (ref.read(defaultTabProvider) == AppTab.todos ? 1 : 0);
    WidgetsBinding.instance.addObserver(this);
    if (widget.initialTab < 0) {
      Future.microtask(() {
        if (!mounted) return;
        ref.listenManual(defaultTabProvider, (prev, next) {
          if (!_userChangedTab && prev != next && mounted) {
            setState(() {
              _currentTab = next == AppTab.todos ? 1 : 0;
            });
          }
        }, fireImmediately: true);
      });
    }
    Future.microtask(() async {
      try {
        final configured = ref.read(isCalDavConfiguredProvider).valueOrNull;
        if (configured == true) {
          final hasSynced = ref.read(lastSyncTimeProvider) != null;
          if (hasSynced) {
            ref.read(triggerIncrementalSyncProvider)();
          } else {
            ref.read(triggerFullSyncProvider)();
          }
        }
        if (!kIsWeb && !kDebugMode) {
          _syncService = ref.read(backgroundSyncServiceProvider);
          await _syncService!.init();
          _syncService!.startForeground();
        }
        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
          ref.read(updateHomeWidgetProvider)();
        }
        _checkOverdueTodos();
      } catch (e) {
        debugPrint('initState microtask error: $e');
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final service = ref.read(backgroundSyncServiceProvider);
    if (state == AppLifecycleState.resumed) {
      service.startForeground();
      _checkOverdueTodos();
    } else if (state == AppLifecycleState.paused) {
      service.stopForeground();
    }
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncService?.stopForeground();
    super.dispose();
  }

  bool get _todosFirst => ref.read(defaultTabProvider) == AppTab.todos;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final todosFirst = _todosFirst;
    final isCalendarTab = todosFirst ? _currentTab == 1 : _currentTab == 0;

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (ref
                  .watch(featureFlagsProvider)
                  .valueOrNull
                  ?.isEnabled(FeatureFlag.aiAssistant) ??
              true)
            IconButton(
              icon: const Icon(CupertinoIcons.sparkles),
              tooltip: l.aiAssistant,
              onPressed: () => context.push('/ai-chat'),
            ),
          IconButton(
            icon: const Icon(CupertinoIcons.search),
            tooltip: l.search,
            onPressed: () => context.push('/search'),
          ),
          IconButton(
            icon: const Icon(CupertinoIcons.settings),
            tooltip: l.settings,
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: isCalendarTab ? _buildCalendarTab() : _buildTodoTab(),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (isCalendarTab) {
            final now = DateTime.now();
            context.push(
              '/event/new?start=${now.millisecondsSinceEpoch}'
              '&end=${now.add(const Duration(hours: 1)).millisecondsSinceEpoch}',
            );
          } else {
            context.push('/todo/new');
          }
        },
        tooltip: isCalendarTab ? l.newEvent : l.newTodo,
        child: const Icon(CupertinoIcons.add),
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
    final eventsAsync = ref.watch(eventsInDateRangeProvider(range));

    return eventsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(l.error('$e'))),
      data: (events) {
        final adapters = expandRecurringEvents(events, range);
        return CalendarSection(
          events: adapters,
          onEventTapped: (event) => context.push('/event/edit', extra: event),
          onTimeSlotTapped: (range) {
            final timeLabel = DateFormatters.formatDateTime(range.start);
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '$timeLabel → ${DateFormatters.formatTime(range.end)}',
                ),
                duration: const Duration(seconds: 1),
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.only(bottom: 80),
              ),
            );
            context.push(
              '/event/new?start=${range.start.millisecondsSinceEpoch}'
              '&end=${range.end.millisecondsSinceEpoch}',
            );
          },
          onEventChanged: (event) async {
            final db = ref.read(databaseProvider);
            await (db.update(db.events)
                  ..where((t) => t.id.equals(event.drifId)))
                .write(event.toUpdateCompanion());
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
          onDateSelected: (date) => setState(() => _selectedDate = date),
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
                  IconButton(
                    icon: const Icon(CupertinoIcons.tag, size: 18),
                    tooltip: l.manageTags,
                    onPressed: () => context.push('/tags'),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(CupertinoIcons.trash, size: 18),
                    tooltip: l.trash,
                    onPressed: () => context.push('/trash'),
                    visualDensity: VisualDensity.compact,
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
    final tagKey = _selectedTagIds.isEmpty
        ? ''
        : (_selectedTagIds.toList()..sort()).join(',');

    if (_selectedDate == null) {
      // Inbox view — undated todos
      final inboxAsync = ref.watch(inboxTodosProvider);
      final completedAsync = ref.watch(completedTodosProvider);

      return inboxAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l.error('$e'))),
        data: (inboxTodos) {
          final completed = completedAsync.valueOrNull ?? [];
          if (inboxTodos.isEmpty && completed.isEmpty) {
            return _emptyState(l);
          }
          return ListView(
            children: [
              if (inboxTodos.isNotEmpty) ...[
                _sectionHeader(l.inbox, inboxTodos.length, null),
                ...inboxTodos.map((t) => _todoTile(t)),
              ],
              if (completed.isNotEmpty) ..._completedGroups(completed),
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
        final dateCompleted = completed.where((t) {
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

        return ListView(
          children: [
            if (overdue.isNotEmpty) ...[
              _sectionHeader(l.overdue, overdue.length, Colors.red),
              ...overdue.map((t) => _todoTile(t)),
            ],
            if (dateTodos.isNotEmpty) ...[
              _sectionHeader(
                _selectedDate == today
                    ? l.today
                    : l.dateLabel(date.month, date.day),
                dateTodos.length,
                Theme.of(context).colorScheme.primary,
              ),
              ...dateTodos.map((t) => _todoTile(t)),
            ],
            if (dateCompleted.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Divider(height: 1),
              ),
              _sectionHeader(l.completed, dateCompleted.length, null),
              ...dateCompleted.map((t) => _todoTile(t, isCompleted: true)),
            ],
          ],
        );
      },
    );
  }

  List<Widget> _completedGroups(List<Todo> completed) {
    // Group by completedAt date
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

    final widgets = <Widget>[
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Divider(height: 1),
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
        label = '${date.month}/${date.day}';
      }
      widgets.add(
        ExpansionTile(
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
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
          ),
          initiallyExpanded: date == today,
          tilePadding: const EdgeInsets.symmetric(horizontal: 8),
          children: todos.map((t) => _todoTile(t, isCompleted: true)).toList(),
        ),
      );
    }
    return widgets;
  }

  Widget _emptyState(AppLocalizations l) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            CupertinoIcons.checkmark_rectangle,
            size: 64,
            color: Colors.grey,
          ),
          const SizedBox(height: 16),
          Text(
            l.noPendingTodos,
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Text(
            l.tapToCreate,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
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
              color: accentColor ?? Colors.grey.shade600,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _todoTile(Todo todo, {bool isCompleted = false}) {
    return TodoListTile(
      summary: todo.summary,
      isCompleted: isCompleted,
      priority: todo.priority,
      todoId: todo.id,
      dueDate: todo.dueDate,
      onToggle: () =>
          ref.read(toggleTodoProvider)(id: todo.id, isCompleted: !isCompleted),
      onTap: () => context.push('/todo/edit', extra: todo),
    );
  }
}
