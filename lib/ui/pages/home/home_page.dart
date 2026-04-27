import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/feature_flags_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/sync_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/background_sync_provider.dart';
import 'package:dayspark/domain/providers/home_widget_provider.dart';
import 'package:dayspark/domain/services/background_sync_service.dart';
import 'package:dayspark/domain/utils/recurring_event_helper.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_section.dart';
import 'package:dayspark/ui/widgets/todo/todo_list_tile.dart';
import 'package:dayspark/l10n/app_localizations.dart';

class HomePage extends ConsumerStatefulWidget {
  final int initialTab;
  const HomePage({super.key, this.initialTab = 0});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> with WidgetsBindingObserver {
  late int _currentTab;
  bool _todoShowToday = true;
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
    _currentTab = widget.initialTab.clamp(0, 1);
    WidgetsBinding.instance.addObserver(this);
    // Trigger initial sync and start background sync service
    Future.microtask(() {
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
        _syncService!.init();
        _syncService!.startForeground();
      }
      // Update home screen widgets with today's data
      Future.microtask(() => ref.read(updateHomeWidgetProvider)());
      // Check for overdue todos on launch
      Future.microtask(() => _checkOverdueTodos());
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
      await ref.read(moveOverdueToTodayProvider)(overdue.map((t) => t.id).toList());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.movedToToday(overdue.length))),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncService?.stopForeground();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.appName),
        actions: [
          if (ref.watch(featureFlagsProvider).valueOrNull?.isEnabled(FeatureFlag.aiAssistant) ?? true)
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
            icon: const Icon(CupertinoIcons.tag),
            tooltip: l.tags,
            onPressed: () => context.push('/tags'),
          ),
          IconButton(
            icon: const Icon(CupertinoIcons.settings),
            tooltip: l.settings,
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: _currentTab == 0 ? _buildCalendarTab() : _buildTodoTab(),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_currentTab == 0) {
            final now = DateTime.now();
            context.push(
              '/event/new?start=${now.millisecondsSinceEpoch}'
              '&end=${now.add(const Duration(hours: 1)).millisecondsSinceEpoch}',
            );
          } else {
            context.push('/todo/new');
          }
        },
        tooltip: _currentTab == 0 ? l.newEvent : l.newTodo,
        child: const Icon(CupertinoIcons.add),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: (i) => setState(() => _currentTab = i),
        destinations: [
          NavigationDestination(
              icon: const Icon(CupertinoIcons.calendar), label: l.calendar),
          NavigationDestination(
              icon: const Icon(CupertinoIcons.checkmark_rectangle), label: l.todos),
        ],
      ),
    );
  }

  Widget _buildCalendarTab() {
    final l = AppLocalizations.of(context)!;
    final range = _calendarRange();
    final eventsAsync = ref.watch(
      eventsInDateRangeProvider(range),
    );

    return eventsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(l.error('$e'))),
      data: (events) {
        final adapters = expandRecurringEvents(events, range);
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: true, label: Text(l.todayTodo)),
              ButtonSegment(value: false, label: Text(l.allTasks)),
            ],
            selected: {_todoShowToday},
            onSelectionChanged: (s) => setState(() => _todoShowToday = s.first),
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll(
                Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
        ),
        Expanded(
          child: _todoShowToday ? _buildTodayTodoView(l) : _buildAllTodoView(l),
        ),
      ],
    );
  }

  Widget _buildTodayTodoView(AppLocalizations l) {
    final todosAsync = ref.watch(pendingTodosProvider);
    final completedAsync = ref.watch(completedTodosProvider);

    return todosAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(l.error('$e'))),
      data: (todos) {
        final completed = completedAsync.valueOrNull ?? [];
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);

        final overdue = <Todo>[];
        final todayTodos = <Todo>[];

        for (final t in todos) {
          if (t.dueDate == null) continue;
          final due = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
          if (due.isBefore(today)) {
            overdue.add(t);
          } else if (due == today) {
            todayTodos.add(t);
          }
        }

        final todayCompleted = completed.where((t) {
          if (t.completedAt == null) return false;
          final c = DateTime(t.completedAt!.year, t.completedAt!.month, t.completedAt!.day);
          return c == today;
        }).toList();

        final allEmpty = overdue.isEmpty && todayTodos.isEmpty && todayCompleted.isEmpty;
        if (allEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(CupertinoIcons.checkmark_rectangle, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(l.noPendingTodos,
                    style: const TextStyle(fontSize: 16, color: Colors.grey)),
                const SizedBox(height: 8),
                Text(l.tapToCreate,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          );
        }

        return ListView(
          children: [
            if (overdue.isNotEmpty) ...[
              _sectionHeader(l.overdue, overdue.length, Colors.red),
              ...overdue.map((t) => _todoTile(t)),
            ],
            if (todayTodos.isNotEmpty) ...[
              _sectionHeader(l.today, todayTodos.length, Theme.of(context).colorScheme.primary),
              ...todayTodos.map((t) => _todoTile(t)),
            ],
            if (todayCompleted.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Divider(height: 1),
              ),
              _sectionHeader(l.completed, todayCompleted.length, null),
              ...todayCompleted.map((t) => _todoTile(t, isCompleted: true)),
            ],
          ],
        );
      },
    );
  }

  Widget _buildAllTodoView(AppLocalizations l) {
    final todosAsync = ref.watch(pendingTodosProvider);
    final completedAsync = ref.watch(completedTodosProvider);

    return todosAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(l.error('$e'))),
      data: (todos) {
        final completed = completedAsync.valueOrNull ?? [];
        if (todos.isEmpty && completed.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(CupertinoIcons.checkmark_rectangle, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(l.noPendingTodos,
                    style: const TextStyle(fontSize: 16, color: Colors.grey)),
                const SizedBox(height: 8),
                Text(l.tapToCreate,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          );
        }
        return ListView(
          children: [
            if (todos.isNotEmpty)
              ...todos.map((t) => _todoTile(t)),
            if (completed.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Divider(height: 1),
              ),
              _sectionHeader(l.completed, completed.length, null),
              ...completed.map((t) => _todoTile(t, isCompleted: true)),
            ],
          ],
        );
      },
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
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade500,
            ),
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
      onToggle: () => ref.read(toggleTodoProvider)(
          id: todo.id, isCompleted: !isCompleted),
      onTap: () => context.push('/todo/edit', extra: todo),
    );
  }
}
