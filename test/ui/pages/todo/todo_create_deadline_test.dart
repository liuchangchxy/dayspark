import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/todo/todo_create_page.dart';

import 'package:go_router/go_router.dart';

Widget _wrap(AppDatabase db) {
  final router = GoRouter(
    initialLocation: '/todo/new',
    routes: [
      GoRoute(path: '/', builder: (_, __) => const Scaffold(body: SizedBox.shrink())),
      GoRoute(path: '/todo/new', builder: (_, __) => const TodoCreatePage()),
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
  await tester.pump(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.calendars).insert(
          CalendarsCompanion.insert(
            name: 'Default Calendar',
            color: const Value('#2196F3'),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('new ordinary Todo defaults to null dueDate when no deadline is picked', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(db));
    await _settle(tester);

    final textField = find.byType(TextField).first;
    await tester.enterText(textField, 'Inbox item without deadline');
    await tester.pump();

    final noDueDateChip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'No due date'),
    );
    expect(noDueDateChip.selected, isTrue);

    final saveButton = find.text('Save');
    expect(saveButton, findsOneWidget);
    await tester.tap(saveButton);
    await _settle(tester);

    final todos = await db.select(db.todos).get();
    expect(todos, hasLength(1));
    expect(todos.first.summary, 'Inbox item without deadline');
    expect(todos.first.dueDate, isNull, reason: 'Creating without picking deadline must leave dueDate null');

    await _unmount(tester);
  });

  testWidgets('new ordinary Todo saves dueDate when user explicitly picks a date', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(db));
    await _settle(tester);

    final textField = find.byType(TextField).first;
    await tester.enterText(textField, 'Item due tomorrow');
    await tester.pump();

    final tomorrowChip = find.widgetWithText(ChoiceChip, 'Tomorrow');
    expect(tomorrowChip, findsOneWidget);
    await tester.tap(tomorrowChip);
    await tester.pump();

    final saveButton = find.text('Save');
    await tester.tap(saveButton);
    await _settle(tester);

    final todos = await db.select(db.todos).get();
    expect(todos, hasLength(1));
    expect(todos.first.summary, 'Item due tomorrow');
    expect(todos.first.dueDate, isNotNull);
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    expect(todos.first.dueDate!.year, tomorrow.year);
    expect(todos.first.dueDate!.month, tomorrow.month);
    expect(todos.first.dueDate!.day, tomorrow.day);

    await _unmount(tester);
  });
}
