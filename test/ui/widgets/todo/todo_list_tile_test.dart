import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
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
    testWidgets('renders summary and checkbox', (tester) async {
      await tester.pumpWidget(_wrap(
        TodoListTile(
          summary: 'Buy groceries',
          isCompleted: false,
          priority: 5,
          todoId: 1,
          dueDate: DateTime(2026, 4, 20),
          onToggle: () {},
          onTap: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Buy groceries'), findsOneWidget);
      expect(find.byType(Checkbox), findsOneWidget);
    });

    testWidgets('shows completed state with strikethrough', (tester) async {
      await tester.pumpWidget(_wrap(
        TodoListTile(
          summary: 'Done task',
          isCompleted: true,
          priority: 0,
          todoId: 2,
          onToggle: () {},
          onTap: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Done task'), findsOneWidget);
      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.value, true);
    });

    testWidgets('shows due date label', (tester) async {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      await tester.pumpWidget(_wrap(
        TodoListTile(
          summary: 'Task',
          isCompleted: false,
          priority: 5,
          todoId: 3,
          dueDate: tomorrow,
          onToggle: () {},
          onTap: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Tomorrow'), findsOneWidget);
    });
  });
}
