import 'dart:async';

import 'package:dayspark/domain/sync/cloud/cloud_sync_backend.dart';
import 'package:dayspark/domain/sync/cloud/cloud_sync_settings.dart';

/// In-memory drive with the same contract a WebDAV server has: a validator
/// that changes on every accepted write, and a write that fails when the
/// validator moved since the read.
class MemoryCloudBackend implements CloudSyncBackend {
  String? body;
  String? etag = 'etag-0';
  int version = 0;
  int reads = 0;
  int writes = 0;

  /// Number of upcoming writes to lose to a peer that got there first.
  int dropNextWrites = 0;

  /// Body to install as "the peer's newer document" for a dropped write.
  String? peerBody;

  @override
  String get displayTarget => 'memory://dayspark/sync.json';

  @override
  Future<void> ensureReady() async {}

  @override
  Future<CloudFileSnapshot?> read() async {
    reads++;
    if (body == null) return null;
    return CloudFileSnapshot(body: body!, etag: etag!);
  }

  @override
  Future<String> write({required String body, required String? ifMatch}) async {
    writes++;
    if (dropNextWrites > 0) {
      dropNextWrites--;
      if (peerBody != null) {
        this.body = peerBody;
        version++;
        etag = 'etag-$version';
      }
      throw const CloudPreconditionFailed();
    }
    final current = this.body == null ? null : etag;
    if (ifMatch != current) throw const CloudPreconditionFailed();
    this.body = body;
    version++;
    etag = 'etag-$version';
    return etag!;
  }
}

class MemoryCloudStateStore implements CloudSyncStateStore {
  String? etag;
  bool provisioned = false;
  DateTime? lastSyncAt;

  @override
  Future<String?> readEtag() async => etag;

  @override
  Future<void> writeEtag(String? value) async => etag = value;

  @override
  Future<bool> isProvisioned() async => provisioned;

  @override
  Future<void> markProvisioned() async => provisioned = true;

  @override
  Future<DateTime?> readLastSyncAt() async => lastSyncAt;

  @override
  Future<void> writeLastSyncAt(DateTime at) async => lastSyncAt = at;

  @override
  Future<void> clear() async {
    etag = null;
    provisioned = false;
    lastSyncAt = null;
  }
}
