import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/ui/widgets/undo_bar.dart';

const _triggerKey = ValueKey('undo-bar-test-trigger');
const _navKey = ValueKey('undo-bar-test-nav');
const _contentKey = ValueKey('undo-bar-content');

Widget _harness({
  required VoidCallback onUndo,
  required VoidCallback onNav,
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: Stack(
        children: [
          Center(
            child: Builder(
              builder: (context) => TextButton(
                key: _triggerKey,
                onPressed: () => showUndoBar(
                  context,
                  message: 'Deleted',
                  undoLabel: 'Undo',
                  onUndo: onUndo,
                ),
                child: const Text('delete'),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: 56,
              child: TextButton(
                key: _navKey,
                onPressed: onNav,
                child: const Text('nav'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

void _usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _showBar(WidgetTester tester) async {
  await tester.tap(find.byKey(_triggerKey));
  await tester.pumpAndSettle();
  expect(find.text('Deleted'), findsOneWidget);
}

void main() {
  testWidgets('undo bar times out on its own', (tester) async {
    _usePhone(tester);
    await tester.pumpWidget(_harness(onUndo: () {}, onNav: () {}));

    await _showBar(tester);

    // Flutter 3.41 persists action snackbars by default, so without an
    // explicit timeout this bar is still here after twelve seconds.
    await tester.pump(const Duration(seconds: 12));
    await tester.pumpAndSettle();

    expect(find.text('Deleted'), findsNothing);
  });

  testWidgets('visible undo bar does not intercept the tab bar', (
    tester,
  ) async {
    _usePhone(tester);
    var navs = 0;
    await tester.pumpWidget(_harness(onUndo: () {}, onNav: () => navs++));

    await _showBar(tester);

    // The bar is lifted above the 56px tab bar: its visible area ends above
    // the nav, and the transparent margin must not absorb the tap.
    await tester.tap(find.byKey(_navKey));
    await tester.pump();

    expect(navs, 1, reason: 'the tab bar must stay tappable under the bar');
  });

  testWidgets('tab bar is tappable again after the bar retires', (tester) async {
    _usePhone(tester);
    var navs = 0;
    await tester.pumpWidget(_harness(onUndo: () {}, onNav: () => navs++));

    await _showBar(tester);
    await tester.pump(kUndoBarDuration);
    await tester.pumpAndSettle();
    expect(find.text('Deleted'), findsNothing);

    await tester.tap(find.byKey(_navKey));
    await tester.pump();

    expect(navs, 1);
  });

  testWidgets('swiping down dismisses the bar', (tester) async {
    _usePhone(tester);
    await tester.pumpWidget(_harness(onUndo: () {}, onNav: () {}));

    await _showBar(tester);
    await tester.drag(find.text('Deleted'), const Offset(0, 200));
    await tester.pumpAndSettle();

    expect(find.text('Deleted'), findsNothing);
  });

  testWidgets('tapping the message dismisses the bar', (tester) async {
    _usePhone(tester);
    var undos = 0;
    await tester.pumpWidget(_harness(onUndo: () => undos++, onNav: () {}));

    await _showBar(tester);
    await tester.tap(find.text('Deleted'));
    await tester.pumpAndSettle();

    expect(find.text('Deleted'), findsNothing);
    expect(undos, 0);
  });

  testWidgets('tapping undo runs the action and dismisses the bar', (
    tester,
  ) async {
    _usePhone(tester);
    var undos = 0;
    await tester.pumpWidget(_harness(onUndo: () => undos++, onNav: () {}));

    await _showBar(tester);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(undos, 1);
    expect(find.text('Deleted'), findsNothing);
  });

  testWidgets('desktop bar is compact, centered and clears the bottom edge', (
    tester,
  ) async {
    _useDesktop(tester);
    var navs = 0;
    await tester.pumpWidget(_harness(onUndo: () {}, onNav: () => navs++));

    await _showBar(tester);

    final rect = tester.getRect(find.byKey(_contentKey));
    expect(rect.width, lessThan(400));
    expect(rect.center.dx, closeTo(720, 1));
    expect(rect.bottom, lessThanOrEqualTo(900 - 84 + 1));

    await tester.tap(find.byKey(_navKey));
    await tester.pump();
    expect(navs, 1);
  });
}
