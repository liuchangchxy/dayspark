import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/sync_client_provider.dart';
import 'package:dayspark/domain/sync/cloud/cloud_sync_engine.dart';
import 'package:dayspark/domain/sync/cloud/cloud_sync_settings.dart';
import 'package:dayspark/domain/sync/cloud/cloud_webdav_config.dart';
import 'package:dayspark/domain/sync/cloud/webdav_backend.dart';
import 'package:dayspark/domain/sync/sync_config.dart';
import 'package:dayspark/domain/sync/sync_engine.dart';

/// Which transport this device is allowed to talk to. Null means "never
/// chosen": the self-hosted transport keeps working exactly as before.
final cloudSyncSourceProvider = FutureProvider<CloudSyncSource?>((ref) async {
  final settings = await ref.watch(syncSettingsProvider.future);
  return PrefsCloudSyncSourceStore(settings.prefs).read();
});

final cloudWebDavConfigProvider = FutureProvider<CloudWebDavConfig?>((ref) async {
  final settings = await ref.watch(syncSettingsProvider.future);
  return PrefsCloudWebDavConfigStore(settings.prefs).load();
});

/// The cloud-drive engine for the active source. Only WebDAV can be built
/// today: the six hosted drives need a client ID registered under the
/// account holder's developer account (docs/cloud-sync-providers.md).
final cloudSyncEngineProvider = Provider<CloudSyncEngine?>((ref) {
  final settings = ref.watch(syncSettingsProvider).valueOrNull;
  final source = ref.watch(cloudSyncSourceProvider).valueOrNull;
  final config = ref.watch(cloudWebDavConfigProvider).valueOrNull;
  if (settings == null) return null;
  if (source != CloudSyncSource.webdav) return null;
  if (config == null || !config.isComplete) return null;

  final engine = CloudSyncEngine(
    db: ref.watch(databaseProvider),
    backend: WebDavBackend(
      baseUrl: config.baseUrl,
      documentPath: config.documentPath,
      username: config.username,
      password: config.password,
    ),
    snapshots: PrefsSyncSnapshotStore(settings.prefs),
    stateStore: PrefsCloudSyncStateStore(settings.prefs),
  );
  unawaited(engine.start());

  var wasOffline = false;
  final connSub = Connectivity().onConnectivityChanged.listen(
    (results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online && wasOffline) unawaited(engine.requestRound());
      wasOffline = !online;
    },
    onError: (Object e) => debugPrint('cloud sync: connectivity error: $e'),
  );
  ref.onDispose(() async {
    await connSub.cancel();
    await engine.stop();
  });
  return engine;
});

class CloudSyncStatusNotifier extends Notifier<SyncStatus> {
  @override
  SyncStatus build() {
    final engine = ref.watch(cloudSyncEngineProvider);
    if (engine == null) return const SyncStatus();
    final sub = engine.statusStream.listen((next) => state = next);
    ref.onDispose(sub.cancel);
    return engine.status;
  }
}

final cloudSyncStatusProvider =
    NotifierProvider<CloudSyncStatusNotifier, SyncStatus>(
      CloudSyncStatusNotifier.new,
    );

class CloudSyncController {
  CloudSyncController(this._ref);

  final Ref _ref;

  /// Switching sources migrates: the new destination receives every local row
  /// on the next round because the cursor, the diff-base snapshots and the
  /// document validator are all dropped first (see [CloudSourceSwitch]).
  Future<void> selectSource(CloudSyncSource next) async {
    final settings = await _ref.read(syncSettingsProvider.future);
    await CloudSourceSwitch(
      sources: PrefsCloudSyncSourceStore(settings.prefs),
      stateStore: PrefsCloudSyncStateStore(settings.prefs),
      cursorStore: PrefsSyncCursorStore(settings.prefs),
      snapshots: PrefsSyncSnapshotStore(settings.prefs),
    ).switchTo(next);
    _ref.invalidate(cloudSyncSourceProvider);
    // The self-hosted engine is built from a synchronous source read, so a
    // source switch has to rebuild it explicitly.
    _ref.invalidate(syncEngineProvider);
  }

  Future<void> saveWebDav(CloudWebDavConfig config) async {
    final settings = await _ref.read(syncSettingsProvider.future);
    await PrefsCloudWebDavConfigStore(settings.prefs).save(config);
    _ref.invalidate(cloudWebDavConfigProvider);
    _ref.invalidate(cloudSyncEngineProvider);
  }

  Future<bool> syncNow() async {
    final engine = _ref.read(cloudSyncEngineProvider);
    if (engine == null) return false;
    return engine.syncNow();
  }
}

final cloudSyncControllerProvider = Provider<CloudSyncController>(
  CloudSyncController.new,
);
