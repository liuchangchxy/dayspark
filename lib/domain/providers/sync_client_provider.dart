import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/sync/sse_listener.dart';
import 'package:dayspark/domain/sync/sync_api_client.dart';
import 'package:dayspark/domain/sync/sync_config.dart';
import 'package:dayspark/domain/sync/sync_engine.dart';

class SyncSettings {
  const SyncSettings({
    required this.prefs,
    required this.baseUrl,
    required this.deviceId,
  });

  final SharedPreferences prefs;
  final String? baseUrl;
  final String deviceId;
}

final syncSettingsProvider = FutureProvider<SyncSettings>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final config = await PrefsSyncConfigStore(prefs).load();
  final deviceId = await loadOrCreateDeviceId(prefs);
  return SyncSettings(prefs: prefs, baseUrl: config?.baseUrl, deviceId: deviceId);
});

final syncTokenStoreProvider = Provider<SyncTokenStore>((ref) {
  return const SecureSyncTokenStore();
});

/// Engine singleton: built once the server base URL is configured, torn
/// down on dispose or config change. Triggers wired here on top of the
/// engine's own outbox listener: SSE cursor signals and connectivity
/// regain both kick a round.
final syncEngineProvider = Provider<SyncEngine?>((ref) {
  final settings = ref.watch(syncSettingsProvider).valueOrNull;
  if (settings == null || settings.baseUrl == null) return null;
  final db = ref.watch(databaseProvider);
  final tokens = ref.watch(syncTokenStoreProvider);
  final client = AuthSyncApiClient(
    transport: DioSyncTransport(baseUrl: settings.baseUrl!),
    tokens: tokens,
  );
  final engine = SyncEngine(
    db: db,
    api: client,
    cursorStore: PrefsSyncCursorStore(settings.prefs),
    tokenStore: tokens,
    snapshots: PrefsSyncSnapshotStore(settings.prefs),
    deviceId: settings.deviceId,
  );
  final sse = SseListener(
    open: client.openCursorStream,
    onCursor: (cursor) => unawaited(engine.notifyRemoteCursor(cursor)),
  );

  // Both engine rounds and SSE need a configured login; T6 writes tokens
  // and invalidates this provider to bring the engine up.
  unawaited(() async {
    if (await tokens.isConfigured()) {
      sse.start();
      await engine.start();
    }
  }());

  var wasOffline = false;
  final connSub = Connectivity().onConnectivityChanged.listen((results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (online && wasOffline) {
      unawaited(engine.requestRound());
    }
    wasOffline = !online;
  });

  ref.onDispose(() async {
    await connSub.cancel();
    await sse.stop();
    await engine.stop();
  });
  return engine;
});

/// One-shot read at app start keeps the provider alive so config/login
/// changes rebuild it (watch chain) without any UI attached.
final syncRuntimeProvider = Provider<void>((ref) {
  ref.watch(syncEngineProvider);
});

class SyncStatusNotifier extends Notifier<SyncStatus> {
  @override
  SyncStatus build() {
    final engine = ref.watch(syncEngineProvider);
    if (engine == null) return const SyncStatus();
    // Attach before reading current status so no transition is missed.
    final sub = engine.statusStream.listen((next) => state = next);
    ref.onDispose(sub.cancel);
    return engine.status;
  }
}

final syncStatusProvider = NotifierProvider<SyncStatusNotifier, SyncStatus>(
  SyncStatusNotifier.new,
);
