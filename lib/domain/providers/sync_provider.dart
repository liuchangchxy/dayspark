import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/data/remote/caldav/caldav_client.dart';
import 'package:dayspark/data/remote/caldav/sync_service.dart';
import 'package:dayspark/domain/providers/database_provider.dart';

Future<void> _saveLastSyncTime() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('last_sync_time_ms', DateTime.now().millisecondsSinceEpoch);
}

/// Keys for secure storage of CalDAV credentials.
const _keyServerUrl = 'caldav_server_url';
const _keyUsername = 'caldav_username';
const _keyPassword = 'caldav_password';

/// Whether CalDAV is configured.
final isCalDavConfiguredProvider = FutureProvider<bool>((ref) async {
  try {
    const storage = FlutterSecureStorage();
    final url = await storage.read(key: _keyServerUrl);
    return url != null && url.isNotEmpty;
  } catch (_) {
    return false;
  }
});

/// Current sync status.
final syncStatusProvider = StateProvider<SyncStatus>((ref) => SyncStatus.idle);

/// Last sync error message.
final syncErrorProvider = StateProvider<String?>((ref) => null);

/// Last sync time.
final lastSyncTimeProvider = StateProvider<DateTime?>((ref) => null);

/// Provider that saves CalDAV credentials to secure storage.
final saveCalDavCredentialsProvider =
    Provider<
      Future<void> Function({
        required String serverUrl,
        required String username,
        required String password,
      })
    >((ref) {
      return ({
        required serverUrl,
        required username,
        required password,
      }) async {
        try {
          const storage = FlutterSecureStorage();
          await storage.write(key: _keyServerUrl, value: serverUrl);
          await storage.write(key: _keyUsername, value: username);
          await storage.write(key: _keyPassword, value: password);
        } catch (_) {}
        ref.invalidate(isCalDavConfiguredProvider);
      };
    });

/// Provider that reads stored CalDAV credentials.
final calDavCredentialsProvider = FutureProvider<Map<String, String>?>((
  ref,
) async {
  try {
    const storage = FlutterSecureStorage();
    final url = await storage.read(key: _keyServerUrl);
    final username = await storage.read(key: _keyUsername);
    final password = await storage.read(key: _keyPassword);

    if (url == null || username == null || password == null) return null;
    return {'serverUrl': url, 'username': username, 'password': password};
  } catch (_) {
    return null;
  }
});

/// Provider to delete CalDAV credentials.
final deleteCalDavCredentialsProvider = Provider<Future<void> Function()>((
  ref,
) {
  return () async {
    try {
      const storage = FlutterSecureStorage();
      await storage.delete(key: _keyServerUrl);
      await storage.delete(key: _keyUsername);
      await storage.delete(key: _keyPassword);
    } catch (_) {}
    ref.invalidate(isCalDavConfiguredProvider);
    ref.invalidate(calDavCredentialsProvider);
  };
});

/// Trigger a full sync.
final triggerFullSyncProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    final db = ref.read(databaseProvider);
    final credentialsAsync = ref.read(calDavCredentialsProvider);

    final creds = credentialsAsync.value;
    if (creds == null) return;

    ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;

    final client = CalDavClient(
      baseUrl: creds['serverUrl']!,
      username: creds['username']!,
      password: creds['password']!,
    );

    final service = SyncService(db: db, client: client);

    service.onStatusChanged = (status) {
      ref.read(syncStatusProvider.notifier).state = status;
    };

    try {
      await service.fullSync();

      ref.read(lastSyncTimeProvider.notifier).state = service.lastSyncTime;
      ref.read(syncErrorProvider.notifier).state = service.lastError;
      _saveLastSyncTime();
    } catch (e) {
      ref.read(syncStatusProvider.notifier).state = SyncStatus.error;
      ref.read(syncErrorProvider.notifier).state = e.toString();
    } finally {
      service.dispose();
    }
  };
});

/// Trigger an incremental sync (uses sync-token, falls back to full sync if needed).
final triggerIncrementalSyncProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    final db = ref.read(databaseProvider);
    final credentialsAsync = ref.read(calDavCredentialsProvider);

    final creds = credentialsAsync.value;
    if (creds == null) return;

    ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;

    final client = CalDavClient(
      baseUrl: creds['serverUrl']!,
      username: creds['username']!,
      password: creds['password']!,
    );

    final service = SyncService(db: db, client: client);

    service.onStatusChanged = (status) {
      ref.read(syncStatusProvider.notifier).state = status;
    };

    try {
      await service.incrementalSync();

      ref.read(lastSyncTimeProvider.notifier).state = service.lastSyncTime;
      ref.read(syncErrorProvider.notifier).state = service.lastError;
      _saveLastSyncTime();
    } catch (e) {
      ref.read(syncStatusProvider.notifier).state = SyncStatus.error;
      ref.read(syncErrorProvider.notifier).state = e.toString();
    } finally {
      service.dispose();
    }
  };
});

/// Sync all accounts stored in the database. Falls back to the legacy
/// single-account mode (secure-storage credentials) when no DB accounts exist.
final triggerSyncAllAccountsProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    final db = ref.read(databaseProvider);

    // Read accounts from DB
    final accounts = await (db.select(db.accounts)).get();

    if (accounts.isEmpty) {
      // Fallback to legacy single-account sync
      await ref.read(triggerFullSyncProvider)();
      return;
    }

    ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;
    String? firstError;
    DateTime? latestSync;

    for (final account in accounts) {
      const storage = FlutterSecureStorage();
      final password = await storage.read(key: 'account_${account.id}_password') ?? account.password;

      final client = CalDavClient(
        baseUrl: account.serverUrl,
        username: account.username,
        password: password,
      );

      final service = SyncService(db: db, client: client);
      try {
        await service.fullSync();

        if (service.lastSyncTime != null) {
          latestSync = service.lastSyncTime!;
        }
      } catch (e) {
        firstError ??= e.toString();
      } finally {
        service.dispose();
      }
    }

    ref.read(lastSyncTimeProvider.notifier).state = latestSync;
    ref.read(syncErrorProvider.notifier).state = firstError;
    ref.read(syncStatusProvider.notifier).state = firstError != null
        ? SyncStatus.error
        : SyncStatus.success;
  };
});
