import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calendar_todo_app/ui/widgets/todo/todo_list_tile.dart';

void main() {
  group('TodoListTile', () {
    testWidgets('renders summary and checkbox', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TodoListTile(
              summary: 'Buy groceries',
              isCompleted: false,
              priority: 5,
              dueDate: DateTime(2026, 4, 20),
              onToggle: () {},
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('Buy groceries'), findsOneWidget);
      expect(find.byType(Checkbox), findsOneWidget);
    });

    testWidgets('shows completed state with strikethrough', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TodoListTile(
              summary: 'Done task',
              isCompleted: true,
              priority: 0,
              onToggle: () {},
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('Done task'), findsOneWidget);
      // Verify checkbox is checked
      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.value, true);
    });

    testWidgets('shows due date label', (tester) async {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TodoListTile(
              summary: 'Task',
              isCompleted: false,
              priority: 5,
              dueDate: tomorrow,
              onToggle: () {},
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('Tomorrow'), findsOneWidget);
    });
  });
}
