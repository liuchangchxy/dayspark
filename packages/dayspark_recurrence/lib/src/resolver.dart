part of '../dayspark_recurrence.dart';

DateTime _resolveLocalDateTime(LocalDateTime nominal, tz.Location location) {
  final wallMillis = nominal._calendarCandidate.millisecondsSinceEpoch;
  final offsets = location.zones
      .map((zone) => zone.offset.inMilliseconds)
      .toSet();
  final candidates = <DateTime>[];
  for (final offset in offsets) {
    final instant = DateTime.fromMillisecondsSinceEpoch(
      wallMillis - offset,
      isUtc: true,
    );
    final local = tz.TZDateTime.from(instant, location);
    if (_sameWallFields(local, nominal)) candidates.add(instant);
  }
  if (candidates.isNotEmpty) {
    candidates.sort();
    return candidates.first;
  }

  for (final transition in location.transitionAt) {
    final beforeOffset = location
        .lookupTimeZone(transition - 1)
        .timeZone
        .offset
        .inMilliseconds;
    final afterOffset = location
        .lookupTimeZone(transition)
        .timeZone
        .offset
        .inMilliseconds;
    if (afterOffset <= beforeOffset) continue;
    final gapStartWall = transition + beforeOffset;
    final gapEndWall = transition + afterOffset;
    if (wallMillis >= gapStartWall && wallMillis < gapEndWall) {
      return DateTime.fromMillisecondsSinceEpoch(
        wallMillis - beforeOffset,
        isUtc: true,
      );
    }
  }
  throw StateError(
    'Could not resolve ${nominal.canonical} in ${location.name}.',
  );
}

bool _sameWallFields(tz.TZDateTime value, LocalDateTime nominal) =>
    value.year == nominal.year &&
    value.month == nominal.month &&
    value.day == nominal.day &&
    value.hour == nominal.hour &&
    value.minute == nominal.minute &&
    value.second == nominal.second;
