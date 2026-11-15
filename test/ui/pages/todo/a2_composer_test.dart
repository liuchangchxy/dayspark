import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/todo/a2_composer.dart';

Widget _app(AppDatabase db, Widget child) {
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
      home: Scaffold(body: child),
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

  late AppDatabase db;
  var calendarId = 0;
  final day = DateTime(2026, 10, 17);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    calendarId = await db
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

  testWidgets('opens on pure capture and promises what save will do', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(db, A2ComposerSheet(contextDate: _DayContext.value)),
    );
    await _settle(tester);

    expect(find.text('Not set'), findsOneWidget);
    expect(find.text('No slot chosen'), findsOneWidget);
    expect(
      find.text('Saving without a slot files this under Unplanned.'),
      findsOneWidget,
    );
    expect(find.text('Save to Unplanned'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('choosing a slot changes the promise and writes an allocation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        db,
        A2ComposerSheet(contextDate: day),
      ),
    );
    await _settle(tester);

    await tester.enterText(
      find.byKey(const ValueKey('a2-composer-title')),
      'Write the retro',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);

    await tester.tap(find.byKey(const ValueKey('a2-composer-plan')));
    await tester.pump();

    expect(find.text('09:00–10:00'), findsOneWidget);
    await tester.tap(find.text('14:00–15:00'));
    await tester.pump();

    expect(find.text('Plan for 10/17'), findsOneWidget);
    expect(
      find.text(
        'This is a planned execution, not a deadline. '
        'Set the deadline separately.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Plan for 10/17'));
    await _settle(tester);

    final todos = await db.select(db.todos).get();
    expect(todos, hasLength(1));
    expect(todos.single.summary, 'Write the retro');
    // A slot is not a deadline: dueDate stays null.
    expect(todos.single.dueDate, isNull);
    final allocations = await db.select(db.taskAllocations).get();
    expect(allocations, hasLength(1));
    expect(allocations.single.todoId, todos.single.id);
    expect(allocations.single.startAt.toLocal(), DateTime(2026, 10, 17, 14));
    expect(allocations.single.endAt.toLocal(), DateTime(2026, 10, 17, 15));
    expect(calendarId, greaterThan(0));

    await _unmount(tester);
  });

  testWidgets('scheduling an existing todo needs a slot and writes no deadline', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final todoId = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Call mum',
          ),
        );
    final todo = await (db.select(db.todos)
          ..where((row) => row.id.equals(todoId)))
        .getSingle();

    await tester.pumpWidget(
      _app(db, A2ComposerSheet(contextDate: day, todo: todo)),
    );
    await _settle(tester);

    expect(find.text('Call mum'), findsOneWidget);
    // Nothing to save until a slot is chosen.
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('a2-composer-plan')));
    await tester.pump();
    await tester.tap(find.text('16:00–17:00'));
    await tester.pump();
    await tester.tap(find.text('Plan for 10/17'));
    await _settle(tester);

    final refreshed = await (db.select(db.todos)
          ..where((row) => row.id.equals(todoId)))
        .getSingle();
    expect(refreshed.dueDate, isNull);
    final allocations = await db.select(db.taskAllocations).get();
    expect(allocations, hasLength(1));
    expect(allocations.single.startAt.toLocal(), DateTime(2026, 10, 17, 16));

    await _unmount(tester);
  });
}

/// Const stand-in so the first case can be `const`.
abstract final class _DayContext {
  static final DateTime value = DateTime(2026, 10, 17);
}
