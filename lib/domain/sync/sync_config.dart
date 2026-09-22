import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class SyncConfig {
  const SyncConfig({required this.baseUrl});

  final String baseUrl;
}

abstract class SyncConfigStore {
  Future<SyncConfig?> load();
  Future<void> save(SyncConfig config);
  Future<void> clear();
}

class PrefsSyncConfigStore implements SyncConfigStore {
  PrefsSyncConfigStore(this._prefs);

  static const _key = 'sync_base_url';

  final SharedPreferences _prefs;

  @override
  Future<SyncConfig?> load() async {
    final url = _prefs.getString(_key);
    if (url == null || url.isEmpty) return null;
    return SyncConfig(baseUrl: url);
  }

  @override
  Future<void> save(SyncConfig config) => _prefs.setString(_key, config.baseUrl);

  @override
  Future<void> clear() => _prefs.remove(_key);
}

/// Pull watermark: everything at or below the stored cursor is already
/// held locally (push.piggyback / pull.nextCursor both honor it).
abstract class SyncCursorStore {
  Future<int?> read();
  Future<void> write(int cursor);
}

class PrefsSyncCursorStore implements SyncCursorStore {
  PrefsSyncCursorStore(this._prefs);

  static const _key = 'sync_pull_cursor';

  final SharedPreferences _prefs;

  @override
  Future<int?> read() async => _prefs.getInt(_key);

  @override
  Future<void> write(int cursor) => _prefs.setInt(_key, cursor);
}

abstract class SyncTokenStore {
  Future<String?> readAccessToken();
  Future<String?> readRefreshToken();
  Future<void> saveTokens({required String accessToken, required String refreshToken});
  Future<void> clear();
}

extension SyncTokenStoreX on SyncTokenStore {
  /// The engine only runs when a refresh token exists — login (T6) writes
  /// both tokens; logout clears them and stops the rounds.
  Future<bool> isConfigured() async => (await readRefreshToken()) != null;
}

class SecureSyncTokenStore implements SyncTokenStore {
  const SecureSyncTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _accessKey = 'accessToken';
  static const _refreshKey = 'refreshToken';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readAccessToken() => _storage.read(key: _accessKey);

  @override
  Future<String?> readRefreshToken() => _storage.read(key: _refreshKey);

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}

Future<String> loadOrCreateDeviceId(SharedPreferences prefs) async {
  const key = 'sync_device_id';
  final existing = prefs.getString(key);
  if (existing != null) return existing;
  final id = const Uuid().v7();
  await prefs.setString(key, id);
  return id;
}
