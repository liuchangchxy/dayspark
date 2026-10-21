import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter/cupertino.dart';
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeader)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: Text(
              l.data,
              style: AppTypography.title,
            ),
          ),
        ListTile(
          leading: const Icon(CupertinoIcons.arrow_down_doc),
          title: Text(l.importExport),
          subtitle: Text(l.calendarData),
          onTap: () => _showIcsDialog(context, ref),
        ),
        ListTile(
          leading: const Icon(CupertinoIcons.archivebox),
          title: Text(l.fullBackup),
          subtitle: Text(l.fullBackupDesc),
          onTap: () => _showBackupDialog(context, ref),
        ),
      ],
    );
  }

  void _showBackupDialog(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.fullBackup),
        content: Text(l.fullBackupDesc),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _restoreBackup(context, ref);
            },
            child: Text(l.restore),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _exportBackup(context, ref);
            },
            child: Text(l.export),
          ),
        ],
      ),
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
      messenger.showSnackBar(
        SnackBar(content: Text(l.exportFailed('$e'))),
      );
    }
  }

  Future<void> _restoreBackup(BuildContext context, WidgetRef ref) async {
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
      final bytes = picked.bytes ??
          (picked.path == null ? null : await File(picked.path!).readAsBytes());
      if (bytes == null) throw StateError('backup file has no content');
      await BackupService(ref.read(databaseProvider)).restoreZip(bytes);
      messenger.showSnackBar(SnackBar(content: Text(l.backupRestored)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.restoreFailed('$e'))));
    }
  }

  void _showIcsDialog(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context)!;
    final db = ref.read(databaseProvider);
    final cals = await (db.select(db.calendars)).get();

    if (!context.mounted) return;

    int? exportCalendarId; // null = all
    var importCalendarId = cals.isNotEmpty ? cals.first.id : null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l.importExport),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.importExportDesc),
              if (cals.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(l.targetCalendar, style: AppTypography.caption),
                const SizedBox(height: AppSpacing.xs),
                DropdownButton<int?>(
                  isExpanded: true,
                  value: importCalendarId,
                  items: cals.map((c) {
                    return DropdownMenuItem<int?>(
                      value: c.id,
                      child: Text(c.name),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => importCalendarId = val);
                    }
                  },
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                try {
                  if (cals.isEmpty) return;
                  final service = IcsService(db);
                  final content = await service.exportCalendar(exportCalendarId);
                  final filename =
                      'calendar_export_${DateTime.now().millisecondsSinceEpoch}.ics';
                  final isWeb = ref.read(isWebProvider);
                  if (isWeb) {
                    ref.read(webFileDownloaderProvider)(
                      content: content,
                      filename: filename,
                    );
                  } else {
                    final path = await service.saveIcsToFile(
                      content,
                      filename,
                    );
                    if (context.mounted) {
                      try {
                        await Share.shareXFiles([
                          XFile(path),
                        ], subject: 'DaySpark Calendar Export');
                      } on UnimplementedError {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l.exportedTo(path))),
                          );
                        }
                      }
                    }
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(l.exportFailed('$e'))));
                  }
                }
              },
              child: Text(l.export),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                try {
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['ics'],
                  );
                  if (result == null || result.files.isEmpty) return;

                  String icsContent;
                  final file = result.files.first;
                  if (kIsWeb) {
                    icsContent = decodeWebIcsBytes(file.bytes!);
                  } else {
                    icsContent = await readFileNative(file.path!);
                  }

                  if (cals.isEmpty || importCalendarId == null) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l.noCalendarToImport)),
                      );
                    }
                    return;
                  }

                  final service = IcsService(db);
                  final imported = await service.importIcsDetailed(
                    icsContent,
                    importCalendarId!,
                  );
                  if (context.mounted) {
                    final message = imported.failed > 0
                        ? l.importedResultWithFailed(
                            imported.events,
                            imported.todos,
                            imported.failed,
                          )
                        : l.importedResult(imported.events, imported.todos);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(message)),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(l.importFailed('$e'))));
                  }
                }
              },
              child: Text(l.import),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l.cancel),
            ),
          ],
        ),
      ),
    );
  }
}

/// Decodes raw bytes from a Web-uploaded ICS file as strict UTF-8.
String decodeWebIcsBytes(List<int> bytes) => utf8.decode(bytes);

/// Decodes raw bytes from an uploaded ICS file as strict UTF-8.
String decodeIcsBytes(List<int> bytes) => decodeWebIcsBytes(bytes);
