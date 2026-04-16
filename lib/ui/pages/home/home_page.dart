import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:calendar_todo_app/domain/models/calendar_event_adapter.dart';
import 'package:calendar_todo_app/domain/providers/events_provider.dart';
import 'package:calendar_todo_app/ui/widgets/calendar/calendar_section.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final rangeStart = DateTime(now.year, now.month - 1, 1);
    final rangeEnd = DateTime(now.year, now.month + 2, 1);
    final eventsAsync = ref.watch(
      eventsInDateRangeProvider(DateTimeRange(start: rangeStart, end: rangeEnd)),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar Todo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.go('/settings'),
          ),
        ],
      ),
      body: eventsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (events) {
          final adapters =
              events.map((e) => CalendaEventAdapter.fromDrift(e)).toList();

          return CalendarSection(
            events: adapters,
            onEventTapped: (event) {
              context.go('/event/edit', extra: event);
            },
            onTimeSlotTapped: (range) {
              context.go(
                '/event/new?start=${range.start.millisecondsSinceEpoch}'
                '&end=${range.end.millisecondsSinceEpoch}',
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          final now = DateTime.now();
          context.go(
            '/event/new?start=${now.millisecondsSinceEpoch}'
            '&end=${now.add(const Duration(hours: 1)).millisecondsSinceEpoch}',
          );
        },
        tooltip: 'New Event',
        child: const Icon(Icons.add),
      ),
    );
  }
}
