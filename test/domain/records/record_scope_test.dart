import 'dart:async';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/record_bus_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/records/record_bus.dart';
import 'package:dayspark/domain/records/record_change.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late RecordBus bus;
  late List<List<RecordChange>> batches;
  late StreamSubscription<List<RecordChange>> subscription;
  late int calendarId;

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    bus = RecordBus.of(db);
    batches = <List<RecordChange>>[];
    subscription = bus.changes.listen(batches.add);
    calendarId = await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(name: 'Test'));
  });

  tearDown(() async {
    await subscription.cancel();
    await db.close();
  });

  test('1 发布时序：body 内 0 批、run 返回后恰好 1 批（提交原子性由 2/3b/9/11 钉）', () async {
    await RecordScope.run(db, (tx) async {
      final id = await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(calendarId: calendarId, summary: 'commit'),
          );
      tx.applied(RecordType.todo, id);
      await settle();
      expect(batches, isEmpty);
    });
    await settle();

    expect(batches.length, 1);
    expect(batches.single.single, isA<RecordApplied>());
  });

  test('2 回滚零发布：body 抛异常 → 抛到调用方、行未写、0 批', () async {
    await expectLater(
      RecordScope.run(db, (tx) async {
        await db
            .into(db.todos)
            .insert(
              TodosCompanion.insert(calendarId: calendarId, summary: 'ghost'),
            );
        tx.applied(RecordType.todo, 1);
        throw StateError('boom');
      }),
      throwsA(isA<StateError>()),
    );
    await settle();

    expect(batches, isEmpty);
    final rows = await db.select(db.todos).get();
    expect(rows.where((t) => t.summary == 'ghost'), isEmpty);
  });

  test('3a 嵌套并入最外层：内层返回不发布，外层成功恰好 1 批', () async {
    await RecordScope.run(db, (outer) async {
      await RecordScope.run(db, (inner) async {
        final id = await db
            .into(db.todos)
            .insert(
              TodosCompanion.insert(calendarId: calendarId, summary: 'nested'),
            );
        inner.applied(RecordType.todo, id);
        await settle();
        expect(batches, isEmpty);
      });
      await settle();
      expect(batches, isEmpty);
    });
    await settle();

    expect(batches.length, 1);
    expect(batches.single.length, 1);
  });

  test('3b 内层抛 → 外层回滚 → 0 批', () async {
    await expectLater(
      RecordScope.run(db, (outer) async {
        outer.applied(RecordType.todo, 42);
        await RecordScope.run(db, (inner) async {
          await db
              .into(db.todos)
              .insert(
                TodosCompanion.insert(
                  calendarId: calendarId,
                  summary: 'nested ghost',
                ),
              );
          inner.applied(RecordType.todo, 43);
          throw StateError('inner boom');
        });
      }),
      throwsA(isA<StateError>()),
    );
    await settle();

    expect(batches, isEmpty);
    expect(await db.select(db.todos).get(), isEmpty);
  });

  test('4a applied 携带 previousReference：updateTodo 改 dueDate', () async {
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    final oldDue = DateTime(2026, 3, 1, 9);
    final newDue = DateTime(2026, 3, 2, 9);
    final id = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'reschedule',
            dueDate: Value(oldDue),
          ),
        );

    await container.read(updateTodoProvider)(id, TodosCompanion(dueDate: Value(newDue)));
    await settle();

    expect(batches.length, 1);
    final change = batches.single.single;
    expect(change, isA<RecordApplied>());
    expect(change.type, RecordType.todo);
    expect(change.localId, id);
    expect((change as RecordApplied).previousReference, oldDue);
    final row = await (db.select(
      db.todos,
    )..where((t) => t.id.equals(id))).getSingle();
    expect(row.dueDate, newDue);
    final outbox = await db.select(db.syncOutbox).get();
    expect(outbox, hasLength(1));
    expect(outbox.single.op, 'upsert');
    expect(outbox.single.type, 'todo');
  });

  test('4b applied 无写前参考 → previousReference 为 null', () async {
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    final id = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'no due date',
          ),
        );

    await container.read(updateTodoProvider)(
      id,
      const TodosCompanion(summary: Value('renamed')),
    );
    await settle();

    expect(batches.length, 1);
    expect((batches.single.single as RecordApplied).previousReference, isNull);
  });

  test('5a removed 携带 reminderIds：硬删前的 reminder id 一个不少', () async {
    final id = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(calendarId: calendarId, summary: 'with alarms'),
        );
    final reminderIds = <int>[
      await db
          .into(db.reminders)
          .insert(
            RemindersCompanion.insert(
              parentType: 'todo',
              parentId: id,
              triggerTime: DateTime(2026, 3, 1, 8),
            ),
          ),
      await db
          .into(db.reminders)
          .insert(
            RemindersCompanion.insert(
              parentType: 'todo',
              parentId: id,
              triggerTime: DateTime(2026, 3, 1, 9),
            ),
          ),
    ];

    await RecordScope.run(db, (tx) async {
      await (db.delete(db.reminders)..where(
            (r) => r.parentType.equals('todo') & r.parentId.equals(id),
          ))
          .go();
      await (db.delete(db.todos)..where((t) => t.id.equals(id))).go();
      tx.removed(RecordType.todo, id, reminderIds: reminderIds);
      await settle();
      expect(batches, isEmpty);
    });
    await settle();

    expect(batches.length, 1);
    final change = batches.single.single;
    expect(change, isA<RecordRemoved>());
    expect(change.localId, id);
    expect((change as RecordRemoved).reminderIds, reminderIds);
    final row = await (db.select(
      db.todos,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    expect(row, isNull);
  });

  test('5b removed 无提醒行 → 空列表（不是 null）', () async {
    final id = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(calendarId: calendarId, summary: 'no alarms'),
        );

    await RecordScope.run(db, (tx) async {
      await (db.delete(db.todos)..where((t) => t.id.equals(id))).go();
      tx.removed(RecordType.todo, id, reminderIds: const []);
      await settle();
      expect(batches, isEmpty);
    });
    await settle();

    final change = batches.single.single as RecordRemoved;
    expect(change.reminderIds, isA<List<int>>());
    expect(change.reminderIds, isEmpty);
  });

  test('8 recordBusProvider 暴露的正是该 DB 的总线', () async {
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    final exposed = container.read(recordBusProvider);
    expect(exposed, same(bus));
    final seen = <List<RecordChange>>[];
    final subscription = exposed.changes.listen(seen.add);
    addTearDown(subscription.cancel);

    await RecordScope.run(db, (tx) async {
      final id = await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(calendarId: calendarId, summary: 'bridge'),
          );
      tx.applied(RecordType.todo, id, previousReference: null);
    });
    await settle();

    expect(seen, hasLength(1));
    expect(seen.single.single, isA<RecordApplied>());
    expect(batches, hasLength(1));
  });

  group('Fix R1 —— 外来事务 fail-fast 与提交边界', () {
    test('9 外来 db.transaction 内调用 run → 抛 StateError，且外层回滚零发布', () async {
      await expectLater(
        db.transaction(() async {
          await db
              .into(db.todos)
              .insert(
                TodosCompanion.insert(
                  calendarId: calendarId,
                  summary: 'outer ghost',
                ),
              );
          await RecordScope.run(db, (tx) async {
            tx.applied(RecordType.todo, 1, previousReference: null);
          });
        }),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('RecordScope.run'), contains('db.transaction')),
          ),
        ),
      );
      await settle();

      expect(batches, isEmpty);
      expect(await db.select(db.todos).get(), isEmpty);
    });

    test('10 机制钉住：drift 事务 zone 键顶层为 null、事务内非 null 且是 drift 连接用户', () async {
      expect(Zone.current[#DatabaseConnectionUser], isNull);

      await db.transaction(() async {
        final user = Zone.current[#DatabaseConnectionUser];
        expect(user, isNotNull);
        expect(user, isA<DatabaseConnectionUser>());
        await expectLater(
          RecordScope.run(db, (tx) async {}),
          throwsA(isA<StateError>()),
        );
      });
    });

    test('11 送达可见性：事件到达时该行已提交可读（不构成"提交后才送达"的证明，见 12）', () async {
      const preallocatedId = 4242;
      final delivered = Completer<int?>();
      final seen = bus.changes.listen((batch) async {
        final change = batch.single;
        final row = await (db.select(
          db.todos,
        )..where((t) => t.id.equals(change.localId))).getSingleOrNull();
        if (!delivered.isCompleted) delivered.complete(row?.id);
      });
      addTearDown(seen.cancel);

      await RecordScope.run(db, (tx) async {
        tx.applied(RecordType.todo, preallocatedId, previousReference: null);
        await db
            .into(db.todos)
            .insert(
              TodosCompanion.insert(
                id: const Value(preallocatedId),
                calendarId: calendarId,
                summary: 'registered first',
              ),
            );
        await settle();
        expect(batches, isEmpty);
      });
      await settle();

      expect(
        await delivered.future.timeout(const Duration(seconds: 5)),
        preallocatedId,
      );
      expect(batches, hasLength(1));
    });
  });

  group('Fix R2 —— 发布自检与 scope 关闭态', () {
    test('12 发布自检：在 drift 事务内 publish → AssertionError，且零送达', () async {
      await expectLater(
        db.transaction(() async {
          bus.publish(<RecordChange>[
            const RecordApplied(RecordType.todo, 1, previousReference: null),
          ]);
        }),
        throwsA(isA<AssertionError>()),
      );
      await settle();

      expect(batches, isEmpty);
    });

    test('13 scope 关闭后登记必响亮：泄漏 tx 出 run 再登记 → StateError', () async {
      late RecordScope leaked;
      await RecordScope.run(db, (tx) async {
        leaked = tx;
      });
      await settle();

      expect(
        () => leaked.applied(RecordType.todo, 1, previousReference: null),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('run 的 body 内'),
          ),
        ),
      );
      expect(
        () => leaked.removed(RecordType.todo, 1, reminderIds: const <int>[]),
        throwsA(isA<StateError>()),
      );
      await settle();

      expect(batches, isEmpty);
    });

    test('14 body 内 fire-and-forget 迟到登记 → StateError 而非静默漏发', () async {
      final bodyReturned = Completer<void>();
      Object? lateError;
      await RecordScope.run(db, (tx) async {
        unawaited(
          bodyReturned.future.then((_) {
            try {
              tx.applied(RecordType.todo, 1, previousReference: null);
            } catch (error) {
              lateError = error;
            }
          }),
        );
      });
      bodyReturned.complete();
      await settle();

      expect(lateError, isA<StateError>());
      expect(batches, isEmpty);
    });
  });

  test('6 bulkChanged 一条粗粒度事件：localId 0 + reason 正确', () {
    const change = RecordsBulkChanged(RecordType.todo, reason: 'identity-reset');

    expect(change, isA<RecordChange>());
    expect(change.type, RecordType.todo);
    expect(change.localId, 0);
    expect(change.reason, 'identity-reset');
  });
}
