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
import 'package:dayspark/ui/pages/todo/todo_detail_page.dart';
import 'package:dayspark/ui/pages/todo/todo_form_page.dart';

/// "Look at this" and "change this" must not be the same gesture: opening a
/// todo shows it, and reaching the form takes a deliberate second step.
Widget _app(AppDatabase db, Todo todo) {
  final router = GoRouter(
    initialLocation: '/todo/detail',
    routes: [
      GoRoute(path: '/', builder: (_, __) => const Scaffold()),
      GoRoute(
        path: '/todo/detail',
        builder: (_, __) => TodoDetailPage(todo: todo),
      ),
      GoRoute(
        path: '/todo/edit',
        builder: (_, state) => TodoFormPage(todo: state.extra as Todo),
      ),
    ],
  );
  return ProviderScope(
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

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final calendarId = await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(name: 'Test'));
    final due = DateTime(2026, 10, 24, 18);
    final id = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Write the report',
            dueDate: Value(due),
          ),
        );
    todo = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(id))).getSingle();
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('detail reads the todo without a single editable field', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db, todo));
    await _settle(tester);

    expect(find.text('Write the report'), findsOneWidget);
    expect(
      find.byType(TextField),
      findsNothing,
      reason: 'a detail page that offers text fields is an edit page in disguise',
    );
    await _unmount(tester);
  });

  testWidgets('edit is a second, explicit step from detail', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db, todo));
    await _settle(tester);
    expect(find.byType(TodoFormPage), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await _settle(tester);

    expect(find.byType(TodoFormPage), findsOneWidget);
    await _unmount(tester);
  });
}
