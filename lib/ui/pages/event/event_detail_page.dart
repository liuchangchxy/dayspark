import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
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
    this.onClose,
    this.onDeleted,
    this.clock,
  });

  final CalendaEventAdapter event;
  final bool embedded;
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
    final statusColor = inProgress ? context.ds.primaryHover : context.ds.ink3;
    final fraction = validRange
        ? (now.difference(start).inMilliseconds / length.inMilliseconds)
              .clamp(0.0, 1.0)
              .toDouble()
        : 0.0;
    final canPickCalendar =
        calendars != null &&
        calendars.isNotEmpty &&
        (calendars.length > 1 || currentCalendar == null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            key: PageStorageKey<String>('event-detail-${widget.event.drifId}'),
            padding: EdgeInsets.fromLTRB(
              side,
              widget.embedded ? 18 : 14,
              side,
              24,
            ),
            children: [
              _header(context, l, live, currentCalendar),
              _status(context, live, status, statusColor, fraction, start, end),
              _fields(
                context,
                l,
                live,
                calendars,
                currentCalendar,
                validRange,
                rowHeight,
                canPickCalendar,
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
                      rrule: live.rrule,
                      anchorDate: start,
                      onChanged: (value) =>
                          _saveSchedule(live, setRrule: true, rrule: value),
                    ),
                    if (live.rrule != null)
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
              _notes(context, l),
              _tags(context, live),
              const SizedBox(height: 8),
              AttachmentList(parentType: 'event', parentId: live.drifId),
              const SizedBox(height: 8),
            ],
          ),
        ),
        _footer(context, l, live, mobile, side),
      ],
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
        '${DateFormat.MMMd(locale).format(live.seriesStart)} '
        '${DateFormat.E(locale).format(live.seriesStart)}';
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
                  isDense: true,
                  // The title sits on the page, not in a box: the theme fills
                  // every field, and a white patch behind the one line of
                  // 20px type reads as a stray input that lost its border.
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintStyle: AppTypography.headline.copyWith(color: ds.ink3),
                ),
              ),
            ],
          ),
        ),
        if (widget.embedded) ...[
          const SizedBox(width: 8),
          _PaneCloseButton(onPressed: widget.onClose, tooltip: l.close),
        ],
      ],
    );
  }

  Widget _status(
    BuildContext context,
    CalendaEventAdapter live,
    String status,
    Color statusColor,
    double fraction,
    DateTime start,
    DateTime end,
  ) {
    final ds = context.ds;
    final left = live.isAllDay
        ? formatDeadline(context, start)
        : DateFormatters.formatTime(start);
    final right = live.isAllDay
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
                  child: ColoredBox(color: ds.primary),
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
    CalendaEventAdapter live,
    List<Calendar>? calendars,
    Calendar? currentCalendar,
    bool validRange,
    double rowHeight,
    bool canPickCalendar,
  ) {
    final ds = context.ds;
    return Column(
      children: [
        const SizedBox(height: 16),
        Container(height: 1, color: ds.line),
        _PaneFieldRow(
          label: l.startTime,
          height: rowHeight,
          value: live.isAllDay
              ? formatDeadline(context, live.seriesStart)
              : formatMoment(context, live.seriesStart),
          onTap: () => _pickBoundary(live, isStart: true),
          showChevron: true,
        ),
        _PaneFieldRow(
          label: l.endTime,
          height: rowHeight,
          value: live.isAllDay
              ? formatDeadline(context, live.seriesEnd)
              : formatMoment(context, live.seriesEnd),
          onTap: () => _pickBoundary(live, isStart: false),
          showChevron: true,
        ),
        _PaneFieldRow(
          label: l.duration,
          height: rowHeight,
          value: validRange
              ? (live.isAllDay
                    ? l.durationAllDay
                    : formatExecutionLength(context, live.seriesEnd.difference(live.seriesStart)))
              : l.invalidTimeRange,
        ),
        _PaneFieldRow(
          label: l.allDay,
          height: rowHeight,
          valueChild: Align(
            alignment: Alignment.centerLeft,
            child: Switch(
              value: live.isAllDay,
              onChanged: (value) => _toggleAllDay(live, value),
            ),
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
          onTap: canPickCalendar
              ? () => _pickCalendar(live, calendars!)
              : null,
          showChevron: canPickCalendar,
        ),
        _PaneFieldRow(
          label: l.location,
          height: rowHeight,
          // No chevron: this row edits in place, it does not open anything.
          showChevron: false,
          valueChild: TextField(
            controller: _location,
            focusNode: _locationFocus,
            style: AppTypography.caption.copyWith(color: ds.ink),
            cursorColor: ds.primary,
            decoration: InputDecoration(
              // The row already says "Location"; repeating it in the empty field
              // printed the same word twice, six pixels apart. The placeholder
              // says what to do instead of what the row is.
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
              _locationTimer?.cancel();
              _locationTimer = Timer(
                const Duration(milliseconds: 600),
                _flushLocation,
              );
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
        Text(
          l.notes,
          style: AppTypography.overline.copyWith(color: ds.ink3),
        ),
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
              _descriptionTimer?.cancel();
              _descriptionTimer = Timer(
                const Duration(milliseconds: 600),
                _flushDescription,
              );
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
    // An event with no tags has nothing to show here, and a heading over
    // nothing reads as content that failed to load.
    if (assigned.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          l.tags,
          style: AppTypography.overline.copyWith(color: ds.ink3),
        ),
        const SizedBox(height: 7),
        Wrap(
          spacing: AppSpacing.s2,
          runSpacing: AppSpacing.s2,
          children: [
            for (final tag in assigned)
              DsChip(
                label: tag.name,
                solid: true,
                leading: DsDot(
                  color: ColorUtils.parseHex(tag.color),
                  size: 7,
                ),
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
          height: height,
          child: Row(
            children: [
              Expanded(
                child: _PaneButton(
                  label: l.edit,
                  height: height,
                  primary: true,
                  expand: true,
                  onPressed: () => context.push('/event/edit', extra: live),
                ),
              ),
              const SizedBox(width: 8),
              _PaneButton(
                label: l.moveToTrash,
                height: height,
                danger: true,
                onPressed: () => _delete(live),
              ),
            ],
          ),
        ),
      ),
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
    final l = AppLocalizations.of(context)!;
    final picked = await showDsSheet<int>(
      context: context,
      title: l.calendarField,
      body: Builder(
        builder: (sheetContext) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final calendar in calendars)
              DsSettingRow(
                label: calendar.name,
                leading: DsDot(
                  color: ColorUtils.parseHex(calendar.color),
                  size: 8,
                ),
                trailing: calendar.id == live.calendarId
                    ? Icon(
                        CupertinoIcons.checkmark,
                        size: 15,
                        color: sheetContext.ds.primary,
                      )
                    : const SizedBox.shrink(),
                selected: calendar.id == live.calendarId,
                onTap: () => Navigator.of(sheetContext).pop(calendar.id),
              ),
          ],
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
            l.deleteEventConfirm(row.title),
            style: AppTypography.body.copyWith(color: context.ds.ink2),
          ),
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
            l.deleteRecurringEventConfirm(row.title),
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
            l.deleteEventConfirm(row.title),
            style: AppTypography.body.copyWith(color: context.ds.ink2),
          ),
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
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              onTap: onPressed,
              hoverColor: ds.surface2,
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 28,
                height: 28,
                child: Icon(CupertinoIcons.xmark, size: 16, color: ds.ink3),
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
              style: TextStyle(
                fontSize: 11,
                height: 16 / 11,
                color: ds.ink3,
              ),
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
    required this.label,
    required this.onPressed,
    required this.height,
    this.primary = false,
    this.danger = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final double height;
  final bool primary;
  final bool danger;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final bg = primary ? ds.primary : ds.surface;
    final fg = primary ? ds.onPrimary : (danger ? ds.danger : ds.ink2);
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                height: height,
                width: expand ? double.infinity : null,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: primary ? Colors.transparent : ds.line,
                  ),
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: height >= 44 ? 14 : 12,
                    fontWeight: height >= 44
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: fg,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
