import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/domain/providers/sync_provider.dart';

/// Whether the device currently has network connectivity.
final isConnectedProvider = StreamProvider<bool>((ref) {
  return Connectivity().onConnectivityChanged.map(
    (results) => results.any((r) => r != ConnectivityResult.none),
  );
});

/// Processes the sync queue whenever connectivity is restored.
final connectivitySyncQueueProcessorProvider = Provider<void Function()>((ref) {
  final sub = ref.listen(isConnectedProvider, (_, next) {
    final connected = next.valueOrNull ?? false;
    if (!connected) return;

    final configured = ref.read(isCalDavConfiguredProvider).valueOrNull;
    if (configured != true) return;

    ref.read(triggerIncrementalSyncProvider)();
  }, onError: (_, __) {});

  ref.onDispose(sub.close);

  return () {};
});
