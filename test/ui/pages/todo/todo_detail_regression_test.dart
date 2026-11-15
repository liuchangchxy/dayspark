import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/pages/todo/todo_detail_page.dart';
import 'package:dayspark/ui/pages/todo/todo_form_page.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

Widget _app(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: child,
    ),
  );
}

Finder _notesField() => find.byWidgetPredicate(
  (widget) =>
      widget is TextField && widget.decoration?.hintText == 'Description',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Todo todo;
  late int calendarId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    calendarId = await db
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

  testWidgets('failed title save keeps input and retries unchanged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var attempts = 0;

    await tester.pumpWidget(
      _app(
        TodoDetailPage(todo: todo),
        overrides: [
          databaseProvider.overrideWithValue(db),
          updateTodoProvider.overrideWithValue((
            id,
            data, {
            RecurrenceSpec? recurrenceSpec,
            bool replaceRecurrence = false,
          }) async {
            attempts++;
            if (attempts == 1) throw StateError('write failed');
            await (db.update(
              db.todos,
            )..where((t) => t.id.equals(id))).write(data);
          }),
        ],
      ),
    );
    await _settle(tester);

    final title = find.byKey(const ValueKey('todo-detail-title'));
    await tester.enterText(title, 'Changed title');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();

    expect(attempts, 1);
    expect(tester.widget<TextField>(title).controller!.text, 'Changed title');
    expect(
      (await (db.select(
        db.todos,
      )..where((row) => row.id.equals(todo.id))).getSingle()).summary,
      'Write the report',
    );
    expect(find.text("That didn't work. Please try again."), findsOneWidget);

    tester.widget<TextField>(title).focusNode!.unfocus();
    await _settle(tester);

    expect(attempts, 2);
    expect(
      (await (db.select(
        db.todos,
      )..where((row) => row.id.equals(todo.id))).getSingle()).summary,
      'Changed title',
    );
    await _unmount(tester);
  });

  testWidgets('failed notes save keeps input and retries unchanged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var attempts = 0;

    await tester.pumpWidget(
      _app(
        TodoDetailPage(todo: todo),
        overrides: [
          databaseProvider.overrideWithValue(db),
          updateTodoProvider.overrideWithValue((
            id,
            data, {
            RecurrenceSpec? recurrenceSpec,
            bool replaceRecurrence = false,
          }) async {
            attempts++;
            if (attempts == 1) throw StateError('write failed');
            await (db.update(
              db.todos,
            )..where((t) => t.id.equals(id))).write(data);
          }),
        ],
      ),
    );
    await _settle(tester);

    final notes = _notesField();
    await tester.enterText(notes, 'Changed notes');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();

    expect(attempts, 1);
    expect(tester.widget<TextField>(notes).controller!.text, 'Changed notes');
    expect(
      (await (db.select(
        db.todos,
      )..where((row) => row.id.equals(todo.id))).getSingle()).description,
      isNull,
    );

    tester.widget<TextField>(notes).focusNode!.unfocus();
    await _settle(tester);

    expect(attempts, 2);
    expect(
      (await (db.select(
        db.todos,
      )..where((row) => row.id.equals(todo.id))).getSingle()).description,
      'Changed notes',
    );
    await _unmount(tester);
  });

  testWidgets('a failed live read shows retry instead of a spinner', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        TodoDetailPage(todo: todo),
        overrides: [
          databaseProvider.overrideWithValue(db),
          allTodosProvider.overrideWith(
            (ref) => Stream<List<Todo>>.error(StateError('load failed')),
          ),
        ],
      ),
    );
    await _settle(tester);

    expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await _unmount(tester);
  });

  testWidgets('a failed detail delete keeps the page and re-enables delete', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var attempts = 0;

    await tester.pumpWidget(
      _app(
        TodoDetailPage(todo: todo),
        overrides: [
          databaseProvider.overrideWithValue(db),
          deleteTodoProvider.overrideWithValue((id) async {
            attempts++;
            throw StateError('delete failed');
          }),
        ],
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('Move to Trash'));
    await _settle(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Move to Trash'));
    await _settle(tester);

    expect(attempts, 1);
    expect(find.text("That didn't work. Please try again."), findsOneWidget);
    expect(find.byKey(const ValueKey('todo-detail-title')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(seconds: 5));
    await _settle(tester);
    await tester.tap(find.text('Move to Trash'));
    await _settle(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(attempts, 1, reason: 'the first attempt failed before a second tap');
    await _unmount(tester);
  });

  testWidgets('a completed todo cannot be scheduled and says why', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await (db.update(
      db.todos,
    )..where((row) => row.id.equals(todo.id))).write(
      TodosCompanion(status: Value('COMPLETED')),
    );

    await tester.pumpWidget(
      _app(
        TodoDetailPage(todo: todo),
        overrides: [databaseProvider.overrideWithValue(db)],
      ),
    );
    await _settle(tester);

    expect(find.text('Schedule · Completed'), findsOneWidget);
    await tester.tap(find.text('Schedule'));
    await _settle(tester);
    expect(find.byKey(const ValueKey('a2-composer-plan')), findsNothing);
    await _unmount(tester);
  });

  testWidgets('a failed form delete keeps the form and re-enables delete', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var attempts = 0;

    await tester.pumpWidget(
      _app(
        TodoFormPage(todo: todo),
        overrides: [
          databaseProvider.overrideWithValue(db),
          deleteTodoProvider.overrideWithValue((id) async {
            attempts++;
            throw StateError('delete failed');
          }),
        ],
      ),
    );
    await _settle(tester);

    await tester.tap(find.byTooltip('Move to Trash'));
    await _settle(tester);
    await tester.tap(find.widgetWithText(DsButton, 'Move to Trash'));
    await _settle(tester);

    expect(attempts, 1);
    expect(find.byType(TodoFormPage), findsOneWidget);
    expect(find.text("That didn't work. Please try again."), findsOneWidget);

    await tester.tap(find.byTooltip('Move to Trash'));
    await _settle(tester);
    expect(find.byType(DsDialog), findsOneWidget);
    await _unmount(tester);
  });
}
