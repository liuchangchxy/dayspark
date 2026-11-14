import 'package:shared_preferences/shared_preferences.dart';

import '../sync_config.dart';

/// Where a device's data lives. Exactly one of these is active at a time —
/// two transports pushing the same rows would each see the other's writes as
/// remote truth and the merge would ping-pong forever.
enum CloudSyncSource {
  daysparkServer,
  webdav,
  googleDrive,
  oneDrive,
  dropbox,
  baiduNetdisk,
  quark,
  pan115;

  String get wireName => name;

  static CloudSyncSource? fromWireName(String? value) {
    if (value == null) return null;
    for (final source in CloudSyncSource.values) {
      if (source.name == value) return source;
    }
    return null;
  }

  /// Which sources can actually be selected today. The six drive providers
  /// need a client ID registered under the account holder's developer
  /// account, so the app cannot ship them yet — see
  /// `docs/cloud-sync-providers.md`. WebDAV needs no registration and the
  /// self-hosted server is this project's own, so those two are the whole
  /// selectable set; the rest stay in the enum so settings and stored
  /// preferences already speak the full vocabulary.
  bool get isWired => this == daysparkServer || this == webdav;

  bool get isCloudDrive => this != daysparkServer;
}

/// Cloud-drive bookkeeping: the validator of the document we last wrote, and
/// whether this device has ever completed a round against the current source.
abstract class CloudSyncStateStore {
  Future<String?> readEtag();
  Future<void> writeEtag(String? etag);

  /// False on a fresh install and after a source switch: the next round must
  /// enqueue every local row so the new destination receives the full
  /// dataset (the task's "provider switch migrates all data").
  Future<bool> isProvisioned();
  Future<void> markProvisioned();

  Future<DateTime?> readLastSyncAt();
  Future<void> writeLastSyncAt(DateTime at);

  Future<void> clear();
}

class PrefsCloudSyncStateStore implements CloudSyncStateStore {
  PrefsCloudSyncStateStore(this._prefs);

  static const _etagKey = 'cloud_sync_etag';
  static const _provisionedKey = 'cloud_sync_provisioned';
  static const _lastSyncKey = 'cloud_sync_last_at';

  final SharedPreferences _prefs;

  @override
  Future<String?> readEtag() async {
    final value = _prefs.getString(_etagKey);
    return value == null || value.isEmpty ? null : value;
  }

  @override
  Future<void> writeEtag(String? etag) async {
    if (etag == null || etag.isEmpty) {
      await _prefs.remove(_etagKey);
    } else {
      await _prefs.setString(_etagKey, etag);
    }
  }

  @override
  Future<bool> isProvisioned() async => _prefs.getBool(_provisionedKey) ?? false;

  @override
  Future<void> markProvisioned() => _prefs.setBool(_provisionedKey, true);

  @override
  Future<DateTime?> readLastSyncAt() async {
    final raw = _prefs.getString(_lastSyncKey);
    return raw == null ? null : DateTime.tryParse(raw)?.toUtc();
  }

  @override
  Future<void> writeLastSyncAt(DateTime at) =>
      _prefs.setString(_lastSyncKey, at.toUtc().toIso8601String());

  @override
  Future<void> clear() async {
    await _prefs.remove(_etagKey);
    await _prefs.remove(_provisionedKey);
    await _prefs.remove(_lastSyncKey);
  }
}

/// Active source selection, persisted so a restart resumes the same one.
class PrefsCloudSyncSourceStore {
  PrefsCloudSyncSourceStore(this._prefs);

  static const _key = 'cloud_sync_source';

  final SharedPreferences _prefs;

  CloudSyncSource? read() =>
      CloudSyncSource.fromWireName(_prefs.getString(_key));

  Future<void> write(CloudSyncSource source) => _prefs.setString(_key, source.name);

  Future<void> clear() => _prefs.remove(_key);
}

/// Everything a source switch must forget, and nothing it must keep.
///
/// WHY each piece: the cursor is a watermark against the OLD dataset; the
/// snapshots are the diff base against the OLD dataset's payloads (keeping
/// them would make every record look "converged" and the new destination
/// would receive nothing); the ETag names a document that is about to be
/// replaced. The rows themselves stay — this is a migration, not a reset.
class CloudSourceSwitch {
  const CloudSourceSwitch({
    required this.sources,
    required this.stateStore,
    required this.cursorStore,
    required this.snapshots,
  });

  final PrefsCloudSyncSourceStore sources;
  final CloudSyncStateStore stateStore;
  final SyncCursorStore cursorStore;
  final SyncSnapshotStore snapshots;

  Future<void> switchTo(CloudSyncSource next) async {
    if (!next.isWired) {
      throw ArgumentError.value(
        next.name,
        'next',
        'source is not wired yet (missing registered client ID)',
      );
    }
    final current = sources.read();
    if (current == next) return;
    await stateStore.clear();
    await cursorStore.clear();
    await snapshots.clear();
    await sources.write(next);
  }
}
