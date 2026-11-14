import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/infrastructure/platform/widget_refresh_scheduler.dart';

void main() {
  const debounce = Duration(milliseconds: 20);
  const maxDeferral = Duration(milliseconds: 200);

  Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

  test('a burst collapses into one run', () async {
    var runs = 0;
    final scheduler = WidgetRefreshScheduler(
      onRun: () async => runs++,
      isEditing: () => false,
      debounce: debounce,
      maxDeferral: maxDeferral,
    );
    addTearDown(scheduler.dispose);

    for (var i = 0; i < 10; i++) {
      scheduler.request();
    }
    await wait(80);

    expect(runs, 1);
  });

  test('holds the run while a text field owns focus', () async {
    var runs = 0;
    var editing = true;
    final scheduler = WidgetRefreshScheduler(
      onRun: () async => runs++,
      isEditing: () => editing,
      debounce: debounce,
      maxDeferral: maxDeferral,
    );
    addTearDown(scheduler.dispose);

    scheduler.request();
    await wait(80);
    expect(runs, 0, reason: '打字期间不重建快照');

    editing = false;
    scheduler.request();
    await wait(80);
    expect(runs, 1);
  });

  test('maxDeferral bounds the hold so widgets never go stale', () async {
    var runs = 0;
    final scheduler = WidgetRefreshScheduler(
      onRun: () async => runs++,
      isEditing: () => true,
      debounce: debounce,
      maxDeferral: maxDeferral,
    );
    addTearDown(scheduler.dispose);

    scheduler.request();
    await wait(80);
    expect(runs, 0);
    await wait(220);
    expect(runs, 1, reason: '持续打字也必须有一次兜底刷新');
  });

  test('requests arriving during a run schedule exactly one follow-up', () async {
    var runs = 0;
    final gate = Completer<void>();
    final scheduler = WidgetRefreshScheduler(
      onRun: () async {
        runs++;
        if (runs == 1) await gate.future;
      },
      isEditing: () => false,
      debounce: debounce,
      maxDeferral: maxDeferral,
    );
    addTearDown(scheduler.dispose);

    scheduler.request();
    await wait(60);
    expect(runs, 1);

    scheduler.request();
    scheduler.request();
    await wait(60);
    expect(runs, 1, reason: '一次只允许一个 in-flight');

    gate.complete();
    await wait(80);
    expect(runs, 2, reason: '并发请求在跑完后合并成一次补跑');
  });

  test('a run that outlives the cap cannot defer forever', () async {
    var runs = 0;
    final gate = Completer<void>();
    final scheduler = WidgetRefreshScheduler(
      onRun: () async {
        runs++;
        if (runs == 1) await gate.future;
      },
      isEditing: () => true,
      debounce: debounce,
      maxDeferral: const Duration(milliseconds: 100),
    );
    addTearDown(scheduler.dispose);

    scheduler.request();
    await wait(120);
    expect(runs, 1, reason: '兜底刷新先跑，且被 gate 卡住');

    // A request lands while that run is still in flight, so the cap that was
    // armed here is consumed by a run that cannot start. The pending request
    // must keep a fresh cap instead of waiting for the field to blur.
    scheduler.request();
    await wait(140);
    gate.complete();
    await wait(400);

    expect(runs, 2, reason: '运行中到达的请求仍必须被 maxDeferral 兜底');
  });

  test('dispose stops pending work', () async {
    var runs = 0;
    final scheduler = WidgetRefreshScheduler(
      onRun: () async => runs++,
      isEditing: () => false,
      debounce: debounce,
      maxDeferral: maxDeferral,
    );

    scheduler.request();
    scheduler.dispose();
    await wait(120);

    expect(runs, 0);
  });
}
