import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/search_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
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
  int _selected = 0;
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
      _selected = 0;
    });
  }

  void _handleSubmitted(String value) {
    final text = value.trim();
    if (text.isEmpty) return;
    if (_query == text && _shown != null) {
      _openSelected();
      return;
    }
    _submitSearch(text);
  }

  void _clear() {
    _debounceTimer?.cancel();
    _searchController.clear();
    setState(() {
      _query = '';
      _eventPage = 1;
      _todoPage = 1;
      _selected = 0;
      _shown = null;
    });
    _searchFocus.requestFocus();
  }

  void _moveSelection(int delta, int length) {
    if (length == 0) return;
    setState(() {
      _selected = (_selected + delta).clamp(0, length - 1);
    });
  }

  void _openHit(_SearchHit hit) {
    switch (hit.kind) {
      case _SearchHitKind.event:
        _openDetail(
          '/event/detail',
          CalendaEventAdapter.fromDrift(hit.event!),
        );
      case _SearchHitKind.todo:
        _openDetail('/todo/detail', hit.todo!);
    }
  }

  void _openSelected() {
    final results = _shown;
    if (results == null) return;
    final hits = _hits(results);
    if (hits.isEmpty) return;
    _openHit(hits[_selected.clamp(0, hits.length - 1)]);
  }

  void _close() {
    final router = GoRouter.maybeOf(context);
    if (router != null && router.canPop()) {
      context.pop();
      return;
    }
    Navigator.of(context).maybePop();
  }

  List<_SearchHit> _hits(SearchResults results) => [
    for (final event in results.events) _SearchHit.event(event),
    for (final todo in results.todos) _SearchHit.todo(todo),
  ];

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

    final hits = results == null ? const <_SearchHit>[] : _hits(results);
    final selected = hits.isEmpty || !desktop
        ? -1
        : _selected.clamp(0, hits.length - 1);

    Widget resultBody({required bool shrinkWrap}) => _query.isEmpty
        ? _suggestions(context, ref, l, desktop, shrinkWrap: shrinkWrap)
        : resultsAsync.hasError && results == null
        ? _failure(context, l, queryState)
        : _results(
            context,
            ref,
            l,
            results,
            desktop,
            selected,
            hits,
            shrinkWrap: shrinkWrap,
          );

    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
          _moveSelection(1, hits.length),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
          _moveSelection(-1, hits.length),
      const SingleActivator(LogicalKeyboardKey.enter): _openSelected,
      const SingleActivator(LogicalKeyboardKey.escape): _close,
    };

    if (desktop) {
      return Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: context.ds.bg),
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 620,
                maxHeight: MediaQuery.sizeOf(context).height - 64,
              ),
              child: Container(
                width: 620,
                decoration: BoxDecoration(
                  color: context.ds.surface,
                  borderRadius: BorderRadius.circular(AppRadii.xl),
                  border: Border.all(color: context.ds.line),
                  boxShadow: AppShadows.two(
                    Theme.of(context).brightness,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Material(
                  color: Colors.transparent,
                  child: CallbackShortcuts(
                    bindings: shortcuts,
                    child: Focus(
                      autofocus: true,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _desktopInput(context, l),
                          if (loading)
                            const LinearProgressIndicator(minHeight: 2)
                          else
                            const SizedBox(height: 2),
                          Flexible(
                            fit: FlexFit.loose,
                            child: resultBody(shrinkWrap: true),
                          ),
                          _footer(context, l),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _mobileInput(context, l),
        if (loading)
          const LinearProgressIndicator(minHeight: 2)
        else
          const SizedBox(height: 2),
        Expanded(child: resultBody(shrinkWrap: false)),
      ],
    );

    return Scaffold(
      backgroundColor: context.ds.bg,
      body: SafeArea(
        top: true,
        child: CallbackShortcuts(
          bindings: shortcuts,
          child: Focus(autofocus: true, child: body),
        ),
      ),
    );
  }

  Widget _desktopInput(BuildContext context, AppLocalizations l) {
    final ds = context.ds;
    return Container(
      height: 56,
      padding: const EdgeInsets.fromLTRB(18, 0, 12, 0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: ds.line)),
      ),
      child: Row(
        children: [
          Icon(CupertinoIcons.search, size: 17, color: ds.faint),
          const SizedBox(width: 10),
          Expanded(child: _field(context, l, 16)),
          if (_searchController.text.isNotEmpty)
            DsIconButton(
              icon: CupertinoIcons.clear,
              size: 15,
              compact: true,
              tooltip: l.cancel,
              onPressed: _clear,
            ),
          const SizedBox(width: AppSpacing.s1),
          const DsKeyCap('esc'),
        ],
      ),
    );
  }

  Widget _mobileInput(BuildContext context, AppLocalizations l) {
    final ds = context.ds;
    return Container(
      height: 44,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: ds.line)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(
                CupertinoIcons.back,
                size: 20,
                color: ds.ink2,
              ),
              onPressed: _close,
            ),
          ),
          Icon(CupertinoIcons.search, size: 15, color: ds.faint),
          const SizedBox(width: 7),
          Expanded(child: _field(context, l, 16)),
          if (_searchController.text.isNotEmpty)
            SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: Icon(
                  CupertinoIcons.clear,
                  size: 14,
                  color: ds.faint,
                ),
                onPressed: _clear,
              ),
            )
          else
            const SizedBox(width: AppSpacing.s3),
        ],
      ),
    );
  }

  Widget _field(BuildContext context, AppLocalizations l, double size) {
    final ds = context.ds;
    return TextField(
      controller: _searchController,
      focusNode: _searchFocus,
      autofocus: true,
      style: AppTypography.body.copyWith(
        color: ds.ink,
        fontSize: size,
        fontWeight: FontWeight.w500,
      ),
      cursorColor: ds.primary,
      cursorWidth: 2,
      decoration: InputDecoration(
        hintText: l.searchEmptyHint,
        isDense: true,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: EdgeInsets.zero,
        hintStyle: AppTypography.body.copyWith(
          color: ds.faint,
          fontSize: size,
        ),
      ),
      textInputAction: TextInputAction.search,
      onSubmitted: _handleSubmitted,
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
              _selected = 0;
            });
          }
        });
      },
    );
  }

  Widget _footer(BuildContext context, AppLocalizations l) {
    final ds = context.ds;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: ds.line)),
      ),
      child: Row(
        children: [
          const DsKeyCap('↑↓'),
          const SizedBox(width: 18),
          const DsKeyCap('Enter'),
          const Spacer(),
          const DsKeyCap('esc'),
          const SizedBox(width: AppSpacing.s1),
          Text(
            l.close,
            style: AppTypography.small.copyWith(color: ds.ink3),
          ),
        ],
      ),
    );
  }

  Widget _failure(
    BuildContext context,
    AppLocalizations l,
    SearchQueryState q,
  ) {
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
            onPressed: () => ref.invalidate(pagedSearchResultsProvider(q)),
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
    int selected,
    List<_SearchHit> hits, {
    required bool shrinkWrap,
  }) {
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
    final calendars = ref.watch(calendarsProvider).valueOrNull ?? const [];
    final horizontal = desktop ? 18.0 : AppSpacing.s4;
    var index = 0;
    return ListView(
      key: const PageStorageKey('search-results'),
      shrinkWrap: shrinkWrap,
      padding: EdgeInsets.only(
        top: desktop ? 6 : 4,
        bottom: AppSpacing.s6,
      ),
      children: [
        if (results.events.isNotEmpty) ...[
          _groupHeader(
            context,
            l.events,
            results.events.length,
            desktop,
          ),
          for (final event in results.events)
            _eventRow(
              context,
              l,
              event,
              calendars,
              selected == index++,
              desktop,
              horizontal,
            ),
          if (results.hasMoreEvents)
            _loadMore(l, () {
              setState(() {
                _eventPage++;
                _selected = 0;
              });
            }, desktop),
        ],
        if (results.todos.isNotEmpty) ...[
          _groupHeader(
            context,
            l.todos,
            results.todos.length,
            desktop,
            topGap: results.events.isNotEmpty,
          ),
          for (final todo in results.todos)
            _todoRow(
              context,
              todo,
              selected == index++,
              desktop,
              horizontal,
            ),
          if (results.hasMoreTodos)
            _loadMore(l, () {
              setState(() {
                _todoPage++;
                _selected = 0;
              });
            }, desktop),
        ],
      ],
    );
  }

  Widget _groupHeader(
    BuildContext context,
    String label,
    int count,
    bool desktop, {
    bool topGap = false,
  }) {
    final ds = context.ds;
    return Container(
      height: desktop ? 30 : 40,
      padding: EdgeInsets.fromLTRB(
        desktop ? 18 : AppSpacing.s4,
        desktop ? 0 : 12,
        desktop ? 18 : AppSpacing.s4,
        desktop ? 0 : 7,
      ),
      decoration: BoxDecoration(
        color: desktop ? null : ds.surface,
        border: desktop && topGap
            ? Border(top: BorderSide(color: ds.line))
            : null,
      ),
      alignment: Alignment.bottomLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: AppTypography.overline.copyWith(
              color: ds.ink3,
              letterSpacing: 0.3,
            ),
          ),
          const Spacer(),
          Text(
            '$count',
            style: AppTypography.small.copyWith(
              color: ds.faint,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _eventRow(
    BuildContext context,
    AppLocalizations l,
    Event event,
    List<Calendar> calendars,
    bool selected,
    bool desktop,
    double horizontal,
  ) {
    final ds = context.ds;
    final calendar = calendars
        .where((c) => c.id == event.calendarId)
        .firstOrNull;
    final dot = calendar == null
        ? ds.faint
        : ColorUtils.parseHex(calendar.color);
    return _SearchRowFrame(
      selected: selected,
      height: desktop ? 52 : 56,
      onTap: () => _openHit(_SearchHit.event(event)),
      onHover: () {
        final hits = _shown == null ? const <_SearchHit>[] : _hits(_shown!);
        final at = hits.indexWhere((hit) => identical(hit.event, event));
        if (at >= 0 && at != _selected) {
          setState(() => _selected = at);
        }
      },
      horizontal: horizontal,
      child: Row(
        children: [
          DsDot(color: dot, size: 6),
          const SizedBox(width: 10),
          Expanded(
            child: _highlighted(
              event.summary,
              _query,
              AppTypography.caption.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: ds.ink,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s3),
          Text(
            _eventMeta(context, l, event),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.small.copyWith(
              color: selected ? ds.primaryHover : ds.ink3,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _todoRow(
    BuildContext context,
    Todo todo,
    bool selected,
    bool desktop,
    double horizontal,
  ) {
    return _SearchRowFrame(
      selected: selected,
      height: desktop ? 52 : 56,
      horizontal: 0,
      onTap: () => _openHit(_SearchHit.todo(todo)),
      child: TodoListTile(
        summary: todo.summary,
        isCompleted: todo.status == 'COMPLETED',
        priority: todo.priority,
        todoId: todo.id,
        todo: todo,
        dueDate: todo.dueDate,
        selected: selected,
        onTap: () => _openHit(_SearchHit.todo(todo)),
      ),
    );
  }

  Widget _loadMore(AppLocalizations l, VoidCallback onTap, bool desktop) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: desktop ? 18 : AppSpacing.s4,
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
    bool desktop, {
    required bool shrinkWrap,
  }) {
    final inbox = ref.watch(inboxTodosProvider).valueOrNull ?? const [];
    if (inbox.isEmpty) {
      return DsEmpty(
        icon: CupertinoIcons.search,
        title: l.searchEmptyTitle,
        message: l.searchEmptyHint,
      );
    }
    return ListView(
      shrinkWrap: shrinkWrap,
      padding: EdgeInsets.only(
        top: desktop ? 6 : 4,
        bottom: AppSpacing.s6,
      ),
      children: [
        _groupHeader(context, l.searchSuggestions, inbox.take(5).length, desktop),
        for (final todo in inbox.take(5))
          Padding(
            padding: EdgeInsets.symmetric(horizontal: desktop ? 6 : 0),
            child: TodoListTile(
              summary: todo.summary,
              isCompleted: todo.status == 'COMPLETED',
              priority: todo.priority,
              todoId: todo.id,
              todo: todo,
              dueDate: todo.dueDate,
              onTap: () => _openDetail('/todo/detail', todo),
            ),
          ),
      ],
    );
  }

  String _eventMeta(BuildContext context, AppLocalizations l, Event event) {
    if (event.isAllDay) return l.allDay;
    final start = event.startDt.toLocal();
    final end = event.endDt.toLocal();
    final today = _today();
    final day = DateTime(start.year, start.month, start.day);
    final clock =
        '${DateFormatters.formatTime(start)}–${DateFormatters.formatTime(end)}';
    if (day == today) return '${l.today} · $clock';
    if (day == today.add(const Duration(days: 1))) {
      return '${l.tomorrow} · $clock';
    }
    final locale = Localizations.localeOf(context).toString();
    return '${DateFormat.MMMd(locale).format(start)} '
        '${DateFormat.E(locale).format(start)} · $clock';
  }

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }
}

class _SearchRowFrame extends StatelessWidget {
  const _SearchRowFrame({
    required this.selected,
    required this.height,
    required this.child,
    this.onTap,
    this.onHover,
    this.horizontal = 18,
  });

  final bool selected;
  final double height;
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onHover;
  final double horizontal;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHover?.call(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: height),
          decoration: BoxDecoration(
            color: selected ? ds.primaryTint : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: selected ? ds.primary : Colors.transparent,
                width: 3,
              ),
              bottom: BorderSide(color: ds.lineSoft),
            ),
          ),
          padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, 0),
          child: child,
        ),
      ),
    );
  }
}

class _SearchHit {
  const _SearchHit.event(this.event)
    : kind = _SearchHitKind.event,
      todo = null;

  const _SearchHit.todo(this.todo)
    : kind = _SearchHitKind.todo,
      event = null;

  final _SearchHitKind kind;
  final Event? event;
  final Todo? todo;
}

enum _SearchHitKind { event, todo }

Widget _highlighted(String text, String query, TextStyle style) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
  final haystack = text.toLowerCase();
  final at = haystack.indexOf(needle);
  if (at < 0) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
  return Text.rich(
    TextSpan(
      children: [
        TextSpan(text: text.substring(0, at)),
        TextSpan(
          text: text.substring(at, at + needle.length),
          style: style.copyWith(fontWeight: FontWeight.w600),
        ),
        TextSpan(text: text.substring(at + needle.length)),
      ],
    ),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: style,
  );
}
