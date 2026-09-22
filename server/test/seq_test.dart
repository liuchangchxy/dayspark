import 'package:dayspark_server/server.dart';
import 'package:test/test.dart';

void main() {
  late AppServer app;

  setUp(() {
    app = AppServer(
      const Config(dbPath: ':memory:', port: 0, jwtSecret: 'test-secret'),
    );
  });

  tearDown(() async {
    await app.close();
  });

  test('nextSeq is strictly monotonic under concurrent calls', () async {
    final results = await Future.wait(
      List.generate(30, (_) => app.db.nextSeqForUser('user-a')),
    );

    final sorted = [...results]..sort();
    expect(sorted, List.generate(30, (i) => i + 1));
  });

  test('nextSeq cursors are isolated per user', () async {
    final firstOfA = await app.db.nextSeqForUser('user-a');
    final firstOfB = await app.db.nextSeqForUser('user-b');

    expect(firstOfA, 1);
    expect(firstOfB, 1);
  });

  test('nextSeq can run inside an outer transaction (push seam)', () async {
    final seq = await app.db.transaction(
      () => app.db.nextSeq(app.db, 'user-a'),
    );

    expect(seq, 1);
    expect(await app.db.nextSeqForUser('user-a'), 2);
  });
}
