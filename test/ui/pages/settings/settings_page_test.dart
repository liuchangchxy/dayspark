import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/settings/settings_page.dart';
import 'package:dayspark/ui/pages/settings/settings_sections/about_section.dart';
import 'package:dayspark/ui/pages/settings/settings_sections/account_section.dart';
import 'package:dayspark/ui/pages/settings/settings_sections/ai_section.dart';
import 'package:dayspark/ui/pages/settings/settings_sections/appearance_section.dart';
import 'package:dayspark/ui/pages/settings/settings_sections/import_export_section.dart';
import 'package:dayspark/ui/pages/settings/settings_sections/todos_section.dart';

Future<void> _pumpSettings(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SettingsPage(),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 350));
}

double _y(WidgetTester tester, Finder finder) =>
    tester.getTopLeft(finder).dy;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'DaySpark',
      packageName: 'com.dayspark.app',
      version: '0.24.0',
      buildNumber: '24',
      buildSignature: '',
    );
  });

  testWidgets('orders sections appearance → todos → data → account → ai, '
      'advanced group collapsed at the end', (tester) async {
    await _pumpSettings(tester);

    expect(_y(tester, find.byType(AppearanceSection)),
        lessThan(_y(tester, find.byType(TodosSection))));
    expect(_y(tester, find.byType(TodosSection)),
        lessThan(_y(tester, find.byType(ImportExportSection))));
    expect(_y(tester, find.byType(ImportExportSection)),
        lessThan(_y(tester, find.byType(AccountSection))));
    expect(_y(tester, find.byType(AccountSection)),
        lessThan(_y(tester, find.byType(AiSection))));

    final advanced = tester.widget<ExpansionTile>(
      find.ancestor(
        of: find.text('Advanced'),
        matching: find.byType(ExpansionTile),
      ),
    );
    expect(advanced.initiallyExpanded, isFalse);
    expect(find.byType(AboutSection), findsNothing);
    expect(_y(tester, find.byType(AiSection)),
        lessThan(_y(tester, find.text('Advanced'))));
  });

  testWidgets('expanding advanced reveals about below the functional groups',
      (tester) async {
    await _pumpSettings(tester);

    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();

    expect(find.byType(AboutSection), findsOneWidget);
    expect(_y(tester, find.byType(AiSection)),
        lessThan(_y(tester, find.byType(AboutSection))));
  });

  testWidgets('list-behavior toggles render inside the todos section',
      (tester) async {
    await _pumpSettings(tester);

    expect(find.byType(TodosSection), findsOneWidget);
    expect(find.text('Six Things'), findsOneWidget);
    expect(find.text('Hide completed'), findsOneWidget);
  });
}
