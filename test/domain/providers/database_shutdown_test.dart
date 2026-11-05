import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/domain/providers/database_provider.dart';

void main() {
  test('close is started once and every caller waits for it', () async {
    final finish = Completer<void>();
    var calls = 0;
    final shutdown = DatabaseShutdown(() {
      calls++;
      return finish.future;
    });

    var firstDone = false;
    final first = shutdown.close().whenComplete(() => firstDone = true);
    final second = shutdown.close();

    expect(calls, 1);
    await pumpEventQueue(times: 5);
    expect(firstDone, isFalse);

    finish.complete();
    await Future.wait([first, second]);
    expect(calls, 1);
    expect(firstDone, isTrue);
  });
}
