import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/domain/sync/sync_api_client.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';

import 'sync_test_support.dart';

void main() {
  late FakeTransport transport;
  late MemoryTokenStore tokens;
  late AuthSyncApiClient client;

  setUp(() {
    transport = FakeTransport();
    tokens = MemoryTokenStore(access: 'access-1', refresh: 'refresh-1');
    client = AuthSyncApiClient(transport: transport, tokens: tokens);
  });

  PushRequest emptyRequest() => PushRequest(
        deviceId: 'dev-1',
        ops: const [],
        cursor: 0,
      );

  test('401 → refresh once → retried with the new bearer', () async {
    final response = await client.push(emptyRequest());

    expect(response.cursor, 0);
    expect(transport.pushCalls, 2, reason: 'original + single retry');
    expect(transport.refreshCalls, 1);
    expect(transport.authorizationHeaders, ['Bearer access-1', 'Bearer access-2']);
    expect(tokens.access, 'access-2');
    expect(tokens.refresh, 'refresh-2');
  });

  test('second 401 does not refresh again — retry happens exactly once',
      () async {
    transport.alwaysPush401 = true;

    await expectLater(
      client.push(emptyRequest()),
      throwsA(isA<SyncApiException>()),
    );

    expect(transport.pushCalls, 2);
    expect(transport.refreshCalls, 1,
        reason: 'refreshed once, retried once, then gave up');
  });

  test('missing refresh token surfaces as unauthorized without retry',
      () async {
    tokens.refresh = null;

    await expectLater(
      client.push(emptyRequest()),
      throwsA(
        isA<SyncApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.code, 'code', 'unauthorized'),
      ),
    );

    expect(transport.pushCalls, 1,
        reason: 'original attempt, then refresh aborted before retry');
    expect(transport.refreshCalls, 0);
  });
}
