import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:workmanager/workmanager.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/data/remote/caldav/caldav_client.dart';
import 'package:dayspark/data/remote/caldav/sync_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final db = AppDatabase();
    try {
      const storage = FlutterSecureStorage();

      final accounts = await (db.select(db.accounts)).get();
      for (final account in accounts) {
        final password =
            await storage.read(key: 'account_${account.id}_password') ??
            account.password;
        final client = CalDavClient(
          baseUrl: account.serverUrl,
          username: account.username,
          password: password,
        );
        final service = SyncService(db: db, client: client);
        try {
          await service.incrementalSync();
        } catch (_) {
        } finally {
          service.dispose();
        }
      }

      if (accounts.isEmpty) {
        final url = await storage.read(key: 'caldav_server_url');
        final username = await storage.read(key: 'caldav_username');
        final password = await storage.read(key: 'caldav_password');
        if (url != null && username != null && password != null) {
          final client = CalDavClient(
            baseUrl: url,
            username: username,
            password: password,
          );
          final service = SyncService(db: db, client: client);
          try {
            await service.incrementalSync();
          } catch (_) {
          } finally {
            service.dispose();
          }
        }
      }

      return true;
    } catch (_) {
      return false;
    } finally {
      await db.close();
    }
  });
}
