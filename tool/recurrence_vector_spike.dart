import 'dart:io';

import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'recurrence_tz_probe.dart';

void main() {
  tzdata.initializeTimeZones();
  stdout.writeln(
    'tz.local=${tz.local.name} UTC-name=${tz.getLocation('UTC').name} '
    'Etc/UTC-name=${tz.getLocation('Etc/UTC').name}',
  );
  for (final (local, zone) in <(DateTime, String)>[
    (DateTime(2026, 3, 8, 2, 30), 'America/New_York'),
    (DateTime(2026, 11, 1, 1, 30), 'America/New_York'),
    (DateTime(2026, 10, 5, 9), 'Asia/Shanghai'),
  ]) {
    final occurrence = resolveNominalLocalOccurrence(
      nominal: local,
      zoneName: zone,
    );
    stdout.writeln(
      '${occurrence.occurrenceId}|${occurrence.instant.toIso8601String()}',
    );
  }
}
