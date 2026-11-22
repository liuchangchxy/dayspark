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
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/ui/design/ds.dart';

import '../settings_ui.dart';

class ImportExportSection extends ConsumerStatefulWidget {
  const ImportExportSection({super.key, this.showHeader = false});

  /// True when the section is rendered on its own rather than inside a
  /// labelled group card.
  final bool showHeader;

  @override
  ConsumerState<ImportExportSection> createState() =>
      _ImportExportSectionState();
}

class _ImportExportSectionState extends ConsumerState<ImportExportSection> {
  bool _backupBusy = false;
  bool _importBusy = false;
  bool _backupFailed = false;
  String? _backupResult;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeader)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: Text(l.data, style: AppTypography.title),
          ),
        SettingsRows(
          children: [
            SettingsRow(
              label: l.importIcs,
              subtitle: l.calendarData,
              chevron: SettingsChevron.right,
              trailing: _importBusy ? const _RowSpinner() : null,
              onTap: _importBusy ? null : _importIcs,
            ),
            SettingsRow(
              label: l.exportIcs,
              value: l.exportAllCalendars,
              chevron: SettingsChevron.right,
              onTap: () => _exportIcs(context, ref),
            ),
            SettingsRow(
              label: l.fullBackup,
              subtitle: l.fullBackupDesc,
              chevron: SettingsChevron.right,
              trailing: _backupBusy ? const _RowSpinner() : null,
              onTap: _backupBusy ? null : _exportBackup,
            ),
            SettingsRow(
              label: l.mergeBackup,
              subtitle: l.mergeBackupDesc,
              chevron: SettingsChevron.right,
              onTap: _backupBusy ? null : _mergeBackup,
            ),
          ],
        ),
        if (_backupBusy || _backupResult != null)
          InlineAlert(
            message: _backupBusy ? l.backupInProgress : _backupResult!,
            isRed: !_backupBusy && _backupFailed,
            action: _backupBusy
                ? const LinearProgressIndicator(minHeight: 3)
                : null,
          ),
        if (_importBusy) InlineAlert(message: l.importInProgress),
      ],
    );
  }

  Future<void> _exportBackup() async {
    if (_backupBusy) return;
    final l = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _backupBusy = true;
      _backupFailed = false;
      _backupResult = null;
    });
    var filename = '';
    try {
      final bytes = await BackupService(ref.read(databaseProvider)).exportZip();
      filename = 'dayspark-backup-${DateTime.now().millisecondsSinceEpoch}.zip';
      if (ref.read(isWebProvider)) {
        ref.read(webBytesDownloaderProvider)(
          bytes: bytes,
          filename: filename,
          mimeType: 'application/zip',
        );
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/$filename';
        await File(path).writeAsBytes(bytes, flush: true);
        try {
          await Share.shareXFiles([XFile(path)], subject: 'DaySpark Backup');
        } on UnimplementedError {
          messenger.showSnackBar(SnackBar(content: Text(l.exportedTo(path))));
        }
      }
      if (!mounted) return;
      setState(() => _backupResult = l.backupComplete(filename));
    } catch (e) {
      debugPrint('backup: export failed: $e');
      messenger.showSnackBar(SnackBar(content: Text(l.exportFailed)));
      if (!mounted) return;
      setState(() {
        _backupFailed = true;
        _backupResult = l.exportFailed;
      });
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  /// Restoring is an upsert, so it is offered as a merge and says so: nothing
  /// on this device is removed by it.
  Future<void> _mergeBackup() async {
    if (_backupBusy) return;
    final l = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _backupBusy = true;
      _backupFailed = false;
      _backupResult = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.first;
      final bytes =
          picked.bytes ??
          (picked.path == null ? null : await File(picked.path!).readAsBytes());
      if (bytes == null) throw StateError('backup file has no content');
      await BackupService(ref.read(databaseProvider)).restoreZip(bytes);
      if (!mounted) return;
      setState(() => _backupResult = l.backupRestored);
    } catch (e) {
      debugPrint('backup: merge failed: $e');
      messenger.showSnackBar(SnackBar(content: Text(l.restoreFailed)));
      if (!mounted) return;
      setState(() {
        _backupFailed = true;
        _backupResult = l.restoreFailed;
      });
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  /// Import asks one question the old combined dialog never made clear: which
  /// calendar the file's events land in. The picker comes after the file, so
  /// cancelling a file pick never leaves an unanswered dialog behind.
  Future<void> _importIcs() async {
    if (_importBusy) return;
    final l = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final db = ref.read(databaseProvider);

    final calendars = await (db.select(db.calendars)).get();
    if (!mounted) return;
    if (calendars.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l.noCalendarToImport)));
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ics'],
      withData: true,
    );
    if (!mounted) return;
    if (result == null || result.files.isEmpty) return;

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
    if (targetId == null || !mounted) return;

    final file = result.files.first;
    final calendarName = calendars
        .where((calendar) => calendar.id == targetId)
        .map((calendar) => calendar.name)
        .firstOrNull;
    final String content;
    try {
      if (kIsWeb) {
        content = decodeWebIcsBytes(file.bytes!);
      } else {
        content = await readFileNative(file.path!);
      }
    } catch (error) {
      debugPrint('ics: read failed: $error');
      messenger.showSnackBar(SnackBar(content: Text(l.importFailed)));
      return;
    }
    if (!mounted) return;

    setState(() => _importBusy = true);
    final IcsImportPreview preview;
    try {
      preview = await IcsService(db).previewIcs(content, targetId);
    } catch (error) {
      debugPrint('ics: preview failed: $error');
      if (!mounted) return;
      setState(() => _importBusy = false);
      await _showImportFailure(file.name);
      return;
    }
    if (!mounted) return;
    setState(() => _importBusy = false);

    final confirmed = await _showPreview(
      preview: preview,
      fileName: file.name,
      calendarName: calendarName ?? '',
    );
    if (confirmed != true || !mounted) return;

    setState(() => _importBusy = true);
    try {
      final imported = await IcsService(
        db,
      ).importIcsDetailed(content, targetId);
      if (!mounted) return;
      setState(() => _importBusy = false);
      await _showImportResult(preview: preview, imported: imported);
    } catch (error) {
      debugPrint('ics: import failed: $error');
      if (!mounted) return;
      setState(() => _importBusy = false);
      await _showImportFailure(file.name);
    }
  }

  Future<bool> _showPreview({
    required IcsImportPreview preview,
    required String fileName,
    required String calendarName,
  }) async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDsSheet<bool>(
      context: context,
      title: l.importPreviewTitle,
      body: _ImportPreviewBody(
        preview: preview,
        fileName: fileName,
        calendarName: calendarName,
      ),
      actions: [
        DsButton(
          label: l.cancel,
          tone: DsButtonTone.ghost,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        DsButton(
          label: l.startImport,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
    return confirmed ?? false;
  }

  Future<void> _showImportResult({
    required IcsImportPreview preview,
    required ({int events, int todos, int failed, int updated}) imported,
  }) async {
    final l = AppLocalizations.of(context)!;
    final created = imported.events + imported.todos - imported.updated;
    final skipped = <IcsPreviewItem>[
      ...preview.skipped,
      if (imported.failed > preview.skippedCount)
        IcsPreviewItem(
          kind: IcsPreviewKind.event,
          status: IcsPreviewStatus.skipped,
          summary: l.importFailedRows(imported.failed - preview.skippedCount),
        ),
    ];
    final skippedLines = skipped
        .map((item) => item.summary)
        .where((summary) => summary.isNotEmpty)
        .toList(growable: false);
    await showDsSheet<void>(
      context: context,
      title: l.importResultTitle,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            imported.events + imported.todos == 0 && imported.failed == 0
                ? l.importNothing
                : l.importResultSummary(
                    created,
                    imported.updated,
                    imported.failed,
                  ),
          ),
          if (skippedLines.isNotEmpty)
            InlineAlert(message: skippedLines.join('\n'), isRed: true),
        ],
      ),
      actions: [
        DsButton(label: l.close, onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }

  Future<void> _showImportFailure(String fileName) async {
    final l = AppLocalizations.of(context)!;
    await showDsSheet<void>(
      context: context,
      title: l.importResultTitle,
      body: InlineAlert(
        title: l.importFailed,
        message: l.importFailureDetail(fileName),
        isRed: true,
      ),
      actions: [
        DsButton(label: l.close, onPressed: () => Navigator.of(context).pop()),
      ],
    );
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

class _RowSpinner extends StatelessWidget {
  const _RowSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 14,
      height: 14,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

class _ImportPreviewBody extends StatelessWidget {
  const _ImportPreviewBody({
    required this.preview,
    required this.fileName,
    required this.calendarName,
  });

  final IcsImportPreview preview;
  final String fileName;
  final String calendarName;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final shown = preview.items.take(8).toList(growable: false);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.importPreviewSummary(
            preview.eventCount,
            preview.todoCount,
            fileName,
          ),
          style: AppTypography.body.copyWith(color: context.ds.ink2),
        ),
        const SizedBox(height: AppSpacing.s2),
        Text(
          l.importPreviewCounts(
            preview.createCount,
            preview.duplicateCount,
            preview.skippedCount,
          ),
          style: AppTypography.small.copyWith(color: context.ds.ink3),
        ),
        if (calendarName.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s2),
          Text(
            '${l.importTo}: $calendarName',
            style: AppTypography.small.copyWith(color: context.ds.ink3),
          ),
        ],
        const SizedBox(height: AppSpacing.s3),
        for (final item in shown) _previewRow(context, l, item),
        if (preview.items.length > shown.length)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s2),
            child: Text(
              l.importPreviewMore(preview.items.length - shown.length),
              style: AppTypography.small.copyWith(color: context.ds.ink3),
            ),
          ),
      ],
    );
  }

  Widget _previewRow(
    BuildContext context,
    AppLocalizations l,
    IcsPreviewItem item,
  ) {
    final ds = context.ds;
    final status = switch (item.status) {
      IcsPreviewStatus.create => l.importPreviewNew,
      IcsPreviewStatus.duplicate => l.importPreviewDuplicate,
      IcsPreviewStatus.skipped => l.importPreviewSkipped,
    };
    final label = item.summary.isNotEmpty
        ? item.summary
        : item.kind == IcsPreviewKind.event
        ? l.events
        : l.todos;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: ds.lineSoft)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body,
                ),
                if (item.at != null)
                  Text(
                    DateFormatters.formatDateTime(item.at!),
                    style: AppTypography.small.copyWith(color: ds.ink3),
                  ),
              ],
            ),
          ),
          Text(
            status,
            style: AppTypography.small.copyWith(
              color: item.status == IcsPreviewStatus.skipped
                  ? ds.danger
                  : ds.ink3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Decodes raw bytes from a Web-uploaded ICS file as strict UTF-8.
String decodeWebIcsBytes(List<int> bytes) => utf8.decode(bytes);

/// Decodes raw bytes from an uploaded ICS file as strict UTF-8.
String decodeIcsBytes(List<int> bytes) => decodeWebIcsBytes(bytes);
