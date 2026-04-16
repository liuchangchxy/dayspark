import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:calendar_todo_app/domain/providers/search_provider.dart';
import 'package:calendar_todo_app/ui/widgets/todo/todo_list_tile.dart';
import 'package:calendar_todo_app/domain/providers/todos_provider.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _submitSearch(String query) {
    setState(() => _query = query.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search events and todos...',
            border: InputBorder.none,
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: _submitSearch,
          onChanged: (v) {
            if (v.trim().isEmpty) setState(() => _query = '');
          },
        ),
      ),
      body: _query.isEmpty
          ? const Center(child: Text('Type to search'))
          : ref.watch(searchResultsProvider(_query)).when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (results) {
                  if (results.isEmpty) {
                    return const Center(child: Text('No results'));
                  }
                  return ListView(
                    children: [
                      if (results.events.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Text('Events',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14)),
                        ),
                        ...results.events.map((event) => ListTile(
                              leading: const Icon(Icons.event_outlined),
                              title: Text(event.summary),
                              subtitle: Text(
                                  '${event.startDt.year}-${event.startDt.month.toString().padLeft(2, '0')}-${event.startDt.day.toString().padLeft(2, '0')}'),
                              onTap: () {
                                Navigator.of(context).pop();
                              },
                            )),
                      ],
                      if (results.todos.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Text('Todos',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14)),
                        ),
                        ...results.todos.map((todo) => TodoListTile(
                              summary: todo.summary,
                              isCompleted: todo.status == 'COMPLETED',
                              priority: todo.priority,
                              dueDate: todo.dueDate,
                              onToggle: () =>
                                  ref.read(completeTodoProvider)(todo.id),
                              onTap: () {
                                Navigator.of(context).pop();
                              },
                            )),
                      ],
                    ],
                  );
                },
              ),
    );
  }
}
