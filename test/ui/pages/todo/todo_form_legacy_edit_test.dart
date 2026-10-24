import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/todo/todo_form_page.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

/// A legacy recurrence rule changes how the date fields are *interpreted*; it
/// must never change whether Save updates or creates. The form used to gate
/// that decision on `_isEditing && !_unknownLegacy`, so editing an imported
/// recurring todo inserted a copy and left the original untouched.
(GoRouter, Widget) _app(AppDatabase db, Todo todo) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/todo/edit',
        builder: (_, __) => TodoFormPage(todo: todo),
      ),
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
  setUpAll(tzdata.initializeTimeZones);

  late AppDatabase db;
  late Todo todo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final calendarId = await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(name: 'Test'));
    final id = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Imported weekly review',
            startDate: Value(DateTime(2026, 10, 5, 9)),
            rrule: const Value('FREQ=WEEKLY;BYDAY=MO'),
            recurrenceLegacyState: const Value('unknownLegacy'),
          ),
        );
    todo = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(id))).getSingle();
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('editing a legacy recurring Todo updates it instead of copying', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final (router, app) = _app(db, todo);
    await tester.pumpWidget(app);
    await _settle(tester);
    // Open the form the way the product does: detail pushes edit, so Save can
    // pop back to the page the user came from.
    router.push('/todo/edit');
    await _settle(tester);

    await tester.enterText(find.byType(TextField).first, 'Renamed review');
    await tester.pump();

    await tester.tap(find.text('Save'));
    await _settle(tester);

    final rows = await db.select(db.todos).get();
    expect(rows, hasLength(1), reason: 'Save must not insert a second row');
    expect(rows.single.id, todo.id, reason: 'the original row is the target');
    expect(rows.single.summary, 'Renamed review');

    await _unmount(tester);
  });
}
