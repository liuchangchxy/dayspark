import 'package:timezone/timezone.dart' as tz;

class ResolvedOccurrence {
  const ResolvedOccurrence(this.nominalLocalKey, this.timeZone, this.instant);

  final String nominalLocalKey;
  final String timeZone;
  final DateTime instant;

  String get occurrenceId => 'v1:DT:$nominalLocalKey@$timeZone';
}

String dateOnlyOccurrenceId(DateTime value, String zoneName) =>
    'v1:DATE:${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}@$zoneName';

List<DateTime> exactCandidates(DateTime nominal, tz.Location location) {
  final wallMillis = DateTime.utc(
    nominal.year,
    nominal.month,
    nominal.day,
    nominal.hour,
    nominal.minute,
    nominal.second,
    nominal.millisecond,
    nominal.microsecond,
  ).millisecondsSinceEpoch;
  final offsets = location.zones
      .map((zone) => zone.offset.inMilliseconds)
      .toSet();
  final matches = <DateTime>[];
  for (final offset in offsets) {
    final instant = DateTime.fromMillisecondsSinceEpoch(
      wallMillis - offset,
      isUtc: true,
    );
    final local = tz.TZDateTime.from(instant, location);
    if (local.year == nominal.year &&
        local.month == nominal.month &&
        local.day == nominal.day &&
        local.hour == nominal.hour &&
        local.minute == nominal.minute &&
        local.second == nominal.second &&
        local.millisecond == nominal.millisecond &&
        local.microsecond == nominal.microsecond) {
      matches.add(instant);
    }
  }
  matches.sort();
  return matches;
}

ResolvedOccurrence resolveNominalLocalOccurrence({
  required DateTime nominal,
  required String zoneName,
}) {
  final location = tz.getLocation(zoneName);
  final key = _localKey(nominal);
  final candidates = exactCandidates(nominal, location);
  if (candidates.isNotEmpty) {
    return ResolvedOccurrence(key, zoneName, candidates.first);
  }

  final wallMillis = DateTime.utc(
    nominal.year,
    nominal.month,
    nominal.day,
    nominal.hour,
    nominal.minute,
    nominal.second,
    nominal.millisecond,
  ).millisecondsSinceEpoch;
  for (final transition in location.transitionAt) {
    final before = location
        .lookupTimeZone(transition - 1)
        .timeZone
        .offset
        .inMilliseconds;
    final after = location
        .lookupTimeZone(transition)
        .timeZone
        .offset
        .inMilliseconds;
    if (after > before &&
        wallMillis >= transition + before &&
        wallMillis < transition + after) {
      final instant = DateTime.fromMillisecondsSinceEpoch(
        wallMillis - before,
        isUtc: true,
      );
      return ResolvedOccurrence(key, zoneName, instant);
    }
  }
  throw StateError('Local time is neither a known gap nor a valid time.');
}

String _localKey(DateTime local) =>
    '${local.year.toString().padLeft(4, '0')}-'
    '${local.month.toString().padLeft(2, '0')}-'
    '${local.day.toString().padLeft(2, '0')}T'
    '${local.hour.toString().padLeft(2, '0')}:'
    '${local.minute.toString().padLeft(2, '0')}:'
    '${local.second.toString().padLeft(2, '0')}';
