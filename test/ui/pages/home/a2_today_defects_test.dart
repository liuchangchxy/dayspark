import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/action_projection_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/design/spec_components.dart';
import 'package:dayspark/ui/pages/home/today_page.dart';

Widget _app({
  required List<Override> overrides,
  required ValueChanged<Todo> onOpenTodo,
  required ValueChanged<Todo> onScheduleTodo,
  required Future<bool> Function(Todo todo, String? occurrenceId, bool completed)
  onToggleTodo,
}) {
  return ProviderScope(
    overrides: overrides,
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
        body: A2TodayPage(
          now: DateTime(2026, 10, 6, 15),
          onOpenTodo: onOpenTodo,
          onOpenEvent: (_) {},
          onToggleTodo: onToggleTodo,
          onOpenUnplanned: () {},
          onScheduleTodo: onScheduleTodo,
        ),
      ),
    ),
  );
}

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
  late int calendarId;
  final day = DateTime(2026, 10, 6);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    calendarId = await db
        .into(db.calendars)
        .insert(
          CalendarsCompanion.insert(
            name: 'Work',
            color: const Value('#2196F3'),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('deadline-only unplanned work keeps the Unplanned entry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'File taxes',
            dueDate: Value(DateTime(2026, 10, 20)),
          ),
        );

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDateProvider.overrideWith((ref) => day),
        ],
        onOpenTodo: (_) {},
        onScheduleTodo: (_) {},
        onToggleTodo: (_, __, ___) async => true,
      ),
    );
    await _settle(tester);

    // The preview only carries no-due rows, so the deadline-bearing item must
    // still keep the shelf and its count alive.
    expect(find.text('Nothing scheduled today'), findsNothing);
    expect(find.text('No date'), findsOneWidget);
    expect(find.text('View 1 undated'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('unplanned row opens details and schedules from its own action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final id = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Buy milk',
          ),
        );
    final opened = <int>[];
    final scheduled = <int>[];

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDateProvider.overrideWith((ref) => day),
        ],
        onOpenTodo: (todo) => opened.add(todo.id),
        onScheduleTodo: (todo) => scheduled.add(todo.id),
        onToggleTodo: (_, __, ___) async => true,
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('Buy milk'));
    await _settle(tester);
    expect(opened, [id]);
    expect(scheduled, isEmpty);

    await tester.tap(find.byTooltip('Schedule'));
    await _settle(tester);
    expect(scheduled, [id]);
    expect(opened, [id]);

    await _unmount(tester);
  });

  testWidgets('completing a row reports it and Undo reopens it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Buy milk',
          ),
        );
    final calls = <bool>[];

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDateProvider.overrideWith((ref) => day),
        ],
        onOpenTodo: (_) {},
        onScheduleTodo: (_) {},
        onToggleTodo: (todo, occurrenceId, completed) async {
          calls.add(completed);
          return true;
        },
      ),
    );
    await _settle(tester);

    await tester.tap(find.byType(DsCheck).first);
    await _settle(tester);
    expect(calls, [true]);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await _settle(tester);
    expect(calls, [true, false]);

    await _unmount(tester);
  });

  testWidgets('projection failure offers retry and recovers', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var attempts = 0;
    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDateProvider.overrideWith((ref) => day),
          unplannedTodosProvider.overrideWith((ref) {
            attempts++;
            return attempts == 1
                ? AsyncValue.error(StateError('offline'), StackTrace.current)
                : const AsyncValue.data(<Todo>[]);
          }),
        ],
        onOpenTodo: (_) {},
        onScheduleTodo: (_) {},
        onToggleTodo: (_, __, ___) async => true,
      ),
    );
    await _settle(tester);

    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await _settle(tester);

    expect(attempts, 2);
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Nothing scheduled today'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('a refresh failure keeps the stale list instead of wiping it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final shouldFail = StateProvider<bool>((ref) => false);
    await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Keep me',
            dueDate: Value(DateTime(2026, 10, 6, 18)),
          ),
        );

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDateProvider.overrideWith((ref) => day),
          shouldFail,
          unplannedTodosProvider.overrideWith((ref) {
            return ref.watch(shouldFail)
                ? AsyncValue<List<Todo>>.error(
                    StateError('offline'),
                    StackTrace.current,
                  )
                : const AsyncValue<List<Todo>>.data(<Todo>[]);
          }),
        ],
        onOpenTodo: (_) {},
        onScheduleTodo: (_) {},
        onToggleTodo: (_, __, ___) async => true,
      ),
    );
    await _settle(tester);
    expect(find.text('Keep me'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(A2TodayPage)),
    );
    container.read(shouldFail.notifier).state = true;
    await _settle(tester);

    // T5: the last good projection is still on screen, with a retry strip on
    // top of it, rather than the day being replaced by an error box.
    expect(find.text('Keep me'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets(
    'P1: mobile section order is tasks (overdue -> due -> undated) -> completed -> timeline',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // Overdue
      await db.into(db.todos).insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Overdue item',
              dueDate: Value(DateTime(2026, 10, 1)),
            ),
          );
      // Due today
      await db.into(db.todos).insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Due item',
              dueDate: Value(DateTime(2026, 10, 6, 18)),
            ),
          );
      // Undated
      await db.into(db.todos).insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Undated item',
            ),
          );
      // Completed today
      await db.into(db.todos).insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Completed item',
              status: const Value('COMPLETED'),
              completedAt: Value(DateTime(2026, 10, 6, 10)),
            ),
          );

      await tester.pumpWidget(
        _app(
          overrides: [
            databaseProvider.overrideWithValue(db),
            actionDateProvider.overrideWith((ref) => day),
          ],
          onOpenTodo: (_) {},
          onScheduleTodo: (_) {},
          onToggleTodo: (_, __, ___) async => true,
        ),
      );
      await _settle(tester);

      final overdueY = tester.getTopLeft(find.text('Overdue item')).dy;
      final dueY = tester.getTopLeft(find.text('Due item')).dy;
      final undatedY = tester.getTopLeft(find.text('Undated item')).dy;
      final completedHeadY = tester.getTopLeft(find.text('Completed Today')).dy;
      final nowY = tester.getTopLeft(find.text('Now')).dy;
      final upcomingY = tester.getTopLeft(find.text('Upcoming')).dy;

      // Spec mobileTaskSections: Tasks -> Completed -> Timeline
      expect(overdueY, lessThan(dueY));
      expect(dueY, lessThan(undatedY));
      expect(undatedY, lessThan(completedHeadY));
      expect(completedHeadY, lessThan(nowY));
      expect(nowY, lessThan(upcomingY));

      await _unmount(tester);
    },
  );

  testWidgets(
    'P1: timeline empty state never renders 70px blank and always keeps Now + Upcoming 0',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // Only one overdue item, no timeline allocations or events
      await db.into(db.todos).insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Past debt',
              dueDate: Value(DateTime(2026, 9, 30)),
            ),
          );

      await tester.pumpWidget(
        _app(
          overrides: [
            databaseProvider.overrideWithValue(db),
            actionDateProvider.overrideWith((ref) => day),
          ],
          onOpenTodo: (_) {},
          onScheduleTodo: (_) {},
          onToggleTodo: (_, __, ___) async => true,
        ),
      );
      await _settle(tester);

      // 70px empty text placeholder is gone
      expect(find.text('Nothing scheduled today'), findsNothing);
      expect(find.text('今天没有时间安排。'), findsNothing);

      // Timeline has Now and Upcoming 0
      expect(find.text('Now'), findsOneWidget);
      expect(find.text('Upcoming'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);

      await _unmount(tester);
    },
  );

  testWidgets(
    'P2: capture placeholder is spec copy and fits 366 width without shortcut hint',
    (tester) async {
      tester.view.physicalSize = const Size(366, 667);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _app(
          overrides: [
            databaseProvider.overrideWithValue(db),
            actionDateProvider.overrideWith((ref) => day),
          ],
          onOpenTodo: (_) {},
          onScheduleTodo: (_) {},
          onToggleTodo: (_, __, ___) async => true,
        ),
      );
      await _settle(tester);

      final textField = tester.widget<TextField>(
        find.byKey(const ValueKey('today-capture-field')),
      );
      expect(textField.decoration?.hintText, 'Capture a task, press Enter');
      // Unfocused on mobile: no shortcut hint that causes truncation
      expect(find.text('Enter'), findsNothing);

      await _unmount(tester);
    },
  );

  testWidgets(
    'P2: page title has fontVariations with wght 650 matching spec .ph-title',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _app(
          overrides: [
            databaseProvider.overrideWithValue(db),
            actionDateProvider.overrideWith((ref) => day),
          ],
          onOpenTodo: (_) {},
          onScheduleTodo: (_) {},
          onToggleTodo: (_, __, ___) async => true,
        ),
      );
      await _settle(tester);

      final titleWidget = tester.widget<Text>(find.text('Oct 6'));
      expect(titleWidget.style?.fontSize, 26.0);
      final has650 = titleWidget.style?.fontVariations?.any(
            (v) => v.axis == 'wght' && v.value == 650.0,
          ) ??
          false;
      expect(has650, isTrue);

      await _unmount(tester);
    },
  );

  testWidgets(
    'P2: mobile task row visual height is ~50, check left is ~19, title start is ~45',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await db.into(db.todos).insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Check geometric layout',
            ),
          );

      await tester.pumpWidget(
        _app(
          overrides: [
            databaseProvider.overrideWithValue(db),
            actionDateProvider.overrideWith((ref) => day),
          ],
          onOpenTodo: (_) {},
          onScheduleTodo: (_) {},
          onToggleTodo: (_, __, ___) async => true,
        ),
      );
      await _settle(tester);

      final title = find.text('Check geometric layout');
      final titleLeft = tester.getTopLeft(title).dx;
      // List padding (16) + check container (22) + gap (7) = 45.0
      expect(titleLeft, closeTo(45.0, 1.0));

      final check = find.byType(SpecCheck);
      final checkCenter = tester.getCenter(check).dx;
      // List padding (16) + check container center (11) = 27.0
      expect(checkCenter, closeTo(27.0, 1.0));
      // Visual circle r=8, so visual left edge is 27.0 - 8 = 19.0 (spec: ~19.5)
      final visualLeft = checkCenter - 8.0;
      expect(visualLeft, closeTo(19.0, 1.0));

      final row = find.ancestor(
        of: title,
        matching: find.byType(GestureDetector),
      ).first;
      final rowSize = tester.getSize(row);
      // Spec minHeight: 50.0
      expect(rowSize.height, closeTo(50.0, 3.0));

      await _unmount(tester);
    },
  );

  testWidgets(
    'P2: undated collection count is unified across summary, group head, and hidden count',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // Insert 5 undated items
      for (var i = 0; i < 5; i++) {
        await db.into(db.todos).insert(
              TodosCompanion.insert(
                calendarId: calendarId,
                summary: 'Undated task $i',
              ),
            );
      }

      await tester.pumpWidget(
        _app(
          overrides: [
            databaseProvider.overrideWithValue(db),
            actionDateProvider.overrideWith((ref) => day),
          ],
          onOpenTodo: (_) {},
          onScheduleTodo: (_) {},
          onToggleTodo: (_, __, ___) async => true,
        ),
      );
      await _settle(tester);

      // Summary says "5 No date"
      expect(find.textContaining('· 5 No date ·'), findsOneWidget);
      // Group head says "5"
      expect(find.text('5'), findsWidgets);
      // 5 total - 3 preview = 2 hidden
      expect(find.text('2 more · Show all'), findsOneWidget);

      await _unmount(tester);
    },
  );
}
