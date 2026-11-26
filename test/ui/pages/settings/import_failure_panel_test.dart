import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/domain/services/ics_service.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/pages/settings/settings_sections/import_export_section.dart';

Widget _panel(ImportFailurePanel panel) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: Scaffold(body: SingleChildScrollView(child: panel)),
);

void main() {
  testWidgets('a whole-file parse error offers a report but no fake skip', (
    tester,
  ) async {
    var reports = 0;
    await tester.pumpWidget(
      _panel(
        ImportFailurePanel(
          error: 'Not a valid VCALENDAR',
          skipped: const [],
          onReport: () => reports++,
          onSkip: null,
        ),
      ),
    );

    expect(find.text('Import failed'), findsOneWidget);
    expect(find.text('Parse error: Not a valid VCALENDAR'), findsOneWidget);
    expect(
      find.text(
        'The whole file cannot be parsed, so error rows cannot be skipped; '
        'fix the file and retry.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('View report'));
    expect(reports, 1);

    // The skip action is present but genuinely disabled: no dead button.
    final skip = tester.widget<DsButton>(
      find.widgetWithText(DsButton, 'Skip error rows and continue'),
    );
    expect(skip.onPressed, isNull);
  });

  testWidgets('row-level failures can be skipped and reported', (tester) async {
    var skips = 0;
    await tester.pumpWidget(
      _panel(
        ImportFailurePanel(
          error: null,
          skipped: const [
            IcsPreviewItem(
              kind: IcsPreviewKind.event,
              status: IcsPreviewStatus.skipped,
              summary: '第 14 行',
            ),
          ],
          onReport: () {},
          onSkip: () => skips++,
        ),
      ),
    );

    expect(find.text('1 row(s) failed during import'), findsOneWidget);
    expect(
      find.text(
        'The whole file cannot be parsed, so error rows cannot be skipped; '
        'fix the file and retry.',
      ),
      findsNothing,
    );

    await tester.tap(find.text('Skip error rows and continue'));
    expect(skips, 1);
  });

  testWidgets(
    'partial import keeps the failure surface and the written summary',
    (tester) async {
      await tester.pumpWidget(
        _panel(
          ImportFailurePanel(
            error: null,
            skipped: const [],
            failedCount: 2,
            summary: 'Created 3 · updated 1 · skipped 2',
            onReport: () {},
            onSkip: () {},
          ),
        ),
      );

      // A partial write is a failure, not an "import complete" alert.
      expect(find.text('Import failed'), findsOneWidget);
      expect(
        find.textContaining('Created 3 · updated 1 · skipped 2'),
        findsOneWidget,
      );
      expect(
        find.textContaining('2 row(s) failed during import'),
        findsOneWidget,
      );
    },
  );
}
