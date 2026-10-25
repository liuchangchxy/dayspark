import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/shell/workspace_page.dart';
import 'package:dayspark/ui/widgets/attachment_list.dart';
import 'package:dayspark/ui/widgets/schedule/repeat_editor.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_pickers.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_row.dart';

/// Read an event without entering edit mode. Same split as [TodoDetailPage].
///
/// The adapter that arrives in `extra` is a snapshot: a calendar edit on
/// another device, or a delete from the form, would otherwise leave this page
/// describing an event that no longer matches. The row is therefore re-read
/// from the database and the snapshot is only the fallback.
class EventDetailPage extends ConsumerWidget {
  const EventDetailPage({super.key, required this.event});

  final CalendaEventAdapter event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final desktop = isWorkspaceLayout(context);
    final live = ref.watch(liveEventProvider(event.drifId)).valueOrNull;
    final gone =
        live == null && ref.watch(liveEventProvider(event.drifId)).hasValue;
    if (gone) {
      return WorkspacePage(
        title: event.title,
        maxContentWidth: desktop ? 720 : null,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text(
              l.goneFromHere,
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(
                color: context.semantic.textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    // Re-reading the row keeps the page honest after an edit, but the row is
    // the *series*: it has no idea which occurrence the calendar handed over.
    // Taking it wholesale would silently turn a tapped occurrence into the
    // series and make "delete this occurrence only" unreachable, so the
    // occurrence identity stays with the snapshot.
    final row = live == null
        ? event
        : event.isRecurringOccurrence
        ? CalendaEventAdapter(
            drifId: live.drifId,
            calendarId: live.calendarId,
            title: live.title,
            description: live.description,
            location: live.location,
            color: live.color,
            isAllDay: live.isAllDay,
            rrule: live.rrule,
            start: event.start,
            end: event.end,
            occurrenceStart: event.occurrenceStart,
            seriesStart: live.seriesStart,
            seriesEnd: live.seriesEnd,
          )
        : live;
    final start = row.isRecurringOccurrence ? row.start : row.seriesStart;
    final end = row.isRecurringOccurrence ? row.end : row.seriesEnd;
    final length = end.difference(start);
    final validRange = !length.isNegative && length > Duration.zero;
    final calendarName = ref
        .watch(calendarsProvider)
        .valueOrNull
        ?.where((c) => c.id == row.calendarId)
        .firstOrNull
        ?.name;

    return WorkspacePage(
      title: row.title,
      maxContentWidth: desktop ? 720 : null,
      actions: [
        PageSaveButton(
          label: l.edit,
          onPressed: () => context.push('/event/edit', extra: row),
        ),
      ],
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          desktop ? AppSpacing.xl : AppSpacing.lg,
          AppSpacing.lg,
          desktop ? AppSpacing.xl : AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          Text(row.title, style: AppTypography.headline),
          if (row.isRecurringOccurrence) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              l.editOccurrenceNotice,
              style: AppTypography.caption.copyWith(
                color: context.semantic.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          const RowDivider(),
          const SizedBox(height: AppSpacing.sm),
          ScheduleRow(
            label: l.startTime,
            value: row.isAllDay
                ? formatDeadline(context, start)
                : formatMoment(context, start),
          ),
          ScheduleRow(
            label: l.endTime,
            value: row.isAllDay
                ? formatDeadline(context, end)
                : formatMoment(context, end),
          ),
          ScheduleRow(
            label: l.duration,
            value: !validRange
                ? l.invalidTimeRange
                : row.isAllDay
                ? l.durationAllDay
                : formatExecutionLength(context, length),
          ),
          ScheduleRow(
            label: l.recurrenceRule,
            value: describeRepeat(context, row.rrule),
            placeholder: row.rrule == null,
          ),
          if (calendarName != null)
            ScheduleRow(label: l.calendar, value: calendarName),
          if (row.location != null && row.location!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const RowDivider(),
            const SizedBox(height: AppSpacing.md),
            ScheduleRow(label: l.location, value: row.location!),
          ],
          if (row.description != null &&
              row.description!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(row.description!, style: AppTypography.body),
          ],
          const SizedBox(height: AppSpacing.lg),
          _Tags(eventId: row.drifId),
          const SizedBox(height: AppSpacing.lg),
          const RowDivider(),
          const SizedBox(height: AppSpacing.md),
          AttachmentList(parentType: 'event', parentId: row.drifId),
          const SizedBox(height: AppSpacing.xl),
          const RowDivider(),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _delete(context, ref, l, row),
              icon: Icon(
                CupertinoIcons.trash,
                size: 16,
                color: Theme.of(context).colorScheme.error,
              ),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                minimumSize: const Size(48, 48),
              ),
              label: Text(l.moveToTrash),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
    CalendaEventAdapter row,
  ) async {
    // A recurring series has two very different deletes; asking which one is
    // the same question the todo side asks before completing an occurrence.
    var occurrenceOnly = false;
    if (row.rrule != null && row.isRecurringOccurrence) {
      final scope = await showDialog<bool>(
    animationStyle: AnimationStyle.noAnimation, context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.deleteScopeTitle),
          content: Text(l.deleteEventConfirm(row.title)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.deleteThisOccurrence),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text(l.deleteWholeSeries),
            ),
          ],
        ),
      );
      if (scope == null || !context.mounted) return;
      occurrenceOnly = !scope;
      if (occurrenceOnly) {
        await ref.read(excludeEventOccurrenceProvider)(
          id: row.drifId,
          occurrenceStart: row.start,
        );
        if (!context.mounted) return;
        _leaveToSource(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.deleted)));
        return;
      }
    } else if (row.rrule != null) {
      final confirmed = await showDialog<bool>(
    animationStyle: AnimationStyle.noAnimation, context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.moveToTrash),
          content: Text(l.deleteRecurringEventConfirm(row.title)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text(l.moveToTrash),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    } else {
      final confirmed = await showDialog<bool>(
    animationStyle: AnimationStyle.noAnimation, context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.moveToTrash),
          content: Text(l.deleteEventConfirm(row.title)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text(l.moveToTrash),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }

    final id = row.drifId;
    final restore = ref.read(restoreEventProvider);
    await ref.read(deleteEventProvider)(id);
    if (!context.mounted) return;
    _leaveToSource(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.deleted),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(label: l.undo, onPressed: () => restore(id)),
      ),
    );
  }
}

/// A deleted object cannot stay on screen. Pop the detail route so the user
/// lands on the list they came from, falling back to Home for deep links.
void _leaveToSource(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router != null && router.canPop()) {
    context.pop();
    return;
  }
  router?.go('/');
}

class _Tags extends ConsumerWidget {
  const _Tags({required this.eventId});

  final int eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(eventTagsProvider(eventId)).valueOrNull ?? const [];
    if (tags.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        for (final tag in tags)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: ColorUtils.parseHex(tag.color),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(tag.name, style: AppTypography.caption),
            ],
          ),
      ],
    );
  }
}
