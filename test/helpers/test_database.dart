import 'package:drift/native.dart';
import 'package:calendar_todo_app/data/local/database/app_database.dart';

/// Creates an in-memory AppDatabase for use in tests.
AppDatabase createTestDatabase() {
  return AppDatabase.forTesting(NativeDatabase.memory());
}
