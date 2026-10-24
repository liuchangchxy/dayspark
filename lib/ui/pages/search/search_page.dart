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
import 'package:dayspark/ui/shell/workspace_page.dart';
import 'package:dayspark/ui/widgets/empty_state.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _searchController = TextEditingController();
  String _query = '';
  int _eventPage = 1;
  int _todoPage = 1;
  Timer? _debounceTimer;

  /// The results already on screen. A new query keeps them visible while the
  /// next page of matches loads, so typing does not blank the list and bounce
  /// the reader back to an empty column on every keystroke.
  SearchResults? _shown;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _submitSearch(String query) {
    _debounceTimer?.cancel();
    setState(() {
      _query = query.trim();
      _eventPage = 1;
      _todoPage = 1;
    });
  }

  void _clear() {
    _debounceTimer?.cancel();
    _searchController.clear();
    setState(() {
      _query = '';
      _eventPage = 1;
      _todoPage = 1;
      _shown = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final queryState = SearchQueryState(
      query: _query,
      eventPage: _eventPage,
      todoPage: _todoPage,
    );
    final resultsAsync = ref.watch(pagedSearchResultsProvider(queryState));
    final loading = resultsAsync.isLoading;
    final results = resultsAsync.valueOrNull ?? _shown;
    if (resultsAsync.hasValue && !identical(results, _shown)) {
      // Written after this frame: the value arrives from the provider during
      // build, and mutating state mid-build is not allowed.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _shown = resultsAsync.value);
      });
    }

    return WorkspacePage(
      title: l.search,
      titleWidget: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              autofocus: true,
              style: AppTypography.body,
              decoration: InputDecoration(
                hintText: l.search,
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintStyle: AppTypography.body.copyWith(
                  color: context.semantic.textTertiary,
                ),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: _submitSearch,
              onChanged: (v) {
                if (v.trim().isEmpty) {
                  _clear();
                  return;
                }
                // Rebuild now so the clear affordance appears with the first
                // character; the query itself waits for the debounce.
                setState(() {});
                _debounceTimer?.cancel();
                _debounceTimer = Timer(const Duration(milliseconds: 300), () {
                  if (!mounted) return;
                  final text = _searchController.text.trim();
                  if (text.isNotEmpty) {
                    setState(() {
                      _query = text;
                      _eventPage = 1;
                      _todoPage = 1;
                    });
                  }
                });
              },
            ),
          ),
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(CupertinoIcons.clear, size: 16),
              tooltip: l.close,
              onPressed: _clear,
            ),
        ],
      ),
      child: _query.isEmpty
          ? EmptyState(
              icon: CupertinoIcons.search,
              title: l.searchEmptyTitle,
              hint: l.searchEmptyHint,
              extra: _suggestions(context, ref, l),
            )
          : Column(
              children: [
                if (loading)
                  const LinearProgressIndicator(minHeight: 2)
                else
                  const SizedBox(height: 2),
                Expanded(
                  child: resultsAsync.hasError && results == null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                l.searchFailed,
                                style: AppTypography.body.copyWith(
                                  color: context.semantic.textSecondary,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              TextButton(
                                onPressed: () => ref.invalidate(
                                  pagedSearchResultsProvider(queryState),
                                ),
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(0, 48),
                                ),
                                child: Text(l.retry),
                              ),
                            ],
                          ),
                        )
                      : _results(context, ref, l, results),
                ),
              ],
            ),
    );
  }

  Widget _results(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
    SearchResults? results,
  ) {
    if (results == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (results.isEmpty) {
      return Center(
        child: Text(
          l.noResults,
          style: AppTypography.body.copyWith(
            color: context.semantic.textSecondary,
          ),
        ),
      );
    }
    return ListView(
      key: const PageStorageKey('search-results'),
      children: [
        if (results.events.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(l.events, style: AppTypography.overline),
          ),
          ...results.events.map((event) {
            return ListTile(
              leading: const Icon(CupertinoIcons.calendar_badge_plus),
              title: Text(event.summary),
              subtitle: Text(DateFormatters.formatDate(event.startDt)),
              onTap: () {
                context.push(
                  '/event/detail',
                  extra: CalendaEventAdapter.fromDrift(event),
                );
              },
            );
          }),
          if (results.hasMoreEvents)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextButton.icon(
                icon: const Icon(CupertinoIcons.chevron_down),
                label: Text(l.loadMore),
                style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: () {
                  setState(() => _eventPage++);
                },
              ),
            ),
        ],
        if (results.todos.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(l.todos, style: AppTypography.overline),
          ),
          // Results are read-only: a search answer is something to open, and a
          // checkbox here would be an edit offered inside a lookup.
          ...results.todos.map(
            (todo) => TodoListTile(
              summary: todo.summary,
              isCompleted: todo.status == 'COMPLETED',
              priority: todo.priority,
              todoId: todo.id,
              todo: todo,
              dueDate: todo.dueDate,
              onTap: () {
                context.push('/todo/detail', extra: todo);
              },
            ),
          ),
          if (results.hasMoreTodos)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextButton.icon(
                icon: const Icon(CupertinoIcons.chevron_down),
                label: Text(l.loadMore),
                style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: () {
                  setState(() => _todoPage++);
                },
              ),
            ),
        ],
      ],
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
            onTap: () => context.push('/todo/detail', extra: todo),
          ),
      ],
    );
  }
}
