import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/records/todo_recurrence.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_pickers.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_row.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';
import 'package:timezone/timezone.dart' as tz;

/// Can this pre-migration rule be interpreted at all? A rule the engine cannot
/// parse is reported as unusable rather than confirmed into a wrong series.
bool legacyRuleIsSupported(String rawRule) {
  final rule = rawRule.startsWith('RRULE:') ? rawRule.substring(6) : rawRule;
  for (final valueType in RecurrenceValueType.values) {
    try {
      ValidatedRRule.parse(rule, valueType: valueType);
      return true;
    } on RecurrenceRuleException {
      continue;
    }
  }
  return false;
}

String expansionError(AppLocalizations l, Object error) {
  final message = error.toString();
  if (message.contains('transition horizon')) {
    return l.recurrenceTimezoneHorizonError;
  }
  if (message.contains('requested limit')) {
    return l.recurrenceOccurrenceLimitError;
  }
  return l.error;
}

/// The zone a pre-migration series actually belongs to.
///
/// The evidence row often still carries the TZID the series was imported with,
/// and re-homing that series to the device zone would shift every occurrence.
/// An unrecognisable or missing TZID leaves the device zone as the only
/// defensible reading.
String legacyRecurrenceTimeZone(Todo todo) {
  String? rawTzid;
  try {
    rawTzid = LegacyRecurrenceEvidence.decode(todo.recurrenceEvidence)?.rawTzid;
  } on FormatException {
    rawTzid = null;
  }
  if (rawTzid == null) return tz.local.name;
  ensureTodoRecurrenceTimeZonesInitialized();
  try {
    tz.getLocation(rawTzid);
  } on tz.LocationNotFoundException {
    return tz.local.name;
  }
  return rawTzid;
}

/// The one-time conversation for a pre-migration recurring todo.
///
/// Older rows carry a rule whose anchor and zone were never recorded, so the app
/// cannot know which date the series repeats from. Guessing would silently move
/// a user's schedule, so the dialog asks once — and it asks the only question a
/// user can answer: which day this repeats from. The rule string, the import
/// evidence and the zone id stay in the database; none of them is a question for
/// a person. The answer is written only when the user saves.
Future<bool> confirmLegacyRecurrence(
  BuildContext context,
  WidgetRef ref,
  Todo freshTodo,
) async {
  final l = AppLocalizations.of(context)!;
  final stored = freshTodo.startDate ?? freshTodo.dueDate;
  var anchor = stored ?? DateTime.now();
  // The stored value type is the only evidence of whether this series was
  // written as a date or as a moment; the clock time is the fallback.
  var asDate = stored == null
      ? freshTodo.recurrenceValueType == 'date'
      : stored.hour == 0 && stored.minute == 0;
  final source = freshTodo.startDate != null
      ? RecurrenceAnchorSource.start
      : RecurrenceAnchorSource.due;
  // Preview and save must agree on the zone, or the dates shown would not be
  // the dates written.
  final timeZone = legacyRecurrenceTimeZone(freshTodo);
  var previewLabels = <String>[];
  String? previewError;
  var previewed = false;

  final accepted = await showDialog<bool>(
    animationStyle: AnimationStyle.noAnimation, context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        void invalidate() => setDialogState(() {
          previewed = false;
          previewLabels = [];
          previewError = null;
        });

        List<String> preview() {
          final spec = RecurrenceSpec.parse(
            anchor: RecurrenceAnchor(
              source: source,
              value: _localValue(anchor, asDate),
            ),
            // The evidence's own zone when it is still recognisable; the
            // device's otherwise.
            timeZone: timeZone,
            rrule: freshTodo.rrule!.startsWith('RRULE:')
                ? freshTodo.rrule!.substring(6)
                : freshTodo.rrule!,
          );
          final now = DateTime.now();
          final nowDate = LocalDate(now.year, now.month, now.day);
          final LocalDate dateWindowStart;
          final DateTime instantWindowStart;
          if (_localValue(anchor, asDate) case final LocalDate date) {
            dateWindowStart = date.compareTo(nowDate) > 0 ? date : nowDate;
            instantWindowStart = now.toUtc();
          } else {
            final dateTime = _localValue(anchor, asDate) as LocalDateTime;
            final candidate = DateTime.utc(
              dateTime.year,
              dateTime.month,
              dateTime.day,
              dateTime.hour,
              dateTime.minute,
              dateTime.second,
            );
            dateWindowStart = nowDate;
            instantWindowStart = candidate.isAfter(now.toUtc())
                ? candidate.subtract(const Duration(days: 1))
                : now.toUtc();
          }
          final results = const RecurrenceEngine().expand(
            spec,
            window: asDate
                ? LocalDateWindow(
                    startInclusive: dateWindowStart,
                    endExclusive: dateWindowStart.addDays(90),
                  )
                : InstantWindow(
                    startInclusive: instantWindowStart,
                    endExclusive: instantWindowStart.add(
                      const Duration(days: 90),
                    ),
                  ),
            limit: 100,
          );
          if (results.isEmpty) {
            throw StateError('No occurrences in the preview window.');
          }
          return results.take(5).map((item) => item.nominal.canonical).toList();
        }

        return AlertDialog(
          title: Text(l.confirmLegacyRecurrenceTitle),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l.confirmLegacyRecurrenceBody,
                    style: AppTypography.caption.copyWith(
                      color: context.semantic.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      ChoiceChip(
                        label: Text(l.dateOnly),
                        selected: asDate,
                        onSelected: (_) {
                          anchor = DateTime(
                            anchor.year,
                            anchor.month,
                            anchor.day,
                          );
                          asDate = true;
                          invalidate();
                        },
                      ),
                      ChoiceChip(
                        label: Text(l.dateAndTime),
                        selected: !asDate,
                        onSelected: (_) {
                          asDate = false;
                          invalidate();
                        },
                      ),
                    ],
                  ),
                  ScheduleRow(
                    label: l.legacyRepeatFrom,
                    value: formatDeadline(context, anchor),
                    onTap: () async {
                      final picked = await pickDeadline(
                        context,
                        initial: anchor,
                        withTime: asDate ? false : true,
                      );
                      if (picked == null) return;
                      anchor = picked;
                      invalidate();
                    },
                  ),
                  if (previewError != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      previewError!,
                      style: AppTypography.caption.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  if (previewLabels.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      l.legacyRecurrencePreview,
                      style: AppTypography.caption.copyWith(
                        color: context.semantic.textSecondary,
                      ),
                    ),
                    for (final label in previewLabels)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text(label, style: AppTypography.body),
                      ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l.cancel),
            ),
            TextButton(
              onPressed: () {
                try {
                  final labels = preview();
                  setDialogState(() {
                    previewLabels = labels;
                    previewError = null;
                    previewed = true;
                  });
                } on Object catch (error) {
                  setDialogState(() {
                    previewLabels = [];
                    previewError = expansionError(l, error);
                    previewed = false;
                  });
                }
              },
              child: Text(l.preview),
            ),
            FilledButton(
              onPressed: previewed
                  ? () => Navigator.of(dialogContext).pop(true)
                  : null,
              child: Text(l.save),
            ),
          ],
        );
      },
    ),
  );
  if (accepted != true || !context.mounted) return false;
  try {
    await ref.read(confirmLegacyRecurrenceProvider)(
      todoId: freshTodo.id,
      timeZone: timeZone,
      interpretation: RecurrenceAnchor(
        source: source,
        value: _localValue(anchor, asDate),
      ),
      rrule: freshTodo.rrule!,
    );
    return true;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.error)));
    }
    return false;
  }
}

RecurrenceLocalValue _localValue(DateTime value, bool asDate) => asDate
    ? LocalDate(value.year, value.month, value.day)
    : LocalDateTime(
        value.year,
        value.month,
        value.day,
        value.hour,
        value.minute,
        value.second,
      );
