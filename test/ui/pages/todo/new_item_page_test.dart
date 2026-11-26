import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/todo/new_item_page.dart';

Widget _routerApp(
  AppDatabase db,
  GoRouter router, {
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db), ...overrides],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(tzdata.initializeTimeZones);

  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db
        .into(db.calendars)
        .insert(
          CalendarsCompanion.insert(
            name: 'Personal',
            color: const Value('#2563EB'),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  Future<GoRouter> pumpPage(
    WidgetTester tester,
    Widget page, {
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/new',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const SizedBox.shrink()),
        GoRoute(path: '/new', builder: (_, __) => page),
      ],
    );
    await tester.pumpWidget(_routerApp(db, router, overrides: overrides));
    await _settle(tester);
    return router;
  }

  testWidgets('an empty title is refused and nothing is written', (
    tester,
  ) async {
    await pumpPage(tester, const NewItemPage());

    await tester.tap(find.byKey(const ValueKey('new-item-primary')));
    await _settle(tester);

    expect(await db.select(db.todos).get(), isEmpty);
    expect(find.text('Title cannot be empty.'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('the page writes a todo through the capture writers', (
    tester,
  ) async {
    final router = await pumpPage(tester, const NewItemPage());

    await tester.enterText(
      find.byKey(const ValueKey('new-item-title')),
      'Weekly review',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('new-item-primary')));
    await _settle(tester);

    final todos = await db.select(db.todos).get();
    expect(todos, hasLength(1));
    expect(todos.single.summary, 'Weekly review');
    final calendars = await db.select(db.calendars).get();
    expect(
      calendars.map((calendar) => calendar.id),
      contains(todos.single.calendarId),
    );
    expect(router.state.uri.path, '/');

    await _unmount(tester);
  });

  testWidgets('a failed write keeps the page and the typed title', (
    tester,
  ) async {
    final start = DateTime(2026, 11, 20, 11);
    await pumpPage(
      tester,
      NewItemPage(
        initialStart: start,
        initialEnd: start.add(const Duration(hours: 1)),
      ),
      overrides: [
        createEventProvider.overrideWithValue(
          ({
            required int calendarId,
            required String summary,
            required DateTime startDt,
            required DateTime endDt,
            required bool isAllDay,
            String? description,
            String? location,
            String? rrule,
          }) async => throw StateError('write failed'),
        ),
      ],
    );

    await tester.enterText(
      find.byKey(const ValueKey('new-item-title')),
      'Design review',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('new-item-type-event')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('new-item-primary')));
    await _settle(tester);

    expect(await db.select(db.events).get(), isEmpty);
    expect(find.byKey(const ValueKey('new-item-primary')), findsOneWidget);
    expect(find.text('Design review'), findsOneWidget);
    expect(find.textContaining('Save failed'), findsWidgets);

    await _unmount(tester);
  });
  testWidgets('switching to event writes an event, not a todo', (tester) async {
    final start = DateTime(2026, 11, 20, 11);
    await pumpPage(
      tester,
      NewItemPage(
        initialStart: start,
        initialEnd: start.add(const Duration(hours: 1)),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('new-item-type-event')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('new-item-title')),
      'Design review',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('new-item-primary')));
    await _settle(tester);

    final events = await db.select(db.events).get();
    expect(events, hasLength(1));
    expect(events.single.summary, 'Design review');
    expect(events.single.startDt, start);
    expect(await db.select(db.todos).get(), isEmpty);

    await _unmount(tester);
  });
}
