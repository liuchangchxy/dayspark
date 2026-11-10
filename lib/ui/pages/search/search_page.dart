import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/search_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/shell/workspace_page.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_pickers.dart';
import 'package:dayspark/ui/widgets/todo/todo_list_tile.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';
  int _eventPage = 1;
  int _todoPage = 1;
  Timer? _debounceTimer;

  SearchResults? _shown;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchFocus.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openDetail(String path, Object extra) async {
    await context.push(path, extra: extra);
    if (!mounted || _query.isEmpty) return;
    ref.invalidate(searchResultsProvider(_query));
    ref.invalidate(
      pagedSearchResultsProvider(
        SearchQueryState(
          query: _query,
          eventPage: _eventPage,
          todoPage: _todoPage,
        ),
      ),
    );
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
    _searchFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final desktop = isWorkspaceLayout(context);
    final queryState = SearchQueryState(
      query: _query,
      eventPage: _eventPage,
      todoPage: _todoPage,
    );
    final resultsAsync = ref.watch(pagedSearchResultsProvider(queryState));
    final loading = resultsAsync.isLoading;
    final results = resultsAsync.valueOrNull ?? _shown;
    if (resultsAsync.hasValue && !identical(results, _shown)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _shown = resultsAsync.value);
      });
    }

    final field = Container(
      height: 44,
      decoration: BoxDecoration(
        color: context.ds.surface,
        borderRadius: AppRadii.control,
        border: Border.all(color: context.ds.line),
      ),
      child: Row(
        children: [
          const SizedBox(width: AppSpacing.s3),
          Icon(CupertinoIcons.search, size: 17, color: context.ds.ink3),
          const SizedBox(width: AppSpacing.s2),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              autofocus: true,
              style: AppTypography.body.copyWith(color: context.ds.ink),
              decoration: InputDecoration(
                hintText: l.searchEmptyHint,
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintStyle: AppTypography.body.copyWith(
                  color: context.ds.ink3,
                ),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: _submitSearch,
              onChanged: (v) {
                if (v.trim().isEmpty) {
                  _clear();
                  return;
                }
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
            DsIconButton(
              icon: CupertinoIcons.clear,
              size: 15,
              compact: true,
              tooltip: l.close,
              onPressed: _clear,
            ),
          if (desktop)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: DsKeyCap('ESC'),
            ),
          const SizedBox(width: AppSpacing.s1),
        ],
      ),
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            desktop ? 0 : AppSpacing.s4,
            AppSpacing.s2,
            desktop ? 0 : AppSpacing.s4,
            AppSpacing.s2,
          ),
          child: field,
        ),
        if (loading)
          const LinearProgressIndicator(minHeight: 2)
        else
          const SizedBox(height: 2),
        Expanded(
          child: _query.isEmpty
              ? _suggestions(context, ref, l, desktop)
              : resultsAsync.hasError && results == null
              ? _failure(context, l, queryState)
              : _results(context, ref, l, results, desktop),
        ),
      ],
    );

    final content = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (GoRouter.maybeOf(context)?.canPop() ?? false) {
            context.pop();
          }
        },
      },
      child: Focus(autofocus: true, child: body),
    );

    if (!desktop) {
      return WorkspacePage(title: l.search, child: content);
    }
    return WorkspacePage(
      title: l.search,
      maxContentWidth: 680,
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.s3),
        child: content,
      ),
    );
  }

  Widget _failure(BuildContext context, AppLocalizations l, SearchQueryState q) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.searchFailed,
            style: AppTypography.body.copyWith(color: context.ds.ink2),
          ),
          const SizedBox(height: AppSpacing.s2),
          DsButton(
            label: l.retry,
            tone: DsButtonTone.secondary,
            small: true,
            onPressed: () =>
                ref.invalidate(pagedSearchResultsProvider(q)),
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
    bool desktop,
  ) {
    if (results == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (results.isEmpty) {
      return DsEmpty(
        icon: CupertinoIcons.search,
        title: l.noResults,
        message: l.searchEmptyHint,
      );
    }
    return ListView(
      key: const PageStorageKey('search-results'),
      padding: const EdgeInsets.only(bottom: AppSpacing.s6),
      children: [
        if (results.events.isNotEmpty) ...[
          DsSectionLabel(
            '${l.events} · ${results.events.length}',
            padding: EdgeInsets.fromLTRB(
              desktop ? 0 : AppSpacing.s4,
              AppSpacing.s3,
              desktop ? 0 : AppSpacing.s4,
              AppSpacing.s1,
            ),
          ),
          for (final event in results.events)
            DsRow(
              title: event.summary,
              meta: DsMeta(
                parts: [
                  DsMetaPart(formatDeadline(context, event.startDt)),
                  if (event.location != null && event.location!.isNotEmpty)
                    DsMetaPart(event.location!),
                ],
              ),
              leading: Icon(
                CupertinoIcons.calendar,
                size: 16,
                color: context.ds.ink3,
              ),
              padding: EdgeInsets.symmetric(
                horizontal: desktop ? 4 : AppSpacing.s4,
                vertical: 10,
              ),
              onTap: () => _openDetail(
                '/event/detail',
                CalendaEventAdapter.fromDrift(event),
              ),
            ),
          if (results.hasMoreEvents)
            _loadMore(l, () => setState(() => _eventPage++), desktop),
        ],
        if (results.todos.isNotEmpty) ...[
          DsSectionLabel(
            '${l.todos} · ${results.todos.length}',
            padding: EdgeInsets.fromLTRB(
              desktop ? 0 : AppSpacing.s4,
              AppSpacing.s4,
              desktop ? 0 : AppSpacing.s4,
              AppSpacing.s1,
            ),
          ),
          for (final todo in results.todos)
            TodoListTile(
              summary: todo.summary,
              isCompleted: todo.status == 'COMPLETED',
              priority: todo.priority,
              todoId: todo.id,
              todo: todo,
              dueDate: todo.dueDate,
              onTap: () => _openDetail('/todo/detail', todo),
            ),
          if (results.hasMoreTodos)
            _loadMore(l, () => setState(() => _todoPage++), desktop),
        ],
      ],
    );
  }

  Widget _loadMore(AppLocalizations l, VoidCallback onTap, bool desktop) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: desktop ? 0 : AppSpacing.s4,
        vertical: AppSpacing.s2,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: DsButton(
          label: l.loadMore,
          tone: DsButtonTone.ghost,
          small: true,
          onPressed: onTap,
        ),
      ),
    );
  }

  Widget _suggestions(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
    bool desktop,
  ) {
    final inbox = ref.watch(inboxTodosProvider).valueOrNull ?? const [];
    if (inbox.isEmpty) {
      return DsEmpty(
        icon: CupertinoIcons.search,
        title: l.searchEmptyTitle,
        message: l.searchEmptyHint,
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.s6),
      children: [
        DsSectionLabel(
          l.searchSuggestions,
          padding: EdgeInsets.fromLTRB(
            desktop ? 0 : AppSpacing.s4,
            AppSpacing.s3,
            desktop ? 0 : AppSpacing.s4,
            AppSpacing.s1,
          ),
        ),
        for (final todo in inbox.take(5))
          TodoListTile(
            summary: todo.summary,
            isCompleted: todo.status == 'COMPLETED',
            priority: todo.priority,
            todoId: todo.id,
            todo: todo,
            dueDate: todo.dueDate,
            onTap: () => _openDetail('/todo/detail', todo),
          ),
      ],
    );
  }
}
