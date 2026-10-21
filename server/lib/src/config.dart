import 'dart:io';

const String serverVersion = '0.1.0';

class Config {
  const Config({
    required this.dbPath,
    required this.port,
    required this.jwtSecret,
    this.accessTtl = const Duration(minutes: 15),
    this.refreshTtl = const Duration(days: 30),
    this.sseHeartbeat = const Duration(seconds: 25),
    this.attachmentDir = './data/attachments',
  });

  factory Config.fromEnv([Map<String, String>? environ]) {
    final env = environ ?? Platform.environment;
    final jwtSecret = env['JWT_SECRET'] ?? '';
    // Docker sets REQUIRE_JWT_SECRET=1 so a container refuses to boot
    // without an explicit secret; local `dart run bin/server.dart` keeps
    // the zero-config dev default. An empty JWT_SECRET is treated as
    // unset (never used as a literal empty signing key).
    if (env['REQUIRE_JWT_SECRET'] == '1' && jwtSecret.isEmpty) {
      throw StateError(
        'JWT_SECRET is empty but REQUIRE_JWT_SECRET=1 — '
        'generate one with `openssl rand -hex 32`',
      );
    }
    return Config(
      dbPath: env['DB_PATH'] ?? './data/dayspark.db',
      port: int.tryParse(env['PORT'] ?? '') ?? 8787,
      jwtSecret: jwtSecret.isEmpty
          ? 'dayspark-dev-insecure-secret'
          : jwtSecret,
      attachmentDir: env['ATTACHMENT_DIR'] ?? './data/attachments',
    );
  }

  final String dbPath;
  final int port;
  final String jwtSecret;
  final Duration accessTtl;
  final Duration refreshTtl;
  final Duration sseHeartbeat;

  /// Attachment blobs are files, not rows: they need their own mount (a
  /// volume in Docker) so a container rebuild does not take user files with
  /// it while the SQLite db survives.
  final String attachmentDir;
}
