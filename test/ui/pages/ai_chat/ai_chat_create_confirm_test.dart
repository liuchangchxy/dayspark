import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/ai_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
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

const _parsed = <String, dynamic>{
  'summary': 'Buy milk',
  'due_date': '2027-01-15',
  'priority': 0,
};

Widget _app(AppDatabase db, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        // Watches the config the way the real provider does, so the page finds
        // it resolved instead of reading a future that has not completed yet.
        isAiConfiguredProvider.overrideWith(
          (ref) async =>
              (await ref.watch(aiConfigProvider.future)) != null,
        ),
        aiConfigProvider.overrideWith(
          (ref) => Future.value(
            AiConfig(apiKey: 'k', baseUrl: 'https://example.invalid/v1', model: 'm'),
          ),
        ),
        parseNaturalLanguageProvider.overrideWithValue((
          {required config,
          required input,
          required type}) async => _parsed,
        ),
        aiChatProvider.overrideWith(
          (ref) => FakeAiChatNotifier([
            AiChatMessage(
              role: 'assistant',
              content: 'I can help schedule your tasks.',
            ),
          ]),
        ),
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
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('nothing reaches the database before the confirm is answered', (
    tester,
  ) async {
    await tester.pumpWidget(_app(db));
    await _settle(tester);
    await tester.tap(find.text('Add Task'));
    await _settle(tester);

    expect(find.text('New Task'), findsOneWidget);
    expect(find.text('Buy milk'), findsOneWidget);
    expect(await db.select(db.todos).get(), isEmpty);

    await tester.tap(find.text('Cancel'));
    await _settle(tester);

    expect(await db.select(db.todos).get(), isEmpty);
    await _unmount(tester);
  });

  testWidgets('one confirm writes exactly one task', (tester) async {
    await tester.pumpWidget(_app(db));
    await _settle(tester);

    await tester.tap(find.text('Add Task'));
    await _settle(tester);
    await tester.tap(find.text('Create'));
    await _settle(tester);

    final rows = await db.select(db.todos).get();
    expect(rows, hasLength(1));
    expect(rows.single.summary, 'Buy milk');
    // A parse that says nothing about priority must not claim medium.
    expect(rows.single.priority, 0);
    expect(find.text('Task created'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('the confirm shows human rows, not internal values', (
    tester,
  ) async {
    await tester.pumpWidget(_app(db));
    await _settle(tester);

    await tester.tap(find.text('Add Task'));
    await _settle(tester);

    final dialogTexts = tester
        .widgetList<Text>(find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(Text),
        ))
        .map((t) => t.data ?? '')
        .toList();
    expect(dialogTexts, containsAll(['Deadline', 'Calendar', 'Personal']));
    // A raw ISO stamp or a calendar id would be an internal value leaking
    // into a dialog whose whole job is to be readable.
    for (final text in dialogTexts) {
      expect(text, isNot(contains('T00:00:00')));
      expect(text, isNot(contains('2027-01-15T')));
      expect(text, isNot(matches(RegExp(r'\b(id|uid|syncId)\b'))));
    }
    await _unmount(tester);
  });

  testWidgets('a second tap mid-flow cannot duplicate the row', (tester) async {
    final gate = Completer<void>();
    var writes = 0;
    await tester.pumpWidget(
      _app(
        db,
        overrides: [
          createTodoProvider.overrideWith(
            (ref) =>
                ({
                  required calendarId,
                  required summary,
                  required priority,
                  required status,
                  dueDate,
                  startDate,
                  description,
                  rrule,
                  recurrenceSpec,
                  parentId,
                }) async {
                  writes++;
                  await gate.future;
                  return 0;
                },
          ),
        ],
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('Add Task'));
    await _settle(tester);
    await tester.tap(find.text('Create'));
    await _settle(tester);

    // The write is in flight, so the chip that started it is disabled.
    final chip = find.ancestor(
      of: find.text('Add Task'),
      matching: find.byType(InkWell),
    );
    expect(tester.widget<InkWell>(chip).onTap, isNull);

    gate.complete();
    await _settle(tester);

    expect(writes, 1);
    await _unmount(tester);
  });
}
