import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/domain/services/chinese_calendar_service.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_section.dart';
import 'package:dayspark/ui/widgets/calendar/marked_month_day_header.dart';

Widget _wrap(Widget child, Locale locale) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    home: Scaffold(body: child),
  ),
);

void main() {
  group('MarkedMonthDayHeader', () {
    testWidgets('renders solar term label in zh', (tester) async {
      await tester.pumpWidget(
        _wrap(
          MarkedMonthDayHeader(date: DateTime(2026, 2, 4)),
          const Locale('zh'),
        ),
      );
      expect(find.text('立春'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('renders English solar term name in en', (tester) async {
      await tester.pumpWidget(
        _wrap(
          MarkedMonthDayHeader(date: DateTime(2026, 2, 4)),
          const Locale('en'),
        ),
      );
      expect(find.text('Spring Begins'), findsOneWidget);
    });

    testWidgets('renders makeup-workday badge for 2026-09-20', (tester) async {
      await tester.pumpWidget(
        _wrap(
          MarkedMonthDayHeader(date: DateTime(2026, 9, 20)),
          const Locale('zh'),
        ),
      );
      expect(find.text('班'), findsOneWidget);
      expect(find.text('20'), findsOneWidget);
    });

    testWidgets('renders rest-day badge for 2026-10-01', (tester) async {
      await tester.pumpWidget(
        _wrap(
          MarkedMonthDayHeader(date: DateTime(2026, 10, 1)),
          const Locale('zh'),
        ),
      );
      expect(find.text('休'), findsOneWidget);
    });

    testWidgets('ordinary day has no badges or term label', (tester) async {
      await tester.pumpWidget(
        _wrap(
          MarkedMonthDayHeader(date: DateTime(2026, 3, 10)),
          const Locale('zh'),
        ),
      );
      expect(find.text('10'), findsOneWidget);
      expect(find.text('班'), findsNothing);
      expect(find.text('休'), findsNothing);
    });
  });

  testWidgets('month view grid shows current-month solar terms', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(760, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(body: CalendarSection(events: [])),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));

    await tester.tap(find.text('月'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));

    final now = DateTime.now();
    final lastDay = DateTime(now.year, now.month + 1, 0);
    final terms = <String>{};
    for (var day = 1; day <= lastDay.day; day++) {
      final term = ChineseCalendarService.solarTerm(
        DateTime(now.year, now.month, day),
      );
      if (term != null) terms.add(term);
    }
    // Every month contains exactly two solar terms; both must render.
    expect(terms.length, 2);
    for (final term in terms) {
      expect(find.text(term), findsWidgets, reason: 'missing term $term');
    }
  });
}
