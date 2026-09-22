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
  });

  factory Config.fromEnv([Map<String, String>? environ]) {
    final env = environ ?? Platform.environment;
    return Config(
      dbPath: env['DB_PATH'] ?? './data/dayspark.db',
      port: int.tryParse(env['PORT'] ?? '') ?? 8787,
      // Dev default keeps `dart run bin/server.dart` zero-config; any real
      // deployment must set JWT_SECRET or access tokens are forgeable.
      jwtSecret: env['JWT_SECRET'] ?? 'dayspark-dev-insecure-secret',
    );
  }

  final String dbPath;
  final int port;
  final String jwtSecret;
  final Duration accessTtl;
  final Duration refreshTtl;
  final Duration sseHeartbeat;
}
