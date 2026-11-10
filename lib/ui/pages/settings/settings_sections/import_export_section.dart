import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import 'package:dayspark/data/file_downloader.dart';
import 'package:dayspark/data/file_reader.dart';
import 'package:path_provider/path_provider.dart';

import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/services/backup_service.dart';
import 'package:dayspark/domain/services/ics_service.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/ui/design/ds.dart';

class ImportExportSection extends ConsumerWidget {
  const ImportExportSection({super.key, this.showHeader = false});

  /// True when the section is rendered on its own rather than inside a
  /// labelled group card.
  final bool showHeader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: Text(l.data, style: AppTypography.title),
          ),
        DsSectionLabel(l.dataExchange),
        DsSettingRow(
          label: l.importIcs,
          value: l.calendarData,
          onTap: () => _importIcs(context, ref),
        ),
        DsSettingRow(
          label: l.exportIcs,
          value: l.exportAllCalendars,
          onTap: () => _exportIcs(context, ref),
        ),
        const DsHairline(),
        DsSectionLabel(l.daysparkBackup),
        DsSettingRow(
          label: l.fullBackup,
          value: l.fullBackupDesc,
          onTap: () => _exportBackup(context, ref),
        ),
        DsSettingRow(
          label: l.mergeBackup,
          value: l.mergeBackupDesc,
          onTap: () => _mergeBackup(context, ref),
        ),
      ],
    );
  }

  Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await BackupService(ref.read(databaseProvider)).exportZip();
      final filename =
          'dayspark-backup-${DateTime.now().millisecondsSinceEpoch}.zip';
      if (ref.read(isWebProvider)) {
        ref.read(webBytesDownloaderProvider)(
          bytes: bytes,
          filename: filename,
          mimeType: 'application/zip',
        );
        return;
      }
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/$filename';
      await File(path).writeAsBytes(bytes, flush: true);
      try {
        await Share.shareXFiles([XFile(path)], subject: 'DaySpark Backup');
      } on UnimplementedError {
        messenger.showSnackBar(SnackBar(content: Text(l.exportedTo(path))));
      }
    } catch (e) {
      debugPrint('backup: export failed: $e');
      messenger.showSnackBar(SnackBar(content: Text(l.exportFailed)));
    }
  }

  /// Restoring is an upsert, so it is offered as a merge and says so: nothing
  /// on this device is removed by it.
  Future<void> _mergeBackup(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    try {
      final bytes =
          picked.bytes ??
          (picked.path == null ? null : await File(picked.path!).readAsBytes());
      if (bytes == null) throw StateError('backup file has no content');
      await BackupService(ref.read(databaseProvider)).restoreZip(bytes);
      messenger.showSnackBar(SnackBar(content: Text(l.backupRestored)));
    } catch (e) {
      debugPrint('backup: merge failed: $e');
      messenger.showSnackBar(SnackBar(content: Text(l.restoreFailed)));
    }
  }

  /// Import asks one question the old combined dialog never made clear: which
  /// calendar the file's events land in. The picker comes after the file, so
  /// cancelling a file pick never leaves an unanswered dialog behind.
  Future<void> _importIcs(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final db = ref.read(databaseProvider);

    final calendars = await (db.select(db.calendars)).get();
    if (calendars.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l.noCalendarToImport)));
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ics'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    if (!context.mounted) return;

    final targetId = await showDsSheet<int>(
      context: context,
      title: l.importTo,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final calendar in calendars)
            DsSettingRow(
              label: calendar.name,
              onTap: () => Navigator.of(context).pop(calendar.id),
            ),
        ],
      ),
    );
    if (targetId == null) return;

    try {
      final file = result.files.first;
      final String content;
      if (kIsWeb) {
        content = decodeWebIcsBytes(file.bytes!);
      } else {
        content = await readFileNative(file.path!);
      }
      final imported = await IcsService(
        db,
      ).importIcsDetailed(content, targetId);
      final message = imported.failed > 0
          ? l.importedResultWithFailed(
              imported.events,
              imported.todos,
              imported.failed,
            )
          : l.importedResult(imported.events, imported.todos);
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      debugPrint('ics: import failed: $error');
      messenger.showSnackBar(SnackBar(content: Text(l.importFailed)));
    }
  }

  /// Export always writes every calendar: a partial export that silently
  /// skipped calendars would look complete and not be.
  Future<void> _exportIcs(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final db = ref.read(databaseProvider);
    try {
      if ((await (db.select(db.calendars)).get()).isEmpty) {
        messenger.showSnackBar(SnackBar(content: Text(l.nothingToExport)));
        return;
      }
      final service = IcsService(db);
      final content = await service.exportCalendar();
      final filename =
          'dayspark-calendars-${DateTime.now().millisecondsSinceEpoch}.ics';
      if (ref.read(isWebProvider)) {
        ref.read(webFileDownloaderProvider)(
          content: content,
          filename: filename,
        );
        return;
      }
      final path = await service.saveIcsToFile(content, filename);
      try {
        await Share.shareXFiles([XFile(path)], subject: 'DaySpark Calendars');
      } on UnimplementedError {
        messenger.showSnackBar(SnackBar(content: Text(l.exportedTo(path))));
      }
    } catch (error) {
      debugPrint('ics: export failed: $error');
      messenger.showSnackBar(SnackBar(content: Text(l.exportFailed)));
    }
  }
}

/// Decodes raw bytes from a Web-uploaded ICS file as strict UTF-8.
String decodeWebIcsBytes(List<int> bytes) => utf8.decode(bytes);

/// Decodes raw bytes from an uploaded ICS file as strict UTF-8.
String decodeIcsBytes(List<int> bytes) => decodeWebIcsBytes(bytes);
