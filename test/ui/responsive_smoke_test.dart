import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/event/event_detail_page.dart';
import 'package:dayspark/ui/pages/search/search_page.dart';
import 'package:dayspark/ui/pages/settings/settings_page.dart';
import 'package:dayspark/ui/pages/todo/todo_detail_page.dart';
import 'package:dayspark/ui/pages/todo/todo_form_page.dart';
import 'package:dayspark/ui/pages/trash/trash_page.dart';

/// The three surfaces the interaction contract names must all lay out at the
/// three reference widths. A page that overflows at 768 is a bug the desktop
/// and phone checks each miss on their own.
///
/// This is a layout smoke, not a journey: it answers "does anything break at
/// this width", and the behaviour of each page is covered by its own file.
const _viewports = <(String, Size)>[
  ('phone', Size(390, 844)),
  ('tablet', Size(820, 900)),
  ('desktop', Size(1440, 900)),
];

(GoRouter, Widget) _app(AppDatabase db, Widget page) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(path: '/page', builder: (_, __) => page),
    ],
  );
  return (
    router,
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
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
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Todo todo;
  late CalendaEventAdapter event;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final calendarId = await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(name: 'Personal'));
    final todoId = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Write the quarterly report',
            dueDate: Value(DateTime(2026, 10, 30, 18)),
            description: Value('Numbers first, narrative second.'),
          ),
        );
    todo = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(todoId))).getSingle();
    final eventId = await db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            calendarId: calendarId,
            summary: 'Design review',
            startDt: DateTime(2026, 10, 30, 10),
            endDt: DateTime(2026, 10, 30, 11),
            location: const Value('Room 3'),
          ),
        );
    event = CalendaEventAdapter.fromDrift(
      await (db.select(
        db.events,
      )..where((row) => row.id.equals(eventId))).getSingle(),
    );
  });

  tearDown(() async {
    await db.close();
  });

  final pages = <String, Widget Function()>{
    'todo detail': () => TodoDetailPage(todo: todo),
    'todo form': () => TodoFormPage(todo: todo),
    'event detail': () => EventDetailPage(event: event),
    'settings': () => const SettingsPage(),
    'trash': () => const TrashPage(),
    'search': () => const SearchPage(),
  };

  for (final entry in pages.entries) {
    for (final (viewport, size) in _viewports) {
      testWidgets('${entry.key} lays out at $viewport', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final (router, app) = _app(db, entry.value());
        await tester.pumpWidget(app);
        await _settle(tester);
        router.push('/page');
        await _settle(tester);

        expect(
          tester.takeException(),
          isNull,
          reason: '${entry.key} at ${size.width.toInt()}dp',
        );
        await _unmount(tester);
      });
    }
  }
}
