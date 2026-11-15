import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/home/day_agenda.dart';
import 'package:dayspark/ui/pages/todo/a2_todo_page.dart';
import 'package:dayspark/ui/shell/workspace_navigation.dart';

/// Bounded pumping: the loading indicator and the providers keep scheduling
/// frames, so an unbounded pumpAndSettle never returns.
Future<void> pumpFrames(
  WidgetTester tester, {
  int frames = 8,
  Duration step = const Duration(milliseconds: 200),
}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(step);
  }
}

void main() {
  testWidgets('failed task list offers retry instead of an empty state', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var attempts = 0;
    final day = DateTime(2026, 11, 15);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          todosViewProvider.overrideWith((ref) => const TodosAllView()),
          allTodosProvider.overrideWith((ref) {
            attempts++;
            return attempts == 1
                ? Stream<List<Todo>>.error(StateError('offline'))
                : Stream<List<Todo>>.value([]);
          }),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: A2TodoPage(
              now: day,
              dayAgenda: DayAgenda(
                day: day,
                events: const [],
                allocations: const [],
                dueTodos: const [],
                overdueTodos: const [],
                instances: const [],
              ),
            ),
          ),
        ),
      ),
    );
    await pumpFrames(tester);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await pumpFrames(tester);
    expect(attempts, 2);
    expect(find.text('Retry'), findsNothing);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    // Disposing the ProviderScope cancels the drift query streams, which
    // schedule zero-duration timers; a pump with a duration is required to
    // run them, or the test ends with "A Timer is still pending" and the
    // runner never exits.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  });
}
