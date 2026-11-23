import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/theme/spec_tokens.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/action_projection_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/default_calendar_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/search_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/utils/capture_parser.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/schedule/repeat_editor.dart';

const List<String> _chineseActionPrefixes = [
  '打开设置',
  '去设置',
  '记一条',
  '记一笔',
  '新建',
  '创建',
  '添加',
  '安排',
  '设置',
];

final recentCommandTodosProvider = StreamProvider.autoDispose<List<Todo>>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.todos)
        ..where((t) => t.deletedAt.isNull() & t.parentId.isNull())
        ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
        ..limit(5))
      .watch();
});

final recentCommandEventsProvider = StreamProvider.autoDispose<List<Event>>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.events)
        ..where((t) => t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
        ..limit(5))
      .watch();
});

/// Opens the command overlay on desktop or navigates to search page on mobile.
Future<void> showCommandOverlay(BuildContext context) {
  if (isWorkspaceLayout(context)) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      useSafeArea: false,
      builder: (_) => const SearchPage(isOverlay: true),
    );
  }
  return context.push('/search');
}

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key, this.isOverlay = false});

  final bool isOverlay;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _resultsScrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  String _query = '';
  int _eventPage = 1;
  int _todoPage = 1;
  int _selected = -1;
  Timer? _debounceTimer;

  SearchResults? _shown;
  List<_CmdHit> _currentHits = const [];

  @override
  void initState() {
    super.initState();
    _searchFocus.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _moveSelection(1, _currentHits.length);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _moveSelection(-1, _currentHits.length);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        final text = _searchController.text.trim();
        if (_selected >= 0 && _selected < _currentHits.length) {
          _openHit(_currentHits[_selected]);
          return KeyEventResult.handled;
        } else if (_query == text && _currentHits.isNotEmpty) {
          _openHit(_currentHits.first);
          return KeyEventResult.handled;
        }
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _close();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyK &&
          (HardwareKeyboard.instance.isMetaPressed ||
              HardwareKeyboard.instance.isControlPressed)) {
        _searchController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _searchController.text.length,
        );
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchFocus.dispose();
    _searchController.dispose();
    _resultsScrollController.dispose();
    super.dispose();
  }

  Future<void> _openTarget(String path, Object? extra) async {
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    if (router.canPop()) {
      router.pop();
    }
    await router.push(path, extra: extra);
  }

  void _submitSearch(String query) {
    _debounceTimer?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _clear();
      return;
    }
    setState(() {
      _query = trimmed;
      _eventPage = 1;
      _todoPage = 1;
      _selected = -1;
    });
  }

  void _handleSubmitted(String value, List<_CmdHit> hits) {
    final text = value.trim();
    if (text.isEmpty && hits.isNotEmpty) {
      if (_selected >= 0 && _selected < hits.length) {
        _openHit(hits[_selected]);
      } else {
        _openHit(hits.first);
      }
      return;
    }
    if (_query == text && hits.isNotEmpty) {
      if (_selected >= 0 && _selected < hits.length) {
        _openHit(hits[_selected]);
      } else {
        _openHit(hits.first);
      }
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
      _selected = -1;
      _shown = null;
    });
    _searchFocus.requestFocus();
  }

  void _moveSelection(int delta, int length) {
    if (length == 0) return;
    setState(() {
      if (_selected < 0) {
        _selected = delta > 0 ? 0 : length - 1;
        return;
      }
      _selected = (_selected + delta).clamp(0, length - 1);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _itemKeys[_selected];
      final targetContext = key?.currentContext;
      if (targetContext != null) {
        Scrollable.ensureVisible(
          targetContext,
          alignment: 0.5,
          duration: const Duration(milliseconds: 100),
        );
      }
    });
  }

  Future<void> _openHit(_CmdHit hit) async {
    switch (hit.kind) {
      case _CmdHitKind.todo:
        _openTarget('/todo/detail', hit.todo!);
      case _CmdHitKind.event:
        _openTarget(
          '/event/detail',
          CalendaEventAdapter.fromDrift(hit.event!),
        );
      case _CmdHitKind.action:
        final summary = _titleFromQuery(_query);
        switch (hit.action!) {
          case _CmdActionKind.captureTodo:
            if (widget.isOverlay) {
              await _createTodoInline(summary);
            } else {
              final path = summary.isNotEmpty
                  ? '/todo/new?summary=${Uri.encodeComponent(summary)}'
                  : '/todo/new';
              _openTarget(path, null);
            }
          case _CmdActionKind.captureEvent:
            if (widget.isOverlay) {
              await _createEventInline(summary);
            } else {
              final path = summary.isNotEmpty
                  ? '/event/new?summary=${Uri.encodeComponent(summary)}'
                  : '/event/new';
              _openTarget(path, null);
            }
          case _CmdActionKind.goSettings:
            _openTarget('/settings', null);
        }
    }
  }

  Future<void> _createTodoInline(String summary) async {
    final l = AppLocalizations.of(context)!;
    final text = summary.trim();
    if (text.isEmpty) {
      _close();
      return;
    }
    final calendars = await ref.read(calendarsProvider.future);
    if (calendars.isEmpty) {
      _close();
      return;
    }
    final calId = resolveNewEntryCalendarId(
      calendars: calendars,
      preferredId: ref.read(defaultCalendarIdProvider),
    ) ?? calendars.first.id;
    final parsed = parseCapture(text, DateTime.now());
    await ref.read(createTodoProvider)(
      calendarId: calId,
      summary: parsed.title.isNotEmpty ? parsed.title : text,
      dueDate: parsed.date,
      priority: 0,
      status: 'NEEDS-ACTION',
    );
    if (!mounted) return;
    _close();
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(l.captureAddedToast),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _createEventInline(String summary) async {
    final l = AppLocalizations.of(context)!;
    final text = summary.trim();
    if (text.isEmpty) {
      _close();
      return;
    }
    final calendars = await ref.read(calendarsProvider.future);
    if (calendars.isEmpty) {
      _close();
      return;
    }
    final calId = resolveNewEntryCalendarId(
      calendars: calendars,
      preferredId: ref.read(defaultCalendarIdProvider),
    ) ?? calendars.first.id;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, now.hour + 1);
    final end = start.add(const Duration(hours: 1));
    await ref.read(createEventProvider)(
      calendarId: calId,
      summary: text,
      startDt: start,
      endDt: end,
      isAllDay: false,
    );
    if (!mounted) return;
    _close();
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(l.eventCreated),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openSelected(List<_CmdHit> hits) {
    if (hits.isEmpty || _selected < 0) return;
    final index = _selected.clamp(0, hits.length - 1);
    _openHit(hits[index]);
  }

  void _close() {
    final router = GoRouter.maybeOf(context);
    if (router != null && router.canPop()) {
      context.pop();
      return;
    }
    Navigator.of(context).maybePop();
  }

  bool _isActionQuery(String q, AppLocalizations l) {
    final trimmed = q.trim();
    final lower = trimmed.toLowerCase();
    final actionWord = l.commandSideAction.toLowerCase();
    final todoWord = l.commandCreateTodo.toLowerCase();
    final eventWord = l.commandCreateEvent.toLowerCase();
    final settingsWord = l.commandGoSettings.toLowerCase();
    return lower.startsWith('>') ||
        lower.startsWith('new') ||
        lower.startsWith('create') ||
        lower.startsWith('add') ||
        lower.contains('setting') ||
        lower.contains('action') ||
        lower.startsWith(todoWord) ||
        lower.startsWith(eventWord) ||
        lower.contains(settingsWord) ||
        lower.contains(actionWord) ||
        _chineseActionPrefixes.any(trimmed.startsWith);
  }

  String _actionRemainder(String q) {
    var text = q.trim();
    if (text.startsWith('>')) {
      text = text.substring(1).trim();
    }
    for (final prefix in _chineseActionPrefixes) {
      if (!text.startsWith(prefix)) continue;
      return text
          .substring(prefix.length)
          .replaceFirst(RegExp(r'^[\s:：,，、]+'), '')
          .trim();
    }
    return '';
  }

  String _titleFromQuery(String q) {
    final remaining = _actionRemainder(q);
    return remaining.isEmpty ? q.trim() : remaining;
  }

  String _actionMetaTitle(AppLocalizations l, String q) =>
      l.commandActionTitleQuery(_titleFromQuery(q));

  List<_CmdHit> _buildHits({
    required BuildContext context,
    required AppLocalizations l,
    required SearchResults? results,
    required List<Todo> recentTodos,
    required List<Event> recentEvents,
  }) {
    final list = <_CmdHit>[];
    if (_query.isEmpty) {
      final recents = <({DateTime updatedAt, _CmdHit hit})>[];
      for (final todo in recentTodos) {
        recents.add((
          updatedAt: todo.updatedAt,
          hit: _CmdHit.todo(
            todo,
            title: todo.summary,
            meta: _todoMeta(context, l, todo),
            side: l.commandSideTodo,
          ),
        ));
      }
      for (final event in recentEvents) {
        recents.add((
          updatedAt: event.updatedAt,
          hit: _CmdHit.event(
            event,
            title: event.summary,
            meta: _eventMeta(context, l, event),
            side: l.commandSideEvent,
          ),
        ));
      }
      recents.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      for (final recent in recents.take(5)) {
        list.add(recent.hit);
      }
      // Actions group
      list.add(
        _CmdHit.action(
          _CmdActionKind.captureTodo,
          title: l.commandCreateTodo,
          meta: l.commandCaptureTodoDesc,
          side: l.commandSideAction,
          icon: CupertinoIcons.plus,
        ),
      );
      list.add(
        _CmdHit.action(
          _CmdActionKind.captureEvent,
          title: l.commandCreateEvent,
          meta: l.commandCaptureEventDesc,
          side: l.commandSideAction,
          icon: CupertinoIcons.calendar,
        ),
      );
      list.add(
        _CmdHit.action(
          _CmdActionKind.goSettings,
          title: l.commandGoSettings,
          meta: l.commandGoSettingsDesc,
          side: l.commandSideAction,
          icon: CupertinoIcons.person,
        ),
      );
    } else {
      if (results != null && (results.todos.isNotEmpty || results.events.isNotEmpty)) {
        // Spec order: Todos first, Events second, Actions third
        for (final todo in results.todos) {
          list.add(
            _CmdHit.todo(
              todo,
              title: todo.summary,
              meta: _todoMeta(context, l, todo),
              side: l.commandSideTodo,
            ),
          );
        }
        for (final event in results.events) {
          list.add(
            _CmdHit.event(
              event,
              title: event.summary,
              meta: _eventMeta(context, l, event),
              side: l.commandSideEvent,
            ),
          );
        }
        // Action group: New todo / New event with query title
        list.add(
          _CmdHit.action(
            _CmdActionKind.captureTodo,
            title: l.commandCreateTodo,
            meta: _actionMetaTitle(l, _query),
            side: l.commandSideAction,
            icon: CupertinoIcons.plus,
          ),
        );
        list.add(
          _CmdHit.action(
            _CmdActionKind.captureEvent,
            title: l.commandCreateEvent,
            meta: _actionMetaTitle(l, _query),
            side: l.commandSideAction,
            icon: CupertinoIcons.calendar,
          ),
        );
      } else if (results != null && results.isEmpty && _isActionQuery(_query, l)) {
        list.add(
          _CmdHit.action(
            _CmdActionKind.captureTodo,
            title: l.commandCreateTodo,
            meta: _actionMetaTitle(l, _query),
            side: l.commandSideAction,
            icon: CupertinoIcons.plus,
          ),
        );
        list.add(
          _CmdHit.action(
            _CmdActionKind.captureEvent,
            title: l.commandCreateEvent,
            meta: _actionMetaTitle(l, _query),
            side: l.commandSideAction,
            icon: CupertinoIcons.calendar,
          ),
        );
        list.add(
          _CmdHit.action(
            _CmdActionKind.goSettings,
            title: l.commandGoSettings,
            meta: l.commandGoSettingsDesc,
            side: l.commandSideAction,
            icon: CupertinoIcons.person,
          ),
        );
      }
    }
    return list;
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
    final fresh = resultsAsync.valueOrNull;
    final results = fresh ?? (resultsAsync.hasError ? null : _shown);
    if (resultsAsync.hasValue && !identical(fresh, _shown)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _shown = fresh);
      });
    }

    final recentTodos =
        ref.watch(recentCommandTodosProvider).valueOrNull ?? const <Todo>[];
    final recentEvents =
        ref.watch(recentCommandEventsProvider).valueOrNull ?? const <Event>[];
    final hits = _buildHits(
      context: context,
      l: l,
      results: results,
      recentTodos: recentTodos,
      recentEvents: recentEvents,
    );
    _currentHits = hits;

    final selected = hits.isEmpty || _selected < 0
        ? -1
        : _selected.clamp(0, hits.length - 1);

    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
          _moveSelection(1, hits.length),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
          _moveSelection(-1, hits.length),
      const SingleActivator(LogicalKeyboardKey.enter): () =>
          _openSelected(hits),
      const SingleActivator(LogicalKeyboardKey.escape): _close,
      const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () {
        _searchController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _searchController.text.length,
        );
        _searchFocus.requestFocus();
      },
      const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
        _searchController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _searchController.text.length,
        );
        _searchFocus.requestFocus();
      },
    };

    Widget resultBody({required bool shrinkWrap}) {
      if (resultsAsync.hasError && results == null) {
        return _failure(context, l, queryState);
      }
      if (_query.isNotEmpty && results != null && results.isEmpty && !_isActionQuery(_query, l)) {
        return _empty(context, l, _query);
      }
      return _results(
        context: context,
        l: l,
        desktop: desktop,
        selected: selected,
        hits: hits,
        results: results,
        shrinkWrap: shrinkWrap,
        loading: loading,
      );
    }

    if (desktop) {
      return Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0x3D191918)),
          Padding(
            padding: const EdgeInsets.only(top: 94),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 620,
                  maxHeight: math.max(
                    474,
                    MediaQuery.sizeOf(context).height - 118,
                  ),
                ),
                child: Container(
                  width: 620,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x47141412),
                        blurRadius: 90,
                        offset: Offset(0, 30),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Material(
                    color: Colors.white,
                    child: CallbackShortcuts(
                      bindings: shortcuts,
                      child: Focus(
                        autofocus: true,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _desktopInput(context, l, hits),
                            if (loading)
                              const LinearProgressIndicator(minHeight: 2)
                            else
                              const SizedBox(height: 2),
                            Flexible(
                              fit: FlexFit.loose,
                              child: ConstrainedBox(
                                key: const ValueKey('cmd-body'),
                                constraints: const BoxConstraints(maxHeight: 390),
                                child: resultBody(shrinkWrap: true),
                              ),
                            ),
                            _footer(context, l, selected, hits),
                          ],
                        ),
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

    final mobileBody = Column(
      children: [
        _mobileInput(context, l, hits),
        if (loading)
          const LinearProgressIndicator(minHeight: 2)
        else
          const SizedBox(height: 2),
        Expanded(child: resultBody(shrinkWrap: false)),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: true,
        child: CallbackShortcuts(
          bindings: shortcuts,
          child: Focus(autofocus: true, child: mobileBody),
        ),
      ),
    );
  }

  Widget _desktopInput(
    BuildContext context,
    AppLocalizations l,
    List<_CmdHit> hits,
  ) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: SpecTokens.hair, width: 1)),
      ),
      child: Row(
        children: [
          const Icon(CupertinoIcons.search, size: 15, color: SpecTokens.faint),
          const SizedBox(width: 10),
          Expanded(child: _field(context, l, 14, hits)),
          if (_searchController.text.isNotEmpty)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                key: const ValueKey('command-clear-button'),
                behavior: HitTestBehavior.opaque,
                onTap: _clear,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    CupertinoIcons.clear,
                    size: 14,
                    color: SpecTokens.faint,
                  ),
                ),
              ),
            ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              border: Border.all(color: SpecTokens.hair2),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text(
              'esc',
              style: TextStyle(
                fontSize: 9,
                color: SpecTokens.faint,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
          ),
          const SizedBox(width: 8),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(CupertinoIcons.xmark, size: 12, color: SpecTokens.faint),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileInput(
    BuildContext context,
    AppLocalizations l,
    List<_CmdHit> hits,
  ) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: SpecTokens.hair, width: 1)),
      ),
      child: Row(
        children: [
          const Icon(CupertinoIcons.search, size: 15, color: SpecTokens.faint),
          const SizedBox(width: 8),
          Expanded(child: _field(context, l, 14, hits)),
          if (_searchController.text.isNotEmpty)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                key: const ValueKey('command-clear-button'),
                behavior: HitTestBehavior.opaque,
                onTap: _clear,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(CupertinoIcons.clear, size: 14, color: SpecTokens.faint),
                ),
              ),
            ),
          const SizedBox(width: 4),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(CupertinoIcons.xmark, size: 14, color: SpecTokens.faint),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    BuildContext context,
    AppLocalizations l,
    double size,
    List<_CmdHit> hits,
  ) {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocus,
      autofocus: true,
      style: TextStyle(
        fontSize: size,
        color: SpecTokens.ink,
        fontWeight: FontWeight.normal,
        fontFamilyFallback: AppTypography.fallback,
      ),
      cursorColor: SpecTokens.ink,
      cursorWidth: 1.5,
      decoration: InputDecoration(
        hintText: l.commandPlaceholder,
        isDense: true,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: EdgeInsets.zero,
        hintStyle: TextStyle(
          color: const Color(0xFF8E8E84),
          fontSize: size,
          fontWeight: FontWeight.normal,
          fontFamilyFallback: AppTypography.fallback,
        ),
      ),
      textInputAction: TextInputAction.search,
      onSubmitted: (v) => _handleSubmitted(v, hits),
      onChanged: (v) {
        if (v.trim().isEmpty) {
          _clear();
          return;
        }
        setState(() {});
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 250), () {
          if (!mounted) return;
          final text = _searchController.text.trim();
          if (text.isNotEmpty) {
            setState(() {
              _query = text;
              _eventPage = 1;
              _todoPage = 1;
              _selected = -1;
            });
          }
        });
      },
    );
  }

  Widget _footer(
    BuildContext context,
    AppLocalizations l,
    int selected,
    List<_CmdHit> hits,
  ) {
    final rightText = selected >= 0 && hits.isNotEmpty
        ? l.commandFootSelected(selected + 1)
        : l.commandFootHint;

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: SpecTokens.hair, width: 1)),
      ),
      child: Row(
        children: [
          Text(
            l.commandFootSelect,
            style: const TextStyle(
              fontSize: 9,
              color: SpecTokens.faint,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
          const SizedBox(width: 14),
          Text(
            l.commandFootOpen,
            style: const TextStyle(
              fontSize: 9,
              color: SpecTokens.faint,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
          const SizedBox(width: 14),
          Text(
            l.commandFootClose,
            style: const TextStyle(
              fontSize: 9,
              color: SpecTokens.faint,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
          const Spacer(),
          Text(
            rightText,
            style: const TextStyle(
              fontSize: 9,
              color: SpecTokens.faint,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context, AppLocalizations l, String query) {
    return CmdEmpty(query: query);
  }

  Widget _failure(
    BuildContext context,
    AppLocalizations l,
    SearchQueryState q,
  ) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: SpecTokens.wash,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: SpecTokens.hair2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              CupertinoIcons.exclamationmark_circle,
              size: 16,
              color: SpecTokens.red,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l.searchFailed,
                style: const TextStyle(
                  fontSize: 12,
                  color: SpecTokens.ink2,
                  fontFamilyFallback: AppTypography.fallback,
                ),
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => ref.invalidate(pagedSearchResultsProvider(q)),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: SpecTokens.hair2),
                ),
                child: Text(
                  l.retry,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: SpecTokens.ink,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _results({
    required BuildContext context,
    required AppLocalizations l,
    required bool desktop,
    required int selected,
    required List<_CmdHit> hits,
    required SearchResults? results,
    required bool shrinkWrap,
    required bool loading,
  }) {
    if (_query.isEmpty) {
      var itemIndex = 0;
      final recentCount = hits
          .where((hit) => hit.kind != _CmdHitKind.action)
          .length;
      return SingleChildScrollView(
        key: const PageStorageKey('search-results-empty'),
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (recentCount > 0) ...[
              _cmdGroupHeader(l.commandHintRecent, mobile: !desktop),
              for (var i = 0; i < recentCount; i++)
                _buildRow(
                  hit: hits[itemIndex],
                  index: itemIndex++,
                  selected: selected,
                  desktop: desktop,
                ),
            ],
            _cmdGroupHeader(l.commandHintActions, mobile: !desktop),
            for (; itemIndex < hits.length; itemIndex++)
              _buildRow(
                hit: hits[itemIndex],
                index: itemIndex,
                selected: selected,
                desktop: desktop,
              ),
          ],
        ),
      );
    }

    if (results == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }

    var itemIndex = 0;
    return SingleChildScrollView(
      key: const PageStorageKey('search-results'),
      controller: _resultsScrollController,
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (results.todos.isNotEmpty) ...[
            _cmdGroupHeader(l.commandHintTodos, mobile: !desktop),
            for (var i = 0; i < results.todos.length; i++)
              _buildRow(
                hit: hits[itemIndex],
                index: itemIndex++,
                selected: selected,
                desktop: desktop,
              ),
            if (results.hasMoreTodos)
              _loadMore(l, () {
                setState(() {
                  _todoPage++;
                  _selected = -1;
                });
              }, desktop, loading),
          ],
          if (results.events.isNotEmpty) ...[
            _cmdGroupHeader(l.commandHintEvents, mobile: !desktop),
            for (var i = 0; i < results.events.length; i++)
              _buildRow(
                hit: hits[itemIndex],
                index: itemIndex++,
                selected: selected,
                desktop: desktop,
              ),
            if (results.hasMoreEvents)
              _loadMore(l, () {
                setState(() {
                  _eventPage++;
                  _selected = -1;
                });
              }, desktop, loading),
          ],
          if (itemIndex < hits.length) ...[
            _cmdGroupHeader(l.commandHintActions, mobile: !desktop),
            for (; itemIndex < hits.length; itemIndex++)
              _buildRow(
                hit: hits[itemIndex],
                index: itemIndex,
                selected: selected,
                desktop: desktop,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildRow({
    required _CmdHit hit,
    required int index,
    required int selected,
    required bool desktop,
  }) {
    return _CmdRowWrapper(
      key: _itemKeys.putIfAbsent(index, () => GlobalKey(debugLabel: 'cmd-row-$index')),
      selected: selected == index,
      child: CmdRow(
        icon: hit.icon,
        title: hit.title,
        meta: hit.meta,
        side: hit.side,
        query: _query,
        selected: selected == index,
        mobile: !desktop,
        onTap: () => _openHit(hit),
        onHover: () => setState(() => _selected = index),
      ),
    );
  }

  Widget _loadMore(
    AppLocalizations l,
    VoidCallback onTap,
    bool desktop,
    bool loading,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: desktop ? 16 : 14,
        vertical: 4,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: loading ? null : onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Text(
              l.loadMore,
              style: const TextStyle(
                fontSize: 11,
                color: SpecTokens.muted,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cmdGroupHeader(String label, {bool mobile = false}) {
    return Padding(
      padding: mobile
          ? const EdgeInsets.fromLTRB(14, 9, 14, 4)
          : const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          letterSpacing: 0.9,
          fontWeight: FontWeight.w600,
          color: SpecTokens.faint,
          fontFamilyFallback: AppTypography.fallback,
        ),
      ),
    );
  }

  String _eventMeta(BuildContext context, AppLocalizations l, Event event) {
    final parts = <String>[];
    final calendars = ref.read(calendarsProvider).valueOrNull ?? const [];
    final cal = calendars.where((c) => c.id == event.calendarId).firstOrNull;
    if (cal != null && cal.name.isNotEmpty) {
      parts.add(cal.name);
    }
    if (event.isAllDay) {
      parts.add(l.allDay);
    } else {
      final start = event.startDt.toLocal();
      final end = event.endDt.toLocal();
      final today = _today();
      final day = DateTime(start.year, start.month, start.day);
      final clock =
          '${DateFormatters.formatTime(start)}–${DateFormatters.formatTime(end)}';
      if (day == today) {
        parts.add('${l.today} $clock');
      } else if (day == today.add(const Duration(days: 1))) {
        parts.add('${l.tomorrow} $clock');
      } else {
        final locale = Localizations.localeOf(context).toString();
        parts.add(
          '${DateFormat.MMMd(locale).format(start)} ${DateFormat.E(locale).format(start)} · $clock',
        );
      }
    }
    if (event.rrule != null && event.rrule!.isNotEmpty) {
      parts.add(describeRepeat(context, event.rrule!));
    }
    return parts.join(' · ');
  }

  String _todoMeta(BuildContext context, AppLocalizations l, Todo todo) {
    final parts = <String>[];
    final calendars = ref.read(calendarsProvider).valueOrNull ?? const [];
    final cal = calendars.where((c) => c.id == todo.calendarId).firstOrNull;
    if (cal != null && cal.name.isNotEmpty) {
      parts.add(cal.name);
    }
    if (todo.dueDate != null) {
      final due = todo.dueDate!.toLocal();
      final today = _today();
      final day = DateTime(due.year, due.month, due.day);
      final timeStr = DateFormatters.formatTime(due);
      if (day == today) {
        parts.add('${l.today} $timeStr ${l.dueTodaySection}');
      } else if (day == today.add(const Duration(days: 1))) {
        parts.add('${l.tomorrow} $timeStr');
      } else {
        final locale = Localizations.localeOf(context).toString();
        parts.add('${DateFormat.MMMd(locale).format(due)} $timeStr');
      }
    }
    if (todo.startDate != null) {
      final start = todo.startDate!.toLocal();
      parts.add('${l.scheduledLabel} ${DateFormatters.formatTime(start)}');
    }
    if (todo.rrule != null && todo.rrule!.isNotEmpty) {
      parts.add(describeRepeat(context, todo.rrule!));
    }
    final projection = ref.read(actionProjectionProvider).valueOrNull;
    if (projection != null) {
      final missedCount = projection.missedTaskInstances
              .where((inst) => inst.todo.id == todo.id)
              .length +
          projection.earlierMissedSeries
              .where((t) => t.id == todo.id)
              .length;
      if (missedCount > 0) {
        parts.add('${l.missed} $missedCount');
      }
    }
    return parts.join(' · ');
  }

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }
}

enum _CmdHitKind { todo, event, action }

enum _CmdActionKind { captureTodo, captureEvent, goSettings }

class _CmdHit {
  final _CmdHitKind kind;
  final Todo? todo;
  final Event? event;
  final _CmdActionKind? action;
  final String title;
  final String meta;
  final String side;
  final IconData icon;

  const _CmdHit.todo(
    this.todo, {
    required this.title,
    required this.meta,
    required this.side,
  })  : kind = _CmdHitKind.todo,
        event = null,
        action = null,
        icon = CupertinoIcons.check_mark;

  const _CmdHit.event(
    this.event, {
    required this.title,
    required this.meta,
    required this.side,
  })  : kind = _CmdHitKind.event,
        todo = null,
        action = null,
        icon = CupertinoIcons.calendar;

  const _CmdHit.action(
    this.action, {
    required this.title,
    required this.meta,
    required this.side,
    required this.icon,
  })  : kind = _CmdHitKind.action,
        todo = null,
        event = null;
}

class CmdRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String meta;
  final String side;
  final String query;
  final bool selected;
  final bool mobile;
  final VoidCallback onTap;
  final VoidCallback onHover;

  const CmdRow({
    super.key,
    required this.icon,
    required this.title,
    required this.meta,
    required this.side,
    required this.query,
    required this.selected,
    this.mobile = false,
    required this.onTap,
    required this.onHover,
  });

  @override
  Widget build(BuildContext context) {
    final minHeight = mobile ? 44.0 : 43.0;
    final padding = mobile
        ? const EdgeInsets.symmetric(horizontal: 14)
        : const EdgeInsets.symmetric(horizontal: 16);

    final bg = selected
        ? (mobile ? const Color(0xFFEFEFE8) : SpecTokens.wash)
        : Colors.transparent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHover(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: minHeight),
          padding: padding,
          decoration: BoxDecoration(
            color: bg,
            border: mobile && selected
                ? const Border(
                    left: BorderSide(color: SpecTokens.ink, width: 3),
                  )
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: SpecTokens.muted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _highlight(
                        title,
                        query,
                        const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: SpecTokens.ink,
                          fontFamilyFallback: AppTypography.fallback,
                        ),
                      ),
                      if (meta.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(
                            meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 9.5,
                              color: SpecTokens.faint,
                              fontFamilyFallback: AppTypography.fallback,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (side.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  side,
                  style: const TextStyle(
                    fontSize: 9.5,
                    color: SpecTokens.faint,
                    letterSpacing: 0.5,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _highlight(String text, String q, TextStyle base) {
    final queryTrimmed = q.trim();
    if (queryTrimmed.isEmpty) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: base,
      );
    }
    final lowerText = text.toLowerCase();
    final lowerQuery = queryTrimmed.toLowerCase();
    final index = lowerText.indexOf(lowerQuery);
    if (index < 0) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: base,
      );
    }
    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        RichText(
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          text: TextSpan(
            style: base,
            children: [
              if (index > 0) TextSpan(text: text.substring(0, index)),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3E7C9), // spec <mark> highlight
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    text.substring(index, index + queryTrimmed.length),
                    style: base.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              if (index + queryTrimmed.length < text.length)
                TextSpan(text: text.substring(index + queryTrimmed.length)),
            ],
          ),
        ),
        Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: base.copyWith(color: Colors.transparent),
        ),
      ],
    );
  }
}

class CmdEmpty extends StatelessWidget {
  final String query;

  const CmdEmpty({super.key, required this.query});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 52, horizontal: 20),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(
            CupertinoIcons.search,
            size: 23,
            color: Color(0xFFB5B5AB),
          ),
          const SizedBox(height: 8),
          Text(
            l.commandNotFound(query),
            style: const TextStyle(
              fontSize: 12,
              color: SpecTokens.muted,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
        ],
      ),
    );
  }
}

class _CmdRowWrapper extends StatefulWidget {
  final Widget child;
  final bool selected;

  const _CmdRowWrapper({super.key, required this.child, required this.selected});

  @override
  State<_CmdRowWrapper> createState() => _CmdRowWrapperState();
}

class _CmdRowWrapperState extends State<_CmdRowWrapper> {
  @override
  void didUpdateWidget(covariant _CmdRowWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && !oldWidget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 80),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
