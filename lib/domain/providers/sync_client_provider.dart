import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/core/utils/device_label.dart';
import 'package:dayspark/domain/providers/account_provider.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/sync/foreground_sync_poller.dart';
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
    deviceId: settings.deviceId,
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
    // Initial head per connection: rewinds a watermark that is AHEAD of a
    // restored server (restore self-heal — see SyncEngine.adoptServerHead).
    onInitialCursor: (head) => unawaited(engine.adoptServerHead(head)),
  );

  // WHY 15s foreground fallback (plan-mandated): proxies can leave the
  // SSE stream lingering without FIN (T4) so the listener never errors
  // and no reconnect/signals fire — periodic rounds keep push+pull
  // flowing while foregrounded. Backgrounded = paused; engine.coalescing
  // caps overlapping triggers at one queued round.
  final poller = ForegroundSyncPoller(requestRound: engine.requestRound);
  final lifecycleListener = AppLifecycleListener(
    // Foreground trigger: round immediately on return + re-arm the timer;
    // isRunning gates the logged-out provider build (baseUrl-only) that
    // would otherwise fire no-op rounds every tick.
    onResume: () {
      if (engine.isRunning) poller.resumed();
    },
    onPause: poller.paused,
  );

  // Both engine rounds and SSE need a configured login; T6 writes tokens
  // and invalidates this provider to bring the engine up.
  unawaited(() async {
    try {
      if (await tokens.isConfigured()) {
        sse.start();
        await engine.start();
        // Foreground-only cadence: skip when built while backgrounded —
        // onResume arms it later.
        final lifecycle = WidgetsBinding.instance.lifecycleState;
        if (lifecycle == null ||
            lifecycle == AppLifecycleState.resumed ||
            lifecycle == AppLifecycleState.inactive) {
          poller.start();
        }
      }
    } catch (e) {
      debugPrint('sync: engine startup error: $e');
    }
  }());

  var wasOffline = false;
  final connSub = Connectivity().onConnectivityChanged.listen(
    (results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online && wasOffline) {
        unawaited(engine.requestRound());
      }
      wasOffline = !online;
    },
    onError: (Object e) =>
        debugPrint('sync: connectivity listener error: $e'),
  );

  ref.onDispose(() async {
    poller.dispose();
    lifecycleListener.dispose();
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

/// 设备注册：登录后与每次冷启动各上报一次（服务端幂等，重复上报不建第二行）。
///
/// 为什么挂在 provider 而不是只塞进登录成功那一行：只挂登录路径的话，
/// **升级前就已经登录过的设备永远不会被登记**——而他们恰恰是最该出现在
/// 「已连接设备」里的那批。
///
/// 注册失败不冒泡：它不该影响同步，下一次冷启动会再试。
final deviceRegistrationProvider = Provider<void>((ref) {
  final settings = ref.watch(syncSettingsProvider).valueOrNull;
  if (settings == null || settings.baseUrl == null) return;
  // Non-null email is the logged-in signal (account_provider).
  final email = ref.watch(accountAuthProvider).valueOrNull?.email;
  if (email == null) return;

  final client = AuthSyncApiClient(
    transport: DioSyncTransport(baseUrl: settings.baseUrl!),
    tokens: ref.watch(syncTokenStoreProvider),
    deviceId: settings.deviceId,
  );
  unawaited(() async {
    try {
      await client.registerDevice(
        deviceId: settings.deviceId,
        name: deviceDisplayName(),
      );
    } catch (e) {
      debugPrint('device register failed: $e');
    }
  }());
});

/// 本账号已注册的设备列表，供设置页展示。
///
/// 只在已登录时构建；未配置服务器/未登录返回空表而不是抛错——设置页不该
/// 因为没配好后端就崩。
final connectedDevicesProvider = FutureProvider<List<DeviceDto>>((ref) async {
  final settings = ref.watch(syncSettingsProvider).valueOrNull;
  if (settings == null || settings.baseUrl == null) return const [];
  final email = ref.watch(accountAuthProvider).valueOrNull?.email;
  if (email == null) return const [];
  final client = AuthSyncApiClient(
    transport: DioSyncTransport(baseUrl: settings.baseUrl!),
    tokens: ref.watch(syncTokenStoreProvider),
    deviceId: settings.deviceId,
  );
  return client.fetchDevices();
});
