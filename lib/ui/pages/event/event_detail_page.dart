import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
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
class EventDetailPage extends ConsumerWidget {
  const EventDetailPage({super.key, required this.event});

  final CalendaEventAdapter event;

  bool get _isRecurring => event.rrule != null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final desktop = MediaQuery.sizeOf(context).width >= 1000;
    final length = event.seriesEnd.difference(event.seriesStart);

    return WorkspacePage(
      title: l.eventDetails,
      maxContentWidth: desktop ? 720 : null,
      actions: [
        IconButton(
          icon: const Icon(CupertinoIcons.trash, size: 18),
          tooltip: l.delete,
          visualDensity: VisualDensity.compact,
          onPressed: () => _delete(context, ref, l),
        ),
        const SizedBox(width: AppSpacing.sm),
        PageSaveButton(
          label: l.edit,
          onPressed: () => context.push('/event/edit', extra: event),
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
          Text(event.title, style: AppTypography.headline),
          const SizedBox(height: AppSpacing.lg),
          const RowDivider(),
          const SizedBox(height: AppSpacing.sm),
          ScheduleRow(
            label: l.startTime,
            value: event.isAllDay
                ? formatDeadline(context, event.seriesStart)
                : formatMoment(context, event.seriesStart),
          ),
          ScheduleRow(
            label: l.endTime,
            value: event.isAllDay
                ? formatDeadline(context, event.seriesEnd)
                : formatMoment(context, event.seriesEnd),
          ),
          ScheduleRow(
            label: l.eventDuration,
            value: event.isAllDay
                ? l.durationAllDay
                : formatExecutionLength(context, length),
          ),
          ScheduleRow(
            label: l.recurrenceRule,
            value: describeRepeat(context, event.rrule),
            placeholder: !_isRecurring,
          ),
          if (event.location != null && event.location!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const RowDivider(),
            const SizedBox(height: AppSpacing.md),
            ScheduleRow(label: l.location, value: event.location!),
          ],
          if (event.description != null &&
              event.description!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(event.description!, style: AppTypography.body),
          ],
          const SizedBox(height: AppSpacing.lg),
          _Tags(eventId: event.drifId),
          const SizedBox(height: AppSpacing.xl),
          const RowDivider(),
          const SizedBox(height: AppSpacing.md),
          AttachmentList(parentType: 'event', parentId: event.drifId),
        ],
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.delete),
        content: Text(
          _isRecurring
              ? l.deleteRecurringEventConfirm(event.title)
              : l.deleteEventConfirm(event.title),
        ),
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
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(deleteEventProvider)(event.drifId);
    if (context.mounted) context.pop();
  }
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
