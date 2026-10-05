import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/search_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/search/search_page.dart';

void main() {
  testWidgets('search result checkbox completes without opening edit', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final todo = Todo(
      id: 1,
      calendarId: 1,
      summary: 'GUI验收-普通Todo-Edit',
      priority: 5,
      status: 'NEEDS-ACTION',
      recurrenceRevision: 0,
      percentComplete: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      sortOrder: 0,
      serverRev: 0,
    );
    final router = GoRouter(
      initialLocation: '/search',
      routes: [
        GoRoute(path: '/search', builder: (_, __) => const SearchPage()),
        GoRoute(
          path: '/todo/edit',
          builder: (_, __) => const Scaffold(body: Text('Todo edit route')),
        ),
      ],
    );
    var completionCalls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todoTagsProvider(todo.id).overrideWith((ref) => Stream.value([])),
          toggleTodoProvider.overrideWith(
            (ref) => ({required int id, required bool isCompleted}) async {
              expect(id, todo.id);
              expect(isCompleted, isTrue);
              completionCalls++;
            },
          ),
          searchResultsProvider(
            'GUI验收-普通Todo-Edit',
          ).overrideWith((ref) async => SearchResults([], [todo])),
        ],
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
      ),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'GUI验收-普通Todo-Edit');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.byType(Checkbox), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    expect(completionCalls, 1);
    expect(find.text('Todo edit route'), findsNothing);
    expect(router.routeInformationProvider.value.uri.path, '/search');

    await tester.tap(find.text('GUI验收-普通Todo-Edit').first);
    await tester.pumpAndSettle();

    expect(find.text('Todo edit route'), findsOneWidget);
    expect(completionCalls, 1);
    debugDefaultTargetPlatformOverride = null;
    router.dispose();
  });
}
