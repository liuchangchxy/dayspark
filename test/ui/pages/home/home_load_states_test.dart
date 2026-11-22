import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/home/home_page.dart';

Widget _app({
  required AppDatabase db,
  required List<Override> overrides,
  required Widget home,
}) => ProviderScope(
  overrides: [
    databaseProvider.overrideWithValue(db),
    ...overrides,
  ],
  child: MaterialApp(
    localizationsDelegates: const [
      ...AppLocalizations.localizationsDelegates,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: home,
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

  setUp(() {
    SharedPreferences.setMockInitialValues({'default_tab': 'calendar'});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('calendar shows a retry when the event query fails, not an '
      'empty week', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var attempts = 0;

    await tester.pumpWidget(
      _app(
        db: db,
        overrides: [
          eventsInDateRangeProvider.overrideWith((ref, rangeKey) {
            attempts++;
            return Stream<List<Event>>.error(StateError('offline'));
          }),
        ],
        home: const HomePage(initialTab: 1),
      ),
    );
    await _settle(tester);

    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Nothing this week.'), findsNothing);
    final beforeRetry = attempts;
    await tester.tap(find.text('Retry'));
    await _settle(tester);
    expect(attempts, greaterThan(beforeRetry));
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Nothing this week.'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('by date shows a retry when the todo query fails', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var attempts = 0;

    await tester.pumpWidget(
      _app(
        db: db,
        overrides: [
          allTodosProvider.overrideWith((ref) {
            attempts++;
            return attempts == 1
                ? Stream<List<Todo>>.error(StateError('offline'))
                : Stream<List<Todo>>.value(const []);
          }),
        ],
        home: const HomePage(initialTab: 2, initialTodoView: 'date'),
      ),
    );
    await _settle(tester);

    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Nothing on this day'), findsNothing);
    await tester.tap(find.text('Retry'));
    await _settle(tester);
    expect(attempts, greaterThan(1));
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Nothing on this day'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('an unreadable calendar value does not reach the empty grid', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        db: db,
        overrides: [
          eventsInDateRangeProvider.overrideWith(
            (ref, rangeKey) => const Stream<List<Event>>.empty(),
          ),
        ],
        home: const HomePage(initialTab: 1),
      ),
    );
    await _settle(tester);

    expect(
      find.byKey(const ValueKey('calendar-loading')),
      findsOneWidget,
    );
    expect(find.text('Nothing this week.'), findsNothing);
    await _unmount(tester);
  });
}
