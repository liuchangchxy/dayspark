import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/infrastructure/platform/alarm_service.dart';

final class _FakeAlarmBackend implements AlarmBackend {
  int initCalls = 0;
  int stopAllCalls = 0;
  bool failInit = false;
  Completer<void>? initGate;
  Completer<void>? stopAllGate;
  final List<AlarmSettings> stored = <AlarmSettings>[];
  final List<int> setCalls = <int>[];

  @override
  Future<void> init() async {
    initCalls++;
    if (failInit) throw StateError('init failed');
    await initGate?.future;
  }

  @override
  Future<List<AlarmSettings>> alarms() async => List<AlarmSettings>.of(stored);

  @override
  Future<bool> set(AlarmSettings settings) async {
    setCalls.add(settings.id);
    stored
      ..removeWhere((a) => a.id == settings.id)
      ..add(settings);
    return true;
  }

  @override
  Future<bool> stop(int id) async {
    stored.removeWhere((alarm) => alarm.id == id);
    return true;
  }

  @override
  Future<void> stopAll() async {
    stopAllCalls++;
    await stopAllGate?.future;
    stored.clear();
  }
}

AlarmSettings _settings(int id, DateTime when) => AlarmSettings(
  id: id,
  dateTime: when,
  assetAudioPath: null,
  loopAudio: true,
  vibrate: true,
  volumeSettings: VolumeSettings.fixed(),
  notificationSettings: const NotificationSettings(
    title: 'Reminder',
    body: 'Body',
    stopButton: 'Stop',
  ),
);

const int _todoAlarmId = 600007;

void main() {
  late _FakeAlarmBackend backend;
  final future = DateTime.now().add(const Duration(days: 1));

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AlarmService.debugPrefKey: true,
    });
    AlarmService.debugReset();
    AlarmService.debugForceNative = true;
    backend = _FakeAlarmBackend();
    AlarmService.backend = backend;
  });

  tearDown(AlarmService.debugReset);

  test('init 只执行一次（并发调用共享同一个 future）', () async {
    await Future.wait([
      AlarmService.init(),
      AlarmService.init(),
      AlarmService.init(),
    ]);

    expect(backend.initCalls, 1);
  });

  test('scheduleAlarm 等待 init，init 完成前不向平台排程', () async {
    backend.initGate = Completer<void>();

    final scheduling = AlarmService.scheduleAlarm(
      id: 7,
      type: 'todo',
      dateTime: future,
      title: 'Title',
      body: 'Body',
    );
    await pumpEventQueue();
    expect(backend.setCalls, isEmpty);

    backend.initGate!.complete();
    await scheduling;
    expect(backend.setCalls, <int>[_todoAlarmId]);
  });

  test('init 失败时 scheduleAlarm 不排程，且下一次调用会重试 init', () async {
    backend.failInit = true;
    await AlarmService.scheduleAlarm(
      id: 7,
      type: 'todo',
      dateTime: future,
      title: 'Title',
      body: 'Body',
    );
    expect(backend.setCalls, isEmpty);
    expect(backend.initCalls, 1);

    backend.failInit = false;
    await AlarmService.scheduleAlarm(
      id: 7,
      type: 'todo',
      dateTime: future,
      title: 'Title',
      body: 'Body',
    );
    expect(backend.initCalls, 2);
    expect(backend.setCalls, <int>[_todoAlarmId]);
  });

  test('OFF 先保存偏好并立即返回，stopAll 随后在后台完成', () async {
    backend.stored.add(_settings(_todoAlarmId, future));
    backend.stopAllGate = Completer<void>();

    final returned = Completer<void>();
    unawaited(AlarmService.setEnabled(false).then((_) => returned.complete()));
    await returned.future.timeout(const Duration(seconds: 1));

    expect(await AlarmService.isEnabled(), isFalse);
    await pumpEventQueue();
    expect(backend.stopAllCalls, 1);
    expect(backend.stopAllGate!.isCompleted, isFalse);
    expect(backend.stored, isNotEmpty, reason: 'stopAll 仍在后台进行');

    backend.stopAllGate!.complete();
    await AlarmService.debugSettled();
    expect(backend.stored, isEmpty, reason: '后台 stopAll 最终必须清空原生闹钟');
  });

  test('OFF → ON：ON 等待未完成的 stopAll，随后可重新排程', () async {
    backend.stored.add(_settings(_todoAlarmId, future));
    backend.stopAllGate = Completer<void>();

    await AlarmService.setEnabled(false);
    final onReturned = Completer<void>();
    unawaited(AlarmService.setEnabled(true).then((_) => onReturned.complete()));
    await pumpEventQueue();
    expect(onReturned.isCompleted, isFalse, reason: 'stopAll 完成前 ON 不得返回');

    backend.stopAllGate!.complete();
    await onReturned.future.timeout(const Duration(seconds: 1));
    expect(await AlarmService.isEnabled(), isTrue);

    await AlarmService.scheduleAlarm(
      id: 7,
      type: 'todo',
      dateTime: future,
      title: 'Title',
      body: 'Body',
    );
    expect(backend.setCalls, <int>[_todoAlarmId]);
    expect(backend.stored.map((a) => a.id), <int>[_todoAlarmId]);
  });

  test('冷启动复用插件已恢复的同一个闹钟，不重复 set', () async {
    backend.stored.add(_settings(_todoAlarmId, future));
    await AlarmService.init();

    await AlarmService.scheduleAlarm(
      id: 7,
      type: 'todo',
      dateTime: future,
      title: 'Title',
      body: 'Body',
    );
    expect(backend.setCalls, isEmpty, reason: 'plugin restore 已排过同一时刻');

    await AlarmService.scheduleAlarm(
      id: 7,
      type: 'todo',
      dateTime: future.add(const Duration(hours: 1)),
      title: 'Title',
      body: 'Body',
    );
    expect(backend.setCalls, <int>[_todoAlarmId], reason: '时刻变了仍需重排');
  });

  test('冷启动时偏好为 OFF：插件恢复的闹钟会被清掉', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AlarmService.debugPrefKey: false,
    });
    backend.stored.add(_settings(_todoAlarmId, future));

    await AlarmService.init();

    expect(backend.stopAllCalls, 1);
    expect(backend.stored, isEmpty);
  });

  test('OFF 清空已知闹钟，ON 后同一时刻会重新下发', () async {
    backend.stored.add(_settings(_todoAlarmId, future));
    await AlarmService.init();
    await AlarmService.scheduleAlarm(
      id: 7,
      type: 'todo',
      dateTime: future,
      title: 'Title',
      body: 'Body',
    );
    expect(backend.setCalls, isEmpty);

    await AlarmService.setEnabled(false);
    await AlarmService.debugSettled();
    expect(backend.stored, isEmpty);

    await AlarmService.setEnabled(true);
    await AlarmService.scheduleAlarm(
      id: 7,
      type: 'todo',
      dateTime: future,
      title: 'Title',
      body: 'Body',
    );
    expect(backend.setCalls, <int>[_todoAlarmId]);
  });
}
