import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/time_picker/wheel_time_picker.dart';

/// Date/time vocabulary shared by every Todo and Event surface.
///
/// The app only ever asks about two things: when something is *due*, and when
/// the user plans to *do* it. Both are plain local times here — nothing in the
/// UI layer carries a rule string, a zone id, or a serialized anchor.

/// Due dates are usually "a day", so the picker stops at the date unless the
/// user asks for a time. Passing [withTime] as null asks for the date only.
Future<DateTime?> pickDeadline(
  BuildContext context, {
  required DateTime initial,
  bool? withTime,
}) async {
  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );
  if (date == null || !context.mounted) return null;
  if (withTime != true) {
    return DateTime(date.year, date.month, date.day);
  }
  final time = await showWheelTimePicker(
    context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  if (time == null) return null;
  return DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
}

/// A single date+time, used for "I'll do it then" and for event boundaries.
Future<DateTime?> pickDateTime(
  BuildContext context, {
  required DateTime initial,
}) async {
  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );
  if (date == null || !context.mounted) return null;
  final time = await showWheelTimePicker(
    context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  if (time == null) return null;
  return DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
}

/// Length of a scheduled block. Fixed choices rather than a second picker: the
/// user is answering "how long", and an end time makes them do the subtraction.
const List<Duration> kExecutionLengths = [
  Duration(minutes: 30),
  Duration(hours: 1),
  Duration(hours: 2),
  Duration(hours: 4),
];

String formatExecutionLength(BuildContext context, Duration length) {
  final l = AppLocalizations.of(context)!;
  if (length.inMinutes < 60) return l.minutesShort(length.inMinutes);
  return l.hoursShort(length.inHours);
}

/// `HH:mm`, or `M/D HH:mm` when the moment is not today — a bare clock time on
/// another date is the classic way to misread a schedule. Past moments are not
/// called "overdue": this formats event boundaries and planned blocks, which
/// are facts about when something happens, not claims about being late.
String formatMoment(BuildContext context, DateTime value) {
  final l = AppLocalizations.of(context)!;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(value.year, value.month, value.day);
  final clock = DateFormatters.formatTime(value);
  if (day == today) return clock;
  if (day == today.add(const Duration(days: 1))) return '${l.tomorrow} $clock';
  return '${DateFormatters.formatShortDate(value)} $clock';
}

/// A deadline that may be date-only reads without a meaningless `00:00`.
String formatDeadline(BuildContext context, DateTime value) {
  final l = AppLocalizations.of(context)!;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(value.year, value.month, value.day);
  final dateOnly = value.hour == 0 && value.minute == 0;
  final dayLabel = day == today
      ? l.today
      : day == today.add(const Duration(days: 1))
      ? l.tomorrow
      : DateFormat.MMMd(Localizations.localeOf(context).toString()).format(value);
  if (dateOnly) return dayLabel;
  return '$dayLabel · ${DateFormatters.formatTime(value)}';
}

/// `M/D HH:mm – HH:mm`, collapsing the second date when the block is within
/// one day.
String formatExecutionRange(
  BuildContext context,
  DateTime start,
  DateTime end, {
  bool includeDate = true,
}) => DateFormatters.formatTaskAllocationRange(
  start,
  end,
  includeDate: includeDate,
);
