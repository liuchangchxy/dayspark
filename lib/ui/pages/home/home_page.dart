import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:calendar_todo_app/domain/models/calendar_event_adapter.dart';
import 'package:calendar_todo_app/domain/providers/events_provider.dart';
import 'package:calendar_todo_app/domain/providers/todos_provider.dart';
import 'package:calendar_todo_app/ui/widgets/calendar/calendar_section.dart';
import 'package:calendar_todo_app/ui/widgets/todo/todo_list_tile.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _currentTab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar Todo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            onPressed: () => context.go('/search'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.go('/settings'),
          ),
        ],
      ),
      body: _currentTab == 0 ? _buildCalendarTab() : _buildTodoTab(),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_currentTab == 0) {
            final now = DateTime.now();
            context.go(
              '/event/new?start=${now.millisecondsSinceEpoch}'
              '&end=${now.add(const Duration(hours: 1)).millisecondsSinceEpoch}',
            );
          } else {
            context.go('/todo/new');
          }
        },
        tooltip: _currentTab == 0 ? 'New Event' : 'New Todo',
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: (i) => setState(() => _currentTab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined), label: 'Calendar'),
          NavigationDestination(
              icon: Icon(Icons.checklist_outlined), label: 'Todos'),
        ],
      ),
    );
  }

  Widget _buildCalendarTab() {
    final now = DateTime.now();
    final rangeStart = DateTime(now.year, now.month - 1, 1);
    final rangeEnd = DateTime(now.year, now.month + 2, 1);
    final eventsAsync = ref.watch(
      eventsInDateRangeProvider(DateTimeRange(start: rangeStart, end: rangeEnd)),
    );

    return eventsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (events) {
        final adapters =
            events.map((e) => CalendaEventAdapter.fromDrift(e)).toList();
        return CalendarSection(
          events: adapters,
          onEventTapped: (event) => context.go('/event/edit', extra: event),
          onTimeSlotTapped: (range) {
            context.go(
              '/event/new?start=${range.start.millisecondsSinceEpoch}'
              '&end=${range.end.millisecondsSinceEpoch}',
            );
          },
        );
      },
    );
  }

  Widget _buildTodoTab() {
    final todosAsync = ref.watch(pendingTodosProvider);

    return todosAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (todos) {
        if (todos.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.checklist_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('No pending todos',
                    style: TextStyle(fontSize: 16, color: Colors.grey)),
                SizedBox(height: 8),
                Text('Tap + to create one',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          );
        }
        return ListView.separated(
          itemCount: todos.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 48),
          itemBuilder: (context, index) {
            final todo = todos[index];
            return TodoListTile(
              summary: todo.summary,
              isCompleted: todo.status == 'COMPLETED',
              priority: todo.priority,
              dueDate: todo.dueDate,
              onToggle: () => ref.read(completeTodoProvider)(todo.id),
              onTap: () => context.go('/todo/edit', extra: todo),
            );
          },
        );
      },
    );
  }
}
