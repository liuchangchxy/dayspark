import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/infrastructure/platform/widget_command.dart';

import '../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late int calId;

  setUp(() async {
    db = createTestDatabase();
    calId = await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(name: 'Test'));
  });

  tearDown(() async {
    await db.close();
  });

  Future<Todo> insertTodo({
    required String summary,
    String? syncId,
    String? rrule,
    String? recurrenceRule,
    String status = 'NEEDS-ACTION',
    DateTime? deletedAt,
  }) async {
    final id = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calId,
            summary: summary,
            syncId: syncId != null ? Value(syncId) : const Value.absent(),
            rrule: rrule != null ? Value(rrule) : const Value.absent(),
            recurrenceRule:
                recurrenceRule != null
                    ? Value(recurrenceRule)
                    : const Value.absent(),
            status: Value(status),
            deletedAt:
                deletedAt != null ? Value(deletedAt) : const Value.absent(),
          ),
        );
    return (db.select(db.todos)..where((t) => t.id.equals(id))).getSingle();
  }

  group('WidgetCommand fixtures and serialization', () {
    test('parses widget_command_v1_todo fixture', () {
      final jsonStr = File(
        'test/fixtures/widget/widget_command_v1_todo.json',
      ).readAsStringSync();
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final command = WidgetCommand.fromJson(map);

      expect(command.version, 1);
      expect(command.commandId, 'a1b2c3d4-e5f6-7890-abcd-ef1234567890');
      expect(command.action, 'complete');
      expect(command.target, 'todo');
      expect(command.todoId, 11);
      expect(command.todoSyncId, 'todo_sync_11');
      expect(command.occurrenceId, isNull);
      expect(command.sourceAllocationId, isNull);
      expect(command.at, DateTime.utc(2026, 10, 7, 14, 30));

      final serialized = command.toJson();
      expect(serialized['commandId'], command.commandId);
      expect(serialized['target'], 'todo');
      expect(serialized['todoId'], 11);
    });

    test('parses widget_command_v1_task_instance fixture', () {
      final jsonStr = File(
        'test/fixtures/widget/widget_command_v1_task_instance.json',
      ).readAsStringSync();
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final command = WidgetCommand.fromJson(map);

      expect(command.version, 1);
      expect(command.commandId, 'b2c3d4e5-f6a7-8901-bcde-f12345678901');
      expect(command.action, 'complete');
      expect(command.target, 'taskInstance');
      expect(command.todoId, 12);
      expect(command.todoSyncId, 'todo_sync_12');
      expect(command.occurrenceId, '2026-10-07T09:00:00.000Z');
      expect(command.sourceAllocationId, 'alloc_202');
    });

    test('rejects malformed command JSON', () {
      expect(
        () => WidgetCommand.fromJson({'action': 'complete'}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => WidgetCommand.fromJson({
          'commandId': '123',
          'action': 42,
          'target': 'todo',
          'todoId': 1,
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('executeWidgetCommand: todo target', () {
    test('executes toggleTodo and succeeds on pending non-recurring todo', () async {
      final todo = await insertTodo(
        summary: 'Non-recurring',
        syncId: 'sync_todo_1',
      );

      var toggledId = -1;
      var toggledComplete = false;
      String? toggledOccurrence;

      final command = WidgetCommand(
        commandId: 'cmd_1',
        action: 'complete',
        target: 'todo',
        todoId: todo.id,
        todoSyncId: todo.syncId,
        at: DateTime.utc(2026, 10, 7, 10),
      );

      final result = await executeWidgetCommand(
        db,
        command,
        toggleTodo: ({required id, required isCompleted, occurrenceId}) async {
          toggledId = id;
          toggledComplete = isCompleted;
          toggledOccurrence = occurrenceId;
        },
      );

      expect(result, CommandExecutionResult.success);
      expect(toggledId, todo.id);
      expect(toggledComplete, isTrue);
      expect(toggledOccurrence, isNull);
    });

    test('semantic idempotency: already completed todo returns alreadyApplied', () async {
      final todo = await insertTodo(
        summary: 'Completed todo',
        status: 'COMPLETED',
        syncId: 'sync_todo_done',
      );

      var called = false;
      final command = WidgetCommand(
        commandId: 'cmd_2',
        action: 'complete',
        target: 'todo',
        todoId: todo.id,
        todoSyncId: todo.syncId,
        at: DateTime.utc(2026, 10, 7, 10),
      );

      final result = await executeWidgetCommand(
        db,
        command,
        toggleTodo: ({required id, required isCompleted, occurrenceId}) async {
          called = true;
        },
      );

      expect(result, CommandExecutionResult.alreadyApplied);
      expect(called, isFalse);
    });

    test('fails closed on non-existent or deleted todo', () async {
      final deleted = await insertTodo(
        summary: 'Deleted',
        deletedAt: DateTime.utc(2026, 10, 6),
      );

      final commandMissing = WidgetCommand(
        commandId: 'cmd_missing',
        action: 'complete',
        target: 'todo',
        todoId: 999999,
        at: DateTime.utc(2026, 10, 7, 10),
      );
      final commandDeleted = WidgetCommand(
        commandId: 'cmd_del',
        action: 'complete',
        target: 'todo',
        todoId: deleted.id,
        at: DateTime.utc(2026, 10, 7, 10),
      );

      final res1 = await executeWidgetCommand(
        db,
        commandMissing,
        toggleTodo: ({required id, required isCompleted, occurrenceId}) async {},
      );
      final res2 = await executeWidgetCommand(
        db,
        commandDeleted,
        toggleTodo: ({required id, required isCompleted, occurrenceId}) async {},
      );

      expect(res1, CommandExecutionResult.terminalInvalid);
      expect(res2, CommandExecutionResult.terminalInvalid);
    });

    test('fails closed if syncId does not match (ruling O identity check)', () async {
      final todo = await insertTodo(
        summary: 'Valid todo',
        syncId: 'sync_real',
      );

      final commandMismatched = WidgetCommand(
        commandId: 'cmd_mismatch',
        action: 'complete',
        target: 'todo',
        todoId: todo.id,
        todoSyncId: 'sync_fake_mismatched',
        at: DateTime.utc(2026, 10, 7, 10),
      );

      final res = await executeWidgetCommand(
        db,
        commandMismatched,
        toggleTodo: ({required id, required isCompleted, occurrenceId}) async {},
      );

      expect(res, CommandExecutionResult.terminalInvalid);
    });

    test('fails closed if recurring todo targeted without occurrenceId (Ruling I)', () async {
      final recurringTodo = await insertTodo(
        summary: 'Recurring daily',
        rrule: 'FREQ=DAILY',
      );

      final command = WidgetCommand(
        commandId: 'cmd_rec_no_occ',
        action: 'complete',
        target: 'todo',
        todoId: recurringTodo.id,
        occurrenceId: null, // missing occurrenceId!
        at: DateTime.utc(2026, 10, 7, 10),
      );

      final res = await executeWidgetCommand(
        db,
        command,
        toggleTodo: ({required id, required isCompleted, occurrenceId}) async {},
      );

      expect(res, CommandExecutionResult.terminalInvalid);
    });
  });

  group('executeWidgetCommand: taskInstance target', () {
    test('succeeds with valid taskInstance and passes occurrenceId', () async {
      final todo = await insertTodo(
        summary: 'Recurring habit',
        syncId: 'sync_habit',
        rrule: 'FREQ=DAILY',
      );

      var toggledId = -1;
      var toggledOccurrence = '';

      final command = WidgetCommand(
        commandId: 'cmd_inst_1',
        action: 'complete',
        target: 'taskInstance',
        todoId: todo.id,
        todoSyncId: todo.syncId,
        occurrenceId: '2026-10-07T08:00:00.000Z',
        at: DateTime.utc(2026, 10, 7, 8, 30),
      );

      final res = await executeWidgetCommand(
        db,
        command,
        toggleTodo: ({required id, required isCompleted, occurrenceId}) async {
          toggledId = id;
          toggledOccurrence = occurrenceId ?? '';
        },
      );

      expect(res, CommandExecutionResult.success);
      expect(toggledId, todo.id);
      expect(toggledOccurrence, '2026-10-07T08:00:00.000Z');
    });

    test('fails closed if taskInstance command lacks occurrenceId', () async {
      final todo = await insertTodo(
        summary: 'Recurring habit',
        syncId: 'sync_habit',
        rrule: 'FREQ=DAILY',
      );

      final command = WidgetCommand(
        commandId: 'cmd_inst_bad',
        action: 'complete',
        target: 'taskInstance',
        todoId: todo.id,
        occurrenceId: null,
        at: DateTime.utc(2026, 10, 7, 8, 30),
      );

      final res = await executeWidgetCommand(
        db,
        command,
        toggleTodo: ({required id, required isCompleted, occurrenceId}) async {},
      );

      expect(res, CommandExecutionResult.terminalInvalid);
    });

    test('semantic idempotency: already completed instance state returns alreadyApplied', () async {
      final todo = await insertTodo(
        summary: 'Recurring habit',
        syncId: 'sync_habit_2',
        rrule: 'FREQ=DAILY',
      );

      // Record completed instance state in DB
      await db.into(db.taskInstanceStates).insert(
            TaskInstanceStatesCompanion.insert(
              syncId: 'state_habit_done',
              todoSyncId: todo.syncId!,
              occurrenceId: '2026-10-07T08:00:00.000Z',
              status: const Value('COMPLETED'),
              completedAt: Value(DateTime.utc(2026, 10, 7, 8, 15)),
            ),
          );

      var called = false;
      final command = WidgetCommand(
        commandId: 'cmd_inst_done',
        action: 'complete',
        target: 'taskInstance',
        todoId: todo.id,
        todoSyncId: todo.syncId,
        occurrenceId: '2026-10-07T08:00:00.000Z',
        at: DateTime.utc(2026, 10, 7, 8, 30),
      );

      final res = await executeWidgetCommand(
        db,
        command,
        toggleTodo: ({required id, required isCompleted, occurrenceId}) async {
          called = true;
        },
      );

      expect(res, CommandExecutionResult.alreadyApplied);
      expect(called, isFalse);
    });
  });

  group('consumeWidgetCommands: transport queue lifecycle', () {
    test('processes commands deterministically, acks terminals and keeps retryable', () async {
      final todo1 = await insertTodo(summary: 'Todo 1');
      final todo2 = await insertTodo(summary: 'Todo 2');

      final cmd1 = WidgetCommand(
        commandId: 'cmd_1',
        action: 'complete',
        target: 'todo',
        todoId: todo1.id,
        at: DateTime.utc(2026, 10, 7, 10, 0),
      );
      final cmd2 = WidgetCommand(
        commandId: 'cmd_2',
        action: 'complete',
        target: 'todo',
        todoId: todo2.id,
        at: DateTime.utc(2026, 10, 7, 10, 5),
      );
      final cmdInvalid = WidgetCommand(
        commandId: 'cmd_invalid',
        action: 'complete',
        target: 'todo',
        todoId: 999999, // missing -> terminalInvalid
        at: DateTime.utc(2026, 10, 7, 10, 2),
      );

      final transport = InMemoryWidgetCommandTransport();
      transport.pushCommand(cmd2);
      transport.pushCommand(cmdInvalid);
      transport.pushCommand(cmd1);

      final completedIds = <int>[];
      await consumeWidgetCommands(
        db: db,
        transport: transport,
        toggleTodo: ({required id, required isCompleted, occurrenceId}) async {
          completedIds.add(id);
        },
      );

      // Checked and executed in chronological order: cmd1 (10:00), cmdInvalid (10:02), cmd2 (10:05)
      expect(completedIds, [todo1.id, todo2.id]);
      // All terminal commands (success + terminalInvalid) are acknowledged from transport storage
      expect(transport.storage, isEmpty);
      expect((await transport.fetchPendingCommands()), isEmpty);
    });
  });
}
