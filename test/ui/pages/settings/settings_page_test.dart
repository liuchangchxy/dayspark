import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/settings/settings_page.dart';
import 'package:dayspark/ui/pages/settings/settings_sections/about_section.dart';
import 'package:dayspark/ui/pages/settings/settings_sections/account_section.dart';
import 'package:dayspark/ui/pages/settings/settings_sections/appearance_section.dart';
import 'package:dayspark/ui/pages/settings/settings_sections/calendar_settings_section.dart';
import 'package:dayspark/ui/pages/settings/settings_sections/data_section.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/pages/settings/settings_ui.dart';
import 'package:dayspark/ui/pages/settings/settings_sections/sync_section.dart';
import 'package:dayspark/ui/pages/tags/tags_page.dart';
import 'package:dayspark/ui/pages/trash/trash_page.dart';

Future<void> _pumpSettings(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
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

double _y(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

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

  testWidgets(
    'mobile index shows the spec home rows including account and AI',
    (tester) async {
      await _pumpSettings(tester);

      // SPEC 2447: eight rows, Account first and AI between Data and Notify.
      expect(find.widgetWithText(SettingsRow, 'Account'), findsOneWidget);
      expect(find.widgetWithText(SettingsRow, 'General'), findsOneWidget);
      expect(
        find.widgetWithText(SettingsRow, 'Manage Calendars'),
        findsOneWidget,
      );
      expect(find.widgetWithText(SettingsRow, 'Data'), findsOneWidget);
      expect(find.widgetWithText(SettingsRow, 'AI Assistant'), findsOneWidget);
      expect(find.widgetWithText(SettingsRow, 'Notifications'), findsOneWidget);
      expect(find.widgetWithText(SettingsRow, 'Sync'), findsOneWidget);
      expect(find.widgetWithText(SettingsRow, 'About'), findsOneWidget);

      // Account opens its section and lands.
      await tester.tap(find.widgetWithText(SettingsRow, 'Account'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(AccountSection), findsOneWidget);
      await tester.tap(find.byType(DsIconButton));
      await tester.pump(const Duration(milliseconds: 350));

      // Tap General -> opens General subpage reusing AppearanceSection
      await tester.tap(find.widgetWithText(SettingsRow, 'General'));
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(AppearanceSection), findsOneWidget);
      expect(find.byType(DsTopBar), findsOneWidget);

      // Tap back -> returns to index
      await tester.tap(find.byType(DsIconButton));
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(AppearanceSection), findsNothing);
      expect(find.widgetWithText(SettingsRow, 'General'), findsOneWidget);
      expect(find.widgetWithText(SettingsRow, 'Data'), findsOneWidget);

      // Tap Data -> opens Data subpage
      await tester.tap(find.widgetWithText(SettingsRow, 'Data'));
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(DataSection), findsOneWidget);
      expect(find.widgetWithText(SettingsRow, 'Tags'), findsOneWidget);
      expect(find.widgetWithText(SettingsRow, 'Trash'), findsOneWidget);

      // Tap Tags -> opens inline TagsPage
      await tester.tap(find.widgetWithText(SettingsRow, 'Tags'));
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(TagsPage), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);

      // Tap back -> returns to Data
      await tester.tap(find.byType(DsIconButton));
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(DataSection), findsOneWidget);

      // Tap back again -> returns to mobile index
      await tester.tap(find.byType(DsIconButton));
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.widgetWithText(SettingsRow, 'General'), findsOneWidget);
      expect(find.widgetWithText(SettingsRow, 'About'), findsOneWidget);
    },
  );

  testWidgets('language and start tab live in general, not AI or calendar', (
    tester,
  ) async {
    await _pumpSettings(tester);

    // Open General subpage on mobile
    await tester.tap(find.widgetWithText(SettingsRow, 'General'));
    await tester.pump(const Duration(milliseconds: 350));

    expect(
      find.descendant(
        of: find.byType(AppearanceSection),
        matching: find.text('Language'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(AppearanceSection),
        matching: find.text('Startup view'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('data section contains tags, trash, import and backup rows', (
    tester,
  ) async {
    await _pumpSettings(tester);

    // Open Data subpage on mobile
    await tester.tap(find.widgetWithText(SettingsRow, 'Data'));
    await tester.pump(const Duration(milliseconds: 350));

    expect(
      find.descendant(
        of: find.byType(DataSection),
        matching: find.text('Tags'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(DataSection),
        matching: find.text('Trash'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(DataSection),
        matching: find.text('Import / Export'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(DataSection),
        matching: find.text('DaySpark backup'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'desktop shows left navigation with all 11 spec items and single section',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
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

      // SPEC 2407-2409: the nav owns both Account and AI, in this order.
      final navItemWidgets = tester.widgetList<SettingsNavItem>(
        find.byType(SettingsNavItem),
      );
      final labels = navItemWidgets.map((item) => item.label).toList();
      expect(labels, [
        'Account',
        'General',
        'Manage Calendars',
        'Data',
        'Tags',
        'Trash',
        'Import & Backup',
        'AI Assistant',
        'Notifications',
        'Sync',
        'About',
      ]);

      for (var i = 0; i < labels.length - 1; i++) {
        expect(
          _y(tester, find.widgetWithText(SettingsNavItem, labels[i])),
          lessThan(
            _y(tester, find.widgetWithText(SettingsNavItem, labels[i + 1])),
          ),
        );
      }

      // Default section is Home (Settings overview)
      expect(find.byType(AppearanceSection), findsNothing);

      // Clicking General nav item switches to General
      await tester.tap(
        find.widgetWithText(SettingsNavItem, 'General'),
      );
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(AppearanceSection), findsOneWidget);

      // Account has a real landing, not only a form behind the sync row.
      await tester.tap(find.widgetWithText(SettingsNavItem, 'Account'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(AccountSection), findsOneWidget);

      // AI is a first-class nav destination too.
      await tester.tap(find.widgetWithText(SettingsNavItem, 'AI Assistant'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Enable AI assistant'), findsOneWidget);

      // Clicking nav item switches section
      await tester.tap(
        find.widgetWithText(SettingsNavItem, 'Manage Calendars'),
      );
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(AppearanceSection), findsNothing);
      expect(find.byType(CalendarSettingsSection), findsOneWidget);
    },
  );

  testWidgets('general shows one read-only warm-gray accent value', (
    tester,
  ) async {
    await _pumpSettings(tester);

    await tester.tap(find.widgetWithText(SettingsRow, 'General'));
    await tester.pump(const Duration(milliseconds: 350));

    // SPEC 2475: accent is a single read-only value, not seven swatches.
    expect(find.text('Warm Gray'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppearanceSection),
        matching: find.byType(ChoiceChip),
      ),
      findsNothing,
    );
  });

  testWidgets('calendars section lists immediately without a duplicate row', (
    tester,
  ) async {
    await _pumpSettings(tester);

    await tester.tap(find.widgetWithText(SettingsRow, 'Manage Calendars'));
    await tester.pump(const Duration(milliseconds: 350));

    // SPEC 2477-2480: the heading is followed by the list, not by another
    // collapsed "Manage Calendars" row.
    expect(find.byType(CalendarSettingsSection), findsOneWidget);
    expect(find.text('New Calendar'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(CalendarSettingsSection),
        matching: find.widgetWithText(SettingsRow, 'Manage Calendars'),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'desktop geometry matches spec: nav 176, gap 46, content 700, and row >= 55 zero padding',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
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

      // Nav width 176
      final navSizedBox = tester.widget<SizedBox>(
        find
            .ancestor(
              of: find.byType(SettingsNavItem).first,
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(navSizedBox.width, 176.0);

      // Gap between nav and content is 46
      final navTopRight = tester.getTopRight(
        find
            .ancestor(
              of: find.byType(SettingsNavItem).first,
              matching: find.byType(SizedBox),
            )
            .first,
      );
      final homeContent = find.byKey(const ValueKey('home'));
      final contentTopLeft = tester.getTopLeft(homeContent);
      expect(contentTopLeft.dx - navTopRight.dx, 46.0);

      // Content max-width is 700
      final constrainedBox = tester.widget<ConstrainedBox>(
        find
            .ancestor(
              of: homeContent,
              matching: find.byType(ConstrainedBox),
            )
            .first,
      );
      expect(constrainedBox.constraints.maxWidth, 700.0);

      // .settings-body left padding is 30 (nav left is 30)
      expect(
        tester
            .getTopLeft(
              find
                  .ancestor(
                    of: find.byType(SettingsNavItem).first,
                    matching: find.byType(SizedBox),
                  )
                  .first,
            )
            .dx,
        30.0,
      );

      // .set-row: min-height 55 and zero horizontal padding
      final rowFinder = find.byType(SettingsRow).first;
      final rowRect = tester.getRect(rowFinder);
      expect(rowRect.height, greaterThanOrEqualTo(55.0));

      // Row width spans the full content width (zero horizontal padding)
      final homeRect = tester.getRect(homeContent);
      expect(rowRect.left, equals(homeRect.left));
      expect(rowRect.right, equals(homeRect.right));
    },
  );

  testWidgets(
    'desktop inline renders tags and trash with 1 scaffold, 0 DsMainBar, and 1 SettingsGroupBlock',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
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

      // Tap Tags nav item
      await tester.tap(find.widgetWithText(SettingsNavItem, 'Tags'));
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(TagsPage), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget); // exactly 1, not 2!
      expect(find.byType(DsMainBar), findsNothing); // 0!
      expect(find.byType(SettingsGroupBlock), findsOneWidget); // exactly 1!

      // Tap Trash nav item
      await tester.tap(find.widgetWithText(SettingsNavItem, 'Trash'));
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(TrashPage), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget); // exactly 1, not 2!
      expect(find.byType(DsMainBar), findsNothing); // 0!
      expect(find.byType(SettingsGroupBlock), findsOneWidget); // exactly 1!
    },
  );

  testWidgets('about section renders 3 rows: version, data, license', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
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

    await tester.tap(find.widgetWithText(SettingsNavItem, 'About'));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(AboutSection), findsOneWidget);
    expect(find.widgetWithText(SettingsRow, 'Version'), findsOneWidget);
    expect(find.widgetWithText(SettingsRow, 'Data'), findsOneWidget);
    expect(find.widgetWithText(SettingsRow, 'License'), findsOneWidget);
  });

  testWidgets('sync section does not contain unspecced sync now row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
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

    await tester.tap(find.widgetWithText(SettingsNavItem, 'Sync'));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(SyncSection), findsOneWidget);
    expect(find.text('Sync now'), findsNothing);
    expect(find.text('立即同步'), findsNothing);
  });

  testWidgets('desktop keyboard arrow keys switch nav selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
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

    // Default section is Home (-1), no section body yet
    expect(find.byType(AppearanceSection), findsNothing);

    // Down arrow moves from Home to Account (0)
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(AccountSection), findsOneWidget);

    // Down arrow moves from Account (0) to General (1)
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(AppearanceSection), findsOneWidget);

    // Down arrow moves from General (1) to Calendars (2)
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(AppearanceSection), findsNothing);
    expect(find.byType(CalendarSettingsSection), findsOneWidget);

    // Up arrow moves back to General (1)
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(AppearanceSection), findsOneWidget);
    expect(find.byType(CalendarSettingsSection), findsNothing);
  });

  testWidgets('mobile subpage shows its title and description only once', (
    tester,
  ) async {
    await _pumpSettings(tester);

    await tester.tap(find.widgetWithText(SettingsRow, 'General'));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('General'), findsOneWidget);
    expect(
      find.text('Decide where new tasks land and what to see on startup.'),
      findsOneWidget,
    );
  });

  testWidgets('mobile system back unwinds section -> data -> index', (
    tester,
  ) async {
    await _pumpSettings(tester);

    await tester.tap(find.widgetWithText(SettingsRow, 'Data'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.widgetWithText(SettingsRow, 'Tags'));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(TagsPage), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(DataSection), findsOneWidget);
    expect(find.byType(TagsPage), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.widgetWithText(SettingsRow, 'General'), findsOneWidget);
    expect(find.byType(DataSection), findsNothing);
  });
}
