import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/calendar_view_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/home/day_agenda.dart';
import 'package:dayspark/ui/pages/todo/a2_todo_page.dart';
import 'package:dayspark/ui/shell/workspace_navigation.dart';

Widget _app({
  required AppDatabase db,
  required DateTime now,
  bool loading = false,
  bool failed = false,
  VoidCallback? onRetry,
}) => ProviderScope(
  overrides: [
    databaseProvider.overrideWithValue(db),
    calendarNowProvider.overrideWithValue(() => now),
    viewedDateProvider.overrideWith((ref) => DateTime(2026, 11, 15)),
    todosViewProvider.overrideWith((ref) => const TodosDayView()),
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
    home: Scaffold(
      body: A2TodoPage(
        now: now,
        dayAgenda: DayAgenda(
          day: DateTime(now.year, now.month, now.day),
          events: const [],
          allocations: const [],
          dueTodos: const [],
          overdueTodos: const [],
          instances: const [],
        ),
        dayAgendaLoading: loading,
        dayAgendaFailed: failed,
        onRetryDayAgenda: onRetry,
      ),
    ),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
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
  final now = DateTime(2026, 11, 15, 10);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('by date waits instead of saying the day is empty', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db: db, now: now, loading: true));
    await _settle(tester);

    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(find.text('Nothing on this day'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('a failed day query offers retry instead of an empty state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var retries = 0;

    await tester.pumpWidget(
      _app(db: db, now: now, failed: true, onRetry: () => retries++),
    );
    await _settle(tester);

    expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Nothing on this day'), findsNothing);
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
    await _unmount(tester);
  });

  testWidgets('a settled empty day keeps the date empty copy', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db: db, now: now));
    await _settle(tester);

    expect(find.text('Nothing on this day'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    await _unmount(tester);
  });
}
