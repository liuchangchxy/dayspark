import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/sync/sync_outbox.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';

final class TodoWriter {
  const TodoWriter._();

  static Future<void> updateTodo(
    AppDatabase db,
    RecordScope tx,
    int id,
    TodosCompanion data,
  ) async {
    final existing = await (db.select(
      db.todos,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    await (db.update(db.todos)..where((t) => t.id.equals(id))).write(data);
    await SyncOutbox.enqueueUpsert(db, RecordType.todo, id);
    tx.applied(RecordType.todo, id, previousReference: existing?.dueDate);
  }
}
