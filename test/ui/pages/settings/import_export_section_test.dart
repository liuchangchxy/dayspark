import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/data/file_downloader.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/services/ics_service.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/settings/settings_sections/import_export_section.dart';

void main() {
  group('ImportExportSection Web Export', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('triggers real web download with standard filename and exact ICS content',
        (tester) async {
      final existingCals = await db.select(db.calendars).get();
      final calId = existingCals.first.id;

      await db.into(db.events).insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'Web Export Meeting',
              startDt: DateTime(2026, 10, 10, 14, 0),
              endDt: DateTime(2026, 10, 10, 15, 0),
            ),
          );
      await db.into(db.todos).insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Web Export Todo Task',
            ),
          );

      final expectedIcs = await IcsService(db).exportCalendar(calId);

      final recordedDownloads = <({String content, String filename})>[];
      void testDownloader({required String content, required String filename}) {
        recordedDownloads.add((content: content, filename: filename));
      }

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            isWebProvider.overrideWithValue(true),
            webFileDownloaderProvider.overrideWithValue(testDownloader),
          ],
          child: const MaterialApp(
            locale: Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ImportExportSection(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open the Import/Export dialog
      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();

      // Tap the Export button
      expect(find.text('Export'), findsOneWidget);
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();

      // Verify that the web downloader seam was invoked exactly once
      expect(recordedDownloads.length, 1);
      final download = recordedDownloads.first;

      // Verify filename pattern: calendar_export_<timestamp>.ics
      final filenamePattern = RegExp(r'^calendar_export_\d+\.ics$');
      expect(
        filenamePattern.hasMatch(download.filename),
        isTrue,
        reason: 'Filename must follow calendar_export_<timestamp>.ics pattern: ${download.filename}',
      );

      // Verify content fidelity: must match exact string from IcsService.exportCalendar
      expect(download.content, expectedIcs);

      // Verify content is valid UTF-8 iCalendar data containing exported items
      expect(download.content, contains('BEGIN:VCALENDAR'));
      expect(download.content, contains('SUMMARY:Web Export Meeting'));
      expect(download.content, contains('SUMMARY:Web Export Todo Task'));
      expect(download.content, contains('END:VCALENDAR'));

      final encoded = utf8.encode(download.content);
      expect(utf8.decode(encoded), download.content);
    });

    testWidgets('export does nothing when no calendars exist on web', (tester) async {
      await db.delete(db.calendars).go();
      final recordedDownloads = <({String content, String filename})>[];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            isWebProvider.overrideWithValue(true),
            webFileDownloaderProvider.overrideWithValue(
              ({required content, required filename}) {
                recordedDownloads.add((content: content, filename: filename));
              },
            ),
          ],
          child: const MaterialApp(
            locale: Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ImportExportSection(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open dialog and tap Export
      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();

      expect(recordedDownloads, isEmpty);
    });

    test('downloadFileWeb native stub throws UnsupportedError', () {
      expect(
        () => downloadFileWeb(
          content: 'test',
          filename: 'test.ics',
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
