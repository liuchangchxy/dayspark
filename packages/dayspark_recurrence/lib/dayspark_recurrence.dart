import 'package:rrule/rrule.dart' as rrule;
import 'package:timezone/timezone.dart' as tz;

part 'src/engine.dart';
part 'src/identity.dart';
part 'src/model.dart';
part 'src/rrule_validator.dart';
part 'src/resolver.dart';

bool isOccurrenceValidForSpec(RecurrenceSpec spec, String occurrenceId) {
  final id = OccurrenceId.parse(occurrenceId);
  if (id.timeZone.id != spec.timeZone ||
      id.nominal.valueType != spec.anchor.valueType) {
    return false;
  }
  final RecurrenceWindow window;
  if (id.nominal case final LocalDate date) {
    window = LocalDateWindow(
      startInclusive: date,
      endExclusive: date.addDays(1),
    );
  } else {
    final nominal = id.nominal as LocalDateTime;
    final candidate = DateTime.utc(
      nominal.year,
      nominal.month,
      nominal.day,
      nominal.hour,
      nominal.minute,
      nominal.second,
    );
    window = InstantWindow(
      startInclusive: candidate.subtract(const Duration(days: 2)),
      endExclusive: candidate.add(const Duration(days: 3)),
    );
  }
  return const RecurrenceEngine()
      .expand(spec, window: window, limit: 10000)
      .any((occurrence) => occurrence.occurrenceId == id);
}
