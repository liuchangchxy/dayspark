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
import 'package:dayspark/ui/pages/home/day_agenda.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/calendar/a2_calendar_page.dart';
import 'package:dayspark/ui/pages/calendar/a2_calendar_views.dart';
import 'package:dayspark/ui/pages/todo/a2_todo_page.dart';

final _testDay = DateTime(2026, 11, 21);

Widget _testApp(
  Widget child, {
  required AppDatabase db,
  DateTime? now,
  double width = 1440,
  double height = 900,
}) {
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      calendarNowProvider.overrideWithValue(() => now ?? DateTime(2026, 11, 21, 12)),
      viewedDateProvider.overrideWith((ref) => _testDay),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(
        body: child,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'calendar_view_mode': 'week'});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Calendar & Todo Frozen Spec Geometry Verification', () {
    testWidgets(
      'time axis height is 648px, hour height is 54px, visible 08:00-20:00',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final page = A2CalendarPage(
          events: const [],
          allocations: const [],
          deadlines: const [],
        );

        await tester.pumpWidget(_testApp(page, db: db));
        await tester.pumpAndSettle();

        // 1. Time axis height is exactly 648
        final timeAxisFinder = find.byType(A2TimeGridView);
        expect(timeAxisFinder, findsOneWidget);

        // Check hour labels: strictly 08:00, 10:00, 12:00, 14:00, 16:00, 18:00, 20:00
        expect(find.text('08:00'), findsOneWidget);
        expect(find.text('10:00'), findsOneWidget);
        expect(find.text('12:00'), findsOneWidget);
        expect(find.text('14:00'), findsOneWidget);
        expect(find.text('16:00'), findsOneWidget);
        expect(find.text('18:00'), findsOneWidget);
        expect(find.text('20:00'), findsOneWidget);

        // Non-spec hour labels are not rendered
        expect(find.text('07:00'), findsNothing);
        expect(find.text('09:00'), findsNothing);
        expect(find.text('21:00'), findsNothing);

        // Verify distance between 08:00 and 10:00 is 108px (54px / hour * 2 hours)
        final pos08 = tester.getCenter(find.text('08:00'));
        final pos10 = tester.getCenter(find.text('10:00'));
        expect((pos10.dy - pos08.dy).round(), equals(108));

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(Duration.zero);
      },
    );

    testWidgets(
      'block percentage positioning maps via (minutes - 480) / 720 * 648',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final page = A2CalendarPage(
          events: [
            CalendaEventAdapter(
              drifId: 101,
              calendarId: 1,
              title: 'Spec Geometry Test Event',
              start: DateTime(2026, 11, 21, 10, 0), // 600 min -> (600-480)/720 = 1/6 = 108px
              end: DateTime(2026, 11, 21, 12, 0),   // 720 min -> (720-480)/720 = 2/6 = 216px, height = 108px
            ),
          ],
          allocations: const [],
          deadlines: const [],
        );

        await tester.pumpWidget(_testApp(page, db: db));
        await tester.pumpAndSettle();

        final blockFinder = find.text('Spec Geometry Test Event');
        expect(blockFinder, findsOneWidget);

        final blockRender = tester.renderObject(blockFinder);
        expect(blockRender.attached, isTrue);

        // Find the DecoratedBox of the block to verify border-left and radius 4
        final boxContainers = tester.widgetList<Container>(
          find.ancestor(
            of: blockFinder,
            matching: find.byType(Container),
          ),
        );

        final blockContainer = boxContainers.firstWhere(
          (c) => c.decoration is BoxDecoration && (c.decoration as BoxDecoration).borderRadius != null,
        );
        final decoration = blockContainer.decoration as BoxDecoration;
        expect(decoration.borderRadius, equals(BorderRadius.circular(4)));
        expect(decoration.border, isNotNull);
        final border = decoration.border as Border;
        expect(border.left.width, equals(3.0)); // Event border-left is 3px

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(Duration.zero);
      },
    );

    testWidgets(
      'narrow width (800-1179) has no inline 380px detail column, wide (>=1180) has 380px column',
      (tester) async {
        final dummyDetail = Container(
          key: const ValueKey('dummy-detail-pane'),
          width: 380,
          color: Colors.white,
        );

        // 1. Narrow width 1000px: no 380px detail column
        tester.view.physicalSize = const Size(1000, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _testApp(
            A2TodoPage(
              now: DateTime(2026, 11, 21, 12),
              dayAgenda: DayAgenda(
                day: _testDay,
                events: const [],
                allocations: const [],
                dueTodos: const [],
                overdueTodos: const [],
                instances: const [],
              ),
              detail: dummyDetail,
            ),
            db: db,
            width: 1000,
            height: 800,
          ),
        );
        await tester.pumpAndSettle();

        // On 1000px (< 1180), detail must NOT be rendered inline
        expect(find.byKey(const ValueKey('dummy-detail-pane')), findsNothing);

        // 2. Wide width 1440px (>= 1180): 380px inline detail is rendered
        tester.view.physicalSize = const Size(1440, 900);
        await tester.pumpWidget(
          _testApp(
            A2TodoPage(
              now: DateTime(2026, 11, 21, 12),
              dayAgenda: DayAgenda(
                day: _testDay,
                events: const [],
                allocations: const [],
                dueTodos: const [],
                overdueTodos: const [],
                instances: const [],
              ),
              detail: dummyDetail,
            ),
            db: db,
            width: 1440,
            height: 900,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('dummy-detail-pane')), findsOneWidget);
        expect(tester.getSize(find.byKey(const ValueKey('dummy-detail-pane'))).width, equals(380.0));

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(Duration.zero);
      },
    );
  });
}
