import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/ui/design/spec_components.dart';

void main() {
  group('SpecCheck', () {
    testWidgets('renders unchecked and responds to tap', (tester) async {
      bool? tappedVal;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpecCheck(
              checked: false,
              onChanged: (v) => tappedVal = v,
            ),
          ),
        ),
      );

      final finder = find.byType(SpecCheck);
      expect(finder, findsOneWidget);
      // touch target is 48 by default
      final size = tester.getSize(finder);
      expect(size.width, greaterThanOrEqualTo(48.0));
      expect(size.height, greaterThanOrEqualTo(48.0));

      await tester.tap(finder);
      expect(tappedVal, isTrue);
    });

    testWidgets('renders checked state with ink fill', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SpecCheck(
              checked: true,
              onChanged: null,
            ),
          ),
        ),
      );

      expect(find.byIcon(CupertinoIcons.checkmark), findsOneWidget);
    });
  });

  group('SpecTaskRow', () {
    testWidgets('renders title, due label, and triggers toggle', (tester) async {
      var toggled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpecTaskRow(
              title: 'Review proposal',
              dueLabel: '18:00',
              onToggle: (v) => toggled = v,
            ),
          ),
        ),
      );

      expect(find.text('Review proposal'), findsOneWidget);
      expect(find.text('18:00'), findsOneWidget);

      await tester.tap(find.byType(SpecCheck));
      expect(toggled, isTrue);
    });

    testWidgets('renders overdue due pill with transparent background and red text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SpecTaskRow(
              title: 'Overdue task',
              dueLabel: '10/20',
              isOverdue: true,
            ),
          ),
        ),
      );

      final text = tester.widget<Text>(find.text('10/20'));
      expect(text.style?.color, const Color(0xFFC92A1E)); // SpecTokens.red
      final container = tester.widget<Container>(
        find.ancestor(of: find.text('10/20'), matching: find.byType(Container)).first,
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, Colors.transparent);
    });

    testWidgets('renders schedule action button when onSchedule is provided', (tester) async {
      var scheduled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpecTaskRow(
              title: 'Schedule task',
              onSchedule: () => scheduled = true,
            ),
          ),
        ),
      );

      expect(find.byIcon(CupertinoIcons.calendar), findsOneWidget);
      await tester.tap(find.byIcon(CupertinoIcons.calendar));
      expect(scheduled, isTrue);
    });

    testWidgets('handles disabled state', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpecTaskRow(
              title: 'Disabled task',
              disabled: true,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Disabled task'));
      expect(tapped, isFalse);
    });
  });

  group('SpecChip', () {
    testWidgets('renders chip tone and handles tap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpecChip(
              label: 'Planned 15:00',
              tone: SpecChipTone.plan,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Planned 15:00'), findsOneWidget);
      await tester.tap(find.text('Planned 15:00'));
      expect(tapped, isTrue);
    });
  });

  group('SpecTimeBlock & SpecTimelineRow', () {
    testWidgets('renders event block with custom bar and bg', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SpecTimeBlock(
              kind: SpecTimeBlockKind.event,
              title: 'Team sync',
              meta: '10:00 - 11:00',
            ),
          ),
        ),
      );

      expect(find.text('Team sync'), findsOneWidget);
      expect(find.text('10:00 - 11:00'), findsOneWidget);
    });

    testWidgets('renders timeline row with 52 time column, 12 rail and content', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SpecTimelineRow(
              timeLabel: '10:00',
              child: SpecTimeBlock(
                kind: SpecTimeBlockKind.event,
                title: 'Review',
              ),
            ),
          ),
        ),
      );

      expect(find.text('10:00'), findsOneWidget);
      expect(find.text('Review'), findsOneWidget);
    });

    testWidgets('renders plan block with tag and check', (tester) async {
      var checked = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpecTimeBlock(
              kind: SpecTimeBlockKind.plan,
              title: 'Write docs',
              planLabel: '计划',
              onToggle: (v) => checked = v,
            ),
          ),
        ),
      );

      expect(find.text('Write docs'), findsOneWidget);
      expect(find.text('计划'), findsOneWidget);
      await tester.tap(find.byType(SpecCheck));
      expect(checked, isTrue);
    });
  });

  group('SpecAlldayStrip', () {
    testWidgets('renders all-day strip with 48px label and chips', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpecAlldayStrip(
              label: '全天',
              items: [
                SpecAlldayItem(
                  title: 'Offsite',
                  onTap: () => tapped = true,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('全天'), findsOneWidget);
      expect(find.text('Offsite'), findsOneWidget);
      await tester.tap(find.text('Offsite'));
      expect(tapped, isTrue);
    });
  });

  group('SpecSegmented', () {
    testWidgets('switches selected option', (tester) async {
      var selected = 'day';
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => MaterialApp(
            home: Scaffold(
              body: SpecSegmented<String>(
                current: selected,
                options: const [('day', 'Day'), ('week', 'Week')],
                onChanged: (v) => setState(() => selected = v),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Day'), findsOneWidget);
      expect(find.text('Week'), findsOneWidget);
      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();
      expect(selected, 'week');
    });
  });

  group('SpecEmpty & SpecErrorState & SpecNowLine', () {
    testWidgets('renders empty state', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SpecEmpty(
              title: 'No tasks today',
              hint: 'Enjoy your clean day',
            ),
          ),
        ),
      );

      expect(find.text('No tasks today'), findsOneWidget);
      expect(find.text('Enjoy your clean day'), findsOneWidget);
    });

    testWidgets('renders error state and retries', (tester) async {
      var retried = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpecErrorState(
              message: 'Failed to connect',
              retryLabel: 'Retry',
              onRetry: () => retried = true,
            ),
          ),
        ),
      );

      expect(find.text('Failed to connect'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retried, isTrue);
    });

    testWidgets('renders now line with left margin 52 and red line without text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SpecNowLine(),
          ),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container).first);
      expect(container.margin, const EdgeInsets.only(left: 52, top: 3, bottom: 3));
      expect(find.byType(Divider), findsOneWidget);
    });
  });

  group('SpecDeleteConfirmDialog', () {
    testWidgets('shows confirmation and cancels or confirms', (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await SpecDeleteConfirmDialog.show(
                    context,
                    title: 'Delete Task?',
                    message: 'It will be moved to trash.',
                    cancelLabel: 'Cancel',
                    confirmLabel: 'Delete',
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Task?'), findsOneWidget);
      expect(find.text('It will be moved to trash.'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });
  });
}
