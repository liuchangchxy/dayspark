import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/domain/sync/foreground_sync_poller.dart';

import 'sync_test_support.dart';

void main() {
  test('start() arms the timer and periodic ticks call requestRound',
      () async {
    var rounds = 0;
    final poller = ForegroundSyncPoller(
      requestRound: () async {
        rounds++;
      },
      interval: const Duration(milliseconds: 20),
    );
    addTearDown(poller.dispose);

    poller.start();
    expect(poller.isActive, isTrue);
    expect(rounds, 0, reason: 'start() alone does not round immediately');

    await waitUntil(() => rounds >= 1,
        reason: 'timer must fire requestRound at the injected interval');

    poller.paused();
    expect(poller.isActive, isFalse);
    final settled = rounds;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(rounds, settled, reason: 'paused stops the cadence');
  });

  test('resumed() triggers a round immediately and re-arms the timer',
      () async {
    var rounds = 0;
    final poller = ForegroundSyncPoller(
      requestRound: () async {
        rounds++;
      },
      interval: const Duration(minutes: 5),
    );
    addTearDown(poller.dispose);

    poller.resumed();
    expect(rounds, 1, reason: 'lifecycle resumed rounds at once');
    expect(poller.isActive, isTrue);

    poller.paused();
    expect(poller.isActive, isFalse);
    final atPause = rounds;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(rounds, atPause);
  });

  test('dispose() stops an armed timer', () async {
    var rounds = 0;
    final poller = ForegroundSyncPoller(
      requestRound: () async {
        rounds++;
      },
      interval: const Duration(milliseconds: 20),
    );
    poller.resumed();
    poller.dispose();
    expect(poller.isActive, isFalse);
    final settled = rounds;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(rounds, settled);
  });
}
