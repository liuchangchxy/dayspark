import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/account_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/feature_flags_provider.dart';
import 'package:dayspark/domain/providers/sync_client_provider.dart';
import 'package:dayspark/domain/sync/sync_api_client.dart';
import 'package:dayspark/domain/sync/sync_engine.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/settings/settings_sections/account_section.dart';

import '../../../domain/sync/sync_test_support.dart';

class _FakeAuthApi implements AuthApi {
  _FakeAuthApi({this.session, this.error});

  AuthSession? session;
  Object? error;
  var loginCalls = 0;
  var registerCalls = 0;
  final List<String> emails = [];

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    loginCalls++;
    emails.add(email);
    if (error != null) throw error!;
    return session!;
  }

  @override
  Future<AuthSession> register({
    required String email,
    required String password,
  }) async {
    registerCalls++;
    emails.add(email);
    if (error != null) throw error!;
    return session!;
  }
}

AuthSession _session() => const AuthSession(
  userId: 'user-1',
  accessToken: 'access-1',
  refreshToken: 'refresh-1',
);

AuthSession _otherSession() => const AuthSession(
  userId: 'user-2',
  accessToken: 'access-2',
  refreshToken: 'refresh-2',
);

class _FixedStatusNotifier extends SyncStatusNotifier {
  _FixedStatusNotifier(this._fixed);

  final SyncStatus _fixed;

  @override
  SyncStatus build() => _fixed;
}

/// Seeds one synced-looking event + todo so identity-reset assertions can
/// check row-level sync state (server_rev / sync_id).
Future<(int, int)> _seedSyncedRows(AppDatabase db) async {
  final calendarId = await db
      .into(db.calendars)
      .insert(CalendarsCompanion.insert(name: 'Personal'));
  final eventId = await db.into(db.events).insert(
        EventsCompanion.insert(
          calendarId: calendarId,
          summary: 'synced event',
          startDt: DateTime(2026, 9, 24, 10),
          endDt: DateTime(2026, 9, 24, 11),
        ),
      );
  await (db.update(db.events)..where((t) => t.id.equals(eventId))).write(
    const EventsCompanion(
      syncId: Value('old-event-sync-id'),
      serverRev: Value(7),
    ),
  );
  final todoId = await db.into(db.todos).insert(
        TodosCompanion.insert(
          calendarId: calendarId,
          summary: 'synced todo',
        ),
      );
  await (db.update(db.todos)..where((t) => t.id.equals(todoId))).write(
    const TodosCompanion(
      syncId: Value('old-todo-sync-id'),
      serverRev: Value(3),
    ),
  );
  return (eventId, todoId);
}

Future<void> _pumpSection(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [syncTokenStoreProvider.overrideWithValue(MemoryTokenStore())],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('en'),
        home: Scaffold(body: SingleChildScrollView(child: AccountSection())),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'logged-out state renders server URL, email, password and both actions',
    (tester) async {
      await _pumpSection(tester);

      expect(find.text('Account'), findsOneWidget);
      expect(find.text('Server URL'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Login'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Register'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.person_crop_circle), findsNothing);
    },
  );

  test('login success persists config, flips sync flag ON, restarts engine',
      () async {
    final tokens = MemoryTokenStore();
    final fake = _FakeAuthApi(session: _session());
    var engineBuilds = 0;
    final container = ProviderContainer(
      overrides: [
        syncTokenStoreProvider.overrideWithValue(tokens),
        accountAuthApiFactoryProvider.overrideWithValue((baseUrl) => fake),
        syncEngineProvider.overrideWith((ref) {
          engineBuilds++;
          return null;
        }),
      ],
    );
    addTearDown(container.dispose);

    await container.read(accountAuthProvider.future);
    await container
        .read(accountAuthProvider.notifier)
        .login(
          serverUrl: 'https://sync.example.com/',
          email: ' user@example.com ',
          password: 'secret123',
        );

    final state = container.read(accountAuthProvider).valueOrNull!;
    expect(state.error, isNull);
    expect(state.email, 'user@example.com');
    expect(fake.loginCalls, 1);
    expect(fake.emails, ['user@example.com']);
    expect(tokens.refresh, 'refresh-1');

    final settings = await container.read(syncSettingsProvider.future);
    expect(settings.baseUrl, 'https://sync.example.com',
        reason: 'trailing slash trimmed');

    final flags = await container.read(featureFlagsProvider.future);
    expect(flags.isEnabled(FeatureFlag.sync), isTrue);

    expect(engineBuilds, greaterThan(0),
        reason: 'engine provider invalidated to restart with new config');
  });

  test('logout clears tokens, flips sync flag OFF, resets account state',
      () async {
    final tokens = MemoryTokenStore(
      access: 'access-1',
      refresh: 'refresh-1',
    );
    SharedPreferences.setMockInitialValues({'account_email': 'a@b.co'});
    final fake = _FakeAuthApi(session: _session());
    final container = ProviderContainer(
      overrides: [
        syncTokenStoreProvider.overrideWithValue(tokens),
        accountAuthApiFactoryProvider.overrideWithValue((baseUrl) => fake),
      ],
    );
    addTearDown(container.dispose);

    final before = await container.read(accountAuthProvider.future);
    expect(before.email, 'a@b.co');

    await container.read(accountAuthProvider.notifier).logout();

    final state = container.read(accountAuthProvider).valueOrNull!;
    expect(state.email, isNull);
    expect(state.busy, isFalse);
    expect(tokens.refresh, isNull);
    expect(tokens.access, isNull);

    final flags = await container.read(featureFlagsProvider.future);
    expect(flags.isEnabled(FeatureFlag.sync), isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('account_email'), isNull);
  });

  test('non-http server URL is rejected locally without calling the API',
      () async {
    final fake = _FakeAuthApi(session: _session());
    final container = ProviderContainer(
      overrides: [
        syncTokenStoreProvider.overrideWithValue(MemoryTokenStore()),
        accountAuthApiFactoryProvider.overrideWithValue((baseUrl) => fake),
      ],
    );
    addTearDown(container.dispose);

    await container.read(accountAuthProvider.future);
    await container
        .read(accountAuthProvider.notifier)
        .login(
          serverUrl: 'ftp://sync.example.com',
          email: 'user@example.com',
          password: 'secret123',
        );

    final state = container.read(accountAuthProvider).valueOrNull!;
    expect(state.error, AccountAuthError.invalidUrl);
    expect(fake.loginCalls, 0);

    final flags = await container.read(featureFlagsProvider.future);
    expect(flags.isEnabled(FeatureFlag.sync), isFalse);
  });

  test('register 409 maps to emailAlreadyRegistered', () async {
    final fake = _FakeAuthApi(
      error: SyncApiException(409, 'conflict', 'email already registered'),
    );
    final container = ProviderContainer(
      overrides: [
        syncTokenStoreProvider.overrideWithValue(MemoryTokenStore()),
        accountAuthApiFactoryProvider.overrideWithValue((baseUrl) => fake),
      ],
    );
    addTearDown(container.dispose);

    await container.read(accountAuthProvider.future);
    await container
        .read(accountAuthProvider.notifier)
        .register(
          serverUrl: 'https://sync.example.com',
          email: 'user@example.com',
          password: 'secret123',
        );

    final state = container.read(accountAuthProvider).valueOrNull!;
    expect(state.error, AccountAuthError.emailExists);
    expect(state.email, isNull);
    expect(fake.registerCalls, 1);
  });

  test(
      'login as a different identity resets cursor, snapshots and '
      'row sync state', () async {
    SharedPreferences.setMockInitialValues({
      'account_email': 'old@example.com',
      'last_sync_identity': 'https://sync.example.com|user-1',
      'sync_pull_cursor': 42,
      'sync_snapshot_old-event-sync-id':
          '{"rev":7,"payload":{"summary":"stale"}}',
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() => db.close());
    final (eventId, todoId) = await _seedSyncedRows(db);

    final fake = _FakeAuthApi(session: _otherSession());
    final container = ProviderContainer(
      overrides: [
        syncTokenStoreProvider.overrideWithValue(MemoryTokenStore()),
        accountAuthApiFactoryProvider.overrideWithValue((baseUrl) => fake),
        syncEngineProvider.overrideWith((ref) => null),
        databaseProvider.overrideWithValue(db),
      ],
    );
    addTearDown(container.dispose);

    await container.read(accountAuthProvider.future);
    await container
        .read(accountAuthProvider.notifier)
        .login(
          serverUrl: 'https://other.example.com/',
          email: 'new@example.com',
          password: 'secret123',
        );

    final state = container.read(accountAuthProvider).valueOrNull!;
    expect(state.error, isNull);
    expect(state.email, 'new@example.com');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('last_sync_identity'),
        'https://other.example.com|user-2');
    expect(prefs.getInt('sync_pull_cursor'), isNull,
        reason: 'stale watermark must not survive an identity switch');
    expect(prefs.getString('sync_snapshot_old-event-sync-id'), isNull,
        reason: 'old-server snapshots must be dropped');

    final event =
        await (db.select(db.events)..where((t) => t.id.equals(eventId)))
            .getSingle();
    expect(event.serverRev, 0);
    expect(event.syncId, isNull);
    final todo =
        await (db.select(db.todos)..where((t) => t.id.equals(todoId)))
            .getSingle();
    expect(todo.serverRev, 0);
    expect(todo.syncId, isNull);
  });

  test('re-login with the same identity keeps sync state untouched',
      () async {
    SharedPreferences.setMockInitialValues({
      'last_sync_identity': 'https://sync.example.com|user-1',
      'sync_pull_cursor': 42,
      'sync_snapshot_old-event-sync-id':
          '{"rev":7,"payload":{"summary":"current"}}',
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() => db.close());
    final (eventId, todoId) = await _seedSyncedRows(db);

    final fake = _FakeAuthApi(session: _session());
    final container = ProviderContainer(
      overrides: [
        syncTokenStoreProvider.overrideWithValue(MemoryTokenStore()),
        accountAuthApiFactoryProvider.overrideWithValue((baseUrl) => fake),
        syncEngineProvider.overrideWith((ref) => null),
        databaseProvider.overrideWithValue(db),
      ],
    );
    addTearDown(container.dispose);

    await container.read(accountAuthProvider.future);
    await container
        .read(accountAuthProvider.notifier)
        .login(
          serverUrl: 'https://sync.example.com/',
          email: 'user@example.com',
          password: 'secret123',
        );

    final state = container.read(accountAuthProvider).valueOrNull!;
    expect(state.error, isNull);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('last_sync_identity'),
        'https://sync.example.com|user-1');
    expect(prefs.getInt('sync_pull_cursor'), 42,
        reason: 'same identity keeps the watermark (continuity)');
    expect(prefs.getString('sync_snapshot_old-event-sync-id'), isNotNull);

    final event =
        await (db.select(db.events)..where((t) => t.id.equals(eventId)))
            .getSingle();
    expect(event.serverRev, 7);
    expect(event.syncId, 'old-event-sync-id');
    final todo =
        await (db.select(db.todos)..where((t) => t.id.equals(todoId)))
            .getSingle();
    expect(todo.serverRev, 3);
    expect(todo.syncId, 'old-todo-sync-id');
  });

  testWidgets('status line surfaces lastRejected codes when non-empty',
      (tester) async {
    SharedPreferences.setMockInitialValues({'account_email': 'a@b.co'});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          syncTokenStoreProvider.overrideWithValue(
            MemoryTokenStore(access: 'a', refresh: 'r'),
          ),
          syncEngineProvider.overrideWith((ref) => null),
          syncStatusProvider.overrideWith(
            () => _FixedStatusNotifier(
              const SyncStatus(lastRejected: ['validation', 'conflict']),
            ),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en'),
          home:
              Scaffold(body: SingleChildScrollView(child: AccountSection())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Rejected: validation, conflict'),
      findsOneWidget,
      reason: 'raw op verdict codes must appear on the status line',
    );
  });
}
