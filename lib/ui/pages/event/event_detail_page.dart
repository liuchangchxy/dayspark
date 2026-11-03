import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/shell/workspace_page.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/attachment_list.dart';
import 'package:dayspark/ui/widgets/schedule/repeat_editor.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_pickers.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_row.dart';
import 'package:dayspark/ui/widgets/tag_chips.dart';

/// An event that is editable where it is read — the same contract as
/// [TodoDetailPane], so the two object types never teach different gestures.
class EventDetailPage extends StatelessWidget {
  const EventDetailPage({super.key, required this.event});

  final CalendaEventAdapter event;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final desktop = isWorkspaceLayout(context);
    return WorkspacePage(
      title: l.eventLabel,
      maxContentWidth: desktop ? 720 : null,
      child: EventDetailPane(event: event),
    );
  }
}

class EventDetailPane extends ConsumerStatefulWidget {
  const EventDetailPane({
    super.key,
    required this.event,
    this.embedded = false,
    this.onClose,
    this.onDeleted,
  });

  final CalendaEventAdapter event;
  final bool embedded;
  final VoidCallback? onClose;
  final VoidCallback? onDeleted;

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
  Timer? _titleTimer;
  Timer? _descriptionTimer;
  Timer? _locationTimer;
  late String _savedTitle;
  late String _savedDescription;
  late String _savedLocation;
  bool _deletedNotified = false;

  @override
  void initState() {
    super.initState();
    _savedTitle = widget.event.title;
    _savedDescription = widget.event.description ?? '';
    _savedLocation = widget.event.location ?? '';
    _title.text = _savedTitle;
    _description.text = _savedDescription;
    _location.text = _savedLocation;
    _titleFocus.addListener(_flushTitle);
    _descriptionFocus.addListener(_flushDescription);
    _locationFocus.addListener(_flushLocation);
  }

  @override
  void dispose() {
    _flushTitle();
    _flushDescription();
    _flushLocation();
    _titleTimer?.cancel();
    _descriptionTimer?.cancel();
    _locationTimer?.cancel();
    _titleFocus.removeListener(_flushTitle);
    _descriptionFocus.removeListener(_flushDescription);
    _locationFocus.removeListener(_flushLocation);
    _titleFocus.dispose();
    _descriptionFocus.dispose();
    _locationFocus.dispose();
    _title.dispose();
    _description.dispose();
    _location.dispose();
    super.dispose();
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
      return const Center(child: CircularProgressIndicator());
    }
    _syncFromLive(live);

    final start = live.seriesStart;
    final end = live.seriesEnd;
    final length = end.difference(start);
    final validRange = !length.isNegative && length > Duration.zero;
    final calendarName = ref
        .watch(calendarsProvider)
        .valueOrNull
        ?.where((c) => c.id == live.calendarId)
        .firstOrNull
        ?.name;

    return ListView(
      key: PageStorageKey<String>('event-detail-${widget.event.drifId}'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('event-detail-title'),
                controller: _title,
                focusNode: _titleFocus,
                style: AppTypography.headline,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (value) {
                  _titleTimer?.cancel();
                  if (value.trim().isEmpty) return;
                  _titleTimer = Timer(
                    const Duration(milliseconds: 600),
                    _flushTitle,
                  );
                },
                onSubmitted: (_) => _flushTitle(),
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
            ),
            if (widget.embedded)
              IconButton(
                icon: const Icon(CupertinoIcons.xmark, size: 16),
                tooltip: l.close,
                onPressed: widget.onClose,
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        if (live.rrule != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
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
        ],
        const SizedBox(height: AppSpacing.lg),
        const RowDivider(),
        const SizedBox(height: AppSpacing.sm),
        ScheduleRow(
          label: l.allDay,
          value: live.isAllDay ? l.durationAllDay : l.eventLabel,
          trailing: Switch(
            value: live.isAllDay,
            onChanged: (value) => _toggleAllDay(live, value),
          ),
        ),
        ScheduleRow(
          label: l.startTime,
          value: live.isAllDay
              ? formatDeadline(context, start)
              : formatMoment(context, start),
          onTap: () => _pickBoundary(live, isStart: true),
        ),
        ScheduleRow(
          label: l.endTime,
          value: live.isAllDay
              ? formatDeadline(context, end)
              : formatMoment(context, end),
          onTap: () => _pickBoundary(live, isStart: false),
        ),
        ScheduleRow(
          label: l.duration,
          value: validRange
              ? (live.isAllDay
                    ? l.durationAllDay
                    : formatExecutionLength(context, length))
              : l.invalidTimeRange,
          placeholder: !validRange,
        ),
        RepeatRow(
          rrule: live.rrule,
          anchorDate: start,
          onChanged: (value) =>
              _saveSchedule(live, setRrule: true, rrule: value),
        ),
        if (calendarName != null)
          ScheduleRow(label: l.calendar, value: calendarName),
        const SizedBox(height: AppSpacing.lg),
        const RowDivider(),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _location,
          focusNode: _locationFocus,
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
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) {
            _locationTimer?.cancel();
            _locationTimer = Timer(
              const Duration(milliseconds: 600),
              _flushLocation,
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _description,
          focusNode: _descriptionFocus,
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
          maxLines: null,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) {
            _descriptionTimer?.cancel();
            _descriptionTimer = Timer(
              const Duration(milliseconds: 600),
              _flushDescription,
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        _tags(context, live),
        const SizedBox(height: AppSpacing.lg),
        const RowDivider(),
        const SizedBox(height: AppSpacing.md),
        AttachmentList(parentType: 'event', parentId: live.drifId),
        const SizedBox(height: AppSpacing.xl),
        const RowDivider(),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _delete(live),
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
    );
  }

  Widget _tags(BuildContext context, CalendaEventAdapter live) {
    final assigned =
        ref.watch(eventTagsProvider(live.drifId)).valueOrNull ?? const [];
    return TagChips(
      parentType: 'event',
      parentId: live.drifId,
      assignedTags: assigned,
    );
  }

  void _syncFromLive(CalendaEventAdapter live) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_titleFocus.hasFocus &&
          _title.text == _savedTitle &&
          _title.text != live.title) {
        _title.text = live.title;
        _savedTitle = live.title;
      }
      final description = live.description ?? '';
      if (!_descriptionFocus.hasFocus &&
          _description.text == _savedDescription &&
          _description.text != description) {
        _description.text = description;
        _savedDescription = description;
      }
      final location = live.location ?? '';
      if (!_locationFocus.hasFocus &&
          _location.text == _savedLocation &&
          _location.text != location) {
        _location.text = location;
        _savedLocation = location;
      }
    });
  }

  void _notifyDeleted() {
    if (_deletedNotified) return;
    _deletedNotified = true;
    final callback = widget.onDeleted;
    if (callback != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => callback());
    }
  }

  void _flushTitle() {
    if (!mounted) return;
    _titleTimer?.cancel();
    _titleTimer = null;
    final text = _title.text.trim();
    if (text.isEmpty) {
      _title.text = _savedTitle;
      return;
    }
    if (text == _savedTitle) return;
    _savedTitle = text;
    unawaited(_saveText(title: text));
  }

  void _flushDescription() {
    if (!mounted) return;
    _descriptionTimer?.cancel();
    _descriptionTimer = null;
    final text = _description.text.trim();
    if (text == _savedDescription) return;
    _savedDescription = text;
    unawaited(_saveText(setDescription: true, description: text));
  }

  void _flushLocation() {
    if (!mounted) return;
    _locationTimer?.cancel();
    _locationTimer = null;
    final text = _location.text.trim();
    if (text == _savedLocation) return;
    _savedLocation = text;
    unawaited(_saveText(setLocation: true, location: text));
  }

  Future<void> _saveText({
    String? title,
    bool setDescription = false,
    String? description,
    bool setLocation = false,
    String? location,
  }) async {
    try {
      await ref.read(updateEventProvider)(
        widget.event.drifId,
        EventsCompanion(
          summary: title != null ? Value(title) : const Value.absent(),
          description: setDescription
              ? Value(description!.isEmpty ? null : description)
              : const Value.absent(),
          location: setLocation
              ? Value(location!.isEmpty ? null : location)
              : const Value.absent(),
          updatedAt: Value(DateTime.now()),
        ),
      );
    } on Object catch (error) {
      debugPrint('event_detail: text update failed: $error');
      _showError();
    }
  }

  Future<void> _toggleAllDay(CalendaEventAdapter live, bool allDay) async {
    if (allDay == live.isAllDay) return;
    final start = allDay
        ? DateTime(live.seriesStart.year, live.seriesStart.month, live.seriesStart.day)
        : live.seriesStart;
    final end = allDay
        ? DateTime(live.seriesEnd.year, live.seriesEnd.month, live.seriesEnd.day)
        : live.seriesEnd;
    await _saveSchedule(live, start: start, end: end, allDay: allDay);
  }

  Future<void> _pickBoundary(
    CalendaEventAdapter live, {
    required bool isStart,
  }) async {
    final current = isStart ? live.seriesStart : live.seriesEnd;
    final picked = live.isAllDay
        ? await pickDeadline(context, initial: current)
        : await pickDateTime(context, initial: current);
    if (picked == null || !mounted) return;
    if (isStart) {
      final length = live.seriesEnd.difference(live.seriesStart);
      final span = length.isNegative || length == Duration.zero
          ? const Duration(hours: 1)
          : length;
      await _saveSchedule(live, start: picked, end: picked.add(span));
    } else {
      await _saveSchedule(live, end: picked);
    }
  }

  Future<void> _saveSchedule(
    CalendaEventAdapter live, {
    DateTime? start,
    DateTime? end,
    bool? allDay,
    bool setRrule = false,
    String? rrule,
  }) async {
    final l = AppLocalizations.of(context)!;
    final nextStart = start ?? live.seriesStart;
    final nextEnd = end ?? live.seriesEnd;
    if (nextEnd.isBefore(nextStart) || nextEnd == nextStart) {
      _showMessage(l.invalidTimeRange);
      return;
    }
    try {
      await ref.read(updateEventProvider)(
        live.drifId,
        EventsCompanion(
          startDt: Value(nextStart),
          endDt: Value(nextEnd),
          isAllDay: allDay != null ? Value(allDay) : const Value.absent(),
          rrule: setRrule
              ? Value(rrule == null || rrule.isEmpty ? null : rrule)
              : const Value.absent(),
          updatedAt: Value(DateTime.now()),
        ),
      );
    } on Object catch (error) {
      debugPrint('event_detail: schedule update failed: $error');
      _showError();
    }
  }

  Future<void> _delete(CalendaEventAdapter row) async {
    final l = AppLocalizations.of(context)!;
    // A recurring series has two very different deletes; asking which one is
    // the same question the todo side asks before completing an occurrence.
    var occurrenceOnly = false;
    if (row.rrule != null && widget.event.isRecurringOccurrence) {
      final scope = await showDialog<bool>(
        animationStyle: AnimationStyle.noAnimation,
        context: context,
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
      if (scope == null || !mounted) return;
      occurrenceOnly = !scope;
      if (occurrenceOnly) {
        await ref.read(excludeEventOccurrenceProvider)(
          id: row.drifId,
          occurrenceStart: widget.event.start,
        );
        if (!mounted) return;
        _leaveAfterDelete();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.deleted)));
        return;
      }
    } else if (row.rrule != null) {
      final confirmed = await showDialog<bool>(
        animationStyle: AnimationStyle.noAnimation,
        context: context,
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
      if (confirmed != true || !mounted) return;
    } else {
      final confirmed = await showDialog<bool>(
        animationStyle: AnimationStyle.noAnimation,
        context: context,
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
      if (confirmed != true || !mounted) return;
    }

    final id = row.drifId;
    final restore = ref.read(restoreEventProvider);
    await ref.read(deleteEventProvider)(id);
    if (!mounted) return;
    _leaveAfterDelete();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.deleted),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(label: l.undo, onPressed: () => restore(id)),
      ),
    );
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
    _showMessage(AppLocalizations.of(context)!.actionFailedRetry);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
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
