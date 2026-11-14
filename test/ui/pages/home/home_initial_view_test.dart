import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/date_context_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/home/home_page.dart';
import 'package:dayspark/ui/shell/workspace_navigation.dart';

Widget _app(
  AppDatabase db, {
  required String? view,
  required DateTime? date,
  required DateTime Function() clock,
}) {
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      clockNowProvider.overrideWithValue(clock),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => HomePage(
              initialTab: 2,
              initialTodoView: view,
              initialDate: date,
            ),
          ),
        ],
      ),
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
  final clock = DateTime(2026, 10, 6, 9, 30);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('view=today lands on the real today even with a date param', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        db,
        view: 'today',
        date: DateTime(2026, 11, 7),
        clock: () => clock,
      ),
    );
    await _settle(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );
    expect(container.read(browseDateProvider), dayOf(clock));
    expect(container.read(todosViewProvider), isA<TodosDayView>());
    await _unmount(tester);
  });

  testWidgets('a by-date link lands on its date', (tester) async {
    await tester.pumpWidget(
      _app(
        db,
        view: 'date',
        date: DateTime(2026, 11, 7),
        clock: () => clock,
      ),
    );
    await _settle(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );
    expect(container.read(browseDateProvider), DateTime(2026, 11, 7));
    expect(container.read(todosViewProvider), isA<TodosDayView>());
    await _unmount(tester);
  });
}
