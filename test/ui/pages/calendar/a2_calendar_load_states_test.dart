import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/calendar_view_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/calendar/a2_calendar_page.dart';
import 'package:dayspark/ui/pages/calendar/a2_calendar_views.dart';

Widget _app(Widget page, {required AppDatabase db}) => ProviderScope(
  overrides: [
    databaseProvider.overrideWithValue(db),
    calendarNowProvider.overrideWithValue(() => DateTime(2026, 11, 15, 15)),
    viewedDateProvider.overrideWith((ref) => DateTime(2026, 11, 15)),
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
    home: Scaffold(body: page),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

A2CalendarPage _page({
  AsyncValue<List<CalendaEventAdapter>>? eventsAsync,
  VoidCallback? onRetry,
}) => A2CalendarPage(
  events: const <CalendaEventAdapter>[],
  allocations: const <TaskAllocationCalendarItem>[],
  deadlines: const [],
  eventsAsync: eventsAsync,
  onRetry: onRetry,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({'calendar_view_mode': 'week'});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('loading does not paint the empty week', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(_page(eventsAsync: const AsyncValue.loading()), db: db),
    );
    await _settle(tester);

    expect(find.byKey(const ValueKey('calendar-loading')), findsOneWidget);
    expect(find.text('Nothing this week.'), findsNothing);
    expect(find.byType(A2PhoneWeekList), findsNothing);
    await _unmount(tester);
  });

  testWidgets('a failed event query offers retry', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var retries = 0;

    await tester.pumpWidget(
      _app(
        _page(
          eventsAsync: AsyncValue.error(
            StateError('offline'),
            StackTrace.empty,
          ),
          onRetry: () => retries++,
        ),
        db: db,
      ),
    );
    await _settle(tester);

    expect(find.byKey(const ValueKey('calendar-load-error')), findsOneWidget);
    expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
    expect(find.text('Nothing this week.'), findsNothing);
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
    await _unmount(tester);
  });

  testWidgets('an empty week names the week, not the day', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        _page(eventsAsync: const AsyncValue.data(<CalendaEventAdapter>[])),
        db: db,
      ),
    );
    await _settle(tester);

    expect(find.text('Nothing this week.'), findsOneWidget);
    expect(
      find.text('Start from capture or a calendar time slot.'),
      findsOneWidget,
    );
    expect(find.text('Nothing on this day'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('an empty desktop day uses the day copy', (tester) async {
    SharedPreferences.setMockInitialValues({'calendar_view_mode': 'day'});
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        _page(eventsAsync: const AsyncValue.data(<CalendaEventAdapter>[])),
        db: db,
      ),
    );
    await _settle(tester);

    expect(find.byType(A2TimeGridView), findsOneWidget);
    expect(find.text('Nothing scheduled that day'), findsOneWidget);
    await _unmount(tester);
  });
}
