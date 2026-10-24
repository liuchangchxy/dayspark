import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/todo/todo_form_page.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

/// Everything typed in a form is a draft until Save. Leaving must therefore
/// ask, and the question must be owned by the form itself — a global Escape
/// binding would have popped the route before the form could ask.
(GoRouter, Widget) _app(AppDatabase db, Todo todo) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: Text('list')),
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
            summary: 'Original title',
            dueDate: Value(DateTime(2026, 10, 30, 18)),
          ),
        );
    todo = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(id))).getSingle();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> openAndType(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final (router, app) = _app(db, todo);
    await tester.pumpWidget(app);
    await _settle(tester);
    router.push('/todo/edit');
    await _settle(tester);
    // The field is empty on first open, so re-entering the same text is not a
    // change; type something the user would notice as a leaked draft.
    await tester.enterText(find.byType(TextField).first, 'Edited title');
    await tester.pump();
  }

  testWidgets('Escape with a dirty draft asks before throwing it away', (
    tester,
  ) async {
    await openAndType(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);

    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await _settle(tester);

    expect(find.byType(TodoFormPage), findsOneWidget);
    expect(find.text('Discard changes?'), findsNothing);

    final rows = await db.select(db.todos).get();
    expect(rows.single.summary, 'Original title', reason: 'nothing was saved');
    await _unmount(tester);
  });

  testWidgets('discarding leaves the form without writing the draft', (
    tester,
  ) async {
    await openAndType(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    await tester.tap(find.text('Discard'));
    await _settle(tester);

    expect(find.byType(TodoFormPage), findsNothing);
    expect(find.text('list'), findsOneWidget);

    final rows = await db.select(db.todos).get();
    expect(rows, hasLength(1));
    expect(rows.single.summary, 'Original title');
    await _unmount(tester);
  });

  testWidgets('an untouched form leaves without asking', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final (router, app) = _app(db, todo);
    await tester.pumpWidget(app);
    await _settle(tester);
    router.push('/todo/edit');
    await _settle(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);

    expect(find.text('Discard changes?'), findsNothing);
    await _unmount(tester);
  });
}
