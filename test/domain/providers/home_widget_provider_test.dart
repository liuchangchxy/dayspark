import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
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
        serverRev: 0,
      ),
    );
  });

  const channel = MethodChannel('home_widget');
  const commandChannel = MethodChannel('com.dayspark.app/widget_commands');
  late Map<String, Object?> store;
  late AppDatabase testDb;
  late ProviderContainer container;
  late _MockNotificationService notifMock;
  late int calId;
  // One snapshot write per flush: counting them counts refreshes, not the
  // fan-out of platform-channel calls inside a single refresh.
  late int flushes;
  late List<MethodCall> methodCalls;
  late Map<String, String> pendingCommands;
  late bool hasWidgets;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({'app_locale': 'en'});
    store = <String, Object?>{};
    flushes = 0;
    methodCalls = <MethodCall>[];
    pendingCommands = <String, String>{};
    hasWidgets = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          methodCalls.add(call);
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(commandChannel, (call) async {
          switch (call.method) {
            case 'getPendingCommands':
              return pendingCommands.entries
                  .map(
                    (entry) => <String, String>{
                      'commandId': entry.key,
                      'raw': entry.value,
                    },
                  )
                  .toList();
            case 'ackCommand':
              pendingCommands.remove((call.arguments as Map)['commandId']);
              return true;
            case 'hasWidgets':
              return hasWidgets;
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
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(commandChannel, null);
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

  test('unsupported platform skips all HomeWidget channel calls', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    await HomeWidgetService.updateWidget(testDb);
    await HomeWidgetService.refreshNativeWidgets();

    expect(methodCalls, isEmpty);
    expect(flushes, 0);
  });

  test('iOS platform keeps native widget refresh path reachable', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await HomeWidgetService.refreshNativeWidgets();

    expect(methodCalls.map((call) => call.method), [
      'updateWidget',
      'updateWidget',
      'updateWidget',
    ]);
    expect(
      methodCalls.map((call) => (call.arguments as Map)['ios']).toList(),
      HomeWidgetService.appleWidgetKinds,
    );
  });

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

      final todo = await (testDb.select(
        testDb.todos,
      )..where((t) => t.id.equals(todoId))).getSingle();
      expect(todo.status, 'COMPLETED');

      final outbox = await testDb.select(testDb.syncOutbox).get();
      expect(outbox, hasLength(1));
      expect(outbox.single.type, 'todo');
      expect(outbox.single.op, 'upsert');

      expect(HomeWidgetService.decodePendingTaps(storedSnapshot()), isEmpty);
      final written = jsonDecode(storedSnapshot()) as Map<String, dynamic>;
      expect(written['version'], 5);
      expect(written.containsKey('action'), isTrue);
      expect(written.containsKey('todos'), isTrue);
    },
  );

  test('a legacy v4 blob is replaced by a v5 snapshot', () async {
    final todoId = await insertTodo();
    store[HomeWidgetService.snapshotKey] = jsonEncode({
      'version': 4,
      'pendingTaps': [
        {
          'todoId': todoId,
          'action': 'complete',
          'at': '2026-09-24T01:02:03.000Z',
        },
      ],
    });

    await HomeWidgetService.updateWidget(testDb);

    final written = jsonDecode(storedSnapshot()) as Map<String, dynamic>;
    expect(written['version'], 5);
    expect(written.containsKey('pendingTaps'), isFalse);
    expect(written['today'], isA<String>());

    final todo = await (testDb.select(
      testDb.todos,
    )..where((t) => t.id.equals(todoId))).getSingle();
    expect(todo.status, 'NEEDS-ACTION');
    expect(await testDb.select(testDb.syncOutbox).get(), isEmpty);
  });

  test('write → native command → consume → ack full cycle', () async {
    final todoId = await insertTodo();

    // 1. App flush writes v5 and leaves the command queue empty.
    await container.read(updateHomeWidgetProvider)();
    expect(pendingCommands, isEmpty);
    final stored = jsonDecode(storedSnapshot()) as Map<String, dynamic>;
    expect(stored['version'], 5);

    // 2. Native writes an independent command, not a snapshot mutation.
    pendingCommands['cmd_1'] = jsonEncode({
      'version': 1,
      'commandId': 'cmd_1',
      'action': 'complete',
      'target': 'todo',
      'todoId': todoId,
      'at': '2026-09-24T05:00:00.000Z',
    });
    final beforeCommand = storedSnapshot();

    // 3. Next app flush consumes it through the complete path and acks it.
    await container.read(updateHomeWidgetProvider)();

    expect(pendingCommands, isEmpty);
    final todo = await (testDb.select(
      testDb.todos,
    )..where((t) => t.id.equals(todoId))).getSingle();
    expect(todo.status, 'COMPLETED');
    expect(await testDb.select(testDb.syncOutbox).get(), hasLength(1));

    // The command contract never rewrites through the snapshot channel.
    final afterCommand = jsonDecode(storedSnapshot()) as Map<String, dynamic>;
    expect(afterCommand['version'], 5);
    expect(beforeCommand, isNot(equals(storedSnapshot())));
  });

  test(
    'bus event drives a flush after tableUpdates is gone; one batch = one flush',
    () async {
      await insertTodo();
      container.read(homeWidgetAutoRefreshProvider);
      final bus = container.read(recordBusProvider);

      // The refresh is deliberately deferred (coalescing + IME hold-off), so
      // poll for the flush instead of sleeping a fixed guess: on a loaded
      // runner a fixed sleep can observe zero flushes. The trailing window is
      // one full debounce, so an *extra* flush would still be caught.
      Future<void> settleRefresh({int expectedGain = 1, int before = 0}) async {
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while (flushes - before < expectedGain &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        await Future<void>.delayed(const Duration(milliseconds: 600));
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
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(
        flushes,
        beforeRawWrite,
        reason: '驱动源已换成总线：裸 DB 写不再触发（这也是 resume/冷启动兜底存在的理由）',
      );

      // 2. A batch of three changes flushes exactly once.
      final beforeBatchOfThree = flushes;
      bus.publish([
        RecordApplied(RecordType.todo, 1, previousReference: null),
        RecordApplied(RecordType.todo, 2, previousReference: DateTime(2026)),
        RecordApplied(RecordType.event, 3, previousReference: null),
      ]);
      await settleRefresh(before: beforeBatchOfThree);
      expect(flushes - beforeBatchOfThree, 1, reason: '一次批 = 一次 refresh');

      // 3. Batch size is irrelevant: one change still flushes exactly once.
      final beforeBatchOfOne = flushes;
      bus.publish([RecordApplied(RecordType.todo, 1, previousReference: null)]);
      await settleRefresh(before: beforeBatchOfOne);
      expect(flushes - beforeBatchOfOne, 1, reason: '批次内容不影响刷新次数');

      // 4. A burst collapses: the refresh window absorbs every publish.
      final beforeBurst = flushes;
      for (var i = 0; i < 8; i++) {
        bus.publish([
          RecordApplied(RecordType.todo, i + 1, previousReference: null),
        ]);
      }
      await settleRefresh(before: beforeBurst);
      expect(
        flushes - beforeBurst,
        1,
        reason: '连续提交只允许一次快照重建，否则平台通道风暴会落在打字窗口里',
      );
    },
  );

  test('no widget instance: commands drain and the snapshot stays current', () async {
    hasWidgets = false;
    final todoId = await insertTodo();
    pendingCommands['cmd_1'] = jsonEncode({
      'version': 1,
      'commandId': 'cmd_1',
      'action': 'complete',
      'target': 'todo',
      'todoId': todoId,
      'at': '2026-09-24T05:00:00.000Z',
    });

    await container.read(updateHomeWidgetProvider)();

    final todo = await (testDb.select(
      testDb.todos,
    )..where((t) => t.id.equals(todoId))).getSingle();
    expect(todo.status, 'COMPLETED', reason: '队列里的用户动作不能因为没实例就丢');
    expect(pendingCommands, isEmpty, reason: '命令必须被确认，否则永远重试');
    // The blob must stay current: a widget pinned later reads it directly and
    // has no way to ask Dart to rebuild.
    expect(flushes, 1, reason: '零实例也要写出可渲染的快照');
    expect(
      methodCalls.map((call) => call.method),
      isNot(contains('updateWidget')),
      reason: '没有实例时广播没有接收者，省掉三段主线程重建',
    );
  });

  test('a consumed legacy tap is cleared even with no instance', () async {
    hasWidgets = false;
    final todoId = await insertTodo();
    store[HomeWidgetService.snapshotKey] = jsonEncode({
      'version': 4,
      'pendingTaps': [
        {
          'todoId': todoId,
          'action': 'complete',
          'at': '2026-09-24T05:00:00.000Z',
        },
      ],
    });

    await container.read(updateHomeWidgetProvider)();

    final todo = await (testDb.select(
      testDb.todos,
    )..where((t) => t.id.equals(todoId))).getSingle();
    expect(todo.status, 'COMPLETED', reason: '旧快照里的点击仍要执行');
    final stored = jsonDecode(store[HomeWidgetService.snapshotKey]! as String)
        as Map<String, dynamic>;
    expect(stored.containsKey('pendingTaps'), isFalse, reason: '消费后必须清除');
  });
}
