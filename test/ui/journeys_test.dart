import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/core/router/app_router.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/infrastructure/platform/notification_service.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/event/event_detail_page.dart';
import 'package:dayspark/ui/pages/event/event_form_page.dart';
import 'package:dayspark/ui/pages/todo/todo_detail_page.dart';
import 'package:dayspark/ui/pages/todo/todo_form_page.dart';
import 'package:dayspark/ui/pages/trash/trash_page.dart';

/// Journeys through the real router and a real database.
///
/// These are the paths a person takes in the shipped app — create, look, edit,
/// delete, restore — driven through [AppRouter] rather than a stand-in, so a
/// route that only works because a test mounted the page directly still fails
/// here.
class _MockNotificationService extends Mock implements NotificationService {}

Widget _app(AppDatabase db) => ProviderScope(
  overrides: [
    databaseProvider.overrideWithValue(db),
    notificationServiceProvider.overrideWithValue(_MockNotificationService()),
  ],
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

  Future<void> start(WidgetTester tester) async {
    AppRouter.router.go('/');
    await tester.pumpWidget(_app(db));
    await _settle(tester);
  }

  testWidgets('journey: create a todo, open it, edit it, and see the edit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await start(tester);

    await tester.tap(find.byKey(const ValueKey('workspace-create')));
    await _settle(tester);
    expect(find.byType(TodoFormPage), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Book the flights');
    await tester.tap(find.text('Save'));
    await _settle(tester);

    final created = (await db.select(db.todos).get()).single;
    expect(created.summary, 'Book the flights');

    // The new todo is reachable through the product's own search.
    AppRouter.router.go('/search');
    await _settle(tester);
    await tester.enterText(find.byType(TextField), 'flights');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _settle(tester);
    await tester.tap(find.text('Book the flights').first);
    await _settle(tester);
    expect(find.byType(TodoDetailPage), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await _settle(tester);
    expect(find.byType(TodoFormPage), findsOneWidget);

    await tester.enterText(
      find.byType(TextField).first,
      'Book the flights now',
    );
    await tester.tap(find.text('Save'));
    await _settle(tester);

    final rows = await db.select(db.todos).get();
    expect(rows, hasLength(1), reason: 'editing is not a second create');
    expect(rows.single.id, created.id);
    expect(rows.single.summary, 'Book the flights now');
    expect(find.text('Book the flights now'), findsWidgets);

    await _unmount(tester);
  });

  testWidgets('journey: delete a todo, land somewhere valid, restore it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final calendarId = (await db.select(db.calendars).get()).single.id;
    await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Cancel the subscription',
          ),
        );
    final todo = (await db.select(db.todos).get()).single;

    await start(tester);
    AppRouter.router.push('/todo/detail', extra: todo);
    await _settle(tester);

    await tester.tap(find.text('Move to Trash'));
    await _settle(tester);
    // The confirm button carries the same words as the row that opened it.
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Move to Trash'),
      ),
    );
    await _settle(tester);

    expect(
      find.byType(TodoDetailPage),
      findsNothing,
      reason: 'a deleted object must not stay on screen',
    );
    expect((await db.select(db.todos).get()).single.deletedAt, isNotNull);

    AppRouter.router.go('/trash');
    await _settle(tester);
    expect(find.byType(TrashPage), findsOneWidget);
    expect(find.text('Cancel the subscription'), findsOneWidget);

    await tester.tap(find.byIcon(CupertinoIcons.arrow_uturn_left).first);
    await _settle(tester);

    final restored = (await db.select(db.todos).get()).single;
    expect(restored.deletedAt, isNull, reason: 'Restore puts it back');
    await _unmount(tester);
  });

  testWidgets('journey: an event opens read-only and edits through the form', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await start(tester);
    AppRouter.router.push(
      '/event/new?start=${DateTime(2026, 10, 30, 10).millisecondsSinceEpoch}'
      '&end=${DateTime(2026, 10, 30, 11).millisecondsSinceEpoch}',
    );
    await _settle(tester);
    expect(find.byType(EventFormPage), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Design review');
    await tester.tap(find.text('Save'));
    await _settle(tester);

    final event = (await db.select(db.events).get()).single;
    expect(event.summary, 'Design review');
    expect(event.startDt, DateTime(2026, 10, 30, 10));
    expect(event.endDt, DateTime(2026, 10, 30, 11));

    AppRouter.router.push(
      '/event/detail',
      extra: CalendaEventAdapter.fromDrift(event),
    );
    await _settle(tester);
    expect(find.byType(EventDetailPage), findsOneWidget);
    expect(
      find.byType(TextField),
      findsNothing,
      reason: 'detail is read-only; the form is the second step',
    );

    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await _settle(tester);
    expect(find.byType(EventFormPage), findsOneWidget);
    await _unmount(tester);
  });
}
