import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/domain/providers/sync_client_provider.dart';
import 'package:dayspark/domain/sync/sync_engine.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/settings/settings_sections/sync_section.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';

import '../../../domain/sync/sync_test_support.dart';

class _FixedStatusNotifier extends SyncStatusNotifier {
  _FixedStatusNotifier(this._fixed);

  final SyncStatus _fixed;

  @override
  SyncStatus build() => _fixed;
}

Widget _app({required SyncStatus status, required int pending}) =>
    ProviderScope(
      overrides: [
        syncTokenStoreProvider.overrideWithValue(
          MemoryTokenStore(access: 'a', refresh: 'r'),
        ),
        syncEngineProvider.overrideWith((ref) => null),
        pendingSyncOpsProvider.overrideWith((ref) => Stream.value(pending)),
        syncStatusProvider.overrideWith(() => _FixedStatusNotifier(status)),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const Scaffold(body: SingleChildScrollView(child: SyncSection())),
      ),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'account_email': 'a@b.co'});
  });

  testWidgets('sync settings shows conflict and rejected counts with reasons', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        pending: 0,
        status: SyncStatus(
          conflicts: [
            SyncConflict(
              recordId: 'abcdef1234567890',
              type: RecordType.event,
              code: 'conflict',
              at: DateTime(2026, 11, 22, 14, 58),
            ),
          ],
          rejectedCount: 2,
          rejectedCodes: const ['validation', 'conflict'],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Conflicts'), findsOneWidget);
    expect(find.text('1 needs review'), findsOneWidget);
    expect(find.text('Latest: abcdef12'), findsOneWidget);
    expect(find.text('Server rejections'), findsOneWidget);
    expect(find.text('2 rejected'), findsOneWidget);
    expect(find.text('Rejected: validation, conflict'), findsOneWidget);
  });

  testWidgets('sync settings shows failure reason, time and pending count', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        pending: 3,
        status: SyncStatus(
          phase: SyncPhase.error,
          lastError: 'SocketException: timeout',
          lastErrorAt: DateTime(2026, 11, 22, 14, 58),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sync error'), findsWidgets);
    expect(find.textContaining('SocketException: timeout'), findsOneWidget);
    expect(find.textContaining('3 pending uploads'), findsWidgets);

    // SPEC 2553: unreachable, local priority and a working retry entry.
    expect(find.text('Unreachable'), findsOneWidget);
    expect(find.text('Local Priority'), findsOneWidget);
    expect(find.text('Retry Now'), findsWidgets);
  });

  testWidgets('conflicts open a per-record screen with real local/server data', (
    tester,
  ) async {
    final choices = <(String, SyncConflictResolution)>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          syncTokenStoreProvider.overrideWithValue(
            MemoryTokenStore(access: 'a', refresh: 'r'),
          ),
          syncEngineProvider.overrideWith((ref) => null),
          pendingSyncOpsProvider.overrideWith((ref) => Stream.value(1)),
          resolveSyncConflictProvider.overrideWithValue((recordId, choice) async {
            choices.add((recordId, choice));
          }),
          syncStatusProvider.overrideWith(
            () => _FixedStatusNotifier(
              SyncStatus(
                conflicts: [
                  SyncConflict(
                    recordId: 'evt-123456789',
                    type: RecordType.event,
                    code: 'conflict',
                    at: DateTime(2026, 11, 22, 14, 58),
                    localPayload: const {
                      'summary': '提交周报给林总',
                      'startDt': '2026-11-22T15:15:00Z',
                    },
                    serverPayload: const {
                      'summary': '提交周报给林总',
                      'startDt': '2026-11-22T16:00:00Z',
                    },
                    serverRev: 4,
                  ),
                ],
              ),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(
            body: SingleChildScrollView(child: SyncSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Conflicts'));
    await tester.pumpAndSettle();

    // SPEC 2554: each record carries its own choice row.
    expect(find.text('Sync conflict'), findsOneWidget);
    expect(find.text('提交周报给林总'), findsOneWidget);
    expect(find.textContaining('Local:'), findsOneWidget);
    expect(find.textContaining('Server:'), findsOneWidget);
    expect(find.text('Keep Local'), findsOneWidget);
    expect(find.text('Keep Server'), findsOneWidget);
    expect(find.text('Merge'), findsOneWidget);

    await tester.tap(find.text('Keep Server'));
    await tester.pump();
    await tester.tap(find.text('Apply choices'));
    await tester.pumpAndSettle();

    expect(choices, [
      ('evt-123456789', SyncConflictResolution.keepRemote),
    ]);
  });
}
