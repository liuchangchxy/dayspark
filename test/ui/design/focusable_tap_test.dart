import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/ui/design/a2.dart';

Widget _app(Widget child) {
  return MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('a disabled FocusableTap leaves the tab order', (tester) async {
    final first = FocusNode(debugLabel: 'first');
    final disabled = FocusNode(debugLabel: 'disabled');
    final third = FocusNode(debugLabel: 'third');
    addTearDown(() {
      first.dispose();
      disabled.dispose();
      third.dispose();
    });

    await tester.pumpWidget(
      _app(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FocusableTap(
              key: const ValueKey('first'),
              focusNode: first,
              onTap: () {},
              semanticsLabel: 'First',
              child: const SizedBox(width: 120, height: 48),
            ),
            FocusableTap(
              key: const ValueKey('disabled'),
              focusNode: disabled,
              semanticsLabel: 'Disabled',
              child: const SizedBox(width: 120, height: 48),
            ),
            FocusableTap(
              key: const ValueKey('third'),
              focusNode: third,
              onTap: () {},
              semanticsLabel: 'Third',
              child: const SizedBox(width: 120, height: 48),
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    final disabledFocus = tester.widget<Focus>(
      find
          .descendant(
            of: find.byKey(const ValueKey('disabled')),
            matching: find.byType(Focus),
          )
          .first,
    );
    expect(disabledFocus.canRequestFocus, isFalse);
    expect(disabledFocus.skipTraversal, isTrue);

    first.requestFocus();
    await tester.pump();
    expect(first.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(third.hasFocus, isTrue);
    expect(disabled.hasFocus, isFalse);
  });

  testWidgets('a labeled control exposes a tap action to screen readers', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var taps = 0;

    await tester.pumpWidget(
      _app(
        FocusableTap(
          key: const ValueKey('labeled'),
          onTap: () => taps++,
          semanticsLabel: 'Open',
          child: const SizedBox(width: 120, height: 48),
        ),
      ),
    );
    await tester.pump();

    final node = tester.getSemantics(find.byKey(const ValueKey('labeled')));
    final data = node.getSemanticsData();
    expect(data.label, 'Open');
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(taps, 0);

    final target = find.semantics.byLabel(
      'Open',
      view: tester.view,
    );
    tester.semantics.tap(target);
    await tester.pump();
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('a nested action keeps its own node and fires alone', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final row = FocusNode(debugLabel: 'row');
    final action = FocusNode(debugLabel: 'action');
    addTearDown(() {
      row.dispose();
      action.dispose();
    });
    var rowTaps = 0;
    var actionTaps = 0;

    await tester.pumpWidget(
      _app(
        FocusableTap(
          key: const ValueKey('row'),
          focusNode: row,
          onTap: () => rowTaps++,
          child: SizedBox(
            width: 240,
            height: 64,
            child: Center(
              child: FocusableTap(
                key: const ValueKey('action'),
                focusNode: action,
                onTap: () => actionTaps++,
                semanticsLabel: 'Undo',
                child: const SizedBox(width: 64, height: 48),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final rowNode = tester.getSemantics(find.byKey(const ValueKey('row')));
    final actionNode = tester.getSemantics(
      find.byKey(const ValueKey('action')),
    );
    expect(rowNode.id, isNot(actionNode.id));
    final actionData = actionNode.getSemanticsData();
    expect(actionData.label, 'Undo');
    expect(actionData.hasAction(SemanticsAction.tap), isTrue);

    await tester.tap(find.byKey(const ValueKey('action')));
    await tester.pump();
    expect(actionTaps, 1);
    expect(rowTaps, 0);

    action.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(actionTaps, 2);
    expect(rowTaps, 0);
    handle.dispose();
  });
}
