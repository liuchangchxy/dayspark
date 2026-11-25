import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/default_calendar_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/domain/records/capture_submit.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/a2.dart';
import 'package:dayspark/ui/design/spec_toast.dart';

/// The Todo tab's capture write. Returns whether anything was written so the
/// panel can stay open on failure instead of dropping the draft.
Future<bool> submitTodoCapture(
  WidgetRef ref,
  BuildContext context,
  String text,
  A2CaptureDraft draft,
) async {
  final l = AppLocalizations.of(context)!;
  final calendars = await ref.read(calendarsProvider.future);
  if (calendars.isEmpty) {
    if (context.mounted) {
      showSpecToast(context, l.noCalendar);
    }
    return false;
  }
  final requested = draft.calendarId;
  final calendarId =
      (requested != null &&
          calendars.any((calendar) => calendar.id == requested))
      ? requested
      : (resolveNewEntryCalendarId(
              calendars: calendars,
              preferredId: ref.read(defaultCalendarIdProvider),
            ) ??
            calendars.first.id);
  try {
    await writeCapturedTodo(
      ref,
      calendarId: calendarId,
      summary: text,
      dueDate: draft.dueDate,
      planStart: draft.planStart,
      planEnd: draft.planEnd,
      reminderOffset: draft.reminderOffset,
    );
    return true;
  } catch (error) {
    debugPrint('todo: capture failed: $error');
    if (context.mounted) {
      showSpecToast(context, l.actionFailedRetry);
    }
    return false;
  }
}

/// The event half of the same capture surface. A capture that switched to
/// "event" writes a real event with the time, calendar, repeat and reminder the
/// panel showed; it is never rerouted through the todo writer.
Future<bool> submitEventCapture(
  WidgetRef ref,
  BuildContext context, {
  required String title,
  required DateTime start,
  required DateTime end,
  int? calendarId,
  String? rrule,
  Duration? reminderOffset,
}) async {
  final l = AppLocalizations.of(context)!;
  final calendars = await ref.read(calendarsProvider.future);
  if (calendars.isEmpty) {
    if (context.mounted) {
      showSpecToast(context, l.noCalendar);
    }
    return false;
  }
  final requested = calendarId;
  final resolvedCalendarId =
      (requested != null &&
          calendars.any((calendar) => calendar.id == requested))
      ? requested
      : (resolveNewEntryCalendarId(
              calendars: calendars,
              preferredId: ref.read(defaultCalendarIdProvider),
            ) ??
            calendars.first.id);
  try {
    await RecordScope.run(ref.read(databaseProvider), (tx) async {
      final eventId = await ref.read(createEventProvider)(
        calendarId: resolvedCalendarId,
        summary: title,
        startDt: start,
        endDt: end,
        isAllDay: false,
        rrule: (rrule == null || rrule.isEmpty) ? null : rrule,
      );
      if (reminderOffset != null) {
        await ref.read(createReminderProvider)(
          parentType: 'event',
          parentId: eventId,
          triggerTime: start.subtract(reminderOffset),
        );
      }
    });
    return true;
  } catch (error) {
    debugPrint('todo: event capture failed: $error');
    if (context.mounted) {
      showSpecToast(context, l.actionFailedRetry);
    }
    return false;
  }
}
