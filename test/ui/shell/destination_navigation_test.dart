import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/core/router/app_router.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/writers/todo_writer.dart';
import 'package:dayspark/domain/providers/search_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/todo/todo_list_tile.dart';
import 'package:dayspark/ui/pages/trash/trash_page.dart';

/// The rail is a destination switcher, not a history. Clicking the item you
/// are already on, or bouncing between two of them, must leave exactly one
/// page under the rail — otherwise Back grows a stack of duplicates.
Widget _app(AppDatabase db) => ProviderScope(
  overrides: [databaseProvider.overrideWithValue(db)],
  child: MaterialApp.router(
    routerConfig: AppRouter.router,
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
  await tester.pump(const Duration(milliseconds: 1));
}

String _currentUri() =>
    AppRouter.router.routerDelegate.currentConfiguration.uri.toString();

int _matchCount() =>
    AppRouter.router.routerDelegate.currentConfiguration.matches.length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({'app_locale': 'en'});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('re-selecting a rail destination does not stack a page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    AppRouter.router.go('/');
    await tester.pumpWidget(_app(db));
    await _settle(tester);

    await tester.tap(find.text('Calendar'));
    await _settle(tester);
    expect(_currentUri(), '/?tab=1');

    await tester.tap(find.text('Calendar'));
    await _settle(tester);
    expect(_currentUri(), '/?tab=1');

    await tester.tap(find.text('Trash'));
    await _settle(tester);
    expect(find.byType(TrashPage), findsOneWidget);

    await tester.tap(find.text('Calendar'));
    await _settle(tester);
    expect(_currentUri(), '/?tab=1');

    expect(
      _matchCount(),
      1,
      reason: 'four clicks between three destinations, one page under the rail',
    );
    expect(AppRouter.router.canPop(), isFalse);
    await _unmount(tester);
  });

  testWidgets('Back to Tasks from an empty trash really lands on Tasks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    AppRouter.router.go('/');
    await tester.pumpWidget(_app(db));
    await _settle(tester);

    AppRouter.router.go('/trash');
    await _settle(tester);
    expect(find.byType(TrashPage), findsOneWidget);
    expect(find.text('Back to Tasks'), findsOneWidget);

    await tester.tap(find.text('Back to Tasks'));
    await _settle(tester);

    expect(_currentUri(), '/?tab=2');
    expect(_matchCount(), 1);
    await _unmount(tester);
  });

  testWidgets('Load more keeps the query and the rows already shown', (
    tester,
  ) async {
    // Tall enough that the whole result list builds: a ListView only keeps the
    // rows it can show, and this test is about how many rows there are.
    tester.view.physicalSize = const Size(1440, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final calendarId = await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(name: 'Test'));
    // One row past the page size: the second page has to exist for the
    // "load more" gesture to be about anything.
    final total = kSearchPageSize + 3;
    for (var i = 0; i < total; i++) {
      await RecordScope.run(
        db,
        (tx) => TodoWriter.create(
          db,
          tx,
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'milk run $i',
            dueDate: Value(DateTime(2027, 1, 15)),
          ),
        ),
      );
    }

    AppRouter.router.go('/search');
    await tester.pumpWidget(_app(db));
    await _settle(tester);

    await tester.enterText(find.byType(TextField).first, 'milk run');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _settle(tester);

    expect(find.byType(TextField).first, isNotNull);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      'milk run',
      reason: 'loading the next page must not reset the query',
    );

    final loadMore = find.text('Load More');
    expect(loadMore, findsOneWidget);
    expect(find.byType(TodoListTile), findsNWidgets(kSearchPageSize));
    expect(find.text('milk run 0'), findsOneWidget);
    expect(find.text('milk run ${total - 1}'), findsNothing);

    await tester.tap(loadMore);
    await _settle(tester);

    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      'milk run',
    );
    // The first page is still there: loading the next one appends, it does not
    // replace the answer and scroll the user back to the top.
    expect(find.byType(TodoListTile), findsNWidgets(total));
    expect(find.text('milk run 0'), findsOneWidget);
    expect(find.text('milk run ${total - 1}'), findsOneWidget);
    expect(loadMore, findsNothing);
    await _unmount(tester);
  });
}
