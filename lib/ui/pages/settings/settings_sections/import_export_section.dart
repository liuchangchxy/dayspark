import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import 'package:dayspark/data/file_downloader.dart';
import 'package:dayspark/data/file_reader.dart';
import 'package:dayspark/data/local/database/app_database.dart';
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

  bool _importMode = false;
  PlatformFile? _pickedFile;
  String? _fileContent;
  int? _targetCalendarId;
  String? _targetCalendarName;
  IcsImportPreview? _importPreview;
  String? _importResultSummary;
  List<Calendar> _availableCalendars = [];

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
        if (_importMode) ...[
          IoCard(
            title: l.importStepFile,
            description: _pickedFile == null
                ? l.importFileHelp
                : '${_pickedFile!.name} (${(_pickedFile!.size / 1024).toStringAsFixed(1)} KB)',
            actions: [
              DsButton(
                label: _pickedFile == null ? l.importIcs : l.importChangeFile,
                tone: DsButtonTone.primary,
                onPressed: _pickIcsFile,
              ),
            ],
          ),
          IoCard(
            title: l.importStepCalendar,
            description: _targetCalendarName != null
                ? '$_targetCalendarName · ${l.importTo}'
                : l.defaultCalendar,
            actions: [
              Wrap(
                spacing: 6,
                children: [
                  for (final cal in _availableCalendars)
                    ChoiceChip(
                      label: Text(cal.name),
                      selected: _targetCalendarId == cal.id,
                      onSelected: (val) {
                        if (val) {
                          setState(() {
                            _targetCalendarId = cal.id;
                            _targetCalendarName = cal.name;
                          });
                          _updatePreview();
                        }
                      },
                    ),
                ],
              ),
            ],
          ),
          IoCard(
            title: l.importStepPreview,
            description: _importPreview == null
                ? l.importPreviewHelp
                : l.importResultSummary(
                    _importPreview!.createCount,
                    _importPreview!.duplicateCount,
                    _importPreview!.skippedCount,
                  ),
            actions: [
              DsButton(
                label: l.startImport,
                tone: DsButtonTone.primary,
                loading: _importBusy,
                onPressed: (_fileContent != null && _targetCalendarId != null && !_importBusy)
                    ? _executeImport
                    : null,
              ),
            ],
            child: _importPreview == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _ImportPreviewBody(
                      preview: _importPreview!,
                      fileName: _pickedFile?.name ?? '',
                      calendarName: _targetCalendarName ?? '',
                    ),
                  ),
          ),
          if (_importResultSummary != null)
            InlineAlert(message: _importResultSummary!),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: DsButton(
              label: l.cancel,
              tone: DsButtonTone.ghost,
              onPressed: () => setState(() {
                _importMode = false;
                _pickedFile = null;
                _fileContent = null;
                _importPreview = null;
                _importResultSummary = null;
              }),
            ),
          ),
        ] else ...[
          IoCard(
            title: l.importIcs,
            description: l.ioCardImportDesc,
            actions: [
              DsButton(
                label: l.importIcs,
                tone: DsButtonTone.primary,
                loading: _importBusy,
                onPressed: _importBusy ? null : _startImportFlow,
              ),
            ],
          ),
          IoCard(
            title: l.exportIcs,
            description: l.ioCardExportDesc,
            actions: [
              DsButton(
                label: l.exportAllCalendars,
                tone: DsButtonTone.secondary,
                onPressed: () => _exportIcs(context, ref),
              ),
            ],
          ),
          IoCard(
            title: l.fullBackup,
            description: l.ioCardBackupDesc,
            actions: [
              DsButton(
                key: const ValueKey('full-backup-btn'),
                label: l.fullBackup,
                tone: DsButtonTone.primary,
                loading: _backupBusy,
                onPressed: _backupBusy ? null : _exportBackup,
              ),
              const SizedBox(width: 8),
              DsButton(
                label: l.mergeBackup,
                tone: DsButtonTone.secondary,
                onPressed: _backupBusy ? null : _mergeBackup,
              ),
            ],
          ),
        ],
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
      final backupService = BackupService(ref.read(databaseProvider));
      final decoded = BackupService.decodeZip(bytes);
      final conflicts = await backupService.inspectConflicts(decoded.data);
      Map<String, BackupConflictResolution>? resolutions;
      if (conflicts.isNotEmpty && mounted) {
        final res = await showDialog<Map<String, BackupConflictResolution>>(
          context: context,
          builder: (ctx) => _BackupConflictDialog(conflicts: conflicts),
        );
        if (res == null) return;
        resolutions = res;
      }
      await backupService.restoreZip(bytes, resolutions: resolutions);
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

  Future<void> _startImportFlow() async {
    final db = ref.read(databaseProvider);
    final calendars = await (db.select(db.calendars)).get();
    if (!mounted) return;
    if (calendars.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.noCalendarToImport)),
      );
      return;
    }
    setState(() {
      _importMode = true;
      _availableCalendars = calendars;
      _targetCalendarId ??= calendars.first.id;
      _targetCalendarName ??= calendars.first.name;
    });
    await _pickIcsFile();
  }

  Future<void> _pickIcsFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ics'],
      withData: true,
    );
    if (!mounted || result == null || result.files.isEmpty) return;

    final file = result.files.first;
    String content;
    try {
      if (kIsWeb) {
        content = decodeWebIcsBytes(file.bytes!);
      } else {
        content = await readFileNative(file.path!);
      }
    } catch (error) {
      debugPrint('ics: read failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.importFailed)),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _pickedFile = file;
      _fileContent = content;
    });
    await _updatePreview();
  }

  Future<void> _updatePreview() async {
    if (_fileContent == null || _targetCalendarId == null) return;
    final db = ref.read(databaseProvider);
    setState(() => _importBusy = true);
    try {
      final preview = await IcsService(db).previewIcs(_fileContent!, _targetCalendarId!);
      if (mounted) {
        setState(() {
          _importPreview = preview;
          _importBusy = false;
        });
      }
    } catch (e) {
      debugPrint('ics: preview failed: $e');
      if (mounted) {
        setState(() => _importBusy = false);
      }
    }
  }

  Future<void> _executeImport() async {
    if (_fileContent == null || _targetCalendarId == null || _importBusy) return;
    final l = AppLocalizations.of(context)!;
    final db = ref.read(databaseProvider);
    setState(() => _importBusy = true);
    try {
      final imported = await IcsService(db).importIcsDetailed(
        _fileContent!,
        _targetCalendarId!,
      );
      final created = imported.events + imported.todos - imported.updated;
      final summary = l.importResultSummary(created, imported.updated, imported.failed);
      if (!mounted) return;
      setState(() {
        _importBusy = false;
        _importResultSummary = summary;
      });
    } catch (error) {
      debugPrint('ics: import failed: $error');
      if (!mounted) return;
      setState(() {
        _importBusy = false;
        _importResultSummary = l.importFailed;
      });
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

class _BackupConflictDialog extends StatefulWidget {
  const _BackupConflictDialog({required this.conflicts});

  final List<BackupConflictItem> conflicts;

  @override
  State<_BackupConflictDialog> createState() => _BackupConflictDialogState();
}

class _BackupConflictDialogState extends State<_BackupConflictDialog> {
  late final Map<String, BackupConflictResolution> _choices;

  @override
  void initState() {
    super.initState();
    _choices = {
      for (final c in widget.conflicts)
        c.key: BackupConflictResolution.keepLocal,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;

    return AlertDialog(
      title: Text(l.backupConflictTitle(widget.conflicts.length)),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.backupConflictDesc),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final c in widget.conflicts) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: ds.lineSoft)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    c.title,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: ds.surface2,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    c.table,
                                    style: TextStyle(fontSize: 10, color: ds.ink3),
                                  ),
                                ),
                              ],
                            ),
                            if (c.localDescription.isNotEmpty ||
                                c.remoteDescription.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                '${l.localStatus}: ${c.localDescription}\n${l.daysparkBackup}: ${c.remoteDescription}',
                                style: TextStyle(fontSize: 11, color: ds.ink3),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                ChoiceChip(
                                  label: Text(l.backupKeepLocal),
                                  selected:
                                      _choices[c.key] ==
                                      BackupConflictResolution.keepLocal,
                                  onSelected: (val) {
                                    if (val) {
                                      setState(
                                        () =>
                                            _choices[c.key] =
                                                BackupConflictResolution.keepLocal,
                                      );
                                    }
                                  },
                                ),
                                const SizedBox(width: 8),
                                ChoiceChip(
                                  label: Text(l.backupKeepRemote),
                                  selected:
                                      _choices[c.key] ==
                                      BackupConflictResolution.keepRemote,
                                  onSelected: (val) {
                                    if (val) {
                                      setState(
                                        () =>
                                            _choices[c.key] =
                                                BackupConflictResolution.keepRemote,
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                            if (c.associatedSkippedCount > 0 &&
                                _choices[c.key] ==
                                    BackupConflictResolution.keepLocal) ...[
                              const SizedBox(height: 4),
                              Text(
                                l.backupConflictSkipAssociated(c.associatedSkippedCount),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: ds.danger,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _choices),
          child: Text(l.backupApplyResolutions),
        ),
      ],
    );
  }
}

/// Decodes raw bytes from a Web-uploaded ICS file as strict UTF-8.
String decodeWebIcsBytes(List<int> bytes) => utf8.decode(bytes);

/// Decodes raw bytes from an uploaded ICS file as strict UTF-8.
String decodeIcsBytes(List<int> bytes) => decodeWebIcsBytes(bytes);
