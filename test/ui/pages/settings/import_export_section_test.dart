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

  group('Web ICS Import Decoding (Production Path)', () {
    test(
      'decodeWebIcsBytes correctly decodes multi-byte UTF-8 containing Chinese and emoji',
      () {
        const unicodeIcsContent =
            'BEGIN:VCALENDAR\r\n'
            'VERSION:2.0\r\n'
            'PRODID:-//DaySpark//CN\r\n'
            'BEGIN:VEVENT\r\n'
            'UID:meeting-2026-utf8\r\n'
            'SUMMARY:灵光团队周会 📅✨\r\n'
            'DESCRIPTION:讨论产品架构优化与多语言支持 🚀🔥\r\n'
            'END:VEVENT\r\n'
            'BEGIN:VTODO\r\n'
            'UID:todo-2026-utf8\r\n'
            'SUMMARY:发布准备清单 📝🎉\r\n'
            'DESCRIPTION:验证 Web 端 ICS 导入中文字符与表情符号 ✨\r\n'
            'END:VTODO\r\n'
            'END:VCALENDAR\r\n';

        final rawBytes = utf8.encode(unicodeIcsContent);

        // Demonstrates that the prior buggy implementation (String.fromCharCodes) corrupted multi-byte characters
        final corruptedText = String.fromCharCodes(rawBytes);
        expect(
          corruptedText,
          isNot(equals(unicodeIcsContent)),
          reason:
              'String.fromCharCodes treats raw bytes as Unicode code units, corrupting UTF-8',
        );

        // Exercises production decoding path
        final decoded = decodeWebIcsBytes(rawBytes);
        expect(decoded, equals(unicodeIcsContent));
        expect(decoded, contains('灵光团队周会 📅✨'));
        expect(decoded, contains('讨论产品架构优化与多语言支持 🚀🔥'));
        expect(decoded, contains('发布准备清单 📝🎉'));
        expect(decoded, contains('验证 Web 端 ICS 导入中文字符与表情符号 ✨'));

        // decodeIcsBytes alias must match production behavior
        expect(decodeIcsBytes(rawBytes), equals(unicodeIcsContent));
      },
    );

    test('decodeWebIcsBytes throws FormatException on malformed UTF-8 bytes', () {
      final malformedBytes = <int>[0xFF, 0xFE, 0xFD];
      expect(
        () => decodeWebIcsBytes(malformedBytes),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => decodeIcsBytes(malformedBytes),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'production decoding path preserves non-ASCII calendar data through IcsService import',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(() async => db.close());

        final cals = await db.select(db.calendars).get();
        final calId = cals.first.id;

        const unicodeIcs =
            'BEGIN:VCALENDAR\r\n'
            'VERSION:2.0\r\n'
            'PRODID:-//DaySpark//CN\r\n'
            'BEGIN:VEVENT\r\n'
            'UID:event-chinese-emoji\r\n'
            'DTSTAMP:20261005T000000Z\r\n'
            'SUMMARY:年度战略总结会 🎯🎉\r\n'
            'DESCRIPTION:评估多语言与多平台稳定性 🚀\r\n'
            'DTSTART:20261102T090000Z\r\n'
            'DTEND:20261102T100000Z\r\n'
            'END:VEVENT\r\n'
            'BEGIN:VTODO\r\n'
            'UID:todo-chinese-emoji\r\n'
            'DTSTAMP:20261005T000000Z\r\n'
            'SUMMARY:完成 ICS 导入验证 📋\r\n'
            'DESCRIPTION:确保非 ASCII 字符无损持久化 🌟\r\n'
            'END:VTODO\r\n'
            'END:VCALENDAR\r\n';

        final rawBytes = utf8.encode(unicodeIcs);
        final decodedIcs = decodeWebIcsBytes(rawBytes);

        final service = IcsService(db);
        final imported = await service.importIcs(decodedIcs, calId);

        expect(imported.events, 1);
        expect(imported.todos, 1);

        final eventList = await db.select(db.events).get();
        expect(eventList.length, 1);
        expect(eventList.first.summary, '年度战略总结会 🎯🎉');
        expect(eventList.first.description, '评估多语言与多平台稳定性 🚀');

        final todoList = await db.select(db.todos).get();
        expect(todoList.length, 1);
        expect(todoList.first.summary, '完成 ICS 导入验证 📋');
        expect(todoList.first.description, '确保非 ASCII 字符无损持久化 🌟');
      },
    );
  });
}

