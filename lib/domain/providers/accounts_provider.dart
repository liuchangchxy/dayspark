import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';

/// Stream all accounts from the database.
final accountsProvider = StreamProvider<List<Account>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.accounts)).watch();
});

/// Add a new CalDAV account to the database.
final addAccountProvider =
    Provider<
      Future<Account> Function({
        required String name,
        required String serverUrl,
        required String username,
        required String password,
      })
    >((ref) {
      return ({
        required name,
        required serverUrl,
        required username,
        required password,
      }) async {
        final db = ref.read(databaseProvider);
        const storage = FlutterSecureStorage();
        final id = await db
            .into(db.accounts)
            .insert(
              AccountsCompanion.insert(
                name: Value(name),
                serverUrl: serverUrl,
                username: username,
                password: '',
              ),
            );
        await storage.write(key: 'account_${id}_password', value: password);
        ref.invalidate(accountsProvider);
        return await (db.select(
          db.accounts,
        )..where((t) => t.id.equals(id))).getSingle();
      };
    });

/// Delete an account and all its associated calendars from the database.
final deleteAccountProvider = Provider<Future<void> Function(int accountId)>((
  ref,
) {
  return (int accountId) async {
    final db = ref.read(databaseProvider);
    const storage = FlutterSecureStorage();
    await storage.delete(key: 'account_${accountId}_password');

    await (db.delete(
      db.calendars,
    )..where((t) => t.accountId.equals(accountId))).go();

    await (db.delete(db.accounts)..where((t) => t.id.equals(accountId))).go();

    ref.invalidate(accountsProvider);
  };
});

/// Migrate plaintext passwords from DB to FlutterSecureStorage.
Future<void> migratePasswordsToSecureStorage(AppDatabase db) async {
  const storage = FlutterSecureStorage();
  final accounts = await (db.select(db.accounts)).get();
  for (final account in accounts) {
    if (account.password.isNotEmpty) {
      await storage.write(
        key: 'account_${account.id}_password',
        value: account.password,
      );
      await (db.update(db.accounts)
            ..where((t) => t.id.equals(account.id)))
          .write(const AccountsCompanion(password: Value('')));
    }
  }
}
