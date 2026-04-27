import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/domain/providers/sync_provider.dart';
import 'package:dayspark/domain/services/background_sync_service.dart';

final backgroundSyncServiceProvider = Provider<BackgroundSyncService>((ref) {
  return BackgroundSyncService(
    syncFn: () async {
      final hasSynced = ref.read(lastSyncTimeProvider) != null;
      final configured = ref.read(isCalDavConfiguredProvider).valueOrNull;
      if (configured != true) return;

      if (hasSynced) {
        await ref.read(triggerIncrementalSyncProvider)();
      } else {
        await ref.read(triggerFullSyncProvider)();
      }
    },
  );
});
