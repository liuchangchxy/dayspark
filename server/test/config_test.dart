import 'package:dayspark_server/server.dart';
import 'package:test/test.dart';

void main() {
  group('Config.fromEnv', () {
    test('keeps zero-config dev default outside Docker', () {
      final config = Config.fromEnv(const {});
      expect(config.jwtSecret, 'dayspark-dev-insecure-secret');
      expect(config.dbPath, './data/dayspark.db');
      expect(config.port, 8787);
    });

    test('explicit JWT_SECRET is used verbatim', () {
      final config = Config.fromEnv(const {
        'JWT_SECRET': 'real-secret',
        'PORT': '9000',
        'DB_PATH': '/data/x.db',
      });
      expect(config.jwtSecret, 'real-secret');
      expect(config.port, 9000);
      expect(config.dbPath, '/data/x.db');
    });

    test('Docker mode (REQUIRE_JWT_SECRET=1) fails fast on empty secret',
        () {
      expect(
        () => Config.fromEnv(const {'REQUIRE_JWT_SECRET': '1'}),
        throwsStateError,
      );
      expect(
        () => Config.fromEnv(const {
          'REQUIRE_JWT_SECRET': '1',
          'JWT_SECRET': '',
        }),
        throwsStateError,
      );
    });

    test('Docker mode boots when a secret is provided', () {
      final config = Config.fromEnv(const {
        'REQUIRE_JWT_SECRET': '1',
        'JWT_SECRET': 'compose-secret',
      });
      expect(config.jwtSecret, 'compose-secret');
    });
  });
}
