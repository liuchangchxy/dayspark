import 'dart:async';

import 'package:flutter/cupertino.dart';
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
  testWidgets('inbox suggestions are read-only and open the todo', (
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
          path: '/todo/detail',
          builder: (_, __) => const Scaffold(body: Text('Todo detail route')),
        ),
      ],
    );
    var completionCalls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inboxTodosProvider.overrideWith((ref) => Stream.value([todo])),
          todoTagsProvider(todo.id).overrideWith((ref) => Stream.value([])),
          toggleTodoProvider.overrideWith(
            (ref) =>
                ({
                  required int id,
                  required bool isCompleted,
                  String? occurrenceId,
                }) async {
                  expect(id, todo.id);
                  expect(isCompleted, isTrue);
                  completionCalls++;
                },
          ),
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
    await tester.pumpAndSettle();

    // A lookup is not an edit surface: there is nothing to tick here.
    expect(find.byType(Checkbox), findsNothing);

    await tester.tap(find.text(todo.summary));
    await tester.pumpAndSettle();

    expect(find.text('Todo detail route'), findsOneWidget);
    expect(completionCalls, 0);
    debugDefaultTargetPlatformOverride = null;
    router.dispose();
  });

  testWidgets('a search result opens its detail and offers no checkbox', (
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
          path: '/todo/detail',
          builder: (_, __) => const Scaffold(body: Text('Todo detail route')),
        ),
      ],
    );
    var completionCalls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todoTagsProvider(todo.id).overrideWith((ref) => Stream.value([])),
          toggleTodoProvider.overrideWith(
            (ref) =>
                ({
                  required int id,
                  required bool isCompleted,
                  String? occurrenceId,
                }) async {
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

    expect(find.byType(Checkbox), findsNothing);
    expect(router.routeInformationProvider.value.uri.path, '/search');

    await tester.tap(find.text('GUI验收-普通Todo-Edit').first);
    await tester.pumpAndSettle();

    expect(find.text('Todo detail route'), findsOneWidget);
    expect(completionCalls, 0);
    debugDefaultTargetPlatformOverride = null;
    router.dispose();
  });

  testWidgets('a new query keeps the previous results until new ones arrive, '
      'and clear returns to the empty state', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final todo = Todo(
      id: 1,
      calendarId: 1,
      summary: 'Quarterly plan',
      priority: 5,
      status: 'NEEDS-ACTION',
      recurrenceRevision: 0,
      percentComplete: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      sortOrder: 0,
      serverRev: 0,
    );
    final pending = Completer<void>();
    final router = GoRouter(
      initialLocation: '/search',
      routes: [
        GoRoute(path: '/search', builder: (_, __) => const SearchPage()),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todoTagsProvider(todo.id).overrideWith((ref) => Stream.value([])),
          inboxTodosProvider.overrideWith((ref) => Stream.value([])),
          searchResultsProvider(
            'plan',
          ).overrideWith((ref) async => SearchResults([], [todo])),
          // The second query never answers: the screen must not go blank
          // while the user is still reading the first answer.
          searchResultsProvider('slow').overrideWith((ref) async {
            await pending.future;
            return SearchResults([], []);
          }),
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

    await tester.enterText(find.byType(TextField), 'plan');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Quarterly plan'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'slow');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      find.text('Quarterly plan'),
      findsOneWidget,
      reason: 'the previous answer stays readable while the next one loads',
    );

    await tester.tap(find.byIcon(CupertinoIcons.clear));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Quarterly plan'), findsNothing);
    expect(find.text('Search your calendar'), findsOneWidget);

    pending.complete();
    debugDefaultTargetPlatformOverride = null;
    router.dispose();
  });
}
