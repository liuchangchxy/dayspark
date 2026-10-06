import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_slot_sheet.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: const [
    ...AppLocalizations.localizationsDelegates,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: Scaffold(body: child),
);

Todo _makeTodo({
  required int id,
  required String summary,
  DateTime? dueDate,
}) {
  final now = DateTime.now();
  return Todo(
    id: id,
    calendarId: 1,
    summary: summary,
    priority: 0,
    status: 'NEEDS-ACTION',
    dueDate: dueDate,
    sortOrder: 0,
    recurrenceRevision: 0,
    percentComplete: 0,
    createdAt: now,
    updatedAt: now,
    serverRev: 0,
  );
}

void main() {
  final testRange = DateTimeRange(
    start: DateTime(2026, 10, 6, 10, 0),
    end: DateTime(2026, 10, 6, 11, 0),
  );

  testWidgets('renders Create Event and Schedule Todo options', (tester) async {
    var eventCreated = false;
    Todo? scheduledTodo;

    await tester.pumpWidget(
      _wrap(
        CalendarSlotSheet(
          range: testRange,
          onCreateEvent: () => eventCreated = true,
          onScheduleTodo: (todo) async => scheduledTodo = todo,
          loadSchedulableTodos: () async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create Event'), findsOneWidget);
    expect(find.text('Schedule Todo'), findsOneWidget);

    await tester.tap(find.text('Create Event'));
    await tester.pumpAndSettle();

    expect(eventCreated, isTrue);
    expect(scheduledTodo, isNull);
  });

  testWidgets('Schedule Todo shows candidates and calls onScheduleTodo on tap', (
    tester,
  ) async {
    Todo? scheduledTodo;
    final candidate = _makeTodo(
      id: 42,
      summary: 'Prepare slides',
      dueDate: DateTime(2026, 10, 8),
    );

    await tester.pumpWidget(
      _wrap(
        CalendarSlotSheet(
          range: testRange,
          onCreateEvent: () {},
          onScheduleTodo: (todo) async => scheduledTodo = todo,
          loadSchedulableTodos: () async => [candidate],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap Schedule Todo
    await tester.tap(find.text('Schedule Todo'));
    await tester.pumpAndSettle();

    expect(find.text('Select Todo to Schedule'), findsOneWidget);
    expect(find.text('Prepare slides'), findsOneWidget);

    // Tap candidate
    await tester.tap(find.text('Prepare slides'));
    await tester.pumpAndSettle();

    expect(scheduledTodo, isNotNull);
    expect(scheduledTodo!.id, 42);
    expect(scheduledTodo!.summary, 'Prepare slides');
  });

  testWidgets('Schedule Todo shows empty message when no schedulable todos exist', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        CalendarSlotSheet(
          range: testRange,
          onCreateEvent: () {},
          onScheduleTodo: (todo) async {},
          loadSchedulableTodos: () async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Schedule Todo'));
    await tester.pumpAndSettle();

    expect(find.text('Select Todo to Schedule'), findsOneWidget);
    expect(find.text('No pending todos available to schedule'), findsOneWidget);
  });
}
