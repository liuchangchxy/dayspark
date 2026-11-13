import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/home/home_page.dart';

Widget _app({required AppDatabase db, required DateTime Function() clock}) {
  return ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: MaterialApp(
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: HomePage(clock: clock),
    ),
  );
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

Finder _rowDueLabel(int todoId, String text) {
  final row = find
      .ancestor(
        of: find.byKey(ValueKey('action-complete-$todoId')),
        matching: find.byType(Row),
      )
      .first;
  return find.descendant(of: row, matching: find.text(text));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late int calendarId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    calendarId = await db
        .into(db.calendars)
        .insert(
          CalendarsCompanion.insert(
            name: 'Default',
            color: const Value('#2196F3'),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets(
    'Action projection advances from day N to day N+1 across midnight and on resume without restart',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // Day N: 2026-10-06 at 23:59:50 (10s before midnight)
      var currentTime = DateTime(2026, 10, 6, 23, 59, 50);

      // Todo A is due on Day N (2026-10-06)
      final dayNTodoId = await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Task Due Day N',
              dueDate: Value(DateTime(2026, 10, 6)),
            ),
          );

      // Todo B is due on Day N+1 (2026-10-07)
      final dayNPlusOneTodoId = await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Task Due Day N+1',
              dueDate: Value(DateTime(2026, 10, 7)),
            ),
          );

      await tester.pumpWidget(_app(db: db, clock: () => currentTime));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // On Day N:
      // - Task Due Day N appears in the sheet's open-today rows
      // - Task Due Day N+1 does not appear in Action timeline/due/overdue
      expect(find.text('Task Due Day N'), findsOneWidget);
      expect(find.text('Task Due Day N+1'), findsNothing);
      expect(_rowDueLabel(dayNTodoId, 'Today'), findsOneWidget);
      expect(find.text('1 still open today'), findsOneWidget);
      expect(find.text('Overdue'), findsNothing);

      // 1. Rollover to Day N+1 via midnight timer
      // Advance clock to Day N+1: 2026-10-07 00:00:05 (15 seconds elapsed)
      currentTime = DateTime(2026, 10, 7, 0, 0, 5);
      await tester.pump(const Duration(seconds: 15));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // On Day N+1 without restart:
      // - Task Due Day N is now overdue
      // - Task Due Day N+1 is now open today
      expect(find.text('Task Due Day N'), findsOneWidget);
      expect(find.text('Task Due Day N+1'), findsOneWidget);
      // The sheet's header counts what is still open today.
      expect(find.text('2 still open today'), findsOneWidget);
      expect(_rowDueLabel(dayNTodoId, 'Overdue'), findsOneWidget);

      // 2. Rollover to Day N+2 via app resume
      // Advance clock to Day N+2: 2026-10-08 10:00:00
      currentTime = DateTime(2026, 10, 8, 10, 0, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // On Day N+2 without restart:
      // - Both tasks are now overdue
      expect(find.text('Task Due Day N'), findsOneWidget);
      expect(find.text('Task Due Day N+1'), findsOneWidget);
      expect(_rowDueLabel(dayNTodoId, 'Overdue'), findsOneWidget);
      expect(_rowDueLabel(dayNPlusOneTodoId, 'Overdue'), findsOneWidget);

      await _unmount(tester);
    },
  );
}
