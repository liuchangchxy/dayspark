import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/widgets/todo/todo_list_tile.dart';

Widget _wrap(Widget child) => ProviderScope(
  overrides: [
    todoTagsProvider(1).overrideWith((ref) => Stream.value([])),
    todoTagsProvider(2).overrideWith((ref) => Stream.value([])),
    todoTagsProvider(3).overrideWith((ref) => Stream.value([])),
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
    home: Scaffold(body: child),
  ),
);

void main() {
  group('TodoListTile', () {
    testWidgets(
      'pending row with index renders both ordinal and functional checkbox',
      (tester) async {
        var toggles = 0;
        await tester.pumpWidget(
          _wrap(
            TodoListTile(
              index: 0,
              summary: 'Buy groceries',
              isCompleted: false,
              priority: 5,
              todoId: 1,
              onToggle: (occurrenceId, isCompleted) async {
                toggles++;
              },
              onTap: () {},
            ),
          ),
        );

        expect(find.text('1'), findsOneWidget);
        expect(find.byType(DsCheck), findsOneWidget);

        await tester.tap(find.byType(DsCheck));
        await tester.pumpAndSettle();

        expect(toggles, 1);
      },
    );

    testWidgets('tapping completion control toggles without opening the row', (
      tester,
    ) async {
      var toggles = 0;
      var rowTaps = 0;
      await tester.pumpWidget(
        _wrap(
          TodoListTile(
            summary: 'Buy groceries',
            isCompleted: false,
            priority: 5,
            todoId: 1,
            onToggle: (occurrenceId, isCompleted) async {
              toggles++;
            },
            onTap: () => rowTaps++,
          ),
        ),
      );

      await tester.tap(find.byType(DsCheck));
      await tester.pumpAndSettle();

      expect(toggles, 1);
      expect(rowTaps, 0);
    });

    testWidgets('tapping row body opens it without toggling completion', (
      tester,
    ) async {
      var toggles = 0;
      var rowTaps = 0;
      await tester.pumpWidget(
        _wrap(
          TodoListTile(
            summary: 'Buy groceries',
            isCompleted: false,
            priority: 5,
            todoId: 1,
            onToggle: (occurrenceId, isCompleted) async {
              toggles++;
            },
            onTap: () => rowTaps++,
          ),
        ),
      );

      await tester.tap(find.text('Buy groceries'));
      await tester.pumpAndSettle();

      expect(rowTaps, 1);
      expect(toggles, 0);
    });

    testWidgets('tapping completed control restores the todo', (tester) async {
      var toggles = 0;
      var rowTaps = 0;
      await tester.pumpWidget(
        _wrap(
          TodoListTile(
            summary: 'Done task',
            isCompleted: true,
            priority: 5,
            todoId: 2,
            onToggle: (occurrenceId, isCompleted) async {
              toggles++;
            },
            onTap: () => rowTaps++,
          ),
        ),
      );

      await tester.tap(find.byType(DsCheck));
      await tester.pumpAndSettle();

      expect(toggles, 1);
      expect(rowTaps, 0);
    });

    testWidgets('mobile long title retains a 48dp independent checkbox', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _wrap(
          TodoListTile(
            summary:
                '这是很长的中文待办事项 Mixed English title with a deadline and further context',
            isCompleted: false,
            priority: 1,
            todoId: 1,
            dueDate: DateTime.now().add(const Duration(days: 1)),
            onToggle: (_, completed) async {},
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(DsCheck)), const Size(48, 48));
      final title = tester.getRect(find.textContaining('Mixed English'));
      final date = tester.getRect(find.textContaining('Tomorrow'));
      expect(date.left, greaterThan(title.right));
    });

    testWidgets('desktop deadline sits at the row edge without a card', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          TodoListTile(
            summary: 'Prepare review',
            isCompleted: false,
            priority: 5,
            todoId: 1,
            dueDate: DateTime.now().add(const Duration(days: 1)),
            onToggle: (_, completed) async {},
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Card), findsNothing);
      final title = tester.getRect(find.text('Prepare review'));
      final date = tester.getRect(find.textContaining('Tomorrow'));
      expect(date.left, greaterThan(title.right));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders summary and checkbox', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TodoListTile(
            summary: 'Buy groceries',
            isCompleted: false,
            priority: 5,
            todoId: 1,
            dueDate: DateTime(2026, 4, 20),
            onToggle: (occurrenceId, isCompleted) async {},
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Buy groceries'), findsOneWidget);
      expect(find.byType(DsCheck), findsOneWidget);
    });

    testWidgets('shows completed state with strikethrough', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TodoListTile(
            summary: 'Done task',
            isCompleted: true,
            priority: 0,
            todoId: 2,
            onToggle: (occurrenceId, isCompleted) async {},
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Done task'), findsOneWidget);
      final title = tester.widget<Text>(find.text('Done task'));
      expect(title.style?.decoration, TextDecoration.lineThrough);
      final checkbox = tester.widget<DsCheck>(find.byType(DsCheck));
      expect(checkbox.checked, true);
    });

    testWidgets('shows due date label', (tester) async {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      await tester.pumpWidget(
        _wrap(
          TodoListTile(
            summary: 'Task',
            isCompleted: false,
            priority: 5,
            todoId: 3,
            dueDate: tomorrow,
            onToggle: (occurrenceId, isCompleted) async {},
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Tomorrow'), findsOneWidget);
    });

    testWidgets('recurrence label sits in the meta line under the title', (
      tester,
    ) async {
      final now = DateTime.now();
      await tester.pumpWidget(
        _wrap(
          TodoListTile(
            summary: 'Recurring task',
            isCompleted: false,
            priority: 5,
            todoId: 3,
            dueDate: now.add(const Duration(days: 3)),
            todo: Todo(
              id: 3,
              calendarId: 1,
              summary: 'Recurring task',
              priority: 0,
              status: 'NEEDS-ACTION',
              rrule: 'FREQ=DAILY',
              sortOrder: 0,
              recurrenceRevision: 0,
              percentComplete: 0,
              createdAt: now,
              updatedAt: now,
              serverRev: 0,
            ),
            onToggle: (occurrenceId, isCompleted) async {},
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final repeat = find.text('Every day');
      final title = find.text('Recurring task');
      expect(repeat, findsOneWidget);
      expect(title, findsOneWidget);
      expect(
        tester.getRect(repeat).top,
        greaterThanOrEqualTo(tester.getRect(title).bottom),
      );
      expect(find.byIcon(CupertinoIcons.repeat), findsNothing);
    });
  });
}
