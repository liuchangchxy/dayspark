import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_pickers.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_row.dart';

/// A reminder the form has staged but not written yet. [id] is set for a row
/// that already exists, so removing it tells the form what to delete on save.
class DraftReminder {
  const DraftReminder({required this.triggerTime, this.id});

  final DateTime triggerTime;
  final int? id;

  @override
  bool operator ==(Object other) =>
      other is DraftReminder &&
      other.id == id &&
      other.triggerTime == triggerTime;

  @override
  int get hashCode => Object.hash(id, triggerTime);
}

/// Reminders for one object.
///
/// Pass [draft] to edit them as part of a form: nothing is written until the
/// form saves, so cancelling leaves the stored reminders alone. Omit it to work
/// against the database directly.
class RemindersSection extends ConsumerWidget {
  const RemindersSection({
    super.key,
    required this.parentType,
    this.parentId,
    this.defaultTriggerTime,
    this.anchorTime,
    this.draft,
    this.onDraftChanged,
    this.enabled = true,
  }) : assert(
         draft != null || parentId != null,
         'either a parent row or a draft list is required',
       );

  final String parentType;
  final int? parentId;
  final DateTime? defaultTriggerTime;

  /// The moment "before" is measured from — a deadline or an event start.
  final DateTime? anchorTime;

  final List<DraftReminder>? draft;
  final ValueChanged<List<DraftReminder>>? onDraftChanged;
  final bool enabled;

  bool get _isDraft => draft != null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(
          l.reminders,
          action: enabled
              ? TextButton.icon(
                  onPressed: () => _add(context, ref),
                  icon: const Icon(CupertinoIcons.add, size: 13),
                  label: Text(l.addReminder),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : null,
        ),
        if (_isDraft)
          _draftRows(context, l)
        else
          ref
              .watch(
                parentType == 'event'
                    ? eventRemindersProvider(parentId!)
                    : todoRemindersProvider(parentId!),
              )
              .when(
                data: (reminders) => reminders.isEmpty
                    ? _empty(context, l)
                    : Column(
                        children: [
                          for (final reminder in reminders)
                            _Row(
                              label: _describe(
                                context,
                                l,
                                reminder.triggerTime,
                              ),
                              onRemove: enabled
                                  ? () => ref.read(deleteReminderProvider)(
                                      reminder.id,
                                    )
                                  : null,
                            ),
                        ],
                      ),
                loading: () => const Padding(
                  padding: EdgeInsets.all(AppSpacing.sm),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                error: (_, __) => _empty(context, l),
              ),
      ],
    );
  }

  Widget _draftRows(BuildContext context, AppLocalizations l) {
    final items = draft!;
    if (items.isEmpty) return _empty(context, l);
    return Column(
      children: [
        for (final reminder in items)
          _Row(
            label: _describe(context, l, reminder.triggerTime),
            onRemove: enabled
                ? () => onDraftChanged!(
                    [...items]..removeWhere((other) => other == reminder),
                  )
                : null,
          ),
      ],
    );
  }

  Widget _empty(BuildContext context, AppLocalizations l) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Text(
      l.noReminders,
      style: AppTypography.caption.copyWith(
        color: context.semantic.textTertiary,
      ),
    ),
  );

  /// An absolute time is a fact; a reminder set relative to the object is
  /// described by the distance, which is what the user actually chose.
  String _describe(
    BuildContext context,
    AppLocalizations l,
    DateTime triggerTime,
  ) {
    final anchor = anchorTime;
    if (anchor != null) {
      final delta = anchor.difference(triggerTime);
      if (delta == Duration.zero) return l.remindOnTime;
      if (delta.inDays >= 1 && delta.inHours % 24 == 0) {
        return l.remindDaysBefore(delta.inDays);
      }
      if (delta.inHours >= 1 && delta.inMinutes % 60 == 0) {
        return l.remindHoursBefore(delta.inHours);
      }
      if (delta.inMinutes >= 1) return l.remindMinutesBefore(delta.inMinutes);
    }
    return formatMoment(context, triggerTime);
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final anchor = anchorTime;
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      builder: (ctx) =>
          _ReminderSheet(anchor: anchor, fallback: defaultTriggerTime),
    );
    if (picked == null || !context.mounted) return;
    if (_isDraft) {
      onDraftChanged!([...draft!, DraftReminder(triggerTime: picked)]);
      return;
    }
    await ref.read(createReminderProvider)(
      parentType: parentType,
      parentId: parentId!,
      triggerTime: picked,
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, this.onRemove});

  final String label;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.bell,
            size: 16,
            color: context.semantic.textSecondary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(label, style: AppTypography.body)),
          if (onRemove != null)
            IconButton(
              icon: const Icon(CupertinoIcons.xmark, size: 16),
              tooltip: l.removeReminder,
              onPressed: onRemove,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
        ],
      ),
    );
  }
}

/// "When should it remind me?" — relative to the object when there is an
/// anchor, because "15 minutes before" is the question the user is answering.
class _ReminderSheet extends StatelessWidget {
  const _ReminderSheet({this.anchor, this.fallback});

  final DateTime? anchor;
  final DateTime? fallback;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final anchor = this.anchor;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.sm,
              0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(l.addReminder, style: AppTypography.title),
                ),
                IconButton(
                  icon: const Icon(CupertinoIcons.xmark, size: 18),
                  tooltip: l.close,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          if (anchor == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Text(
                l.reminderNeedsAnchor,
                style: AppTypography.caption.copyWith(
                  color: context.semantic.textTertiary,
                ),
              ),
            ),
          if (anchor != null) ...[
            _Option(
              label: l.remindOnTime,
              onTap: () => Navigator.of(context).pop(anchor),
            ),
            _Option(
              label: l.remindMinutesBefore(5),
              onTap: () => Navigator.of(
                context,
              ).pop(anchor.subtract(const Duration(minutes: 5))),
            ),
            _Option(
              label: l.remindMinutesBefore(15),
              onTap: () => Navigator.of(
                context,
              ).pop(anchor.subtract(const Duration(minutes: 15))),
            ),
            _Option(
              label: l.remindMinutesBefore(30),
              onTap: () => Navigator.of(
                context,
              ).pop(anchor.subtract(const Duration(minutes: 30))),
            ),
            _Option(
              label: l.remindHoursBefore(1),
              onTap: () => Navigator.of(
                context,
              ).pop(anchor.subtract(const Duration(hours: 1))),
            ),
            _Option(
              label: l.remindDaysBefore(1),
              onTap: () => Navigator.of(
                context,
              ).pop(anchor.subtract(const Duration(days: 1))),
            ),
          ],
          _Option(
            label: l.remindCustom,
            onTap: () async {
              final initial =
                  anchor ??
                  fallback ??
                  DateTime.now().add(const Duration(hours: 1));
              final picked = await pickDateTime(context, initial: initial);
              if (!context.mounted) return;
              Navigator.of(context).pop(picked);
            },
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(label, style: AppTypography.body),
            ),
          ),
        ),
      ),
    );
  }
}
