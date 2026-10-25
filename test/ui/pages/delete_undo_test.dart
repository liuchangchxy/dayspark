import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/writers/todo_writer.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/event/event_detail_page.dart';
import 'package:dayspark/ui/pages/todo/todo_detail_page.dart';

/// Delete is "move to trash", and the snackbar is the way back. The two halves
/// only work together: without Undo the user has to find the row in Trash, and
/// without the trash move Undo would be lying about what it restores. Both
/// object types answer the same way, so the test covers both.
Widget _app(AppDatabase db, {Todo? todo, CalendaEventAdapter? event}) {
  final router = GoRouter(
    initialLocation: '/detail',
    routes: [
      GoRoute(path: '/', builder: (_, __) => const Scaffold(body: SizedBox())),
      GoRoute(
        path: '/detail',
        builder: (_, __) => todo != null
            ? TodoDetailPage(todo: todo)
            : EventDetailPage(event: event!),
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
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<Todo> seedTodo() async {
    final calendarId = await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(name: 'Test'));
    final id = await RecordScope.run(
      db,
      (tx) => TodoWriter.create(
        db,
        tx,
        TodosCompanion.insert(
          calendarId: calendarId,
          summary: 'Pay the rent',
        ),
      ),
    );
    return (db.select(db.todos)..where((row) => row.id.equals(id))).getSingle();
  }

  Future<CalendaEventAdapter> seedEvent() async {
    final calendarId = await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(name: 'Test'));
    final id = await db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            calendarId: calendarId,
            summary: 'Dentist',
            startDt: DateTime(2026, 10, 20, 9),
            endDt: DateTime(2026, 10, 20, 10),
          ),
        );
    final row = await (db.select(db.events)
          ..where((t) => t.id.equals(id)))
        .getSingle();
    return CalendaEventAdapter.fromDrift(row);
  }

  Future<void> openAndConfirmDelete(WidgetTester tester) async {
    await tester.tap(find.text('Move to Trash'));
    await _settle(tester);
    // The dialog title and the destructive button share a label; the button is
    // the last one.
    await tester.tap(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Move to Trash'),
          )
          .last,
    );
    await _settle(tester);
  }

  testWidgets('deleting a Task trashes the row and Undo brings it back', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final todo = await seedTodo();
    await tester.pumpWidget(_app(db, todo: todo));
    await _settle(tester);

    await tester.tap(find.text('Move to Trash'));
    await _settle(tester);
    expect(find.text('Are you sure you want to delete?'), findsOneWidget);
    await tester.tap(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Move to Trash'),
          )
          .last,
    );
    await _settle(tester);

    // Trashed, not erased: the row is still there, out of the live lists.
    final trashed = await (db.select(db.todos)
          ..where((row) => row.id.equals(todo.id)))
        .getSingle();
    expect(trashed.deletedAt, isNotNull);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await _settle(tester);

    final restored = await (db.select(db.todos)
          ..where((row) => row.id.equals(todo.id)))
        .getSingle();
    expect(restored.deletedAt, isNull);
    expect(restored.summary, 'Pay the rent');
    await _unmount(tester);
  });

  testWidgets('deleting an Event trashes the row and Undo brings it back', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final event = await seedEvent();
    await tester.pumpWidget(_app(db, event: event));
    await _settle(tester);

    await openAndConfirmDelete(tester);

    final trashed = await (db.select(db.events)
          ..where((row) => row.id.equals(event.drifId)))
        .getSingle();
    expect(trashed.deletedAt, isNotNull);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await _settle(tester);

    final restored = await (db.select(db.events)
          ..where((row) => row.id.equals(event.drifId)))
        .getSingle();
    expect(restored.deletedAt, isNull);
    expect(restored.summary, 'Dentist');
    await _unmount(tester);
  });

  testWidgets('cancelling the confirm leaves the row alone', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final todo = await seedTodo();
    await tester.pumpWidget(_app(db, todo: todo));
    await _settle(tester);

    await tester.tap(find.text('Move to Trash'));
    await _settle(tester);
    await tester.tap(find.text('Cancel'));
    await _settle(tester);

    final row = await (db.select(db.todos)
          ..where((row) => row.id.equals(todo.id)))
        .getSingle();
    expect(row.deletedAt, isNull);
    expect(find.byType(AlertDialog), findsNothing);
    await _unmount(tester);
  });
}
