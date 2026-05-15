import 'dart:io';

import 'package:drift/native.dart';

import 'app_database.dart';

/// Opens a database at [dbPath] using a pure-Dart SQLite connection (no
/// Flutter dependency). Used by the CLI (`bin/dayspark.dart`).
///
/// The directory must already exist. WAL and foreign keys are enabled.
AppDatabase openDatabaseFile(String dbPath) {
  final db = NativeDatabase(File(dbPath));
  return AppDatabase.forExecutor(db);
}
