import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/feedback/feedback_page.dart';

Widget _app({required FeedbackLinkOpener opener}) => ProviderScope(
      overrides: [feedbackLinkOpenerProvider.overrideWithValue(opener)],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('en'),
        home: FeedbackPage(),
      ),
    );

void main() {
  testWidgets('a failed browser launch keeps the text and explains inline', (
    tester,
  ) async {
    await tester.pumpWidget(_app(opener: (uri) async => false));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '拖动后结束时间没有跟着变');
    await tester.pump();

    expect(find.text('12 characters · Logs are not attached automatically'), findsOneWidget);
    expect(find.text('You can copy it or take it to GitHub'), findsOneWidget);
    expect(find.textContaining('DaySpark never submits anything'), findsOneWidget);

    await tester.tap(find.text('Submit on GitHub'));
    await tester.pumpAndSettle();

    // SPEC 2698: no silent failure — the page says why and the text stays.
    expect(find.text('Could not open the browser.'), findsOneWidget);
    expect(
      find.text(
        'Your text is still here; retry, or copy it to the clipboard and open it manually.',
      ),
      findsOneWidget,
    );
    expect(find.text('拖动后结束时间没有跟着变'), findsOneWidget);
  });

  testWidgets('a successful launch does not show the error alert', (tester) async {
    await tester.pumpWidget(_app(opener: (uri) async => true));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.tap(find.text('Submit on GitHub'));
    await tester.pumpAndSettle();

    expect(find.text('Could not open the browser.'), findsNothing);
  });
}
