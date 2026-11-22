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
    expect(find.text('3 pending uploads'), findsWidgets);
  });
}
