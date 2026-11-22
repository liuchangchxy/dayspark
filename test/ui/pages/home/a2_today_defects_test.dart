import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/writers/todo_writer.dart';
import 'package:dayspark/ui/pages/todo/a2_composer.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/action_projection_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/records/todo_occurrence.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/design/a2.dart';
import 'package:dayspark/ui/design/spec_components.dart';
import 'package:dayspark/ui/pages/home/today_page.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';

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

    // A deadline-bearing item has a due date, so it must not pollute
    // the undated section, group head, or "View N undated".
    expect(find.text('No date'), findsNothing);
    expect(find.textContaining('undated'), findsNothing);

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
    expect(find.text('Marked completed · Buy milk'), findsOneWidget);
    expect(find.text('Undo'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('undo-bar')), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('undo-bar')),
        matching: find.text('Undo'),
      ),
    );
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

  testWidgets(
    'P1-A: 48dp hit targets: check center +/- 18px toggles, schedule center +/- 18px schedules, title tap opens details',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await db.into(db.todos).insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Hit target test task',
            ),
          );

      var toggleCount = 0;
      var detailCount = 0;
      var scheduleCount = 0;

      await tester.pumpWidget(
        _app(
          overrides: [
            databaseProvider.overrideWithValue(db),
            actionDateProvider.overrideWith((ref) => day),
          ],
          onOpenTodo: (t) => detailCount++,
          onScheduleTodo: (t) => scheduleCount++,
          onToggleTodo: (_, __, ___) async {
            toggleCount++;
            return true;
          },
        ),
      );
      await _settle(tester);

      // Verify row visual layout: height ~ 50, check visual left ~ 19, title left ~ 45
      final title = find.text('Hit target test task');
      final titleLeft = tester.getTopLeft(title).dx;
      expect(titleLeft, closeTo(45.0, 1.0));

      final check = find.byType(SpecCheck);
      final checkCenter = tester.getCenter(check);
      expect(checkCenter.dx, closeTo(27.0, 1.0));
      final visualLeft = checkCenter.dx - 8.0;
      expect(visualLeft, closeTo(19.0, 1.0));

      // 1. Tapping check center - 18px (dx = 9) toggles, does not open detail
      await tester.tapAt(Offset(checkCenter.dx - 18, checkCenter.dy));
      await _settle(tester);
      expect(toggleCount, 1);
      expect(detailCount, 0);
      expect(scheduleCount, 0);

      // 2. Tapping check center + 18px (dx = 45) toggles, does not open detail
      await tester.tapAt(Offset(checkCenter.dx + 18, checkCenter.dy));
      await _settle(tester);
      expect(toggleCount, 2);
      expect(detailCount, 0);
      expect(scheduleCount, 0);

      // 3. Find Schedule action (CupertinoIcons.calendar)
      final calendarIcon = find.byIcon(CupertinoIcons.calendar);
      final scheduleCenter = tester.getCenter(calendarIcon);
      expect(scheduleCenter.dx, closeTo(358.0, 1.0));

      // 4. Tapping schedule center - 18px (dx = 340) schedules, does not open detail
      await tester.tapAt(Offset(scheduleCenter.dx - 18, scheduleCenter.dy));
      await _settle(tester);
      expect(scheduleCount, 1);
      expect(toggleCount, 2);
      expect(detailCount, 0);

      // 5. Tapping schedule center + 18px (dx = 376) schedules, does not open detail
      await tester.tapAt(Offset(scheduleCenter.dx + 18, scheduleCenter.dy));
      await _settle(tester);
      expect(scheduleCount, 2);
      expect(toggleCount, 2);
      expect(detailCount, 0);

      // 6. Tapping between check hit box and schedule hit box (e.g. dx = 100) opens detail
      await tester.tapAt(Offset(100, checkCenter.dy));
      await _settle(tester);
      expect(detailCount, 1);
      expect(toggleCount, 2);
      expect(scheduleCount, 2);

      await _unmount(tester);
    },
  );

  testWidgets(
    'P1-B: overdue single item has 0 undated, group head not shown, View N undated not shown',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // 1 overdue item (yesterday)
      await db.into(db.todos).insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Overdue task',
              dueDate: Value(day.subtract(const Duration(days: 1))),
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

      // Summary shows "0 No date"
      expect(find.textContaining('· 0 No date ·'), findsOneWidget);
      // Group head for No date must NOT appear
      expect(find.text('No date'), findsNothing);
      // View N undated must NOT appear
      expect(find.textContaining('undated'), findsNothing);

      await _unmount(tester);
    },
  );

  testWidgets(
    'P1-B: three items (overdue, due today, undated) has exactly 1 undated, N = 1 - 1 = 0',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // 1 overdue item
      await db.into(db.todos).insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Overdue task',
              dueDate: Value(day.subtract(const Duration(days: 1))),
            ),
          );
      // 1 due today item
      await db.into(db.todos).insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Due today task',
              dueDate: Value(day),
            ),
          );
      // 1 undated item
      await db.into(db.todos).insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Undated task',
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

      // Summary shows "1 No date"
      expect(find.textContaining('· 1 No date ·'), findsOneWidget);
      // Group head shows 1
      expect(find.text('1'), findsWidgets);
      // View N undated must NOT appear since N = 1 - 1 = 0
      expect(find.textContaining('undated'), findsNothing);

      await _unmount(tester);
    },
  );

  testWidgets(
    'P1-B desktop: multi undated items has N = total undated - shown preview',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // 1 overdue item
      await db.into(db.todos).insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Overdue task',
              dueDate: Value(day.subtract(const Duration(days: 1))),
            ),
          );
      // 1 due today item
      await db.into(db.todos).insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Due today task',
              dueDate: Value(day),
            ),
          );
      // 5 undated items
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
      // N = 5 - 3 = 2 -> View 2 undated
      expect(find.text('View 2 undated'), findsOneWidget);

      await _unmount(tester);
    },
  );

  testWidgets(
    'P1: Earlier missed entry is visible and clickable when 30-day window has no missed items but has earlier missed series',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final earlierTodo = await db.into(db.todos).insertReturning(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Ancient recurring task',
              rrule: const Value('FREQ=DAILY;COUNT=10'),
            ),
          );

      final customProjection = ActionProjectionData(
        missedTaskInstances: const [],
        hasEarlierMissed: true,
        earlierMissedSeries: [earlierTodo],
      );

      await tester.pumpWidget(
        _app(
          overrides: [
            databaseProvider.overrideWithValue(db),
            actionDateProvider.overrideWith((ref) => day),
            actionProjectionProvider.overrideWithValue(AsyncValue.data(customProjection)),
          ],
          onOpenTodo: (_) {},
          onScheduleTodo: (_) {},
          onToggleTodo: (_, __, ___) async => true,
        ),
      );
      await _settle(tester);

      // Missed group header must appear
      expect(find.text('Missed'), findsOneWidget);
      // Earlier missed entry must be visible
      final earlierMissedFinder = find.text('Earlier missed…');
      expect(earlierMissedFinder, findsOneWidget);

      // Tapping Earlier missed expands the series
      await tester.tap(earlierMissedFinder);
      await _settle(tester);

      // Now earlier missed series row appears
      final ancientRecurringFinder = find.text('Ancient recurring task');
      expect(ancientRecurringFinder, findsAtLeastNWidgets(1));

      await _unmount(tester);
    },
  );

  testWidgets(
    'P1: mobile time row time label left edge aligns with group head (same x = 16 or 19)',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await db.into(db.events).insertReturning(
            EventsCompanion.insert(
              calendarId: calendarId,
              summary: 'Morning Standup',
              startDt: DateTime(2026, 10, 6, 9),
              endDt: DateTime(2026, 10, 6, 9, 30),
            ),
          );

      await tester.pumpWidget(
        _app(
          overrides: [
            databaseProvider.overrideWithValue(db),
            actionDateProvider.overrideWith((ref) => DateTime(2026, 10, 6)),
          ],
          onOpenTodo: (_) {},
          onScheduleTodo: (_) {},
          onToggleTodo: (_, __, ___) async => true,
        ),
      );
      await _settle(tester);

      // Group head has horizontal padding 16 inside ListView, content has padding horizontal 3 -> x = 19
      final groupHeadTextFinder = find.text('Earlier today');
      expect(groupHeadTextFinder, findsOneWidget);
      final groupHeadRect = tester.getRect(groupHeadTextFinder);

      // Mobile time row has horizontal padding 16 inside ListView -> row starts at x = 16
      final timeLabelFinder = find.text('09:00');
      expect(timeLabelFinder, findsOneWidget);
      final timeLabelParentRowFinder = find.ancestor(
        of: timeLabelFinder,
        matching: find.byType(Row),
      ).first;
      final timeRowRect = tester.getRect(timeLabelParentRowFinder);

      expect(
        timeRowRect.left,
        16.0,
        reason: '_mobileTimeRow must have horizontal padding 16 so time label column starts at x = 16',
      );
      // Group head title text starts at x = 16 + 3 = 19
      expect(groupHeadRect.left, 19.0);

      await _unmount(tester);
    },
  );

  testWidgets(
    'P1-1: desktop unplanned group is not rendered when unplanned has 0 items',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // Only an overdue todo, NO unplanned todos
      await db.into(db.todos).insert(
        TodosCompanion.insert(
          calendarId: calendarId,
          summary: 'Overdue task',
          dueDate: Value(DateTime(2026, 10, 5, 12)),
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

      // Overdue group is visible
      expect(find.text('Overdue'), findsOneWidget);
      // P1-1: Unplanned group head 'No date' must NOT be rendered when unplanned is empty
      expect(find.text('No date'), findsNothing);
      expect(find.text('No unscheduled tasks'), findsNothing);

      await _unmount(tester);
    },
  );

  testWidgets(
    'P1-2: desktop completing a todo shows floating undo bar with task name and undo, clears on tap',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await db.into(db.todos).insert(
        TodosCompanion.insert(
          calendarId: calendarId,
          summary: 'Desktop Task To Complete',
          dueDate: Value(DateTime(2026, 10, 6, 17)),
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
          onToggleTodo: (todo, occurrenceId, completed) async {
            await RecordScope.run(
              db,
              (tx) => TodoWriter.setCompletion(
                db,
                tx,
                todo.id,
                isCompleted: completed,
                occurrenceId: occurrenceId,
              ),
            );
            return true;
          },
        ),
      );
      await _settle(tester);

      expect(find.text('Desktop Task To Complete'), findsOneWidget);
      expect(find.byKey(const ValueKey('undo-bar')), findsNothing);

      // Tap check on Desktop Task
      final checkFinder = find.byWidgetPredicate(
        (w) => w is DsCheck && w.label == 'Desktop Task To Complete',
      );
      expect(checkFinder, findsOneWidget);
      await tester.tap(checkFinder);
      await _settle(tester);

      // P1-2: Floating undo bar appears with task summary and Undo
      final undoBarFinder = find.byKey(const ValueKey('undo-bar'));
      expect(undoBarFinder, findsOneWidget);
      expect(
        find.descendant(
          of: undoBarFinder,
          matching: find.textContaining('Desktop Task To Complete'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: undoBarFinder,
          matching: find.text('Undo'),
        ),
        findsOneWidget,
      );

      // Spec geometry: bottom 84, measured on the bar content (the snackbar
      // widget's own box includes the transparent lifting margin).
      final undoRect = tester.getRect(
        find.byKey(const ValueKey('undo-bar-content')),
      );
      expect(undoRect.bottom, 900 - 84);

      // Tap Undo in undo bar
      await tester.tap(find.descendant(
        of: undoBarFinder,
        matching: find.text('Undo'),
      ));
      await _settle(tester);

      // Undo bar dismissed
      expect(find.byKey(const ValueKey('undo-bar')), findsNothing);

      await _unmount(tester);
    },
  );

  testWidgets(
    'P1-3: desktop Earlier today is collapsed by default and toggles on click',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final todoId = await db.into(db.todos).insert(
        TodosCompanion.insert(
          calendarId: calendarId,
          summary: 'Early Morning Review',
        ),
      );

      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      // Ended allocation: 10:00 to 11:00 (now is 15:00)
      await container.read(createTaskAllocationProvider)(
        todoId: todoId,
        startAt: DateTime(2026, 10, 6, 10),
        endAt: DateTime(2026, 10, 6, 11),
      );
      container.dispose();

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

      // P1-3: Earlier today group head is rendered
      final headFinder = find.text('Earlier today');
      expect(headFinder, findsOneWidget);

      // Default earlyOpen: false -> items inside are NOT rendered
      expect(find.text('Early Morning Review'), findsNothing);

      // Tap group head to expand
      await tester.tap(headFinder);
      await _settle(tester);

      // Expanded: items inside are rendered
      expect(find.text('Early Morning Review'), findsOneWidget);

      // Tap group head again to collapse
      await tester.tap(headFinder);
      await _settle(tester);

      // Collapsed again
      expect(find.text('Early Morning Review'), findsNothing);

      await _unmount(tester);
    },
  );

  testWidgets(
    'P1-4: all-day events are excluded from upcoming timeline and do not show at 00:00',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final allDayEvent = CalendaEventAdapter(
        drifId: 1,
        calendarId: calendarId,
        title: 'Full Day Festival',
        start: DateTime(2026, 10, 6, 0, 0),
        end: DateTime(2026, 10, 7, 0, 0),
        isAllDay: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            actionProjectionProvider.overrideWith(
              (ref) => AsyncValue.data(
                ActionProjectionData(
                  events: [allDayEvent],
                ),
              ),
            ),
            unplannedTodosProvider.overrideWith(
              (ref) => const AsyncValue.data(<Todo>[]),
            ),
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
              body: A2TodayPage(
                now: DateTime(2026, 10, 6, 15),
                onOpenTodo: (_) {},
                onOpenEvent: (_) {},
                onToggleTodo: (_, __, ___) async => true,
                onOpenUnplanned: () {},
                onScheduleTodo: (_) {},
              ),
            ),
          ),
        ),
      );
      await _settle(tester);

      // All day event shows in all-day strip
      expect(find.text('Full Day Festival'), findsOneWidget);
      expect(find.byType(SpecAlldayStrip), findsOneWidget);

      // P1-4: Must NOT show in upcoming / timeline at 00:00
      expect(find.text('00:00'), findsNothing);
      expect(find.text('Upcoming'), findsNothing);

      await _unmount(tester);
    },
  );

  testWidgets(
    'P1-5: mobile capture bar onExpand opens composer sheet',
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

      expect(find.byType(A2ComposerSheet), findsNothing);

      // Tap send button on empty capture bar (triggers onExpand)
      final sendTarget = find.byKey(const ValueKey('capture-send-target'));
      expect(sendTarget, findsOneWidget);
      await tester.tap(sendTarget);
      await _settle(tester);

      // P1-5: A2ComposerSheet opens!
      expect(find.byType(A2ComposerSheet), findsOneWidget);

      await _unmount(tester);
    },
  );

  testWidgets(
    'P1: A2CaptureBar onSubmit error preserves input text and keeps focus',
    (tester) async {
      const originalText = 'Important task that failed to save';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: A2CaptureBar(
              fieldKey: const ValueKey('test-capture-field'),
              placeholder: 'Add task',
              hint: 'Enter',
              onSubmit: (text) async {
                throw Exception('Database write failed');
              },
            ),
          ),
        ),
      );
      await tester.pump();

      final textFieldFinder = find.byKey(const ValueKey('test-capture-field'));
      await tester.enterText(textFieldFinder, originalText);
      await tester.pump();

      expect(tester.widget<TextField>(textFieldFinder).controller!.text, originalText);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(tester.widget<TextField>(textFieldFinder).controller!.text, equals(originalText));
      expect(tester.widget<TextField>(textFieldFinder).focusNode!.hasFocus, isTrue);

      await tester.tap(find.byKey(const ValueKey('capture-send-target')));
      await tester.pump();

      expect(tester.widget<TextField>(textFieldFinder).controller!.text, equals(originalText));
      expect(tester.widget<TextField>(textFieldFinder).focusNode!.hasFocus, isTrue);

      await _unmount(tester);
    },
  );

  testWidgets(
    'P1: mobile completion shows the spec undo bar and Undo restores the task',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final todoId = await db.into(db.todos).insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Walk the dog',
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
          onToggleTodo: (todo, occurrenceId, completed) async {
            await RecordScope.run(
              db,
              (tx) => TodoWriter.setCompletion(
                db,
                tx,
                todo.id,
                isCompleted: completed,
                occurrenceId: occurrenceId,
              ),
            );
            return true;
          },
        ),
      );
      await _settle(tester);

      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is DsCheck && widget.label == 'Walk the dog',
        ),
      );
      await _settle(tester);

      final bar = find.byKey(const ValueKey('undo-bar-content'));
      expect(bar, findsOneWidget);
      expect(
        find.descendant(
          of: bar,
          matching: find.text('Marked completed · Walk the dog'),
        ),
        findsOneWidget,
      );
      final rect = tester.getRect(bar);
      expect(rect.left, 12);
      expect(rect.right, 390 - 12);
      expect(rect.bottom, 844 - 118);

      await tester.tap(
        find.descendant(of: bar, matching: find.text('Undo')),
      );
      await _settle(tester);

      expect(find.byKey(const ValueKey('undo-bar')), findsNothing);
      final row = await (db.select(
        db.todos,
      )..where((table) => table.id.equals(todoId))).getSingle();
      expect(row.status, 'NEEDS-ACTION');

      await _unmount(tester);
    },
  );

  testWidgets(
    'P1: summary counts the full data, not the visible list subset',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final overdue = await db.into(db.todos).insertReturning(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Late report',
              dueDate: Value(day.subtract(const Duration(days: 1))),
            ),
          );
      final due = await db.into(db.todos).insertReturning(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Ship build',
              dueDate: Value(day.add(const Duration(hours: 18))),
            ),
          );
      final seriesA = await db.into(db.todos).insertReturning(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Daily review',
              dueDate: Value(day.subtract(const Duration(days: 3))),
              rrule: const Value('FREQ=DAILY'),
              syncId: const Value('series-a'),
            ),
          );
      final seriesB = await db.into(db.todos).insertReturning(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Weekly notes',
              dueDate: Value(day.subtract(const Duration(days: 3))),
              rrule: const Value('FREQ=WEEKLY'),
              syncId: const Value('series-b'),
            ),
          );
      final completed = await db.into(db.todos).insertReturning(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Finished item',
              status: const Value('COMPLETED'),
              completedAt: Value(DateTime(2026, 10, 6, 10)),
            ),
          );
      for (var i = 0; i < 5; i++) {
        await db.into(db.todos).insert(
              TodosCompanion.insert(
                calendarId: calendarId,
                summary: 'Undated task $i',
              ),
            );
      }

      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      final allocationId = await container.read(createTaskAllocationProvider)(
        todoId: due.id,
        startAt: DateTime(2026, 10, 6, 9),
        endAt: DateTime(2026, 10, 6, 10),
      );
      container.dispose();
      final allocation = await (db.select(
        db.taskAllocations,
      )..where((table) => table.id.equals(allocationId))).getSingle();

      TodoOccurrence occurrence(String syncId, int dayOfMonth) =>
          TodoOccurrence(
            todoSyncId: syncId,
            occurrenceId: 'v2:DATE:2026-10-${dayOfMonth.toString().padLeft(2, '0')}',
            nominalAnchor: LocalDate(2026, 10, dayOfMonth),
            resolvedStartInstant: null,
            timeZone: 'Asia/Shanghai',
          );

      final projection = ActionProjectionData(
        overdueTodos: [overdue],
        dueTodayTodos: [due],
        allocations: [
          TaskAllocationCalendarItem(allocation: allocation, todo: due),
        ],
        missedTaskInstances: [
          ProjectedTaskInstance(
            todo: seriesA,
            occurrence: occurrence('series-a', 3),
            status: 'pending',
          ),
          ProjectedTaskInstance(
            todo: seriesA,
            occurrence: occurrence('series-a', 4),
            status: 'pending',
          ),
          ProjectedTaskInstance(
            todo: seriesB,
            occurrence: occurrence('series-b', 5),
            status: 'pending',
          ),
        ],
        completedTodayTodos: [completed],
      );

      const summary = '3 Overdue · 1 Due today · 5 No date · 1 Completed';

      await tester.pumpWidget(
        _app(
          overrides: [
            databaseProvider.overrideWithValue(db),
            actionDateProvider.overrideWith((ref) => day),
            actionProjectionProvider.overrideWithValue(
              AsyncValue.data(projection),
            ),
          ],
          onOpenTodo: (_) {},
          onScheduleTodo: (_) {},
          onToggleTodo: (_, __, ___) async => true,
        ),
      );
      await _settle(tester);
      expect(find.text(summary), findsOneWidget);

      tester.view.physicalSize = const Size(1440, 900);
      await tester.pumpWidget(
        _app(
          overrides: [
            databaseProvider.overrideWithValue(db),
            actionDateProvider.overrideWith((ref) => day),
            actionProjectionProvider.overrideWithValue(
              AsyncValue.data(projection),
            ),
          ],
          onOpenTodo: (_) {},
          onScheduleTodo: (_) {},
          onToggleTodo: (_, __, ___) async => true,
        ),
      );
      await _settle(tester);
      expect(find.text(summary), findsOneWidget);

      await _unmount(tester);
    },
  );

  testWidgets(
    'desktop capture keeps the sentence when the write fails and clears on retry',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      var fail = true;
      await tester.pumpWidget(
        _app(
          overrides: [
            databaseProvider.overrideWithValue(db),
            actionDateProvider.overrideWith((ref) => day),
            createTodoProvider.overrideWith((ref) {
              return ({
                required int calendarId,
                required String summary,
                required int priority,
                required String status,
                DateTime? dueDate,
                DateTime? startDate,
                String? description,
                String? rrule,
                RecurrenceSpec? recurrenceSpec,
                int? parentId,
              }) async {
                if (fail) throw StateError('offline');
                return 1;
              };
            }),
          ],
          onOpenTodo: (_) {},
          onScheduleTodo: (_) {},
          onToggleTodo: (_, __, ___) async => true,
        ),
      );
      await _settle(tester);

      final field = find.byKey(const ValueKey('desktop-capture-input'));
      expect(field, findsOneWidget);
      await tester.enterText(field, 'Keep this sentence');
      tester.widget<TextField>(field).onSubmitted!('Keep this sentence');
      await _settle(tester);

      expect(
        tester.widget<TextField>(field).controller!.text,
        'Keep this sentence',
      );

      fail = false;
      tester.widget<TextField>(field).onSubmitted!('Keep this sentence');
      await _settle(tester);
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);

      await _unmount(tester);
    },
  );
}
