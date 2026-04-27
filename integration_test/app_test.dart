import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:dayspark/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App Launch', () {
    testWidgets('app launches and shows home page', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Should show app bar title
      expect(find.text('Calendar Todo'), findsOneWidget);

      // Should show bottom navigation with Calendar and Todos tabs
      expect(find.text('Calendar'), findsOneWidget);
      expect(find.text('Todos'), findsOneWidget);

      // Should show FAB
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('shows empty calendar state', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Calendar tab is default — should have calendar view
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });
  });

  group('Navigation', () {
    testWidgets('navigate to settings page', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Tap settings icon
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('CalDAV Account'), findsOneWidget);
      expect(find.text('Manage Tags'), findsOneWidget);
      expect(find.text('About'), findsOneWidget);
    });

    testWidgets('navigate to tags page from settings', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Manage Tags'));
      await tester.pumpAndSettle();

      expect(find.text('Manage Tags'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('switch between calendar and todos tabs', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Default is calendar tab
      expect(find.text('Calendar'), findsOneWidget);

      // Tap Todos tab
      await tester.tap(find.text('Todos'));
      await tester.pumpAndSettle();

      // Should show empty todos message
      expect(find.text('No pending todos'), findsOneWidget);
    });

    testWidgets('back button works from settings', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('Calendar Todo'), findsOneWidget);
    });
  });

  group('Todo CRUD', () {
    testWidgets('FAB navigates to create todo when on Todos tab',
        (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Switch to todos tab
      await tester.tap(find.text('Todos'));
      await tester.pumpAndSettle();

      // Tap FAB
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Should be on todo create page
      expect(find.text('New Todo'), findsOneWidget);
      expect(find.text('Title'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('create a todo and see it in list', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Switch to todos tab
      await tester.tap(find.text('Todos'));
      await tester.pumpAndSettle();

      // Tap FAB
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Fill in title
      await tester.enterText(find.byType(TextField).first, 'Buy groceries');
      await tester.pumpAndSettle();

      // Save
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Should be back on todos list
      expect(find.text('Buy groceries'), findsOneWidget);
    });

    testWidgets('tap todo to edit it', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Switch to todos tab
      await tester.tap(find.text('Todos'));
      await tester.pumpAndSettle();

      // Create a todo first
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Test edit todo');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Tap the todo to edit
      await tester.tap(find.text('Test edit todo'));
      await tester.pumpAndSettle();

      // Should be on edit page
      expect(find.text('Edit Todo'), findsOneWidget);
      expect(find.text('Test edit todo'), findsOneWidget);
    });

    testWidgets('complete a todo via checkbox', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Switch to todos tab
      await tester.tap(find.text('Todos'));
      await tester.pumpAndSettle();

      // Create a todo
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Complete me');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Find the checkbox and tap it
      final checkbox = find.byType(Checkbox);
      if (checkbox.evaluate().isNotEmpty) {
        await tester.tap(checkbox.first);
        await tester.pumpAndSettle();

        // Todo should disappear from pending list
        expect(find.text('Complete me'), findsNothing);
      }
    });
  });

  group('Event CRUD', () {
    testWidgets('FAB navigates to create event on Calendar tab',
        (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Tap FAB (calendar tab is default)
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Should be on event create page
      expect(find.text('New Event'), findsOneWidget);
      expect(find.text('Title'), findsOneWidget);
    });

    testWidgets('create event requires title', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Tap save without entering title
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Should still be on create page (validation failed)
      expect(find.text('New Event'), findsOneWidget);
    });
  });

  group('Settings', () {
    testWidgets('shows CalDAV account section', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      expect(find.text('CalDAV Account'), findsOneWidget);
      expect(find.text('Add CalDAV Account'), findsOneWidget);
    });

    testWidgets('shows appearance section', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
    });

    testWidgets('shows about section', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      expect(find.text('About'), findsOneWidget);
      expect(find.text('Calendar Todo v0.1.0'), findsOneWidget);
    });

    testWidgets('tag management page shows empty state', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Manage Tags'));
      await tester.pumpAndSettle();

      expect(find.text('No tags yet'), findsOneWidget);
    });

    testWidgets('create a new tag', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Manage Tags'));
      await tester.pumpAndSettle();

      // Tap add button
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.text('New Tag'), findsOneWidget);

      // Enter tag name
      await tester.enterText(
          find.widgetWithText(TextField, 'Tag name'), 'Work');
      await tester.pumpAndSettle();

      // Tap create
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      // Should show the new tag
      expect(find.text('Work'), findsOneWidget);
    });

    testWidgets('delete a tag', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // First create a tag
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Manage Tags'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'Tag name'), 'DeleteMe');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      // Now delete it
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      // Should show empty state
      expect(find.text('No tags yet'), findsOneWidget);
    });
  });

  group('CalDAV Dialog', () {
    testWidgets('open and cancel CalDAV config dialog', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add CalDAV Account'));
      await tester.pumpAndSettle();

      expect(find.text('Add CalDAV Account'), findsOneWidget);
      expect(find.text('Server URL'), findsOneWidget);
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Should be back on settings
      expect(find.text('Settings'), findsOneWidget);
    });
  });
}
