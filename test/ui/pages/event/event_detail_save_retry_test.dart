import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/event/event_detail_page.dart';

/// Bounded pumping: the live event stream and the text cursor keep scheduling
/// frames, so an unbounded pumpAndSettle never returns.
Future<void> pumpFrames(
  WidgetTester tester, {
  int frames = 8,
  Duration step = const Duration(milliseconds: 200),
}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(step);
  }
}

void main() {
  testWidgets(
    'failed detail text save keeps input and retries unchanged text',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final calendar = (await db.select(db.calendars).get()).single;
      final id = await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calendar.id,
              summary: 'Original',
              startDt: DateTime(2026, 11, 15, 9),
              endDt: DateTime(2026, 11, 15, 10),
            ),
          );
      final event = await (db.select(
        db.events,
      )..where((t) => t.id.equals(id))).getSingle();
      var attempts = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            updateEventProvider.overrideWithValue((id, data) async {
              attempts++;
              if (attempts == 1) throw StateError('write failed');
              await (db.update(
                db.events,
              )..where((t) => t.id.equals(id))).write(data);
            }),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: EventDetailPage(event: CalendaEventAdapter.fromDrift(event)),
          ),
        ),
      );
      await pumpFrames(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final title = find.byKey(const ValueKey('event-detail-title'));
      expect(title, findsOneWidget);
      await tester.enterText(title, 'Changed');
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      expect(attempts, 1);
      expect(tester.widget<TextField>(title).controller!.text, 'Changed');
      expect(find.text('That didn\'t work. Please try again.'), findsOneWidget);
      expect(
        (await (db.select(
          db.events,
        )..where((t) => t.id.equals(id))).getSingle()).summary,
        'Original',
      );

      tester.widget<TextField>(title).focusNode!.unfocus();
      await pumpFrames(tester);
      expect(attempts, 2);
      expect(
        (await (db.select(
          db.events,
        )..where((t) => t.id.equals(id))).getSingle()).summary,
        'Changed',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      // Disposing the ProviderScope cancels the drift query streams, which
      // schedule zero-duration timers; a pump with a duration is required to
      // run them, or the test ends with "A Timer is still pending" and the
      // runner never exits.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    },
  );
}
