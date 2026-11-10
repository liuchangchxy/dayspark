import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/shell/workspace_page.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/attachment_list.dart';
import 'package:dayspark/ui/widgets/schedule/repeat_editor.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_pickers.dart';

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
    final calendars = ref.watch(calendarsProvider).valueOrNull;
    final currentCalendar = calendars
        ?.where((c) => c.id == live.calendarId)
        .firstOrNull;

    return ListView(
      key: PageStorageKey<String>('event-detail-${widget.event.drifId}'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s5,
        AppSpacing.s4,
        AppSpacing.s5,
        AppSpacing.s8,
      ),
      children: [
        if (widget.embedded)
          Align(
            alignment: Alignment.centerRight,
            child: DsIconButton(
              icon: CupertinoIcons.xmark,
              size: 16,
              compact: true,
              tooltip: l.close,
              onPressed: widget.onClose,
            ),
          ),
        Wrap(
          spacing: AppSpacing.s2,
          runSpacing: AppSpacing.s2,
          children: [
            DsChip(
              key: const ValueKey('calendar-picker'),
              solid: true,
              label: currentCalendar?.name ?? l.calendarUnavailable,
              leading: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: live.color,
                  shape: BoxShape.circle,
                ),
              ),
              onTap: calendars != null &&
                      calendars.isNotEmpty &&
                      (calendars.length > 1 || currentCalendar == null)
                  ? () => _pickCalendar(live, calendars)
                  : null,
            ),
            if (live.rrule != null)
              DsChip(label: l.recurringSeriesNoticeShort, compact: true),
          ],
        ),
        const SizedBox(height: AppSpacing.s2),
        TextField(
          key: const ValueKey('event-detail-title'),
          controller: _title,
          focusNode: _titleFocus,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            height: 1.3,
            letterSpacing: -0.2,
            color: context.ds.ink,
          ),
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
            hintStyle: TextStyle(fontSize: 22, color: context.ds.ink3),
          ),
        ),
        const SizedBox(height: AppSpacing.s2),
        Text(
          '${formatMoment(context, start)}'
          '${live.isAllDay ? '' : ' – ${formatMoment(context, end)}'}',
          style: AppTypography.caption.copyWith(color: context.ds.ink2),
        ),
        const SizedBox(height: AppSpacing.s4),
        DsSectionLabel(
          l.sectionTime,
          padding: const EdgeInsets.only(bottom: AppSpacing.s1),
        ),
        DsSettingRow(
          label: l.allDay,
          value: live.isAllDay ? l.durationAllDay : l.eventLabel,
          trailing: Switch.adaptive(
            value: live.isAllDay,
            activeTrackColor: context.ds.primary,
            onChanged: (value) => _toggleAllDay(live, value),
          ),
        ),
        DsSettingRow(
          label: l.startTime,
          value: live.isAllDay
              ? formatDeadline(context, start)
              : formatMoment(context, start),
          onTap: () => _pickBoundary(live, isStart: true),
        ),
        DsSettingRow(
          label: l.endTime,
          value: live.isAllDay
              ? formatDeadline(context, end)
              : formatMoment(context, end),
          onTap: () => _pickBoundary(live, isStart: false),
        ),
        DsSettingRow(
          label: l.duration,
          value: validRange
              ? (live.isAllDay
                    ? l.durationAllDay
                    : formatExecutionLength(context, length))
              : l.invalidTimeRange,
          danger: !validRange,
        ),
        if (calendars != null)
          DsSettingRow(
            label: l.calendar,
            value: calendars.isEmpty
                ? l.noCalendar
                : currentCalendar?.name ?? l.calendarUnavailable,
            onTap:
                calendars.isNotEmpty &&
                    (calendars.length > 1 || currentCalendar == null)
                ? () => _pickCalendar(live, calendars)
                : null,
          ),
        RepeatRow(
          rrule: live.rrule,
          anchorDate: start,
          onChanged: (value) =>
              _saveSchedule(live, setRrule: true, rrule: value),
        ),
        const SizedBox(height: AppSpacing.s3),
        DsHairline(color: context.ds.lineSoft),
        DsSectionLabel(
          l.sectionContent,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
        ),
        TextField(
          controller: _location,
          focusNode: _locationFocus,
          style: AppTypography.body.copyWith(color: context.ds.ink),
          decoration: InputDecoration(
            hintText: l.location,
            prefixIcon: Icon(
              CupertinoIcons.location,
              size: 16,
              color: context.ds.ink3,
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 30,
              minHeight: 24,
            ),
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            hintStyle: AppTypography.body.copyWith(color: context.ds.ink3),
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
        const SizedBox(height: AppSpacing.s2),
        TextField(
          controller: _description,
          focusNode: _descriptionFocus,
          style: AppTypography.body.copyWith(color: context.ds.ink),
          decoration: InputDecoration(
            hintText: l.description,
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            hintStyle: AppTypography.body.copyWith(color: context.ds.ink3),
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
        const SizedBox(height: AppSpacing.s3),
        _tags(context, live),
        const SizedBox(height: AppSpacing.s3),
        DsHairline(color: context.ds.lineSoft),
        const SizedBox(height: AppSpacing.s3),
        AttachmentList(parentType: 'event', parentId: live.drifId),
        const SizedBox(height: AppSpacing.s6),
        DsHairline(color: context.ds.lineSoft),
        const SizedBox(height: AppSpacing.s3),
        Wrap(
          spacing: AppSpacing.s2,
          runSpacing: AppSpacing.s2,
          children: [
            DsButton(
              label: l.edit,
              tone: DsButtonTone.secondary,
              small: true,
              onPressed: () => context.push('/event/edit', extra: live),
            ),
            DsButton(
              label: l.moveToTrash,
              tone: DsButtonTone.danger,
              small: true,
              onPressed: () => _delete(live),
            ),
          ],
        ),
      ],
    );
  }

  Widget _tags(BuildContext context, CalendaEventAdapter live) {
    final assigned =
        ref.watch(eventTagsProvider(live.drifId)).valueOrNull ?? const [];
    if (assigned.isEmpty) {
      return SizedBox(
        height: 40,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            AppLocalizations.of(context)!.tags,
            style: AppTypography.small.copyWith(color: context.ds.ink3),
          ),
        ),
      );
    }
    return Wrap(
      spacing: AppSpacing.s2,
      runSpacing: AppSpacing.s2,
      children: [
        for (final tag in assigned)
          DsChip(
            label: tag.name,
            solid: true,
            leading: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: ColorUtils.parseHex(tag.color),
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
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

  Future<void> _pickCalendar(
    CalendaEventAdapter live,
    List<Calendar> calendars,
  ) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
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
                  trailing: calendar.id == live.calendarId
                      ? const Icon(CupertinoIcons.checkmark, size: 16)
                      : null,
                  onTap: () => Navigator.of(ctx).pop(calendar.id),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted || picked == live.calendarId) return;
    try {
      final current = await ref.read(calendarsProvider.future);
      if (!mounted) return;
      if (!current.any((calendar) => calendar.id == picked)) {
        _showMessage(AppLocalizations.of(context)!.calendarUnavailable);
        return;
      }
      await ref.read(updateEventProvider)(
        live.drifId,
        EventsCompanion(
          calendarId: Value(picked),
          updatedAt: Value(DateTime.now()),
        ),
      );
    } on Object catch (error) {
      debugPrint('event_detail: calendar update failed: $error');
      _showError();
    }
  }

  Future<void> _toggleAllDay(CalendaEventAdapter live, bool allDay) async {
    if (allDay == live.isAllDay) return;
    final start = allDay
        ? DateTime(
            live.seriesStart.year,
            live.seriesStart.month,
            live.seriesStart.day,
          )
        : live.seriesStart;
    final end = allDay
        ? DateTime(
            live.seriesEnd.year,
            live.seriesEnd.month,
            live.seriesEnd.day,
          )
        : live.seriesEnd;
    final validEnd = allDay && !end.isAfter(start)
        ? DateTime(start.year, start.month, start.day + 1)
        : end;
    await _saveSchedule(live, start: start, end: validEnd, allDay: allDay);
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
