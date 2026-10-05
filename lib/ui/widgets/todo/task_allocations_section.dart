import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/records/todo_occurrence.dart';
import 'package:dayspark/domain/records/todo_recurrence.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';
import 'package:timezone/timezone.dart' as tz;

class TaskAllocationsSection extends ConsumerWidget {
  const TaskAllocationsSection({super.key, required this.todo});

  final Todo todo;

  bool get _canSchedule =>
      todo.deletedAt == null &&
      todo.status != 'COMPLETED' &&
      todo.status != 'CANCELLED';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final allocationsAsync = ref.watch(taskAllocationsForTodoProvider(todo.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l.taskAllocations,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            if (_canSchedule)
              TextButton.icon(
                icon: const Icon(CupertinoIcons.add, size: 16),
                label: Text(l.addTaskAllocation),
                onPressed: () => _create(context, ref),
              ),
          ],
        ),
        allocationsAsync.when(
          data: (allocations) {
            if (allocations.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  l.noTaskAllocations,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }
            return Column(
              children: allocations.map((allocation) {
                final active = allocation.state == 'active';
                final orphan =
                    allocation.occurrenceId != null &&
                    !_isCurrentOccurrence(allocation.occurrenceId!);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(CupertinoIcons.time),
                  title: Text(
                    DateFormatters.formatTaskAllocationRange(
                      allocation.startAt,
                      allocation.endAt,
                    ),
                  ),
                  subtitle: orphan
                      ? Text(l.orphanTaskAllocation)
                      : active
                      ? null
                      : Text(l.cancelledTaskAllocation),
                  trailing: active
                      ? IconButton(
                          tooltip: l.cancelTaskAllocation,
                          icon: const Icon(CupertinoIcons.xmark_circle),
                          onPressed: () => _cancel(context, ref, allocation.id),
                        )
                      : null,
                );
              }).toList(),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (error, _) => Text(l.error('$error')),
        ),
      ],
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context)!;
    final now = DateTime.now();
    String? occurrenceId;
    if (todo.rrule != null && todo.rrule!.isNotEmpty) {
      var freshTodo =
          await (ref
                  .read(databaseProvider)
                  .select(ref.read(databaseProvider).todos)
                ..where((row) => row.id.equals(todo.id)))
              .getSingle();
      if (!context.mounted) return;
      if (TodoRecurrence.fromTodo(freshTodo).isUnknownLegacy) {
        if (!legacyRuleIsSupported(freshTodo.rrule ?? '')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.unsupportedLegacyRecurrence)),
          );
          return;
        }
        final confirmed = await confirmLegacyRecurrence(
          context,
          ref,
          freshTodo,
        );
        if (!confirmed || !context.mounted) return;
        freshTodo =
            await (ref
                    .read(databaseProvider)
                    .select(ref.read(databaseProvider).todos)
                  ..where((row) => row.id.equals(todo.id)))
                .getSingle();
        if (!context.mounted) return;
      }
      final TodoOccurrenceExpansion expansion;
      try {
        expansion = expandTodoOccurrences(
          freshTodo,
          startInclusive: now,
          endExclusive: now.add(const Duration(days: 90)),
          maxOccurrences: 100,
        );
      } on Object catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(expansionError(l, error))));
        }
        return;
      }
      if (expansion.status != TodoOccurrenceExpansionStatus.expanded) {
        if (context.mounted) {
          final message = switch (expansion.status) {
            TodoOccurrenceExpansionStatus.requiresLegacyConfirmation =>
              l.legacyRecurrenceRequiresConfirmation,
            TodoOccurrenceExpansionStatus.unsupported =>
              l.unsupportedRecurrence,
            _ => l.noOccurrencesAvailable,
          };
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
        return;
      }
      if (expansion.occurrences.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.noOccurrencesAvailable)));
        return;
      }
      final selected = await showDialog<TodoOccurrence>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: Text(l.selectTodoOccurrence),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              child: Text(l.occurrenceWindowHint),
            ),
            for (final occurrence in expansion.occurrences)
              SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(occurrence),
                child: Text(_occurrenceLabel(occurrence)),
              ),
          ],
        ),
      );
      if (selected == null || !context.mounted) return;
      occurrenceId = selected.occurrenceId;
    }
    final initialStart = DateTime(now.year, now.month, now.day, now.hour + 1);
    final date = await showDatePicker(
      context: context,
      initialDate: initialStart,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !context.mounted) return;
    final startTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialStart),
    );
    if (startTime == null || !context.mounted) return;
    final initialEnd = initialStart.add(const Duration(hours: 1));
    final endTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialEnd),
    );
    if (endTime == null || !context.mounted) return;
    final startAt = DateTime(
      date.year,
      date.month,
      date.day,
      startTime.hour,
      startTime.minute,
    );
    var endAt = DateTime(
      date.year,
      date.month,
      date.day,
      endTime.hour,
      endTime.minute,
    );
    if (!endAt.isAfter(startAt)) endAt = endAt.add(const Duration(days: 1));
    try {
      await ref.read(createTaskAllocationProvider)(
        todoId: todo.id,
        startAt: startAt,
        endAt: endAt,
        occurrenceId: occurrenceId,
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.error('$error'))));
      }
    }
  }

  static bool legacyRuleIsSupported(String rawRule) {
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

  static String expansionError(AppLocalizations l, Object error) {
    final message = error.toString();
    if (message.contains('transition horizon')) {
      return l.recurrenceTimezoneHorizonError;
    }
    if (message.contains('requested limit')) {
      return l.recurrenceOccurrenceLimitError;
    }
    return l.error('$error');
  }

  static Future<bool> confirmLegacyRecurrence(
    BuildContext context,
    WidgetRef ref,
    Todo freshTodo,
  ) async {
    final l = AppLocalizations.of(context)!;
    final zoneController = TextEditingController(text: tz.local.name);
    final initialAnchor = freshTodo.startDate ?? freshTodo.dueDate;
    final anchorController = TextEditingController(
      text: initialAnchor == null ? '' : canonicalDateTime(initialAnchor),
    );
    final evidence = LegacyRecurrenceEvidence.decode(
      freshTodo.recurrenceEvidence,
    );
    var source = freshTodo.startDate != null
        ? RecurrenceAnchorSource.start
        : RecurrenceAnchorSource.due;
    var asDate = false;
    var previewed = false;
    var previewLabels = <String>[];
    String? previewError;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(l.confirmLegacyRecurrenceTitle),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.confirmLegacyRecurrenceBody),
                  const SizedBox(height: 12),
                  if (evidence != null) ...[
                    Text(
                      l.legacyRecurrenceEvidence(
                        evidence.source,
                        evidence.timeSemantic,
                        evidence.rawTzid == null
                            ? ''
                            : ' (${evidence.rawTzid})',
                      ),
                    ),
                    if (evidence.hasVTimezone) Text(l.legacyVTimezonePresent),
                  ] else
                    Text(l.legacyRecurrenceEvidenceMissing),
                  Text('${l.recurrenceRule}: ${freshTodo.rrule ?? ''}'),
                  TextField(
                    controller: zoneController,
                    decoration: InputDecoration(
                      labelText: l.recurrenceTimeZone,
                      helperText: l.recurrenceTimeZoneSuggested,
                    ),
                    onChanged: (_) => setDialogState(() {
                      previewed = false;
                      previewError = null;
                    }),
                  ),
                  const SizedBox(height: 8),
                  DropdownButton<RecurrenceAnchorSource>(
                    value: source,
                    isExpanded: true,
                    items: [
                      DropdownMenuItem(
                        value: RecurrenceAnchorSource.start,
                        child: Text(l.startDate),
                      ),
                      DropdownMenuItem(
                        value: RecurrenceAnchorSource.due,
                        child: Text(l.dueDate),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() {
                          source = value;
                          previewed = false;
                          previewLabels = [];
                          final selectedDate =
                              value == RecurrenceAnchorSource.start
                              ? freshTodo.startDate
                              : freshTodo.dueDate;
                          anchorController.text = selectedDate == null
                              ? ''
                              : canonicalDateTime(selectedDate);
                        });
                      }
                    },
                  ),
                  Wrap(
                    children: [
                      ChoiceChip(
                        label: Text(l.dateOnly),
                        selected: asDate,
                        onSelected: (_) => setDialogState(() {
                          asDate = true;
                          previewed = false;
                          previewLabels = [];
                          anchorController.text = anchorController.text
                              .split('T')
                              .first;
                        }),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: Text(l.dateAndTime),
                        selected: !asDate,
                        onSelected: (_) => setDialogState(() {
                          asDate = false;
                          previewed = false;
                          previewLabels = [];
                          if (!anchorController.text.contains('T') &&
                              anchorController.text.isNotEmpty) {
                            anchorController.text += 'T00:00:00';
                          }
                        }),
                      ),
                    ],
                  ),
                  TextField(
                    controller: anchorController,
                    decoration: InputDecoration(
                      labelText: l.legacyAnchorValue,
                      helperText: asDate
                          ? l.legacyDateFormatHint
                          : l.legacyDateTimeFormatHint,
                    ),
                    onChanged: (_) => setDialogState(() {
                      previewed = false;
                      previewError = null;
                    }),
                  ),
                  if (previewError != null) Text(previewError!),
                  if (previewLabels.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(l.legacyRecurrencePreview),
                    for (final label in previewLabels) Text(label),
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
                  final value = parseLegacyAnchor(
                    anchorController.text.trim(),
                    asDate,
                  );
                  final spec = RecurrenceSpec.parse(
                    anchor: RecurrenceAnchor(source: source, value: value),
                    timeZone: zoneController.text.trim(),
                    rrule: freshTodo.rrule!.startsWith('RRULE:')
                        ? freshTodo.rrule!.substring(6)
                        : freshTodo.rrule!,
                  );
                  final now = DateTime.now();
                  final nowDate = LocalDate(now.year, now.month, now.day);
                  final LocalDate dateWindowStart;
                  final DateTime instantWindowStart;
                  if (value case final LocalDate date) {
                    dateWindowStart = date.compareTo(nowDate) > 0
                        ? date
                        : nowDate;
                    instantWindowStart = now.toUtc();
                  } else {
                    final dateTime = value as LocalDateTime;
                    final anchorCandidate = DateTime.utc(
                      dateTime.year,
                      dateTime.month,
                      dateTime.day,
                      dateTime.hour,
                      dateTime.minute,
                      dateTime.second,
                    );
                    dateWindowStart = nowDate;
                    instantWindowStart = anchorCandidate.isAfter(now.toUtc())
                        ? anchorCandidate.subtract(const Duration(days: 1))
                        : now.toUtc();
                  }
                  final results = const RecurrenceEngine().expand(
                    spec,
                    window: value is LocalDate
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
                  setDialogState(() {
                    previewLabels = results.take(5).map((item) {
                      final nominal = item.nominal;
                      return nominal is LocalDate
                          ? nominal.canonical
                          : nominal.canonical;
                    }).toList();
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
        ),
      ),
    );
    if (accepted != true || !context.mounted) {
      zoneController.dispose();
      anchorController.dispose();
      return false;
    }
    final RecurrenceLocalValue value;
    try {
      value = parseLegacyAnchor(anchorController.text.trim(), asDate);
      await ref.read(confirmLegacyRecurrenceProvider)(
        todoId: freshTodo.id,
        timeZone: zoneController.text.trim(),
        interpretation: RecurrenceAnchor(source: source, value: value),
        rrule: freshTodo.rrule!,
      );
      return true;
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.error('$error'))));
      }
      return false;
    } finally {
      zoneController.dispose();
      anchorController.dispose();
    }
  }

  static String canonicalDateTime(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}T'
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}:'
      '${value.second.toString().padLeft(2, '0')}';

  static RecurrenceLocalValue parseLegacyAnchor(String value, bool asDate) {
    if (asDate && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      final parts = value.split('-').map(int.parse).toList();
      return LocalDate(parts[0], parts[1], parts[2]);
    }
    if (!asDate &&
        RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$').hasMatch(value)) {
      final split = value.split('T');
      final date = split[0].split('-').map(int.parse).toList();
      final time = split[1].split(':').map(int.parse).toList();
      return LocalDateTime(
        date[0],
        date[1],
        date[2],
        time[0],
        time[1],
        time[2],
      );
    }
    throw const FormatException(
      'Enter an anchor matching the selected value type.',
    );
  }

  String _occurrenceLabel(TodoOccurrence occurrence) {
    final nominal = occurrence.nominalAnchor;
    if (nominal is LocalDate) return nominal.canonical;
    final instant = occurrence.resolvedStartInstant;
    return instant == null
        ? nominal.canonical
        : '${nominal.canonical} (${DateFormatters.formatDate(instant.toLocal())} '
              '${DateFormatters.formatTime(instant.toLocal())})';
  }

  bool _isCurrentOccurrence(String occurrenceId) {
    try {
      return !TodoRecurrence.fromTodo(todo).isUnknownLegacy &&
          isOccurrenceStillValidForSeries(todo, occurrenceId);
    } on FormatException {
      return false;
    } on RecurrenceRuleException {
      return false;
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref, int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.cancelTaskAllocation),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppLocalizations.of(context)!.cancelTaskAllocation),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(cancelTaskAllocationProvider)(id);
  }
}
