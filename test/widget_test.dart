import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:calendar_todo_app/main.dart';

void main() {
  testWidgets('App renders HomePage with title', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: CalendarTodoApp()));

    // Verify the app title is shown
    expect(find.text('Calendar Todo'), findsOneWidget);

    // Verify the skeleton text is shown
    expect(find.text('Calendar & Todo'), findsOneWidget);

    // Verify settings button exists
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });

  testWidgets('Settings navigation works', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: CalendarTodoApp()));

    // Tap the settings icon
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    // Verify we're on the settings page
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('CalDAV Accounts'), findsOneWidget);
    expect(find.text('AI Configuration'), findsOneWidget);
  });
}
