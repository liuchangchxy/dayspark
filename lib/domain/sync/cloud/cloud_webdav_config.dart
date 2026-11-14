import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// WebDAV destination. Unlike the six drive providers this one is expected to
/// ask for an address and credentials — the task excludes it (and the
/// self-hosted server) from the "no Server address / API key" rule because a
/// WebDAV endpoint is something the user owns.
class CloudWebDavConfig {
  const CloudWebDavConfig({
    required this.baseUrl,
    this.documentPath = defaultDocumentPath,
    this.username,
    this.password,
  });

  static const String defaultDocumentPath = '/dayspark/sync.json';

  final String baseUrl;
  final String documentPath;
  final String? username;
  final String? password;

  bool get isComplete =>
      baseUrl.trim().isNotEmpty && documentPath.trim().isNotEmpty;

  /// Where a person would look for the document, for settings display.
  Uri get documentUri {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final path = documentPath.startsWith('/')
        ? documentPath
        : '/$documentPath';
    return Uri.parse('$base$path');
  }
}

abstract class CloudWebDavConfigStore {
  Future<CloudWebDavConfig?> load();
  Future<void> save(CloudWebDavConfig config);
  Future<void> clear();
}

class PrefsCloudWebDavConfigStore implements CloudWebDavConfigStore {
  PrefsCloudWebDavConfigStore(
    this._prefs, {
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  static const _baseUrlKey = 'cloud_webdav_base_url';
  static const _documentPathKey = 'cloud_webdav_document_path';
  static const _usernameKey = 'cloud_webdav_username';
  static const _passwordKey = 'cloud_webdav_password';

  final SharedPreferences _prefs;
  final FlutterSecureStorage _storage;

  @override
  Future<CloudWebDavConfig?> load() async {
    final baseUrl = _prefs.getString(_baseUrlKey);
    if (baseUrl == null || baseUrl.isEmpty) return null;
    return CloudWebDavConfig(
      baseUrl: baseUrl,
      documentPath:
          _prefs.getString(_documentPathKey) ??
          CloudWebDavConfig.defaultDocumentPath,
      username: _prefs.getString(_usernameKey),
      password: await _storage.read(key: _passwordKey),
    );
  }

  @override
  Future<void> save(CloudWebDavConfig config) async {
    await _prefs.setString(_baseUrlKey, config.baseUrl.trim());
    await _prefs.setString(
      _documentPathKey,
      config.documentPath.trim().isEmpty
          ? CloudWebDavConfig.defaultDocumentPath
          : config.documentPath.trim(),
    );
    final username = config.username?.trim();
    if (username == null || username.isEmpty) {
      await _prefs.remove(_usernameKey);
      await _storage.delete(key: _passwordKey);
    } else {
      await _prefs.setString(_usernameKey, username);
      final password = config.password;
      if (password == null || password.isEmpty) {
        await _storage.delete(key: _passwordKey);
      } else {
        await _storage.write(key: _passwordKey, value: password);
      }
    }
  }

  @override
  Future<void> clear() async {
    await _prefs.remove(_baseUrlKey);
    await _prefs.remove(_documentPathKey);
    await _prefs.remove(_usernameKey);
    await _storage.delete(key: _passwordKey);
  }
}
