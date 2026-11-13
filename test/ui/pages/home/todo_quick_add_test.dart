import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/pages/home/home_page.dart';

GoRouter _router() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const HomePage(initialTab: 2)),
    GoRoute(
      path: '/todo/detail',
      builder: (_, __) => const Scaffold(body: SizedBox.shrink()),
    ),
    GoRoute(
      path: '/tags',
      builder: (_, __) => const Scaffold(body: SizedBox.shrink()),
    ),
    GoRoute(
      path: '/trash',
      builder: (_, __) => const Scaffold(body: SizedBox.shrink()),
    ),
  ],
);

Widget _app(AppDatabase db) => ProviderScope(
  overrides: [databaseProvider.overrideWithValue(db)],
  child: MaterialApp.router(
    routerConfig: _router(),
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

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
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

  setUp(() async {
    SharedPreferences.setMockInitialValues({'default_tab': 'calendar'});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(name: 'Test'));
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('five tasks in a row stay in the list and keep the field ready', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db));
    await _settle(tester);

    final field = find.byKey(const ValueKey('todo-quick-add'));
    expect(field, findsOneWidget);
    // The day view supplies a deadline, so it is stated before anything is
    // written instead of being attached silently.
    expect(find.byType(DsChip), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DsChip),
        matching: find.textContaining('Deadline:'),
      ),
      findsOneWidget,
    );

    for (var i = 0; i < 5; i++) {
      await tester.enterText(field, 'Quick $i');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _settle(tester);
    }

    final rows = await db.select(db.todos).get();
    expect(rows, hasLength(5));
    expect(rows.map((row) => row.summary), containsAll(['Quick 0', 'Quick 4']));
    final today = DateTime.now();
    expect(
      rows.first.dueDate,
      DateTime(today.year, today.month, today.day),
      reason: 'a task added in a day view lands on that day',
    );

    // Still on the list, with the new rows visible and the field empty and
    // focused for the next line.
    expect(find.text('Quick 0'), findsOneWidget);
    expect(find.text('Quick 4'), findsOneWidget);
    final editable = tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
    expect(editable.controller.text, isEmpty);
    expect(editable.focusNode.hasFocus, isTrue);

    await _unmount(tester);
  });

  testWidgets('quick create shows and edits the inherited deadline', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db));
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('workspace-create')));
    await _settle(tester);

    final title = find.byKey(const ValueKey('todo-quick-create-title'));
    expect(title, findsOneWidget);
    final chip = find.ancestor(
      of: find.descendant(
        of: find.byType(BottomSheet),
        matching: find.textContaining('Deadline:'),
      ),
      matching: find.byType(DsChip),
    );
    expect(chip, findsOneWidget);
    expect(
      find.descendant(of: chip, matching: find.textContaining('Deadline:')),
      findsOneWidget,
    );

    await tester.tap(chip);
    await _settle(tester);
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await _settle(tester);

    await tester.enterText(title, 'Visible deadline');
    await tester.tap(find.widgetWithText(DsButton, 'Save'));
    await _settle(tester);

    final row = (await db.select(db.todos).get()).single;
    expect(row.summary, 'Visible deadline');
    final now = DateTime.now();
    expect(row.dueDate, DateTime(now.year, now.month, now.day));
    await _unmount(tester);
  });
}
