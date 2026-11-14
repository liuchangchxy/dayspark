/// Storage seam for the cloud-drive transports.
///
/// One document, read then conditionally written: everything the DaySpark
/// server would arbitrate happens in `mergeCloudOps`, so the backend's only
/// job is to make a lost race visible instead of silently overwriting the
/// peer's edit. Backends that cannot express "write only if unchanged"
/// (no ETag / rev / If-Match) cannot serve this transport — see
/// `docs/cloud-sync-providers.md`.
class CloudFileSnapshot {
  const CloudFileSnapshot({required this.body, required this.etag});

  final String body;

  /// Opaque validator from the last read/write, replayed as `If-Match`.
  final String etag;
}

/// The document changed between our read and our write: the caller must
/// re-read, re-merge its still-pending ops, and try again.
class CloudPreconditionFailed implements Exception {
  const CloudPreconditionFailed();

  @override
  String toString() => 'CloudPreconditionFailed';
}

class CloudBackendException implements Exception {
  const CloudBackendException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      'CloudBackendException(${statusCode ?? '-'}): $message';
}

abstract class CloudSyncBackend {
  /// Null when the document does not exist yet (first device on this drive).
  Future<CloudFileSnapshot?> read();

  /// Returns the validator to present on the next write.
  ///
  /// [ifMatch] is the ETag from the snapshot we merged against; null means
  /// "the document must not exist", which must be enforced as an
  /// if-none-match create rather than a blind overwrite.
  Future<String> write({required String body, required String? ifMatch});

  /// Prepares the destination (folders, etc.) before the first write.
  Future<void> ensureReady();

  /// Human-readable target for settings/status, e.g. the URL.
  String get displayTarget;
}
