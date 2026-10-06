import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/ai_provider.dart';
import 'package:dayspark/domain/providers/ai_scheduler_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/writers/todo_writer.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/ai_chat/ai_chat_page.dart';

class FakeAiChatNotifier extends StateNotifier<List<AiChatMessage>>
    implements AiChatNotifier {
  FakeAiChatNotifier(super.state);

  @override
  void clear() {
    state = [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(AppDatabase db, {List<Override> overrides = const []}) => ProviderScope(
  overrides: [
    databaseProvider.overrideWithValue(db),
    isAiConfiguredProvider.overrideWith((ref) => Future.value(true)),
    aiChatProvider.overrideWith((ref) => FakeAiChatNotifier([
      AiChatMessage(role: 'assistant', content: 'I can help schedule your tasks.'),
    ])),
    ...overrides,
  ],
  child: const MaterialApp(
    localizationsDelegates: [
      ...AppLocalizations.localizationsDelegates,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: Locale('en'),
    home: AiChatPage(),
  ),
);

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
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.calendars).insert(
      CalendarsCompanion.insert(name: 'Default'),
    );
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('tap Schedule with no schedulable todos shows SnackBar', (tester) async {
    await tester.pumpWidget(_app(db));
    await _settle(tester);

    // Initial message from AI is present. Tap Schedule quick action.
    final scheduleChip = find.text('Schedule');
    expect(scheduleChip, findsOneWidget);
    await tester.tap(scheduleChip);
    await _settle(tester);

    expect(find.text('No pending todos available to schedule'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('tap Schedule on ordinary task writes TaskAllocation without Event, leaves dueDate untouched', (tester) async {
    final due = DateTime.utc(2026, 10, 25, 18, 0);
    final todoId = await db.into(db.todos).insert(
      TodosCompanion.insert(
        calendarId: 1,
        summary: 'Important Report',
        dueDate: Value(due),
        priority: const Value(1),
      ),
    );

    // Mock suggestTimeSlotsProvider to return deterministic slots quickly
    final overrideSlots = suggestTimeSlotsProvider.overrideWithValue(
      ({required taskDescription, required rangeStart, required rangeEnd, slotDuration = const Duration(hours: 1)}) async {
        return [
          {
            'start': '2026-10-21T10:00:00.000',
            'end': '2026-10-21T11:00:00.000',
            'reason': 'Free morning slot',
          },
        ];
      },
    );

    await tester.pumpWidget(_app(db, overrides: [overrideSlots]));
    await _settle(tester);

    // Tap Schedule
    await tester.tap(find.text('Schedule'));
    await _settle(tester);

    // Step 1: Select Todo dialog is displayed
    expect(find.text('Select Todo to Schedule'), findsOneWidget);
    expect(find.text('Important Report'), findsOneWidget);
    await tester.tap(find.text('Important Report'));
    await _settle(tester);

    // Step 2: Suggested slots dialog is displayed
    expect(find.text('Suggested Time Slots'), findsOneWidget);
    expect(find.text('Free morning slot'), findsOneWidget);
    await tester.tap(find.text('Free morning slot'));
    await _settle(tester);

    // Step 3: Explicit confirmation dialog
    expect(find.text('Schedule Todo'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Schedule'), findsOneWidget);

    // Confirm write
    await tester.tap(find.widgetWithText(FilledButton, 'Schedule'));
    await _settle(tester);

    // Success SnackBar
    expect(find.text('Scheduled: Important Report'), findsOneWidget);

    // Verify DB state:
    // 1. TaskAllocation was created
    final allocations = await (db.select(db.taskAllocations)..where((t) => t.todoId.equals(todoId))).get();
    expect(allocations, hasLength(1));
    expect(allocations.first.state, 'active');
    expect(allocations.first.occurrenceId, isNull);

    // 2. Zero Events were created
    final events = await (db.select(db.events)).get();
    expect(events, isEmpty);

    // 3. Todo dueDate was untouched
    final todoAfter = await (db.select(db.todos)..where((t) => t.id.equals(todoId))).getSingle();
    expect(todoAfter.dueDate!.toUtc(), due);

    await _unmount(tester);
  });

  testWidgets('tap Schedule on recurring task picks occurrence and binds exact occurrenceId', (tester) async {
    final now = DateTime.now();
    final spec = RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: RecurrenceAnchorSource.start,
        value: LocalDate(now.year, now.month, now.day),
      ),
      timeZone: 'Asia/Shanghai',
      rrule: 'FREQ=DAILY;COUNT=7',
    );

    final seriesId = await RecordScope.run(
      db,
      (tx) => TodoWriter.create(
        db,
        tx,
        TodosCompanion.insert(
          calendarId: 1,
          summary: 'Daily Standup',
          rrule: Value(spec.rule.canonical),
        ),
        recurrenceSpec: spec,
      ),
    );

    final overrideSlots = suggestTimeSlotsProvider.overrideWithValue(
      ({required taskDescription, required rangeStart, required rangeEnd, slotDuration = const Duration(hours: 1)}) async {
        return [
          {
            'start': '2026-10-21T09:00:00.000',
            'end': '2026-10-21T10:00:00.000',
            'reason': 'Optimal morning free slot',
          },
        ];
      },
    );

    await tester.pumpWidget(_app(db, overrides: [overrideSlots]));
    await _settle(tester);

    // Tap Schedule
    await tester.tap(find.text('Schedule'));
    await _settle(tester);

    // Step 1: Select Todo dialog
    expect(find.text('Select Todo to Schedule'), findsOneWidget);
    expect(find.text('Daily Standup'), findsOneWidget);
    await tester.tap(find.text('Daily Standup'));
    await _settle(tester);

    // Step 2: Occurrence picker sheet appears
    expect(find.text('Select occurrence'), findsOneWidget);
    final occurrenceTile = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(ListTile),
    ).first;
    await tester.tap(occurrenceTile);
    await _settle(tester);

    // Step 3: Suggested slots dialog appears
    expect(find.text('Suggested Time Slots'), findsOneWidget);
    expect(find.text('Optimal morning free slot'), findsOneWidget);
    await tester.tap(find.text('Optimal morning free slot'));
    await _settle(tester);

    // Step 4: Confirmation dialog
    expect(find.text('Schedule Todo'), findsOneWidget);
    expect(find.textContaining('Recurring:'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Schedule'));
    await _settle(tester);

    // Verification
    final allocations = await (db.select(db.taskAllocations)..where((t) => t.todoId.equals(seriesId))).get();
    expect(allocations, hasLength(1));
    expect(allocations.first.state, 'active');
    expect(allocations.first.occurrenceId, isNotNull);
    expect(allocations.first.occurrenceId, startsWith('v2:DATE:'));

    // Zero Events
    final events = await (db.select(db.events)).get();
    expect(events, isEmpty);

    // Series dueDate untouched
    final seriesAfter = await (db.select(db.todos)..where((t) => t.id.equals(seriesId))).getSingle();
    expect(seriesAfter.dueDate, isNull);

    await _unmount(tester);
  });
}
