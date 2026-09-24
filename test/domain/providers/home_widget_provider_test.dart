import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/home_widget_provider.dart';
import 'package:dayspark/domain/providers/record_bus_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/domain/records/record_change.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:dayspark/infrastructure/platform/home_widget_service.dart';
import 'package:dayspark/infrastructure/platform/notification_service.dart';

import '../../helpers/test_database.dart';

class _MockNotificationService extends Mock implements NotificationService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(
      Reminder(
        id: 0,
        parentType: 'todo',
        parentId: 0,
        triggerTime: DateTime(2020),
        isTriggered: false,
      ),
    );
  });

  const channel = MethodChannel('home_widget');
  late Map<String, Object?> store;
  late AppDatabase testDb;
  late ProviderContainer container;
  late _MockNotificationService notifMock;
  late int calId;
  // One snapshot write per flush: counting them counts refreshes, not the
  // fan-out of platform-channel calls inside a single refresh.
  late int flushes;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'app_locale': 'en'});
    store = <String, Object?>{};
    flushes = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = (call.arguments as Map).cast<String, dynamic>();
          switch (call.method) {
            case 'getWidgetData':
              return store[args['id'] as String];
            case 'saveWidgetData':
              if (args['id'] == HomeWidgetService.snapshotKey) flushes++;
              store[args['id'] as String] = args['data'];
              return true;
            case 'updateWidget':
            case 'setAppGroupId':
              return true;
            default:
              return null;
          }
        });

    notifMock = _MockNotificationService();
    when(() => notifMock.cancel(any())).thenAnswer((_) async {});
    when(
      () => notifMock.scheduleFromReminder(
        any(),
        eventReminderTitle: any(named: 'eventReminderTitle'),
        todoReminderTitle: any(named: 'todoReminderTitle'),
        eventReminderBody: any(named: 'eventReminderBody'),
        todoReminderBody: any(named: 'todoReminderBody'),
      ),
    ).thenAnswer((_) async {});

    testDb = createTestDatabase();
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(testDb),
        notificationServiceProvider.overrideWithValue(notifMock),
      ],
    );
    calId = await testDb
        .into(testDb.calendars)
        .insert(CalendarsCompanion.insert(name: 'Test'));
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    container.dispose();
    await testDb.close();
  });

  Future<int> insertTodo({String summary = 'Widget todo'}) {
    return testDb
        .into(testDb.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calId,
            summary: summary,
            status: const Value('NEEDS-ACTION'),
          ),
        );
  }

  String storedSnapshot() =>
      store[HomeWidgetService.snapshotKey] as String? ?? '';

  test(
    'flush consumes pendingTaps via toggle path, clears channel, lands sync op',
    () async {
      final todoId = await insertTodo();
      store[HomeWidgetService.snapshotKey] = jsonEncode({
        'version': 2,
        'generatedAt': '2026-09-24T00:00:00.000Z',
        'pendingTaps': [
          {
            'todoId': todoId,
            'action': 'complete',
            'at': '2026-09-24T01:02:03.000Z',
          },
        ],
      });

      await container.read(updateHomeWidgetProvider)();

      final todo =
          await (testDb.select(testDb.todos)
                ..where((t) => t.id.equals(todoId)))
              .getSingle();
      expect(todo.status, 'COMPLETED');

      final outbox = await testDb.select(testDb.syncOutbox).get();
      expect(outbox, hasLength(1));
      expect(outbox.single.type, 'todo');
      expect(outbox.single.op, 'upsert');

      expect(HomeWidgetService.decodePendingTaps(storedSnapshot()), isEmpty);
      final written =
          jsonDecode(storedSnapshot()) as Map<String, dynamic>;
      expect(written['version'], 2);
    },
  );

  test('flush without a consumer preserves native-appended pendingTaps', () async {
    final todoId = await insertTodo();
    store[HomeWidgetService.snapshotKey] = jsonEncode({
      'version': 2,
      'pendingTaps': [
        {
          'todoId': todoId,
          'action': 'complete',
          'at': '2026-09-24T01:02:03.000Z',
        },
      ],
    });

    await HomeWidgetService.updateWidget(testDb);

    final taps = HomeWidgetService.decodePendingTaps(storedSnapshot());
    expect(taps, hasLength(1));
    expect(taps.single.todoId, todoId);

    final todo =
        await (testDb.select(testDb.todos)..where((t) => t.id.equals(todoId)))
            .getSingle();
    expect(todo.status, 'NEEDS-ACTION');
    expect(await testDb.select(testDb.syncOutbox).get(), isEmpty);
  });

  test('write → native append → consume → clear full cycle', () async {
    final todoId = await insertTodo();

    // 1. App flush writes an empty channel.
    await container.read(updateHomeWidgetProvider)();
    expect(HomeWidgetService.decodePendingTaps(storedSnapshot()), isEmpty);

    // 2. Native appends a tap onto the stored snapshot (last-wins queue).
    final stored = jsonDecode(storedSnapshot()) as Map<String, dynamic>;
    (stored['pendingTaps'] as List).add({
      'todoId': todoId,
      'action': 'complete',
      'at': '2026-09-24T05:00:00.000Z',
    });
    store[HomeWidgetService.snapshotKey] = jsonEncode(stored);
    expect(HomeWidgetService.decodePendingTaps(storedSnapshot()), hasLength(1));

    // 3. Next app flush consumes the tap through the complete path…
    await container.read(updateHomeWidgetProvider)();

    // …and clears the channel for the next native append.
    expect(HomeWidgetService.decodePendingTaps(storedSnapshot()), isEmpty);
    final todo =
        await (testDb.select(testDb.todos)..where((t) => t.id.equals(todoId)))
            .getSingle();
    expect(todo.status, 'COMPLETED');
    expect(await testDb.select(testDb.syncOutbox).get(), hasLength(1));
  });

  test(
    'bus event drives a flush after tableUpdates is gone; one batch = one flush',
    () async {
      await insertTodo();
      container.read(homeWidgetAutoRefreshProvider);
      final bus = container.read(recordBusProvider);

      // 等到条件成立（全套件并行时事件循环会被挤），再多让几轮以捕捉"多余的一次"。
      Future<void> waitUntil(bool Function() condition) async {
        for (var i = 0; i < 200 && !condition(); i++) {
          await pumpEventQueue(times: 5);
        }
        await pumpEventQueue(times: 50);
      }

      // 1. A raw drift write no longer drives a refresh: tableUpdates is gone.
      final beforeRawWrite = flushes;
      await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'raw write',
              status: const Value('NEEDS-ACTION'),
            ),
          );
      await waitUntil(() => false);
      expect(
        flushes,
        beforeRawWrite,
        reason: '驱动源已换成总线：裸 DB 写不再触发（这也是 resume/冷启动兜底存在的理由）',
      );

      // 2. A batch of three changes flushes exactly once.
      final beforeBatchOfThree = flushes;
      bus.publish([
        RecordApplied(RecordType.todo, 1, previousReference: null),
        RecordApplied(
          RecordType.todo,
          2,
          previousReference: DateTime(2026),
        ),
        RecordApplied(RecordType.event, 3, previousReference: null),
      ]);
      await waitUntil(() => flushes > beforeBatchOfThree);
      expect(flushes - beforeBatchOfThree, 1, reason: '一次批 = 一次 refresh');

      // 3. Batch size is irrelevant: one change still flushes exactly once.
      final beforeBatchOfOne = flushes;
      bus.publish([
        RecordApplied(RecordType.todo, 1, previousReference: null),
      ]);
      await waitUntil(() => flushes > beforeBatchOfOne);
      expect(
        flushes - beforeBatchOfOne,
        1,
        reason: '批次内容不影响刷新次数',
      );
    },
  );
}
