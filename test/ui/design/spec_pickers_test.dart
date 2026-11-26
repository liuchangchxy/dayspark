import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/design/spec_pickers.dart';

Widget _host(void Function(BuildContext) onOpen) {
  return MaterialApp(
    localizationsDelegates: const [
      ...AppLocalizations.localizationsDelegates,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => onOpen(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('date picker returns the tapped day at midnight', (tester) async {
    DateTime? result;
    await tester.pumpWidget(
      _host(
        (context) async => result = await showSpecDatePicker(
          context,
          initialDate: DateTime(2026, 11, 15, 14, 30),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(SpecDatePickerDialog), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('spec-day-2026-11-03')));
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.byType(SpecDatePickerDialog), findsNothing);
    expect(result, DateTime(2026, 11, 3));
  });

  testWidgets('date picker pages by month and keeps the selection', (
    tester,
  ) async {
    DateTime? result;
    await tester.pumpWidget(
      _host(
        (context) async => result = await showSpecDatePicker(
          context,
          initialDate: DateTime(2026, 11, 15),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('2026 / 11'), findsOneWidget);
    await tester.tap(find.byIcon(CupertinoIcons.chevron_right));
    await tester.pumpAndSettle();
    expect(find.text('2026 / 12'), findsOneWidget);
    await tester.tap(find.byIcon(CupertinoIcons.chevron_left));
    await tester.pumpAndSettle();
    expect(find.text('2026 / 11'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('spec-day-2026-11-20')));
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(result, DateTime(2026, 11, 20));
  });

  testWidgets('date picker cancel returns null', (tester) async {
    DateTime? result;
    await tester.pumpWidget(
      _host(
        (context) async => result = await showSpecDatePicker(
          context,
          initialDate: DateTime(2026, 11, 15),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  testWidgets('date picker fits a phone width without overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        (context) async => showSpecDatePicker(
          context,
          initialDate: DateTime(2026, 11, 15),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SpecDatePickerDialog), findsOneWidget);
  });

  testWidgets('time picker returns the typed time', (tester) async {
    TimeOfDay? result;
    await tester.pumpWidget(
      _host(
        (context) async => result = await showSpecTimePicker(
          context,
          initialTime: const TimeOfDay(hour: 15, minute: 15),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '9');
    await tester.enterText(fields.at(1), '5');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(result, const TimeOfDay(hour: 9, minute: 5));
  });

  testWidgets('time picker refuses an impossible hour instead of guessing', (
    tester,
  ) async {
    TimeOfDay? result;
    var closed = false;
    await tester.pumpWidget(
      _host(
        (context) async {
          result = await showSpecTimePicker(
            context,
            initialTime: const TimeOfDay(hour: 15, minute: 15),
          );
          closed = true;
        },
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '25');
    await tester.pumpAndSettle();

    // The spec's invalid state: red boxes, an explanation, and 确定 disabled.
    expect(find.textContaining('00–23'), findsOneWidget);
    final ok = tester.widget<DsButton>(
      find.widgetWithText(DsButton, 'OK'),
    );
    expect(ok.onPressed, isNull, reason: 'an impossible hour cannot be saved');

    await tester.enterText(find.byType(TextField).at(0), '09');
    await tester.pumpAndSettle();
    expect(find.textContaining('00–23'), findsNothing);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(result, const TimeOfDay(hour: 9, minute: 15));
  });
}
