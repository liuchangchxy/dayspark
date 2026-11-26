import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/domain/providers/default_tab_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/shell/spark_top_bar.dart';
import 'package:dayspark/ui/shell/workspace_navigation.dart';

Widget _app({
  EdgeInsets padding = EdgeInsets.zero,
  double width = 800,
  double height = 600,
  ValueChanged<int>? onSelect,
  ProviderContainer? container,
}) {
  final widget = MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, height),
        padding: padding,
        viewPadding: padding,
      ),
      child: Scaffold(
        body: SparkTopBar(
          clock: () => DateTime(2026, 11, 15, 10),
          onSelect: onSelect,
        ),
      ),
    ),
  );

  if (container != null) {
    return UncontrolledProviderScope(container: container, child: widget);
  }
  return ProviderScope(child: widget);
}

void main() {
  testWidgets('search action hit target is at least 48dp on a narrow bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await tester.pump();

    final size = tester.getSize(find.byKey(const ValueKey('nav-search')));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));

    final visual = tester.getSize(
      find.byKey(const ValueKey('nav-search-visual')),
    );
    expect(visual.height, 29);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets(
    'Android wide window (762dp, top: 52) clears status bar and enables tab switching',
    (tester) async {
      tester.view.physicalSize = const Size(762, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      var selectedIndex = 0;
      await tester.pumpWidget(
        _app(
          padding: const EdgeInsets.only(top: 52),
          width: 762,
          height: 1000,
          onSelect: (index) => selectedIndex = index,
          container: container,
        ),
      );
      await tester.pump();

      // Top bar overall height is 52 + 52 = 104.
      final barSize = tester.getSize(find.byType(SparkTopBar));
      expect(barSize.height, 104);

      // Assert all first-row controls top >= 52.
      expect(tester.getTopLeft(find.text('DaySpark')).dy, greaterThanOrEqualTo(52));
      expect(tester.getTopLeft(find.byKey(const ValueKey('nav-today'))).dy, greaterThanOrEqualTo(52));
      expect(tester.getTopLeft(find.byKey(const ValueKey('nav-todos'))).dy, greaterThanOrEqualTo(52));
      expect(tester.getTopLeft(find.byKey(const ValueKey('nav-calendar'))).dy, greaterThanOrEqualTo(52));
      expect(tester.getTopLeft(find.byKey(const ValueKey('nav-search'))).dy, greaterThanOrEqualTo(52));
      expect(tester.getTopLeft(find.byKey(const ValueKey('nav-search-visual'))).dy, greaterThanOrEqualTo(52));
      expect(tester.getTopLeft(find.text('Me')).dy, greaterThanOrEqualTo(52));

      // Initial tab is AppTab.action.
      expect(container.read(workspaceTabProvider), AppTab.action);

      // Tap Tasks nav button to switch tab.
      await tester.tap(find.byKey(const ValueKey('nav-todos')));
      await tester.pump();
      expect(selectedIndex, 2);
      expect(container.read(workspaceTabProvider), AppTab.todos);

      // Tap Calendar nav button to switch tab.
      await tester.tap(find.byKey(const ValueKey('nav-calendar')));
      await tester.pump();
      expect(selectedIndex, 1);
      expect(container.read(workspaceTabProvider), AppTab.calendar);

      // Tap Today nav button to switch tab.
      await tester.tap(find.byKey(const ValueKey('nav-today')));
      await tester.pump();
      expect(selectedIndex, 0);
      expect(container.read(workspaceTabProvider), AppTab.action);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    },
  );

  testWidgets(
    'padding.top=0 maintains pixel-for-pixel original desktop geometry',
    (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _app(padding: EdgeInsets.zero, width: 800, height: 600),
      );
      await tester.pump();

      // Top bar height is strictly 52.
      final barSize = tester.getSize(find.byType(SparkTopBar));
      expect(barSize.height, 52);

      // Nav buttons height is 52 and starts at top = 0.
      final todayNav = find.byKey(const ValueKey('nav-today'));
      final todosNav = find.byKey(const ValueKey('nav-todos'));
      final calendarNav = find.byKey(const ValueKey('nav-calendar'));

      expect(tester.getSize(todayNav).height, 51.0);
      expect(tester.getSize(todosNav).height, 51.0);
      expect(tester.getSize(calendarNav).height, 51.0);

      expect(tester.getTopLeft(todayNav).dy, 0);
      expect(tester.getTopLeft(todosNav).dy, 0);
      expect(tester.getTopLeft(calendarNav).dy, 0);

      // Spacing between nav buttons.
      final todayRight = tester.getTopRight(todayNav).dx;
      final todosLeft = tester.getTopLeft(todosNav).dx;
      expect(todosLeft - todayRight, 4);

      final todosRight = tester.getTopRight(todosNav).dx;
      final calendarLeft = tester.getTopLeft(calendarNav).dx;
      expect(calendarLeft - todosRight, 4);

      // Tool button height is strictly 29.
      final searchVisual = find.byKey(const ValueKey('nav-search-visual'));
      expect(tester.getSize(searchVisual).height, 29);
      expect(tester.getTopLeft(searchVisual).dy, 11.0);

      // Wordmark icon height is 22, top is 15.
      final dBadge = find.text('D');
      expect(tester.getTopLeft(dBadge).dy, greaterThanOrEqualTo(15));

      // Me button height is 27, top is 12.5.
      final meBadge = find.text('Me');
      expect(tester.getTopLeft(meBadge).dy, greaterThanOrEqualTo(12.5));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    },
  );

  testWidgets('top-bar nav buttons activate from the keyboard', (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    int? selected;
    await tester.pumpWidget(
      _app(
        width: 900,
        height: 700,
        onSelect: (index) => selected = index,
        container: container,
      ),
    );
    await tester.pump();

    final todosNav = find.byKey(const ValueKey('nav-todos'));
    final gesture = find
        .descendant(of: todosNav, matching: find.byType(GestureDetector))
        .first;
    Focus.of(tester.element(gesture)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(selected, 2);
    expect(container.read(workspaceTabProvider), AppTab.todos);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
