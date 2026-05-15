import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

/// Opens a Drift database connection using Flutter's native SQLite plugin.
///
/// This function has a transitive dependency on `dart:ui` via `drift_flutter`,
/// so it must NOT be imported by the CLI (`bin/dayspark.dart`).
/// The CLI uses [AppDatabase.forFile] instead, which creates a pure-Dart
/// connection via [NativeDatabase].
QueryExecutor openFlutterDatabase() {
  return driftDatabase(
    name: 'calendar_todo',
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.js'),
    ),
  );
}
