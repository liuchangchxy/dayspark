part of '../dayspark_recurrence.dart';

int? _cachedTimezoneHorizonYear;

final class RecurrenceExpansionException implements Exception {
  const RecurrenceExpansionException(this.message);

  final String message;

  @override
  String toString() => 'RecurrenceExpansionException: $message';
}

final class RecurrenceEngine {
  const RecurrenceEngine();

  static const maximumOccurrencesPerExpansion = 10000;
  static const maximumCalendarPeriodsToScan = 100000;
  static const _offsetSafetyMargin = Duration(days: 2);

  List<RecurrenceOccurrence> expand(
    RecurrenceSpec spec, {
    required RecurrenceWindow window,
    required int limit,
  }) {
    if (limit < 1 || limit > maximumOccurrencesPerExpansion) {
      throw ArgumentError.value(
        limit,
        'limit',
        'Must be between 1 and $maximumOccurrencesPerExpansion.',
      );
    }
    final isDate = spec.anchor.valueType == RecurrenceValueType.date;
    if ((isDate && window is! LocalDateWindow) ||
        (!isDate && window is! InstantWindow)) {
      throw ArgumentError('Window type must match the recurrence anchor.');
    }

    final location = isDate ? null : _getLocation(spec.timeZone);
    final start = spec.anchor.value._calendarCandidate;
    final candidateBounds = _candidateBounds(
      spec.anchor.value,
      window,
      location,
    );
    var before = candidateBounds.before;
    if (spec.anchor.valueType == RecurrenceValueType.dateTime &&
        spec.rule.until != null) {
      final untilLocal = _calendarFields(
        tz.TZDateTime.from(spec.rule.until!, location!),
      ).add(_offsetSafetyMargin);
      if (untilLocal.isBefore(before)) before = untilLocal;
    }
    if (before.isBefore(start) ||
        (candidateBounds.after != null &&
            !candidateBounds.after!.isBefore(before))) {
      return const [];
    }
    if (!isDate && before.year > _timezoneHorizonYear()) {
      throw const RecurrenceExpansionException(
        'The query exceeds the future transition horizon in the bundled timezone database.',
      );
    }
    _checkScanDistance(start, candidateBounds.after, before, spec.rule);

    final instances = spec.rule.toLibraryRule().getInstances(
      start: start,
      after: candidateBounds.after,
      before: before,
      includeBefore: false,
    );
    final result = <RecurrenceOccurrence>[];
    var examined = 0;
    for (final candidate in instances) {
      examined++;
      if (examined > maximumOccurrencesPerExpansion + 4) {
        throw const RecurrenceExpansionException(
          'Candidate safety limit exceeded.',
        );
      }
      final nominal = isDate
          ? LocalDate(candidate.year, candidate.month, candidate.day)
          : LocalDateTime(
              candidate.year,
              candidate.month,
              candidate.day,
              candidate.hour,
              candidate.minute,
              candidate.second,
            );
      final resolvedInstant = switch (nominal) {
        LocalDateTime value => _resolveLocalDateTime(value, location!),
        LocalDate() => null,
      };
      if (!_insideWindow(nominal, resolvedInstant, window)) continue;
      if (!_beforeUntil(spec.rule, nominal, resolvedInstant)) continue;
      result.add(
        RecurrenceOccurrence(
          nominal: nominal,
          occurrenceId: OccurrenceId.forNominal(nominal, spec.timeZone),
          resolvedInstant: resolvedInstant,
        ),
      );
      if (result.length > limit) {
        throw RecurrenceExpansionException(
          'Expansion exceeds the requested limit of $limit occurrences.',
        );
      }
    }
    return List.unmodifiable(result);
  }

  tz.Location _getLocation(String timeZone) {
    IanaTimeZone.validateSyntax(timeZone);
    if (!tz.timeZoneDatabase.isInitialized) {
      throw const RecurrenceRuleException(
        RecurrenceRuleErrorKind.invalid,
        'Timezone database is not initialized.',
      );
    }
    try {
      return tz.getLocation(timeZone);
    } on tz.LocationNotFoundException {
      throw RecurrenceRuleException(
        RecurrenceRuleErrorKind.invalid,
        'Unknown IANA timezone: $timeZone.',
      );
    } on StateError {
      throw const RecurrenceRuleException(
        RecurrenceRuleErrorKind.invalid,
        'Timezone database is not initialized.',
      );
    }
  }

  _CandidateBounds _candidateBounds(
    RecurrenceLocalValue anchor,
    RecurrenceWindow window,
    tz.Location? location,
  ) {
    if (window case final LocalDateWindow dateWindow) {
      final after = dateWindow.startInclusive.addDays(-1)._calendarCandidate;
      final before = dateWindow.endExclusive._calendarCandidate;
      return _CandidateBounds(
        after.isAfter(anchor._calendarCandidate) ? after : null,
        before,
      );
    }
    final instantWindow = window as InstantWindow;
    final localStart = _calendarFields(
      tz.TZDateTime.from(instantWindow.startInclusive, location!),
    );
    final localEnd = _calendarFields(
      tz.TZDateTime.from(instantWindow.endExclusive, location),
    );
    final after = localStart.subtract(_offsetSafetyMargin);
    final before = localEnd.add(_offsetSafetyMargin);
    final anchorFields = anchor._calendarCandidate;
    return _CandidateBounds(after.isAfter(anchorFields) ? after : null, before);
  }

  DateTime _calendarFields(DateTime value) => DateTime.utc(
    value.year,
    value.month,
    value.day,
    value.hour,
    value.minute,
    value.second,
  );

  int _timezoneHorizonYear() {
    final cached = _cachedTimezoneHorizonYear;
    if (cached != null) return cached;
    final counts = <int, int>{};
    for (final location in tz.timeZoneDatabase.locations.values) {
      if (location.transitionAt.isEmpty) continue;
      final last = location.transitionAt.last;
      if (last <= tz.minTime || last >= tz.maxTime) continue;
      final year = DateTime.fromMillisecondsSinceEpoch(last, isUtc: true).year;
      counts.update(year, (count) => count + 1, ifAbsent: () => 1);
    }
    if (counts.isEmpty) {
      throw const RecurrenceExpansionException(
        'Timezone database has no finite transition horizon.',
      );
    }
    final horizon = counts.entries.reduce((left, right) {
      if (left.value == right.value) {
        return left.key < right.key ? left : right;
      }
      return left.value > right.value ? left : right;
    }).key;
    _cachedTimezoneHorizonYear = horizon;
    return horizon;
  }

  void _checkScanDistance(
    DateTime start,
    DateTime? after,
    DateTime before,
    ValidatedRRule rule,
  ) {
    if (rule.count != null) return;
    final boundaries = after == null ? [before] : [after, before];
    final periods = boundaries
        .map(
          (boundary) => switch (rule.frequency) {
            'DAILY' => boundary.difference(start).inDays,
            'WEEKLY' => boundary.difference(start).inDays ~/ 7,
            'MONTHLY' =>
              (boundary.year - start.year) * 12 + boundary.month - start.month,
            'YEARLY' => boundary.year - start.year,
            _ => 0,
          },
        )
        .reduce((left, right) => left > right ? left : right);
    if (periods > 0 &&
        periods ~/ rule.interval > maximumCalendarPeriodsToScan) {
      throw const RecurrenceExpansionException(
        'Query range is too far from its anchor for a bounded expansion.',
      );
    }
  }

  bool _insideWindow(
    RecurrenceLocalValue nominal,
    DateTime? resolvedInstant,
    RecurrenceWindow window,
  ) => switch ((nominal, resolvedInstant, window)) {
    (LocalDate date, null, LocalDateWindow range) =>
      date.compareTo(range.startInclusive) >= 0 &&
          date.compareTo(range.endExclusive) < 0,
    (_, final DateTime instant, InstantWindow range) =>
      !instant.isBefore(range.startInclusive) &&
          instant.isBefore(range.endExclusive),
    _ => false,
  };

  bool _beforeUntil(
    ValidatedRRule rule,
    RecurrenceLocalValue nominal,
    DateTime? resolvedInstant,
  ) {
    if (rule.until == null) return true;
    if (rule.valueType == RecurrenceValueType.date) {
      return (nominal as LocalDate).compareTo(rule._untilDate!) <= 0;
    }
    return resolvedInstant != null && !resolvedInstant.isAfter(rule.until!);
  }
}

final class _CandidateBounds {
  const _CandidateBounds(this.after, this.before);

  final DateTime? after;
  final DateTime before;
}
