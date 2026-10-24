import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/ai_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/attachments_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/services/attachment_service.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/shell/workspace_page.dart';
import 'package:dayspark/ui/widgets/attachment_list.dart';
import 'package:dayspark/ui/widgets/reminder/reminders_section.dart';
import 'package:dayspark/ui/widgets/schedule/repeat_editor.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_pickers.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_row.dart';
import 'package:dayspark/ui/widgets/tag_chips.dart';

/// One page for "write an event", mirroring [TodoFormPage]: passing [event]
/// edits it, omitting it creates one.
///
/// The write rule from CONSTRAINTS is preserved verbatim — a recurring event is
/// one series, so edits target the row's own DTSTART/DTEND and never the
/// occurrence that was tapped. What changed is only how it is explained: the
/// page says "this repeats" in a phrase, not in an RRULE vocabulary.
class EventFormPage extends ConsumerStatefulWidget {
  const EventFormPage({
    super.key,
    this.event,
    this.initialStart,
    this.initialEnd,
  }) : assert(
         event != null || (initialStart != null && initialEnd != null),
         'either an event to edit or an initial range is required',
       );

  final CalendaEventAdapter? event;
  final DateTime? initialStart;
  final DateTime? initialEnd;

  @override
  ConsumerState<EventFormPage> createState() => _EventFormPageState();
}

class _EventFormPageState extends ConsumerState<EventFormPage> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  late DateTime _start;
  late DateTime _end;
  bool _isAllDay = false;
  late final bool _openedAsAllDay;
  bool _saving = false;
  bool _aiLoading = false;
  String? _rrule;
  int? _calendarId;
  Set<int> _tagIds = {};
  List<DraftReminder> _reminders = [];
  List<DraftAttachment> _attachments = [];

  /// The values the form opened with; [isDirty] compares against them.
  _EventSnapshot? _initial;

  bool get _isEditing => widget.event != null;

  /// True for a series row or any of its occurrences — both write to the same
  /// row, so both have to say so.
  bool get _isRecurring => widget.event?.rrule != null;

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    if (event != null) {
      // The times this page edits: the row's own DTSTART/DTEND, not the
      // position of the occurrence that was tapped.
      _start = event.seriesStart;
      _end = event.seriesEnd;
      _titleController.text = event.title;
      _descriptionController.text = event.description ?? '';
      _locationController.text = event.location ?? '';
      _isAllDay = event.isAllDay;
      _openedAsAllDay = event.isAllDay;
      _rrule = event.rrule;
      _calendarId = event.calendarId;
      _seedAssociations(event.drifId);
    } else {
      _start = widget.initialStart!;
      _end = widget.initialEnd!;
      _openedAsAllDay = false;
      _initial = _snapshot();
    }
  }

  Future<void> _seedAssociations(int eventId) async {
    final tags = await ref.read(eventTagsProvider(eventId).future);
    final reminders = await ref.read(eventRemindersProvider(eventId).future);
    final attachments = await ref.read(
      eventAttachmentsProvider(eventId).future,
    );
    if (!mounted) return;
    setState(() {
      _tagIds = tags.map((tag) => tag.id).toSet();
      _reminders = [
        for (final row in reminders)
          DraftReminder(id: row.id, triggerTime: row.triggerTime),
      ];
      _attachments = [
        for (final row in attachments) DraftAttachment.fromRow(row),
      ];
      _initial = _snapshot();
    });
  }

  _EventSnapshot _snapshot() => _EventSnapshot(
    title: _titleController.text.trim(),
    description: _descriptionController.text.trim(),
    location: _locationController.text.trim(),
    calendarId: _calendarId,
    start: _start,
    end: _end,
    isAllDay: _isAllDay,
    rrule: _rrule,
    tagIds: {..._tagIds},
    reminders: [..._reminders],
    attachments: [..._attachments],
  );

  bool get _isDirty {
    final initial = _initial;
    if (initial == null) return false;
    return _snapshot() != initial;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  /// All-day events are stored at midnight. Existing all-day rows keep whatever
  /// they already carry — normalising on every save would move a series'
  /// DTSTART that the user never touched.
  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  bool get _normaliseAllDay => _isAllDay && !_openedAsAllDay;

  DateTime get _startDt => _normaliseAllDay ? _dateOnly(_start) : _start;

  DateTime get _endDt => _normaliseAllDay ? _dateOnly(_end) : _end;

  /// An end at or before the start is not a duration the app can describe, so
  /// Save refuses instead of writing a row that renders as a fake length.
  bool get _validRange => !_endDt.isBefore(_startDt) && _endDt != _startDt;

  String? get _descriptionText {
    final text = _descriptionController.text.trim();
    return text.isEmpty ? null : text;
  }

  String? get _locationText {
    final text = _locationController.text.trim();
    return text.isEmpty ? null : text;
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context)!;
    if (_saving) return;
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.enterTitle)));
      return;
    }
    if (!_validRange) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.invalidTimeRange)));
      return;
    }
    final start = _startDt;
    final end = _endDt;

    setState(() => _saving = true);
    try {
      final calendars = await ref.read(calendarsProvider.future);
      if (!mounted) return;
      if (calendars.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.noCalendar)));
        return;
      }
      // The event keeps its calendar unless the user picked another one; a
      // calendar that has since been deleted has to be replaced explicitly.
      final chosen = _calendarId;
      if (chosen != null && !calendars.any((c) => c.id == chosen)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.calendarUnavailable)));
        return;
      }
      final calendarId = chosen ?? calendars.first.id;

      // Bytes first, and outside the transaction: a source file that has gone
      // missing has to fail the save before anything is written, not halfway
      // through it.
      final staged = <({DraftAttachment draft, Uint8List bytes})>[];
      for (final item in _attachments.where((a) => a.id == null)) {
        staged.add((
          draft: item,
          bytes: await ref.read(stageAttachmentProvider)(
            bytes: item.bytes,
            sourcePath: item.sourcePath,
            fileName: item.fileName,
          ),
        ));
      }

      final db = ref.read(databaseProvider);
      final uploaded = <({int id, List<int>? bytes})>[];
      final residue = <AttachmentResidue?>[];
      final stagedFiles = <String?>[];

      // One scope for the whole draft: Save commits the draft as a whole, so
      // a failure anywhere leaves the database exactly as it was instead of
      // a renamed event with half its tags.
      await RecordScope.run(db, (tx) async {
        // Editing or creating is decided only by whether the form opened on an
        // event; nothing about the event's shape can turn one into the other.
        final int eventId;
        if (_isEditing) {
          eventId = widget.event!.drifId;
          final updated = widget.event!.copyWithData(
            calendarId: calendarId,
            seriesStart: start,
            seriesEnd: end,
            title: _titleController.text.trim(),
            description: _descriptionText,
            location: _locationText,
            rrule: _rrule,
            isAllDay: _isAllDay,
          );
          await ref.read(updateEventProvider)(
            eventId,
            updated.toUpdateCompanion(),
          );
        } else {
          eventId = await ref.read(createEventProvider)(
            calendarId: calendarId,
            summary: _titleController.text.trim(),
            startDt: start,
            endDt: end,
            isAllDay: _isAllDay,
            description: _descriptionText,
            location: _locationText,
            rrule: _rrule,
          );
        }

        try {
          await _commitDrafts(tx, eventId, staged, uploaded, residue, stagedFiles);
        } catch (error) {
          // The row is gone with the rollback, but the file this transaction
          // already wrote is not — and SQLite may hand the same id to a later
          // insert, which would adopt the orphan as its own.
          await ref.read(discardStagedFilesProvider)(stagedFiles);
          rethrow;
        }
      });

      // Past the commit: the network and the filesystem have no business
      // holding a transaction open, and neither can roll one back.
      await ref.read(uploadAttachmentsProvider)(uploaded);
      for (final item in residue) {
        await ref.read(discardAttachmentResidueProvider)(item);
      }
      if (!mounted) return;
      context.pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.actionFailedRetry)));
        debugPrint('event_form: save error: $error');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Writes everything the form staged, inside the caller's transaction.
  ///
  /// Nothing is swallowed here: Save commits the whole draft, so a failed tag
  /// write has to take the title down with it.
  Future<void> _commitDrafts(
    RecordScope tx,
    int eventId,
    List<({DraftAttachment draft, Uint8List bytes})> staged,
    List<({int id, List<int>? bytes})> uploaded,
    List<AttachmentResidue?> residue,
    List<String?> stagedFiles,
  ) async {
    final initial = _initial;

    final initialTags = initial?.tagIds ?? const <int>{};
    for (final tagId in _tagIds.difference(initialTags)) {
      await ref.read(addTagToEventProvider)(eventId: eventId, tagId: tagId);
    }
    for (final tagId in initialTags.difference(_tagIds)) {
      await ref.read(removeTagFromEventProvider)(eventId: eventId, tagId: tagId);
    }

    final initialReminders = initial?.reminders ?? const <DraftReminder>[];
    for (final item in initialReminders.where((item) => item.id != null)) {
      if (_reminders.any((other) => other.id == item.id)) continue;
      await ref.read(deleteReminderProvider)(item.id!);
    }
    for (final item in _reminders.where((item) => item.id == null)) {
      await ref.read(createReminderProvider)(
        parentType: 'event',
        parentId: eventId,
        triggerTime: item.triggerTime,
      );
    }

    final initialAttachments =
        initial?.attachments ?? const <DraftAttachment>[];
    for (final item in initialAttachments.where((item) => item.id != null)) {
      if (_attachments.any((other) => other.id == item.id)) continue;
      residue.add(await ref.read(deleteAttachmentRowProvider)(tx, item.id!));
    }
    for (final item in staged) {
      final stage = await ref.read(insertAttachmentRowProvider)(
        tx,
        parentType: 'event',
        parentId: eventId,
        fileName: item.draft.fileName,
        mimeType: item.draft.mimeType,
        data: item.bytes,
        onFileWritten: stagedFiles.add,
      );
      uploaded.add((id: stage.id, bytes: item.bytes));
    }
  }

  Future<void> _confirmDiscard() async {
    final l = AppLocalizations.of(context)!;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.discardChanges),
        content: Text(l.discardChangesBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.keepEditing),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l.discard),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.moveToTrash),
        content: Text(
          _isRecurring
              ? l.deleteRecurringEventConfirm(widget.event!.title)
              : l.deleteEventConfirm(widget.event!.title),
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
            child: Text(l.moveToTrash),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final id = widget.event!.drifId;
    final restore = ref.read(restoreEventProvider);
    await ref.read(deleteEventProvider)(id);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.deleted),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(label: l.undo, onPressed: () => restore(id)),
      ),
    );
  }

  Future<void> _pickBoundary(bool isStart) async {
    final current = isStart ? _start : _end;
    // An all-day event has no clock time, so asking for one would be a
    // question the user has already answered.
    final picked = _isAllDay
        ? await pickDeadline(context, initial: current)
        : await pickDateTime(context, initial: current);
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        // Keep the length: moving the start of a 1h meeting should not turn it
        // into a zero-length one the user then has to fix.
        final length = _end.difference(_start);
        _start = picked;
        _end = picked.add(
          length.isNegative || length == Duration.zero
              ? const Duration(hours: 1)
              : length,
        );
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _aiParse() async {
    final l = AppLocalizations.of(context)!;
    final text = _titleController.text.trim();
    if (text.isEmpty) return;
    final config = ref.read(aiConfigProvider).value;
    if (config == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.aiNotConfiguredHint)));
      return;
    }
    setState(() => _aiLoading = true);
    try {
      final result = await parseNaturalLanguage(
        config: config,
        input: text,
        type: 'event',
      );
      if (!mounted) return;
      setState(() {
        if (result['summary'] != null) {
          _titleController.text = result['summary'] as String;
        }
        if (result['start'] != null) {
          _start = DateTime.parse(result['start'] as String);
        }
        if (result['end'] != null) {
          _end = DateTime.parse(result['end'] as String);
        }
        if (result['description'] != null) {
          _descriptionController.text = result['description'] as String;
        }
        if (result['location'] != null) {
          _locationController.text = result['location'] as String;
        }
        if (result['is_all_day'] == true) {
          _isAllDay = true;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.aiError)));
      }
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  Widget _buildCalendarRow(AppLocalizations l) {
    final calendarsAsync = ref.watch(calendarsProvider);
    return calendarsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (calendars) {
        if (calendars.isEmpty) {
          return Row(
            children: [
              Expanded(
                child: Text(
                  l.noCalendar,
                  style: AppTypography.caption.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => ref.invalidate(calendarsProvider),
                child: Text(l.retry),
              ),
            ],
          );
        }
        final selected = _calendarId ?? calendars.first.id;
        final current = calendars.where((c) => c.id == selected).firstOrNull;
        // A dangling calendar (deleted on another device) must be resolved by
        // the user. Falling back to `calendars.first` would silently move the
        // event to a calendar nobody chose.
        final needsChoice = current == null;
        return ScheduleRow(
          label: l.calendar,
          value: current?.name ?? l.calendarUnavailable,
          trailing: const Icon(CupertinoIcons.chevron_down, size: 12),
          onTap: calendars.length == 1 && !needsChoice
              ? null
              : () async {
                  final picked = await showModalBottomSheet<int>(
                    context: context,
                    builder: (ctx) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final calendar in calendars)
                            ListTile(
                              leading: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: ColorUtils.parseHex(calendar.color),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              title: Text(calendar.name),
                              trailing: calendar.id == selected
                                  ? const Icon(
                                      CupertinoIcons.checkmark,
                                      size: 16,
                                    )
                                  : null,
                              onTap: () => Navigator.of(ctx).pop(calendar.id),
                            ),
                        ],
                      ),
                    ),
                  );
                  if (picked != null) setState(() => _calendarId = picked);
                },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final desktop = isWorkspaceLayout(context);
    // Escape belongs to the form: it goes through the same PopScope path as
    // the back button, so unsaved work is never dropped without asking.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (!_isDirty) {
            Navigator.of(context).maybePop();
          } else {
            _confirmDiscard();
          }
        },
      },
      child: PopScope(
        canPop: !_isDirty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _confirmDiscard();
        },
        child: WorkspacePage(
          title: _isEditing ? l.editEvent : l.newEvent,
          maxContentWidth: desktop ? 720 : null,
          actions: [
            if (_isEditing)
              IconButton(
                icon: const Icon(CupertinoIcons.trash, size: 18),
                onPressed: _saving ? null : _delete,
                tooltip: l.moveToTrash,
              ),
            IconButton(
              icon: _aiLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(CupertinoIcons.sparkles, size: 18),
              onPressed: _aiLoading ? null : _aiParse,
              tooltip: l.aiParse,
            ),
            const SizedBox(width: AppSpacing.sm),
            PageSaveButton(
              label: l.save,
              saving: _saving,
              // A page cannot offer a Save that only fails afterwards: an end at
              // or before the start disables it until the range makes sense.
              onPressed: _validRange ? _save : null,
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
              TextField(
                controller: _titleController,
                autofocus: !_isEditing,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                style: AppTypography.headline,
                decoration: InputDecoration(
                  hintText: l.title,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintStyle: AppTypography.headline.copyWith(
                    color: context.semantic.textTertiary,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const RowDivider(),
              const SizedBox(height: AppSpacing.sm),
              if (_isRecurring) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    children: [
                      Icon(
                        CupertinoIcons.repeat,
                        size: 13,
                        color: context.semantic.textSecondary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          l.recurringSeriesNoticeShort,
                          style: AppTypography.caption.copyWith(
                            color: context.semantic.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // One row, one switch: the value text is not a second button
              // competing with the switch for the same answer.
              ScheduleRow(
                label: l.allDay,
                value: _isAllDay ? l.durationAllDay : l.eventLabel,
                trailing: Switch(
                  value: _isAllDay,
                  onChanged: (value) => setState(() => _isAllDay = value),
                ),
              ),
              ScheduleRow(
                label: l.startTime,
                value: _isAllDay
                    ? formatDeadline(context, _start)
                    : formatMoment(context, _start),
                onTap: () => _pickBoundary(true),
              ),
              ScheduleRow(
                label: l.endTime,
                value: _isAllDay
                    ? formatDeadline(context, _end)
                    : formatMoment(context, _end),
                onTap: () => _pickBoundary(false),
              ),
              ScheduleRow(
                label: l.duration,
                // The length is a consequence of the two times, never a number
                // the app invents when they disagree.
                value: _validRange
                    ? (_isAllDay
                          ? l.durationAllDay
                          : formatExecutionLength(
                              context,
                              _endDt.difference(_startDt),
                            ))
                    : l.invalidTimeRange,
                placeholder: !_validRange,
              ),
              RepeatRow(
                rrule: _rrule,
                anchorDate: _start,
                anchorLabel: null,
                onChanged: (value) => setState(() => _rrule = value),
              ),
              const SizedBox(height: AppSpacing.lg),
              const RowDivider(),
              const SizedBox(height: AppSpacing.md),
              _buildCalendarRow(l),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _locationController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: l.location,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintStyle: AppTypography.body.copyWith(
                    color: context.semantic.textTertiary,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _descriptionController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: l.description,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintStyle: AppTypography.body.copyWith(
                    color: context.semantic.textTertiary,
                  ),
                ),
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: AppSpacing.lg),
              TagChips(
                selectedIds: _tagIds,
                onSelectedIdsChanged: (value) =>
                    setState(() => _tagIds = value),
              ),
              const SizedBox(height: AppSpacing.lg),
              RemindersSection(
                parentType: 'event',
                parentId: widget.event?.drifId,
                anchorTime: _start,
                draft: _reminders,
                onDraftChanged: (value) => setState(() => _reminders = value),
              ),
              const SizedBox(height: AppSpacing.lg),
              AttachmentList(
                parentType: 'event',
                parentId: widget.event?.drifId,
                draft: _attachments,
                onDraftChanged: (value) => setState(() => _attachments = value),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The form's contents, for the dirty check. Equality here is what decides
/// whether Back has to ask before throwing the edits away.
class _EventSnapshot {
  const _EventSnapshot({
    required this.title,
    required this.description,
    required this.location,
    required this.calendarId,
    required this.start,
    required this.end,
    required this.isAllDay,
    required this.rrule,
    required this.tagIds,
    required this.reminders,
    required this.attachments,
  });

  final String title;
  final String description;
  final String location;
  final int? calendarId;
  final DateTime start;
  final DateTime end;
  final bool isAllDay;
  final String? rrule;
  final Set<int> tagIds;
  final List<DraftReminder> reminders;
  final List<DraftAttachment> attachments;

  @override
  bool operator ==(Object other) =>
      other is _EventSnapshot &&
      other.title == title &&
      other.description == description &&
      other.location == location &&
      other.calendarId == calendarId &&
      other.start == start &&
      other.end == end &&
      other.isAllDay == isAllDay &&
      other.rrule == rrule &&
      _sameSet(other.tagIds, tagIds) &&
      _sameList(other.reminders, reminders) &&
      _sameList(other.attachments, attachments);

  @override
  int get hashCode => Object.hash(
    title,
    description,
    location,
    calendarId,
    start,
    end,
    isAllDay,
    rrule,
    Object.hashAll(tagIds),
    Object.hashAll(reminders),
    Object.hashAll(attachments),
  );
}

bool _sameSet<T>(Set<T> a, Set<T> b) =>
    a.length == b.length && a.containsAll(b);

bool _sameList<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
