import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/default_calendar_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/design/spec_toast.dart';
import 'package:dayspark/ui/pages/settings/settings_ui.dart';
import 'package:dayspark/ui/shell/workspace_page.dart';
import 'package:dayspark/ui/widgets/empty_state.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/domain/providers/default_tab_provider.dart';
import 'package:dayspark/ui/shell/workspace_navigation.dart';

class TrashPage extends ConsumerStatefulWidget {
  const TrashPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends ConsumerState<TrashPage> {
  ({String message, bool isRed})? _feedback;

  void _showFeedback(String message, {bool isRed = false}) {
    setState(() => _feedback = (message: message, isRed: isRed));
  }

  Widget _feedbackBanner() {
    final feedback = _feedback!;
    return InlineAlert(message: feedback.message, isRed: feedback.isRed);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final deletedAsync = ref.watch(deletedTodosProvider);
    final deletedEventsAsync = ref.watch(deletedEventsProvider);
    final todos = deletedAsync.valueOrNull ?? [];
    final events = deletedEventsAsync.valueOrNull ?? [];
    final hasAny = todos.isNotEmpty || events.isNotEmpty;

    final content = deletedAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _loadFailure(context, ref, l),
      data: (todoRows) => deletedEventsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _loadFailure(context, ref, l),
        data: (eventRows) {
          if (todoRows.isEmpty && eventRows.isEmpty) {
            final empty = EmptyState(
              icon: CupertinoIcons.trash,
              title: l.trashEmpty,
              hint: l.trashEmptyHint,
              action: DsButton(
                // "Back to todos" has to land on Todos — the Home root
                // defaults to whichever tab was last open.
                label: l.trashEmptyAction,
                onPressed: () {
                  ref.read(workspaceTabProvider.notifier).setTab(AppTab.todos);
                  context.go('/?tab=2');
                },
              ),
            );
            if (widget.embedded) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_feedback != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s4,
                      ),
                      child: _feedbackBanner(),
                    ),
                  empty,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_feedback != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s4,
                    ),
                    child: _feedbackBanner(),
                  ),
                Expanded(child: empty),
              ],
            );
          }
          if (widget.embedded) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_feedback != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.s4,
                      0,
                      AppSpacing.s4,
                      0,
                    ),
                    child: _feedbackBanner(),
                  ),
                if (todoRows.isNotEmpty) ...[
                  _sectionHeader(l.todos, todoRows.length),
                  for (final todo in todoRows)
                    _buildTodoTile(context, ref, l, todo),
                ],
                if (eventRows.isNotEmpty) ...[
                  _sectionHeader(l.events, eventRows.length),
                  for (final event in eventRows)
                    _buildEventTile(context, ref, l, event),
                ],
                if (hasAny)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.s4,
                      AppSpacing.s3,
                      AppSpacing.s4,
                      AppSpacing.s1,
                    ),
                    child: DsButton(
                      label: l.emptyTrash,
                      icon: CupertinoIcons.delete,
                      tone: DsButtonTone.danger,
                      expand: true,
                      onPressed: () => _confirmEmptyTrash(
                        context,
                        ref,
                        l,
                        todos.length + events.length,
                      ),
                    ),
                  ),
              ],
            );
          }
          return CustomScrollView(
            slivers: [
              if (_feedback != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s4,
                    ),
                    child: _feedbackBanner(),
                  ),
                ),
              if (todoRows.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _sectionHeader(l.todos, todoRows.length),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) =>
                        _buildTodoTile(context, ref, l, todoRows[index]),
                    childCount: todoRows.length,
                  ),
                ),
              ],
              if (eventRows.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _sectionHeader(l.events, eventRows.length),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) =>
                        _buildEventTile(context, ref, l, eventRows[index]),
                    childCount: eventRows.length,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );

    if (widget.embedded) {
      return content;
    }

    return WorkspacePage(
      title: l.trash,
      maxContentWidth: 720,
      actions: [
        if (hasAny)
          DsButton(
            label: l.emptyTrash,
            tone: DsButtonTone.danger,
            small: true,
            onPressed: () => _confirmEmptyTrash(
              context,
              ref,
              l,
              todos.length + events.length,
            ),
          ),
      ],
      child: content,
    );
  }

  Widget _buildTodoTile(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
    Todo todo,
  ) {
    final calendars = ref.watch(calendarsProvider).valueOrNull ?? const [];
    final calName = calendars
            .where((c) => c.id == todo.calendarId)
            .map((c) => c.name)
            .firstOrNull ??
        '';

    return DsRow(
      key: ValueKey('trash-todo-${todo.id}'),
      title: todo.summary,
      meta: DsMeta(
        parts: [
          DsMetaPart(l.todos),
          if (calName.isNotEmpty) DsMetaPart(calName),
          if (todo.deletedAt != null)
            DsMetaPart(l.deletedOn(DateFormatters.formatDate(todo.deletedAt!))),
        ],
      ),
      trailing: _restoreDeleteActions(
        l,
        onRestore: () async {
          final cals = ref.read(calendarsProvider).valueOrNull ?? const [];
          if (cals.isNotEmpty && !cals.any((c) => c.id == todo.calendarId)) {
            final defaultCalId = ref.read(defaultCalendarIdProvider) ?? cals.first.id;
            try {
              await ref.read(updateTodoProvider)(
                todo.id,
                TodosCompanion(calendarId: Value(defaultCalId)),
              );
            } catch (_) {}
          }
          await ref.read(restoreTodoProvider)(todo.id);
          if (mounted) _showFeedback(l.trashRestoredBanner(todo.summary));
        },
        onDelete: () async {
          await ref.read(permanentDeleteTodoProvider)(todo.id);
          if (mounted) _showFeedback(l.trashDeletedBanner(todo.summary));
        },
        confirmDelete: () => _confirmPermanentDelete(context, l),
      ),
    );
  }

  Widget _buildEventTile(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
    Event event,
  ) {
    final calendars = ref.watch(calendarsProvider).valueOrNull ?? const [];
    final calName = calendars
            .where((c) => c.id == event.calendarId)
            .map((c) => c.name)
            .firstOrNull ??
        '';

    return DsRow(
      key: ValueKey('trash-event-${event.id}'),
      title: event.summary,
      meta: DsMeta(
        parts: [
          DsMetaPart(l.events),
          if (calName.isNotEmpty) DsMetaPart(calName),
          DsMetaPart(DateFormatters.formatDateTime(event.startDt)),
          if (event.deletedAt != null)
            DsMetaPart(
              l.deletedOn(DateFormatters.formatDate(event.deletedAt!)),
            ),
        ],
      ),
      trailing: _restoreDeleteActions(
        l,
        onRestore: () async {
          final cals = ref.read(calendarsProvider).valueOrNull ?? const [];
          if (cals.isNotEmpty && !cals.any((c) => c.id == event.calendarId)) {
            final defaultCalId = ref.read(defaultCalendarIdProvider) ?? cals.first.id;
            try {
              await ref.read(updateEventProvider)(
                event.id,
                EventsCompanion(calendarId: Value(defaultCalId)),
              );
            } catch (_) {}
          }
          await ref.read(restoreEventProvider)(event.id);
          if (mounted) _showFeedback(l.trashRestoredBanner(event.summary));
        },
        onDelete: () async {
          await ref.read(hardDeleteEventWithChildrenProvider)(event.id);
          if (mounted) _showFeedback(l.trashDeletedBanner(event.summary));
        },
        confirmDelete: () => _confirmPermanentDelete(context, l),
      ),
    );
  }

  Widget _loadFailure(BuildContext context, WidgetRef ref, AppLocalizations l) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.error,
            style: AppTypography.body.copyWith(color: context.ds.ink2),
          ),
          const SizedBox(height: AppSpacing.s2),
          DsButton(
            label: l.retry,
            tone: DsButtonTone.ghost,
            small: true,
            onPressed: () {
              ref.invalidate(deletedTodosProvider);
              ref.invalidate(deletedEventsProvider);
            },
          ),
        ],
      ),
    );
  }

  Widget _restoreDeleteActions(
    AppLocalizations l, {
    required Future<void> Function() onRestore,
    required Future<void> Function() onDelete,
    required Future<bool> Function() confirmDelete,
  }) {
    return _TrashActions(
      l: l,
      onRestore: onRestore,
      onDelete: onDelete,
      confirmDelete: confirmDelete,
    );
  }

  Widget _sectionHeader(String title, int count) {
    return DsGroupHead(title, count: count);
  }

  Future<bool> _confirmPermanentDelete(
    BuildContext context,
    AppLocalizations l,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => DsDialog(
        title: l.permanentDelete,
        width: 440,
        actions: [
          const Spacer(),
          DsButton(
            label: l.cancel,
            tone: DsButtonTone.ghost,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          const SizedBox(width: AppSpacing.s2),
          DsButton(
            label: l.permanentDelete,
            tone: DsButtonTone.danger,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
        child: Text(
          l.confirmPermanentDelete,
          style: AppTypography.body.copyWith(color: context.ds.ink2),
        ),
      ),
    );
    return result ?? false;
  }

  void _confirmEmptyTrash(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
    int count,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => DsDialog(
        title: l.emptyTrash,
        width: 440,
        actions: [
          const Spacer(),
          DsButton(
            label: l.cancel,
            tone: DsButtonTone.ghost,
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          const SizedBox(width: AppSpacing.s2),
          DsButton(
            label: l.emptyTrash,
            tone: DsButtonTone.danger,
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await ref.read(emptyTrashProvider)();
                await ref.read(emptyEventTrashProvider)();
                if (mounted) _showFeedback(l.trashClearedBanner);
              } catch (error) {
                debugPrint('trash: empty error: $error');
                if (context.mounted) {
                  showSpecToast(context, l.error);
                }
              }
            },
          ),
        ],
        child: Text(
          '${l.confirmEmptyTrash} ${l.dayItemCount(count)}',
          style: AppTypography.body.copyWith(color: context.ds.ink2),
        ),
      ),
    );
  }
}

/// Restore and permanent-delete are asynchronous, so the row owns a busy flag:
/// a failed call must leave both buttons usable instead of dead.
class _TrashActions extends StatefulWidget {
  const _TrashActions({
    required this.l,
    required this.onRestore,
    required this.onDelete,
    required this.confirmDelete,
  });

  final AppLocalizations l;
  final Future<void> Function() onRestore;
  final Future<void> Function() onDelete;
  final Future<bool> Function() confirmDelete;

  @override
  State<_TrashActions> createState() => _TrashActionsState();
}

class _TrashActionsState extends State<_TrashActions> {
  bool _busy = false;

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      await widget.onRestore();
    } catch (error) {
      debugPrint('trash: restore error: $error');
      if (mounted) {
        showSpecToast(context, widget.l.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await widget.confirmDelete();
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      await widget.onDelete();
    } catch (error) {
      debugPrint('trash: delete error: $error');
      if (mounted) {
        showSpecToast(context, widget.l.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DsButton(
          label: l.restoreTodo,
          icon: CupertinoIcons.arrow_uturn_left,
          small: true,
          tone: DsButtonTone.secondary,
          loading: _busy,
          onPressed: _busy ? null : _restore,
        ),
        const SizedBox(width: AppSpacing.s2),
        DsIconButton(
          icon: CupertinoIcons.delete,
          size: 17,
          compact: true,
          color: context.ds.danger,
          tooltip: l.permanentDelete,
          onPressed: _busy ? null : _delete,
        ),
      ],
    );
  }
}
