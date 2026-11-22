import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/shell/spark_top_bar.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';

Widget _scaffoldApp({
  required double width,
  required double height,
  required EdgeInsets padding,
  required Widget child,
}) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, height),
        padding: padding,
        viewPadding: padding,
      ),
      child: WorkspaceScaffold(child: child),
    ),
  ),
);

void main() {
  testWidgets(
    'WorkspaceScaffold on wide window (762dp, top: 52) clears status bar and removes top padding from child',
    (tester) async {
      tester.view.physicalSize = const Size(762, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      EdgeInsets? childPadding;

      await tester.pumpWidget(
        _scaffoldApp(
          width: 762,
          height: 1000,
          padding: const EdgeInsets.only(top: 52),
          child: Builder(
            builder: (context) {
              childPadding = MediaQuery.paddingOf(context);
              return const Scaffold(body: Text('Workspace Child Content'));
            },
          ),
        ),
      );
      await tester.pump();

      // SparkTopBar is present and its height includes top padding (52 + 52 = 104).
      expect(find.byType(SparkTopBar), findsOneWidget);
      expect(tester.getSize(find.byType(SparkTopBar)).height, 104);

      // Child receives top padding = 0 because top bar consumed it.
      expect(childPadding?.top, 0);

      // Content of child starts below SparkTopBar.
      expect(
        tester.getTopLeft(find.text('Workspace Child Content')).dy,
        greaterThanOrEqualTo(104),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    },
  );

  testWidgets(
    'WorkspaceScaffold on narrow window (< 720dp) passes child directly without top bar',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      EdgeInsets? childPadding;

      await tester.pumpWidget(
        _scaffoldApp(
          width: 390,
          height: 844,
          padding: const EdgeInsets.only(top: 48),
          child: Builder(
            builder: (context) {
              childPadding = MediaQuery.paddingOf(context);
              return const Scaffold(body: Text('Mobile Child Content'));
            },
          ),
        ),
      );
      await tester.pump();

      // No SparkTopBar on mobile.
      expect(find.byType(SparkTopBar), findsNothing);

      // Child retains original top padding for its own mobile SafeArea.
      expect(childPadding?.top, 48);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    },
  );
}
