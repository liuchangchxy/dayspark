import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark/domain/providers/search_provider.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/ui/widgets/todo/todo_list_tile.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';

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
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          onPressed: () => context.pop(),
        ),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: l.search,
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
          ? Center(child: Text(l.typeToSearch))
          : ref.watch(searchResultsProvider(_query)).when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text(l.error('$e'))),
                data: (results) {
                  if (results.isEmpty) {
                    return Center(child: Text(l.noResults));
                  }
                  return ListView(
                    children: [
                      if (results.events.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Text(l.events,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14)),
                        ),
                        ...results.events.map((event) {
                              return ListTile(
                                leading: const Icon(CupertinoIcons.calendar_badge_plus),
                                title: Text(event.summary),
                                subtitle: Text(
                                    '${event.startDt.year}-${event.startDt.month.toString().padLeft(2, '0')}-${event.startDt.day.toString().padLeft(2, '0')}'),
                                onTap: () {
                                  context.push('/event/edit',
                                      extra: CalendaEventAdapter.fromDrift(event));
                                },
                              );
                            }),
                      ],
                      if (results.todos.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Text(l.todos,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14)),
                        ),
                        ...results.todos.map((todo) => TodoListTile(
                              summary: todo.summary,
                              isCompleted: todo.status == 'COMPLETED',
                              priority: todo.priority,
                              todoId: todo.id,
                              dueDate: todo.dueDate,
                              onToggle: () =>
                                  ref.read(toggleTodoProvider)(id: todo.id, isCompleted: todo.status != 'COMPLETED'),
                              onTap: () {
                                context.push('/todo/edit', extra: todo);
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
