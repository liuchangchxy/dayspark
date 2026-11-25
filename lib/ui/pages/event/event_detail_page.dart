import 'package:drift/drift.dart' hide Column;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/theme/spec_tokens.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/attachments_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/services/attachment_service.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/design/spec_toast.dart';
import 'package:dayspark/ui/shell/workspace_page.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/attachment_list.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_picker.dart';
import 'package:dayspark/ui/widgets/reminder/reminders_section.dart';
import 'package:dayspark/ui/widgets/schedule/repeat_editor.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_pickers.dart';
import 'package:dayspark/ui/widgets/undo_bar.dart';

/// An event that is editable where it is read — the same contract as
/// [TodoDetailPane], so the two object types never teach different gestures.
/// Edits are a draft: only the footer's save writes them, and cancel discards
/// them.
class EventDetailPage extends StatelessWidget {
  const EventDetailPage({super.key, required this.event, this.clock});

  final CalendaEventAdapter event;

  /// The instant the pane reads its status and progress from. Tests pin it so
  /// a capture does not drift with the wall clock; live screens use the clock.
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final desktop = isWorkspaceLayout(context);
    return WorkspacePage(
      title: l.eventLabel,
      maxContentWidth: desktop ? 720 : null,
      child: EventDetailPane(event: event, clock: clock),
    );
  }
}

class EventDetailPane extends ConsumerStatefulWidget {
  const EventDetailPane({
    super.key,
    required this.event,
    this.embedded = false,
    this.inlineSummary = false,
    this.onClose,
    this.onDeleted,
    this.clock,
  });

  final CalendaEventAdapter event;
  final bool embedded;
  final bool inlineSummary;
  final VoidCallback? onClose;
  final VoidCallback? onDeleted;
  final DateTime Function()? clock;

  @override
  ConsumerState<EventDetailPane> createState() => _EventDetailPaneState();
}

class _EventDetailPaneState extends ConsumerState<EventDetailPane> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _location = TextEditingController();
  final _titleFocus = FocusNode();
  final _descriptionFocus = FocusNode();
  final _locationFocus = FocusNode();
  late _EventDraft _snapshot;
  late _EventDraft _draft;
  bool _dirty = false;
  bool _saving = false;
  bool _titleError = false;
  bool _timeError = false;
  bool _saveFailed = false;
  bool _deleting = false;
  bool _deletedNotified = false;
  bool _editing = false;

  /// Reminders and attachments are part of the same draft as the event fields:
  /// nothing reaches the database until Save, and Cancel restores the rows the
  /// pane opened with. [DraftReminder.triggerTime] is what the popup stores; the
  /// saved lookup replaces id-less rows with their new ids so a later save
  /// cannot add them twice.
  List<DraftReminder> _reminders = const [];
  List<DraftAttachment> _attachments = const [];
  List<DraftReminder> _snapshotReminders = const [];
  List<DraftAttachment> _snapshotAttachments = const [];
  bool _remindersTouched = false;
  bool _attachmentsTouched = false;
  bool _associationsLoaded = false;
  Future<void>? _associationLoad;

  @override
  void initState() {
    super.initState();
    _snapshot = _EventDraft.fromAdapter(widget.event);
    _draft = _snapshot;
    _title.text = _draft.title;
    _description.text = _draft.description;
    _location.text = _draft.location;
    _editing = !(widget.inlineSummary || widget.embedded);
    if (_editing) _loadAssociations();
  }

  @override
  void dispose() {
    _titleFocus.dispose();
    _descriptionFocus.dispose();
    _locationFocus.dispose();
    _title.dispose();
    _description.dispose();
    _location.dispose();
    super.dispose();
  }

  void _syncFromLive(CalendaEventAdapter live) {
    if (_dirty || _saving || _deleting) return;
    final next = _EventDraft.fromAdapter(live);
    if (_sameEventDraft(next, _draft)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _dirty || _saving) return;
      setState(() {
        _snapshot = next;
        _draft = next;
      });
      if (!_titleFocus.hasFocus && _title.text != next.title) {
        _title.text = next.title;
      }
      if (!_descriptionFocus.hasFocus &&
          _description.text != next.description) {
        _description.text = next.description;
      }
      if (!_locationFocus.hasFocus && _location.text != next.location) {
        _location.text = next.location;
      }
    });
  }

  /// Reads the stored reminders and attachments once, as the baseline the
  /// draft is diffed against. Save awaits this future, so a tap that beats the
  /// read cannot commit an empty draft over rows it never saw.
  Future<void> _loadAssociations() {
    final future = _readAssociations();
    _associationLoad = future;
    return future;
  }

  /// Waits for the baseline, retrying once if the first read failed. A transient
  /// read error must not turn Save into a permanently failing button.
  Future<bool> _ensureAssociationsLoaded() async {
    if (_associationsLoaded) return true;
    await _associationLoad;
    if (_associationsLoaded) return true;
    await _loadAssociations();
    return _associationsLoaded;
  }

  Future<void> _readAssociations() async {
    final id = widget.event.drifId;
    try {
      final reminders = await ref.read(eventRemindersProvider(id).future);
      final attachments = await ref.read(eventAttachmentsProvider(id).future);
      if (!mounted) return;
      final reminderRows = [
        for (final row in reminders)
          DraftReminder(id: row.id, triggerTime: row.triggerTime),
      ];
      final attachmentRows = [
        for (final row in attachments) DraftAttachment.fromRow(row),
      ];
      setState(() {
        _snapshotReminders = reminderRows;
        _snapshotAttachments = attachmentRows;
        // A row the user already staged before the read landed must survive it;
        // only the baseline changes underneath.
        if (!_remindersTouched) _reminders = [...reminderRows];
        if (!_attachmentsTouched) _attachments = [...attachmentRows];
        _associationsLoaded = true;
      });
    } catch (error) {
      debugPrint('event_detail: association load failed: $error');
      if (!mounted) return;
      setState(() => _associationsLoaded = false);
    }
  }

  void _setReminders(List<DraftReminder> next) {
    setState(() {
      _reminders = next;
      _remindersTouched = true;
      _dirty = true;
      _saveFailed = false;
    });
  }

  void _setAttachments(List<DraftAttachment> next) {
    setState(() {
      _attachments = next;
      _attachmentsTouched = true;
      _dirty = true;
      _saveFailed = false;
    });
  }

  void _setDraft(_EventDraft next) {
    setState(() {
      _draft = next;
      _dirty = true;
      _saveFailed = false;
      if (_timeError && next.end.isAfter(next.start)) {
        _timeError = false;
      }
    });
  }

  _EventDraft _withDraft({
    String? title,
    String? description,
    String? location,
    DateTime? start,
    DateTime? end,
    bool? allDay,
    int? calendarId,
    Object? rrule = _unsetEventDraft,
  }) {
    return _EventDraft(
      title: title ?? _draft.title,
      description: description ?? _draft.description,
      location: location ?? _draft.location,
      start: start ?? _draft.start,
      end: end ?? _draft.end,
      allDay: allDay ?? _draft.allDay,
      calendarId: calendarId ?? _draft.calendarId,
      rrule: identical(rrule, _unsetEventDraft)
          ? _draft.rrule
          : rrule as String?,
    );
  }

  Future<bool> _confirmDiscardIfNeeded() async {
    if (!_dirty) return true;
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      animationStyle: AnimationStyle.noAnimation,
      context: context,
      builder: (ctx) => DsDialog(
        title: l.discardChanges,
        actions: [
          const Spacer(),
          DsButton(
            label: l.cancel,
            tone: DsButtonTone.ghost,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          const SizedBox(width: AppSpacing.s2),
          DsButton(
            label: l.discard,
            tone: DsButtonTone.danger,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
        child: Text(
          l.discardChangesBody,
          style: AppTypography.body.copyWith(color: context.ds.ink2),
        ),
      ),
    );
    return confirmed ?? false;
  }

  /// Saving a recurring occurrence writes the series anchor and therefore
  /// every instance. Nothing here offers an instance-level override: the
  /// dialog exists to say that out loud before the write, and Cancel leaves
  /// the database untouched.
  ///
  /// "Recurring" is decided by what the pane opened on, not by the current
  /// rule: clearing the repeat control is itself a series-wide edit and still
  /// deserves the confirmation.
  Future<bool> _confirmSeriesSave() async {
    if (!widget.event.isRecurringOccurrence && _snapshot.rrule == null) {
      return true;
    }
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      animationStyle: AnimationStyle.noAnimation,
      context: context,
      builder: (ctx) => DsDialog(
        title: l.saveSeriesTitle,
        actions: [
          const Spacer(),
          DsButton(
            label: l.cancel,
            tone: DsButtonTone.ghost,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          const SizedBox(width: AppSpacing.s2),
          DsButton(
            label: l.saveSeriesConfirm,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
        child: Text(
          l.saveSeriesBody,
          style: AppTypography.body.copyWith(color: context.ds.ink2),
        ),
      ),
    );
    return confirmed ?? false;
  }

  void _beginEdit(CalendaEventAdapter live) {
    setState(() {
      _snapshot = _EventDraft.fromAdapter(live);
      _draft = _snapshot;
      _title.text = _draft.title;
      _description.text = _draft.description;
      _location.text = _draft.location;
      _dirty = false;
      _editing = true;
      _remindersTouched = false;
      _attachmentsTouched = false;
      _associationsLoaded = false;
    });
    _loadAssociations();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final liveAsync = ref.watch(liveEventProvider(widget.event.drifId));
    final live = liveAsync.valueOrNull;
    if (live == null) {
      if (liveAsync.hasValue) {
        _notifyDeleted();
        return Center(
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
        );
      }
      if (liveAsync.hasError) {
        return _loadFailure(
          context,
          l,
          () => ref.invalidate(liveEventProvider(widget.event.drifId)),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    _syncFromLive(live);

    final start = _draft.start;
    final end = _draft.end;
    final length = end.difference(start);
    final validRange = !length.isNegative && length > Duration.zero;
    final calendars = ref.watch(calendarsProvider).valueOrNull;
    final currentCalendar = calendars
        ?.where((c) => c.id == _draft.calendarId)
        .firstOrNull;

    final now = widget.clock?.call() ?? DateTime.now();
    final mobile = !isWorkspaceLayout(context);
    final side = widget.embedded ? 18.0 : (mobile ? 20.0 : 24.0);
    final rowHeight = mobile ? 56.0 : 58.0;
    final inProgress = !now.isBefore(start) && now.isBefore(end);
    final ended = !now.isBefore(end);
    final remaining = end.difference(now);
    final status = inProgress
        ? (remaining.inMinutes >= 1
              ? '${l.inProgress} · ${l.remainingMinutes(remaining.inMinutes)}'
              : l.inProgress)
        : ended
        ? l.completedLabel
        : l.upcoming;
    final statusColor = inProgress ? context.ds.danger : context.ds.ink3;
    final fraction = validRange
        ? (now.difference(start).inMilliseconds / length.inMilliseconds)
              .clamp(0.0, 1.0)
              .toDouble()
        : 0.0;

    final isSummary = (widget.inlineSummary || widget.embedded) && !_editing;
    final summaryTags = isSummary
        ? ref.watch(eventTagsProvider(live.drifId)).valueOrNull
        : null;
    final summaryReminders = isSummary
        ? ref.watch(eventRemindersProvider(live.drifId)).valueOrNull
        : null;

    final pageContent = isSummary
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _drawerHead(context, l),
              Expanded(
                child: _summaryBody(
                  context,
                  l,
                  live,
                  status: status,
                  statusColor: statusColor,
                  fraction: fraction,
                  start: start,
                  end: end,
                  validRange: validRange,
                  currentCalendar: currentCalendar,
                  calendarColor: currentCalendar == null
                      ? context.ds.ink3
                      : ColorUtils.parseHex(currentCalendar.color),
                  tags: summaryTags ?? const <Tag>[],
                  reminders: summaryReminders ?? const <Reminder>[],
                ),
              ),
              _summaryFooter(context, l, live),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.embedded) _drawerHead(context, l),
              Expanded(
                child: ListView(
                  key: PageStorageKey<String>(
                    'event-detail-${widget.event.drifId}',
                  ),
                  padding: EdgeInsets.fromLTRB(
                    side,
                    widget.embedded ? 18 : 14,
                    side,
                    24,
                  ),
                  children: [
                    if (_saveFailed) _saveErrorBanner(context, l),
                    _header(context, l, live, currentCalendar),
                    _status(context, status, statusColor, fraction, start, end),
                    _fields(
                      context,
                      l,
                      calendars,
                      currentCalendar,
                      validRange,
                      rowHeight,
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: context.ds.lineSoft),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          RepeatRow(
                            rrule: _draft.rrule,
                            anchorDate: _draft.start,
                            onChanged: (value) =>
                                _setDraft(_withDraft(rrule: value)),
                          ),
                          if (_draft.rrule != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(0, 2, 0, 10),
                              child: Text(
                                l.recurringSeriesNoticeShort,
                                style: AppTypography.small.copyWith(
                                  color: context.ds.ink3,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    RemindersSection(
                      parentType: 'event',
                      parentId: live.drifId,
                      anchorTime: _draft.start,
                      draft: _reminders,
                      onDraftChanged: _setReminders,
                    ),
                    const SizedBox(height: 18),
                    _notes(context, l),
                    _tags(context, live),
                    const SizedBox(height: 8),
                    AttachmentList(
                      parentType: 'event',
                      parentId: live.drifId,
                      draft: _attachments,
                      onDraftChanged: _setAttachments,
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              _footer(context, l, live, mobile, side),
            ],
          );

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _confirmDiscardIfNeeded();
        if (shouldPop && mounted) {
          if (widget.embedded) {
            widget.onClose?.call();
          } else {
            Navigator.of(this.context).pop();
          }
        }
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () async {
            if (_dirty) {
              final shouldPop = await _confirmDiscardIfNeeded();
              if (shouldPop && mounted) {
                if (widget.embedded) {
                  widget.onClose?.call();
                } else {
                  Navigator.of(this.context).maybePop();
                }
              }
            } else {
              if (widget.embedded) {
                widget.onClose?.call();
              } else {
                Navigator.of(this.context).maybePop();
              }
            }
          },
        },
        child: Focus(autofocus: true, child: pageContent),
      ),
    );
  }

  Widget _summaryBody(
    BuildContext context,
    AppLocalizations l,
    CalendaEventAdapter live, {
    required String status,
    required Color statusColor,
    required double fraction,
    required DateTime start,
    required DateTime end,
    required bool validRange,
    required Calendar? currentCalendar,
    required Color calendarColor,
    required List<Tag> tags,
    required List<Reminder> reminders,
  }) {
    final ds = context.ds;
    final locale = Localizations.localeOf(context).toString();
    final date =
        '${DateFormat.MMMd(locale).format(start)} ${DateFormat.E(locale).format(start)}';
    final eyebrow = [currentCalendar?.name ?? l.eventLabel, date].join(' · ');
    final repeatLabel = _draft.rrule == null
        ? '—'
        : describeRepeat(context, _draft.rrule);
    final reminderLabel = reminders.isEmpty
        ? l.noReminders
        : reminders
              .map((item) => formatDeadline(context, item.triggerTime))
              .join(' · ');
    final tagLabel = tags.isEmpty
        ? l.noTags
        : tags.map((tag) => tag.name).join(' · ');
    final note = _draft.description.trim();
    final side = widget.embedded ? 18.0 : 24.0;
    const rowHeight = 58.0;

    return ListView(
      key: PageStorageKey<String>('event-summary-${live.drifId}'),
      padding: EdgeInsets.fromLTRB(side, 18, side, 24),
      children: [
        Row(
          children: [
            DsDot(color: calendarColor),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                eyebrow,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, height: 16 / 11, color: ds.ink3),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          live.title,
          key: const ValueKey('event-detail-summary-title'),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            height: 26 / 20,
            letterSpacing: 0.2,
            color: ds.ink,
          ),
        ),
        _status(context, status, statusColor, fraction, start, end),
        const SizedBox(height: 10),
        _PaneFieldRow(
          key: const ValueKey('event-summary-start'),
          label: l.startTime,
          height: rowHeight,
          value: _draft.allDay
              ? formatDeadline(context, _draft.start)
              : formatMoment(context, _draft.start),
          leading: Icon(CupertinoIcons.clock, size: 12, color: ds.ink3),
        ),
        _PaneFieldRow(
          key: const ValueKey('event-summary-end'),
          label: l.endTime,
          height: rowHeight,
          value: _draft.allDay
              ? formatDeadline(context, _draft.end)
              : formatMoment(context, _draft.end),
          leading: Icon(CupertinoIcons.clock, size: 12, color: ds.ink3),
        ),
        _PaneFieldRow(
          key: const ValueKey('event-summary-duration'),
          label: l.duration,
          height: rowHeight,
          value: validRange
              ? (_draft.allDay
                    ? l.durationAllDay
                    : formatExecutionLength(
                        context,
                        _draft.end.difference(_draft.start),
                      ))
              : l.invalidTimeRange,
        ),
        _PaneFieldRow(
          key: const ValueKey('event-summary-calendar'),
          label: l.calendarField,
          height: rowHeight,
          value: currentCalendar?.name ?? l.calendarUnavailable,
          leading: DsDot(color: calendarColor, size: 7),
        ),
        if (_draft.location.isNotEmpty)
          _PaneFieldRow(
            key: const ValueKey('event-summary-location'),
            label: l.location,
            height: rowHeight,
            value: _draft.location,
            leading: Icon(CupertinoIcons.location, size: 12, color: ds.ink3),
          ),
        _PaneFieldRow(
          key: const ValueKey('event-summary-repeat'),
          label: l.repeatField,
          height: rowHeight,
          value: repeatLabel,
          leading: Icon(CupertinoIcons.repeat, size: 12, color: ds.ink3),
        ),
        _PaneFieldRow(
          key: const ValueKey('event-summary-reminders'),
          label: l.reminders,
          height: rowHeight,
          value: reminderLabel,
          leading: Icon(CupertinoIcons.bell, size: 12, color: ds.ink3),
        ),
        _PaneFieldRow(
          key: const ValueKey('event-summary-tags'),
          label: l.tags,
          height: rowHeight,
          value: tagLabel,
        ),
        DsSectionLabel(
          l.notes,
          padding: const EdgeInsets.only(top: 16, bottom: 6),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: ds.bg,
            border: Border.all(color: ds.lineSoft),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            note.isEmpty ? '—' : note,
            key: const ValueKey('event-summary-notes'),
            style: TextStyle(fontSize: 13, height: 22 / 13, color: ds.ink2),
          ),
        ),
        const SizedBox(height: 12),
        AttachmentList(
          parentType: 'event',
          parentId: live.drifId,
          enabled: false,
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _summaryFooter(
    BuildContext context,
    AppLocalizations l,
    CalendaEventAdapter live,
  ) {
    final ds = context.ds;
    return Container(
      decoration: BoxDecoration(
        color: ds.surface,
        border: Border(top: BorderSide(color: ds.line)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 16),
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              Expanded(
                child: _PaneButton(
                  key: const ValueKey('event-detail-edit'),
                  label: l.edit,
                  height: 48,
                  primary: true,
                  onPressed: () => _beginEdit(live),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PaneButton(
                  key: const ValueKey('event-detail-delete-summary'),
                  label: l.delete,
                  height: 48,
                  danger: true,
                  onPressed: () => _delete(live),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _drawerHead(BuildContext context, AppLocalizations l) {
    final ds = context.ds;
    return Container(
      height: 50,
      padding: const EdgeInsets.only(left: 18, right: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: ds.line)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            widget.inlineSummary && _editing
                ? '${l.eventLabel} · ${l.edit}'
                : l.eventLabel,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.09 * 9.5,
              color: ds.ink3,
            ),
          ),
          _PaneCloseButton(onPressed: widget.onClose, tooltip: l.close),
        ],
      ),
    );
  }

  Widget _saveErrorBanner(BuildContext context, AppLocalizations l) {
    final ds = context.ds;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: ds.dangerSoft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l.saveFailedNotWritten,
              style: TextStyle(
                fontSize: 12,
                height: 18 / 12,
                fontWeight: FontWeight.w600,
                color: ds.danger,
              ),
            ),
          ),
          TextButton(
            key: const ValueKey('event-detail-retry-save'),
            onPressed: _saving ? null : _save,
            child: Text(l.retrySave),
          ),
        ],
      ),
    );
  }

  Widget _header(
    BuildContext context,
    AppLocalizations l,
    CalendaEventAdapter live,
    Calendar? calendar,
  ) {
    final ds = context.ds;
    final locale = Localizations.localeOf(context).toString();
    final date =
        '${DateFormat.MMMd(locale).format(_draft.start)} '
        '${DateFormat.E(locale).format(_draft.start)}';
    final eyebrow = calendar == null ? date : '${calendar.name} · $date';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  DsDot(color: live.color ?? ds.ink3),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      eyebrow,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.small.copyWith(color: ds.ink3),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              TextField(
                key: const ValueKey('event-detail-title'),
                controller: _title,
                focusNode: _titleFocus,
                style: AppTypography.headline.copyWith(color: ds.ink),
                strutStyle: StrutStyle.fromTextStyle(
                  AppTypography.headline,
                  forceStrutHeight: true,
                ),
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (value) {
                  if (!_dirty) setState(() => _dirty = true);
                  if (_titleError && value.trim().isNotEmpty) {
                    setState(() => _titleError = false);
                  }
                },
                decoration: InputDecoration(
                  hintText: l.title,
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintStyle: AppTypography.headline.copyWith(color: ds.ink3),
                  errorText: _titleError ? l.titleRequired : null,
                  errorStyle: TextStyle(
                    fontSize: 11,
                    height: 16 / 11,
                    color: ds.danger,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _status(
    BuildContext context,
    String status,
    Color statusColor,
    double fraction,
    DateTime start,
    DateTime end,
  ) {
    final ds = context.ds;
    final left = _draft.allDay
        ? formatDeadline(context, start)
        : DateFormatters.formatTime(start);
    final right = _draft.allDay
        ? formatDeadline(context, end)
        : DateFormatters.formatTime(end);
    final timeStyle = AppTypography.small.copyWith(
      color: ds.faint,
      fontFeatures: AppTypography.tabular,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 11),
          child: Row(
            children: [
              DsDot(color: statusColor),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.small.copyWith(
                    fontWeight: FontWeight.w500,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 5,
            child: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: ds.surface3)),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: fraction,
                  heightFactor: 1,
                  child: ColoredBox(color: ds.danger),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(left, style: timeStyle),
            Text(right, style: timeStyle),
          ],
        ),
      ],
    );
  }

  Widget _fields(
    BuildContext context,
    AppLocalizations l,
    List<Calendar>? calendars,
    Calendar? currentCalendar,
    bool validRange,
    double rowHeight,
  ) {
    final ds = context.ds;
    return Column(
      children: [
        const SizedBox(height: 16),
        Container(height: 1, color: ds.line),
        _PaneFieldRow(
          label: l.startTime,
          height: rowHeight,
          value: _draft.allDay
              ? formatDeadline(context, _draft.start)
              : formatMoment(context, _draft.start),
          onTap: () => _pickBoundary(isStart: true),
          showChevron: true,
        ),
        _PaneFieldRow(
          label: l.endTime,
          height: rowHeight,
          value: _draft.allDay
              ? formatDeadline(context, _draft.end)
              : formatMoment(context, _draft.end),
          onTap: () => _pickBoundary(isStart: false),
          showChevron: true,
        ),
        if (_timeError)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              l.invalidTimeRange,
              style: TextStyle(fontSize: 11, height: 16 / 11, color: ds.danger),
            ),
          ),
        _PaneFieldRow(
          label: l.duration,
          height: rowHeight,
          value: validRange
              ? (_draft.allDay
                    ? l.durationAllDay
                    : formatExecutionLength(
                        context,
                        _draft.end.difference(_draft.start),
                      ))
              : l.invalidTimeRange,
        ),
        _PaneFieldRow(
          label: l.allDay,
          height: rowHeight,
          valueChild: Align(
            alignment: Alignment.centerLeft,
            child: Switch(value: _draft.allDay, onChanged: _toggleAllDay),
          ),
        ),
        _PaneFieldRow(
          key: const ValueKey('calendar-picker'),
          label: l.calendarField,
          height: rowHeight,
          leading: currentCalendar == null
              ? null
              : DsDot(
                  color: ColorUtils.parseHex(currentCalendar.color),
                  size: 7,
                ),
          value: calendars == null
              ? ''
              : calendars.isEmpty
              ? l.noCalendar
              : (currentCalendar?.name ?? l.calendarUnavailable),
          onTap: _pickCalendar,
          showChevron: true,
        ),
        _PaneFieldRow(
          label: l.location,
          height: rowHeight,
          showChevron: false,
          valueChild: TextField(
            controller: _location,
            focusNode: _locationFocus,
            style: AppTypography.caption.copyWith(color: ds.ink),
            cursorColor: ds.primary,
            decoration: InputDecoration(
              hintText: l.locationHint,
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintStyle: AppTypography.caption.copyWith(color: ds.ink3),
            ),
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) {
              if (!_dirty) setState(() => _dirty = true);
            },
          ),
        ),
      ],
    );
  }

  Widget _notes(BuildContext context, AppLocalizations l) {
    final ds = context.ds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.notes, style: AppTypography.overline.copyWith(color: ds.ink3)),
        const SizedBox(height: 7),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: ds.bg,
            border: Border.all(color: ds.lineSoft),
            borderRadius: BorderRadius.circular(6),
          ),
          child: TextField(
            controller: _description,
            focusNode: _descriptionFocus,
            style: AppTypography.caption.copyWith(
              color: ds.ink2,
              height: 22 / 13,
            ),
            strutStyle: StrutStyle.fromTextStyle(
              AppTypography.caption.copyWith(height: 22 / 13),
              forceStrutHeight: true,
            ),
            cursorColor: ds.primary,
            decoration: InputDecoration(
              hintText: l.notesHint,
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintStyle: AppTypography.caption.copyWith(
                color: ds.ink3,
                height: 22 / 13,
              ),
            ),
            maxLines: null,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) {
              if (!_dirty) setState(() => _dirty = true);
            },
          ),
        ),
      ],
    );
  }

  Widget _tags(BuildContext context, CalendaEventAdapter live) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final assigned =
        ref.watch(eventTagsProvider(live.drifId)).valueOrNull ?? const [];
    if (assigned.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(l.tags, style: AppTypography.overline.copyWith(color: ds.ink3)),
        const SizedBox(height: 7),
        Wrap(
          spacing: AppSpacing.s2,
          runSpacing: AppSpacing.s2,
          children: [
            for (final tag in assigned)
              DsChip(
                label: tag.name,
                solid: true,
                leading: DsDot(color: ColorUtils.parseHex(tag.color), size: 7),
              ),
          ],
        ),
      ],
    );
  }

  Widget _footer(
    BuildContext context,
    AppLocalizations l,
    CalendaEventAdapter live,
    bool mobile,
    double side,
  ) {
    final ds = context.ds;
    final height = mobile ? 48.0 : 36.0;
    final primaryLabel = _saveFailed ? l.retrySave : l.save;
    final save = _PaneButton(
      key: const ValueKey('event-detail-save'),
      label: primaryLabel,
      height: height,
      primary: true,
      onPressed: _saving ? null : _save,
    );
    final cancel = _PaneButton(
      key: const ValueKey('event-detail-cancel'),
      label: l.cancel,
      height: height,
      onPressed: _saving ? null : _cancel,
    );
    final remove = _PaneButton(
      key: const ValueKey('event-detail-delete'),
      label: l.moveToTrash,
      height: height,
      danger: true,
      onPressed: _deleting ? null : () => _delete(live),
    );
    return Container(
      decoration: BoxDecoration(
        color: widget.embedded ? ds.surface : ds.bg,
        border: Border(top: BorderSide(color: ds.line)),
      ),
      padding: EdgeInsets.fromLTRB(side, mobile ? 12 : 14, side, 0),
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.only(bottom: mobile ? 12 : 16),
        child: SizedBox(
          height: height < 48 ? 48 : height,
          child: Row(
            children: [
              Expanded(flex: 2, child: save),
              const SizedBox(width: 8),
              Expanded(child: cancel),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: remove),
            ],
          ),
        ),
      ),
    );
  }

  void _notifyDeleted() {
    if (_deletedNotified) return;
    _deletedNotified = true;
    final callback = widget.onDeleted;
    if (callback != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => callback());
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() {
        _titleError = true;
        _saveFailed = false;
      });
      _titleFocus.requestFocus();
      return;
    }
    if (!_draft.end.isAfter(_draft.start)) {
      setState(() {
        _timeError = true;
        _saveFailed = false;
      });
      return;
    }
    final description = _description.text.trim();
    final location = _location.text.trim();
    final allDayChanged = _draft.allDay != _snapshot.allDay;
    // The stored time only changes when the user changed a time control. An
    // all-day row whose DTSTART carries a clock time keeps it on a title-only
    // edit; the one exception is a row this pane just turned into all-day, and
    // the toggle has already normalised it to midnight.
    final timeChanged =
        !_sameEventTime(_draft, _snapshot) || (allDayChanged && _draft.allDay);
    // Saving a recurring occurrence is a series-wide write; say so first and
    // treat Cancel as no write at all.
    if (!await _confirmSeriesSave()) return;
    if (!mounted) return;
    setState(() {
      _saving = true;
      _saveFailed = false;
      _titleError = false;
      _timeError = false;
    });
    try {
      if (!await _ensureAssociationsLoaded()) {
        // The baseline still never arrived. Writing the event while the
        // reminder and attachment drafts have nothing to diff against would
        // silently keep (or duplicate) rows, so this is a failed save the user
        // can retry.
        if (!mounted) return;
        setState(() {
          _saveFailed = true;
          _saving = false;
        });
        return;
      }
      if (!mounted) return;

      // Bytes first, outside the transaction: a source file that has gone
      // missing has to fail the save before anything is written, not halfway.
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
      if (!mounted) return;

      final db = ref.read(databaseProvider);
      final uploaded = <({int id, List<int>? bytes})>[];
      final residue = <AttachmentResidue?>[];
      final stagedFiles = <String?>[];

      // One scope for the event row and its children: Save means "the draft as
      // a whole", so a failure anywhere has to leave the database as it was.
      final committed = await RecordScope.run(db, (tx) async {
        await ref.read(updateEventProvider)(
          widget.event.drifId,
          EventsCompanion(
            summary: Value(title),
            description: Value(description.isEmpty ? null : description),
            location: Value(location.isEmpty ? null : location),
            startDt: timeChanged ? Value(_draft.start) : const Value.absent(),
            endDt: timeChanged ? Value(_draft.end) : const Value.absent(),
            isAllDay: allDayChanged
                ? Value(_draft.allDay)
                : const Value.absent(),
            calendarId: Value(_draft.calendarId),
            rrule: Value(_draft.rrule),
            updatedAt: Value(DateTime.now()),
          ),
        );
        try {
          return await _commitDrafts(
            tx,
            staged: staged,
            uploaded: uploaded,
            residue: residue,
            stagedFiles: stagedFiles,
          );
        } catch (error) {
          // The event update rolled back, but a file this scope already wrote
          // did not — and SQLite may hand the same id to a later insert.
          await ref.read(discardStagedFilesProvider)(stagedFiles);
          rethrow;
        }
      });

      // Past the commit: the network and the filesystem cannot roll a scope
      // back, so they run after it.
      await ref.read(uploadAttachmentsProvider)(uploaded);
      for (final item in residue) {
        await ref.read(discardAttachmentResidueProvider)(item);
      }

      if (!mounted) return;
      setState(() {
        _snapshotReminders = committed.reminders;
        _reminders = [...committed.reminders];
        _snapshotAttachments = committed.attachments;
        _attachments = [...committed.attachments];
        _remindersTouched = false;
        _attachmentsTouched = false;
        _associationsLoaded = true;
      });
    } catch (error) {
      debugPrint('event_detail: save failed: $error');
      if (!mounted) return;
      setState(() {
        _saveFailed = true;
        _saving = false;
      });
      return;
    }
    if (!mounted) return;
    final saved = _EventDraft(
      title: title,
      description: description,
      location: location,
      start: timeChanged ? _draft.start : _snapshot.start,
      end: timeChanged ? _draft.end : _snapshot.end,
      allDay: _draft.allDay,
      calendarId: _draft.calendarId,
      rrule: _draft.rrule,
    );
    setState(() {
      _snapshot = saved;
      _draft = saved;
      _dirty = false;
      _saving = false;
      _title.text = title;
      if (widget.inlineSummary || widget.embedded) _editing = false;
    });
  }

  /// Writes the reminder and attachment drafts inside the caller's scope:
  /// rows that vanished are deleted, rows that appeared are created or
  /// inserted. Existing rows keep their id, so an edit that did not touch them
  /// stays untouched.
  Future<({List<DraftReminder> reminders, List<DraftAttachment> attachments})>
  _commitDrafts(
    RecordScope tx, {
    required List<({DraftAttachment draft, Uint8List bytes})> staged,
    required List<({int id, List<int>? bytes})> uploaded,
    required List<AttachmentResidue?> residue,
    required List<String?> stagedFiles,
  }) async {
    for (final item in _snapshotReminders.where((item) => item.id != null)) {
      if (_reminders.any((other) => other.id == item.id)) continue;
      await ref.read(deleteReminderProvider)(item.id!);
    }
    final createdReminders = <DraftReminder>[];
    for (final item in _reminders.where((item) => item.id == null)) {
      final id = await ref.read(createReminderProvider)(
        parentType: 'event',
        parentId: widget.event.drifId,
        triggerTime: item.triggerTime,
      );
      createdReminders.add(
        DraftReminder(id: id, triggerTime: item.triggerTime),
      );
    }

    for (final item in _snapshotAttachments.where((item) => item.id != null)) {
      if (_attachments.any((other) => other.id == item.id)) continue;
      residue.add(await ref.read(deleteAttachmentRowProvider)(tx, item.id!));
    }
    final insertedAttachments = <DraftAttachment>[];
    for (final item in staged) {
      final stage = await ref.read(insertAttachmentRowProvider)(
        tx,
        parentType: 'event',
        parentId: widget.event.drifId,
        fileName: item.draft.fileName,
        mimeType: item.draft.mimeType,
        data: item.bytes,
        onFileWritten: stagedFiles.add,
      );
      uploaded.add((id: stage.id, bytes: item.bytes));
      insertedAttachments.add(
        DraftAttachment(
          id: stage.id,
          fileName: item.draft.fileName,
          mimeType: item.draft.mimeType,
          fileSize: item.draft.fileSize,
          serverFileRef: item.draft.serverFileRef,
        ),
      );
    }

    final reminders = [
      for (final item in _reminders)
        if (item.id != null) item,
      ...createdReminders,
    ];
    final attachments = [
      for (final item in _attachments)
        if (item.id != null) item,
      ...insertedAttachments,
    ];
    return (reminders: reminders, attachments: attachments);
  }

  void _cancel() {
    setState(() {
      _draft = _snapshot;
      _dirty = false;
      _saving = false;
      _titleError = false;
      _timeError = false;
      _saveFailed = false;
      _title.text = _snapshot.title;
      _description.text = _snapshot.description;
      _location.text = _snapshot.location;
      // Cancel restores the reminders and attachments the pane opened with;
      // nothing was written while the draft lived.
      _reminders = [..._snapshotReminders];
      _attachments = [..._snapshotAttachments];
      _remindersTouched = false;
      _attachmentsTouched = false;
      if (widget.inlineSummary || widget.embedded) _editing = false;
    });
    _titleFocus.unfocus();
    _descriptionFocus.unfocus();
    _locationFocus.unfocus();
    if (widget.inlineSummary || (widget.embedded && !_editing)) return;
    if (widget.embedded) {
      widget.onClose?.call();
      return;
    }
    _leaveToSource(context);
  }

  Future<void> _pickCalendar() async {
    final picked = await pickCalendar(
      context,
      ref,
      selectedId: _draft.calendarId,
    );
    if (picked == null || !mounted || picked == _draft.calendarId) return;
    _setDraft(_withDraft(calendarId: picked));
  }

  void _toggleAllDay(bool allDay) {
    if (allDay == _draft.allDay) return;
    if (allDay) {
      final start = DateTime(
        _draft.start.year,
        _draft.start.month,
        _draft.start.day,
      );
      var end = DateTime(_draft.end.year, _draft.end.month, _draft.end.day);
      if (!end.isAfter(start)) {
        end = DateTime(start.year, start.month, start.day + 1);
      }
      _setDraft(_withDraft(allDay: true, start: start, end: end));
      return;
    }
    // Turning all-day off used to leave 00:00 → next 00:00: a 24-hour timed
    // event that belongs to neither day. A same-day range keeps its times;
    // anything that crosses midnight, lasts 24 hours or collapses to zero is
    // reset to a normal 09:00–10:00 on the start date.
    final start = _draft.start;
    final end = _draft.end;
    final sameDay =
        start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;
    final length = end.difference(start);
    final keepTimes =
        sameDay && length > Duration.zero && length < const Duration(hours: 24);
    final nextStart = keepTimes
        ? start
        : DateTime(start.year, start.month, start.day, 9);
    final nextEnd = keepTimes
        ? end
        : DateTime(start.year, start.month, start.day, 10);
    _setDraft(_withDraft(allDay: false, start: nextStart, end: nextEnd));
  }

  Future<void> _pickBoundary({required bool isStart}) async {
    final current = isStart ? _draft.start : _draft.end;
    final picked = _draft.allDay
        ? await pickDeadline(context, initial: current)
        : await pickDateTime(context, initial: current);
    if (picked == null || !mounted) return;
    if (isStart) {
      final length = _draft.end.difference(_draft.start);
      final span = length.isNegative || length == Duration.zero
          ? const Duration(hours: 1)
          : length;
      _setDraft(_withDraft(start: picked, end: picked.add(span)));
    } else {
      _setDraft(_withDraft(end: picked));
    }
  }

  Future<void> _delete(CalendaEventAdapter row) async {
    if (_deleting) return;
    final l = AppLocalizations.of(context)!;
    final title = _title.text.trim().isEmpty ? row.title : _title.text.trim();
    var occurrenceOnly = false;
    if (row.rrule != null && widget.event.isRecurringOccurrence) {
      final scope = await showDialog<bool>(
        animationStyle: AnimationStyle.noAnimation,
        context: context,
        builder: (ctx) => DsDialog(
          title: l.deleteScopeTitle,
          actions: [
            Expanded(
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.s2,
                runSpacing: AppSpacing.s2,
                children: [
                  DsButton(
                    label: l.cancel,
                    tone: DsButtonTone.ghost,
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                  DsButton(
                    label: l.deleteThisOccurrence,
                    tone: DsButtonTone.ghost,
                    onPressed: () => Navigator.of(ctx).pop(false),
                  ),
                  DsButton(
                    label: l.deleteWholeSeries,
                    tone: DsButtonTone.danger,
                    onPressed: () => Navigator.of(ctx).pop(true),
                  ),
                ],
              ),
            ),
          ],
          child: Text(
            l.deleteEventConfirm(title),
            style: AppTypography.body.copyWith(color: context.ds.ink2),
          ),
        ),
      );
      if (scope == null || !mounted) return;
      occurrenceOnly = !scope;
      if (occurrenceOnly) {
        setState(() => _deleting = true);
        try {
          await ref.read(excludeEventOccurrenceProvider)(
            id: row.drifId,
            occurrenceStart: widget.event.start,
          );
        } catch (error) {
          debugPrint('event_detail: delete occurrence failed: $error');
          if (!mounted) return;
          setState(() => _deleting = false);
          _showError();
          return;
        }
        if (!mounted) return;
        _leaveAfterDelete();
        showSpecToast(context, l.deleted);
        return;
      }
    } else if (row.rrule != null) {
      final confirmed = await showDialog<bool>(
        animationStyle: AnimationStyle.noAnimation,
        context: context,
        builder: (ctx) => DsDialog(
          title: l.moveToTrash,
          actions: [
            const Spacer(),
            DsButton(
              label: l.cancel,
              tone: DsButtonTone.ghost,
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
            const SizedBox(width: AppSpacing.s2),
            DsButton(
              label: l.moveToTrash,
              tone: DsButtonTone.danger,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
          child: Text(
            l.deleteRecurringEventConfirm(title),
            style: AppTypography.body.copyWith(color: context.ds.ink2),
          ),
        ),
      );
      if (confirmed != true || !mounted) return;
    } else {
      final confirmed = await showDialog<bool>(
        animationStyle: AnimationStyle.noAnimation,
        context: context,
        builder: (ctx) => DsDialog(
          title: l.moveToTrash,
          actions: [
            const Spacer(),
            DsButton(
              label: l.cancel,
              tone: DsButtonTone.ghost,
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
            const SizedBox(width: AppSpacing.s2),
            DsButton(
              label: l.moveToTrash,
              tone: DsButtonTone.danger,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
          child: Text(
            l.deleteEventConfirm(title),
            style: AppTypography.body.copyWith(color: context.ds.ink2),
          ),
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    final id = row.drifId;
    final restore = ref.read(restoreEventProvider);
    setState(() => _deleting = true);
    try {
      await ref.read(deleteEventProvider)(id);
    } catch (error) {
      debugPrint('event_detail: delete failed: $error');
      if (!mounted) return;
      setState(() => _deleting = false);
      _showError();
      return;
    }
    if (!mounted) return;
    showUndoBar(
      context,
      message: l.deleted,
      undoLabel: l.undo,
      onUndo: () => restore(id),
    );
    _leaveAfterDelete();
  }

  Widget _loadFailure(
    BuildContext context,
    AppLocalizations l,
    VoidCallback retry,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l.error,
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(
                color: context.semantic.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.s3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(onPressed: retry, child: Text(l.retry)),
                const SizedBox(width: AppSpacing.s2),
                TextButton(onPressed: _leaveFromFailure, child: Text(l.close)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _leaveFromFailure() {
    if (widget.embedded) {
      final close = widget.onClose;
      if (close != null) {
        close();
        return;
      }
    }
    _leaveToSource(context);
  }

  void _leaveAfterDelete() {
    _deletedNotified = true;
    if (widget.onDeleted != null) {
      widget.onDeleted!();
      return;
    }
    _leaveToSource(context);
  }

  void _showError() {
    if (!mounted) return;
    showSpecToast(context, AppLocalizations.of(context)!.actionFailedRetry);
  }
}

const Object _unsetEventDraft = Object();

class _EventDraft {
  const _EventDraft({
    required this.title,
    required this.description,
    required this.location,
    required this.start,
    required this.end,
    required this.allDay,
    required this.calendarId,
    required this.rrule,
  });

  factory _EventDraft.fromAdapter(CalendaEventAdapter event) {
    return _EventDraft(
      title: event.title,
      description: event.description ?? '',
      location: event.location ?? '',
      start: event.seriesStart,
      end: event.seriesEnd,
      allDay: event.isAllDay,
      calendarId: event.calendarId,
      rrule: event.rrule,
    );
  }

  final String title;
  final String description;
  final String location;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final int calendarId;
  final String? rrule;
}

bool _sameEventDraft(_EventDraft a, _EventDraft b) {
  return a.title == b.title &&
      a.description == b.description &&
      a.location == b.location &&
      a.start == b.start &&
      a.end == b.end &&
      a.allDay == b.allDay &&
      a.calendarId == b.calendarId &&
      a.rrule == b.rrule;
}

/// Whether the form changed the event's stored time. A row that was already
/// all-day keeps its DTSTART/DTEND on an edit that leaves them alone, including
/// the clock time an imported all-day row may carry.
bool _sameEventTime(_EventDraft a, _EventDraft b) =>
    a.start == b.start && a.end == b.end && a.allDay == b.allDay;

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

class _PaneCloseButton extends StatelessWidget {
  const _PaneCloseButton({required this.onPressed, required this.tooltip});

  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: MouseRegion(
          cursor: onPressed == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              hoverColor: ds.surface2,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 28,
                height: 28,
                child: Center(
                  child: Icon(CupertinoIcons.xmark, size: 13, color: ds.ink3),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PaneFieldRow extends StatelessWidget {
  const _PaneFieldRow({
    super.key,
    required this.label,
    required this.height,
    this.value,
    this.valueChild,
    this.leading,
    this.onTap,
    this.showChevron = false,
  });

  final String label;
  final double height;
  final String? value;
  final Widget? valueChild;
  final Widget? leading;
  final VoidCallback? onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final content = SizedBox(
      height: height,
      child: Row(
        children: [
          SizedBox(
            width: 62,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, height: 16 / 11, color: ds.ink3),
            ),
          ),
          Expanded(
            child:
                valueChild ??
                Row(
                  children: [
                    if (leading != null) ...[
                      leading!,
                      const SizedBox(width: 7),
                    ],
                    Flexible(
                      child: Text(
                        value ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 18 / 13,
                          color: ds.ink,
                        ),
                      ),
                    ),
                  ],
                ),
          ),
          if (showChevron)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(
                CupertinoIcons.chevron_forward,
                size: 13,
                color: ds.faint,
              ),
            ),
        ],
      ),
    );
    final row = DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: ds.lineSoft)),
      ),
      child: content,
    );
    if (onTap == null) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(onTap: onTap, hoverColor: ds.surface2, child: row),
      ),
    );
  }
}

class _PaneButton extends StatelessWidget {
  const _PaneButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.height,
    this.primary = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final double height;
  final bool primary;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final bg = primary ? SpecTokens.ink : ds.surface;
    final fg = primary ? Colors.white : (danger ? ds.danger : ds.ink2);
    final enabled = onPressed != null;
    // A plain Container, not Ink: these footers sit on an opaque paper
    // surface with no Material for the ink layer, so Ink's fill and border
    // never painted and the primary button's white label vanished.
    final visual = Container(
      key: const ValueKey('pane-button-visual'),
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: primary ? Colors.transparent : ds.line),
      ),
      child: Center(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: height >= 44 ? 14 : 12,
            fontWeight: height >= 44 ? FontWeight.w600 : FontWeight.w500,
            color: fg,
            height: 1.2,
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(6),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                child: Center(child: visual),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
