import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/settings/settings_sections/about_section.dart';

void main() {
  testWidgets('AboutSection renders version, data, license and shows license page on tap', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('en'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AboutSection(version: '0.35.0'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Version'), findsOneWidget);
    expect(find.text('0.35.0'), findsOneWidget);
    expect(find.text('License'), findsOneWidget);

    await tester.tap(find.text('License'));
    await tester.pumpAndSettle();

    // showLicensePage opens a LicensePage dialog/route
    expect(find.byType(LicensePage), findsOneWidget);
  });
}
