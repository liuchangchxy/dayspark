import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark/domain/providers/search_provider.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/ui/widgets/todo/todo_list_tile.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/ui/widgets/empty_state.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _searchController = TextEditingController();
  String _query = '';
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _submitSearch(String query) {
    _debounceTimer?.cancel();
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
            if (v.trim().isEmpty) {
              _debounceTimer?.cancel();
              setState(() => _query = '');
              return;
            }
            _debounceTimer?.cancel();
            _debounceTimer = Timer(const Duration(milliseconds: 300), () {
              final text = _searchController.text.trim();
              if (text.isNotEmpty) {
                setState(() => _query = text);
              }
            });
          },
        ),
      ),
      body: _query.isEmpty
          ? EmptyState(
              icon: CupertinoIcons.search,
              title: l.searchEmptyTitle,
              hint: l.searchEmptyHint,
              extra: _suggestions(context, ref, l),
            )
          : ref
                .watch(searchResultsProvider(_query))
                .when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
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
                            child: Text(
                              l.events,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          ...results.events.map((event) {
                            return ListTile(
                              leading: const Icon(
                                CupertinoIcons.calendar_badge_plus,
                              ),
                              title: Text(event.summary),
                              subtitle: Text(
                                DateFormatters.formatDate(event.startDt),
                              ),
                              onTap: () {
                                context.push(
                                  '/event/edit',
                                  extra: CalendaEventAdapter.fromDrift(event),
                                );
                              },
                            );
                          }),
                        ],
                        if (results.todos.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Text(
                              l.todos,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          ...results.todos.map(
                            (todo) => TodoListTile(
                              summary: todo.summary,
                              isCompleted: todo.status == 'COMPLETED',
                              priority: todo.priority,
                              todoId: todo.id,
                              todo: todo,
                              dueDate: todo.dueDate,
                              onToggle: (occurrenceId, isCompleted) =>
                                  ref.read(toggleTodoProvider)(
                                    id: todo.id,
                                    isCompleted: isCompleted,
                                    occurrenceId: occurrenceId,
                                  ),
                              onTap: () {
                                context.push('/todo/edit', extra: todo);
                              },
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
    );
  }

  /// Search starts blank otherwise; the inbox is the closest thing to "your
  /// recent stuff" without storing a query history (DESIGN 空状态模板).
  Widget _suggestions(BuildContext context, WidgetRef ref, AppLocalizations l) {
    final inbox = ref.watch(inboxTodosProvider).valueOrNull ?? const [];
    if (inbox.isEmpty) return const SizedBox.shrink();
    final top = inbox.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.searchSuggestions,
          style: AppTypography.overline.copyWith(
            color: context.semantic.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final todo in top)
          TodoListTile(
            summary: todo.summary,
            isCompleted: todo.status == 'COMPLETED',
            priority: todo.priority,
            todoId: todo.id,
            todo: todo,
            dueDate: todo.dueDate,
            onToggle: (occurrenceId, isCompleted) =>
                ref.read(toggleTodoProvider)(
                  id: todo.id,
                  isCompleted: isCompleted,
                  occurrenceId: occurrenceId,
                ),
            onTap: () => context.push('/todo/edit', extra: todo),
          ),
      ],
    );
  }
}
