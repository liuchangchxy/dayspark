import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/domain/providers/sync_client_provider.dart';
import 'package:dayspark/domain/sync/sync_engine.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/shell/sync_status_banner.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';

class _FixedStatusNotifier extends SyncStatusNotifier {
  _FixedStatusNotifier(this._fixed);

  final SyncStatus _fixed;

  @override
  SyncStatus build() => _fixed;
}

Widget _app({
  required bool online,
  required int pending,
  required SyncStatus status,
}) => ProviderScope(
  overrides: [
    syncActiveProvider.overrideWithValue(true),
    syncEngineProvider.overrideWith((ref) => null),
    syncOnlineProvider.overrideWith((ref) => Stream.value(online)),
    pendingSyncOpsProvider.overrideWith((ref) => Stream.value(pending)),
    syncStatusProvider.overrideWith(() => _FixedStatusNotifier(status)),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: const Scaffold(body: Column(children: [SyncStatusBanner()])),
  ),
);

void main() {
  testWidgets('offline banner reports local changes waiting to upload', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(online: false, pending: 3, status: const SyncStatus()),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Offline · 3 local changes waiting to upload.'),
      findsOneWidget,
    );
  });

  testWidgets('failure banner carries the pending count and retry action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        online: true,
        pending: 2,
        status: SyncStatus(
          phase: SyncPhase.error,
          lastError: 'timeout',
          lastErrorAt: DateTime(2026, 11, 22, 14, 58),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sync error'), findsOneWidget);
    expect(find.text('2 pending uploads'), findsOneWidget);
    expect(find.text('Retry Now'), findsOneWidget);
  });

  testWidgets('conflict banner shows the count awaiting review', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        online: true,
        pending: 0,
        status: SyncStatus(
          conflicts: [
            SyncConflict(
              recordId: 'record-1',
              type: RecordType.event,
              code: 'conflict',
              at: DateTime(2026, 11, 22, 14, 58),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 needs review'), findsOneWidget);
  });
}
