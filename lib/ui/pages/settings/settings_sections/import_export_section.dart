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
import 'package:dayspark/core/theme/spec_tokens.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/design/spec_toast.dart';

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
  double _backupProgress = 0;
  String? _backupFileName;
  int? _backupBytes;
  _BackupCounts? _backupCounts;

  bool _importMode = false;
  PlatformFile? _pickedFile;
  String? _fileContent;
  int? _targetCalendarId;
  String? _targetCalendarName;
  IcsImportPreview? _importPreview;
  String? _importResultSummary;
  String? _importError;
  int _importFailedCount = 0;
  List<IcsPreviewItem> _importFailedRows = const [];
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
                onPressed:
                    (_fileContent != null &&
                        _targetCalendarId != null &&
                        !_importBusy)
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
          if (_importResultSummary != null && _importFailedCount == 0)
            InlineAlert(message: _importResultSummary!),
          if (_importError != null ||
              _importFailedCount > 0 ||
              _importFailedRows.isNotEmpty)
            ImportFailurePanel(
              error: _importError,
              skipped: _importFailedRows,
              failedCount: _importFailedCount > 0 ? _importFailedCount : null,
              summary: _importFailedCount > 0 ? _importResultSummary : null,
              onReport: () => _showImportReport(l),
              onSkip: _importError != null ? null : _skipErrorRows,
            ),
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
                _importError = null;
                _importFailedCount = 0;
                _importFailedRows = const [];
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
        if (_backupBusy && _backupFileName != null)
          IoCard(
            title: l.backupProgressPercent((_backupProgress * 100).round()),
            description: l.backupProgressWriting(_backupFileName!),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                minHeight: 4,
                value: _backupProgress,
                backgroundColor: const Color(0xFFECECE6),
                color: SpecTokens.ink,
              ),
            ),
          )
        else if (_backupBusy)
          InlineAlert(message: l.backupInProgress),
        if (_backupFailed && _backupFileName != null)
          InlineAlert(
            title: l.backupFailedTitle,
            message: l.backupNoPartial,
            isRed: true,
            action: Align(
              alignment: Alignment.centerLeft,
              child: DsButton(
                label: l.retry,
                small: true,
                tone: DsButtonTone.secondary,
                onPressed: _exportBackup,
              ),
            ),
          ),
        if (!_backupBusy && !_backupFailed && _backupCounts != null)
          IoCard(
            title: l.backupDoneTitle,
            description:
                '${_backupFileName!} · ${_formatBytes(_backupBytes ?? 0)}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.backupIncludes,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: SpecTokens.ink,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l.backupIncludesCounts(
                    _backupCounts!.calendars,
                    _backupCounts!.todos,
                    _backupCounts!.events,
                    _backupCounts!.attachments,
                  ),
                  style: const TextStyle(
                    fontSize: 10.5,
                    height: 1.55,
                    color: SpecTokens.muted,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: SpecTokens.wash,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    l.backupSavedLocation,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: SpecTokens.ink2,
                      fontFamilyFallback: AppTypography.fallback,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (_backupFailed && _backupFileName == null && _backupResult != null)
          InlineAlert(message: _backupResult!, isRed: true),
        if (!_backupBusy &&
            !_backupFailed &&
            _backupCounts == null &&
            _backupResult != null)
          InlineAlert(message: _backupResult!),
        if (_importBusy) InlineAlert(message: l.importInProgress),
      ],
    );
  }

  Future<void> _exportBackup() async {
    if (_backupBusy) return;
    final l = AppLocalizations.of(context)!;
    final filename =
        'dayspark-backup-${DateTime.now().millisecondsSinceEpoch}.zip';
    setState(() {
      _backupBusy = true;
      _backupFailed = false;
      _backupResult = null;
      _backupProgress = 0;
      _backupFileName = filename;
      _backupBytes = null;
      _backupCounts = null;
    });
    try {
      final service = BackupService(ref.read(databaseProvider));
      final bytes = await service.exportZip(
        onProgress: (progress) {
          if (mounted) setState(() => _backupProgress = progress);
        },
      );
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
          if (mounted) showSpecToast(context, l.exportedTo(path));
        }
      }
      final counts = await _loadBackupCounts();
      if (!mounted) return;
      setState(() {
        _backupBytes = bytes.length;
        _backupCounts = counts;
        _backupResult = l.backupComplete(filename);
      });
    } catch (e) {
      debugPrint('backup: export failed: $e');
      if (mounted) showSpecToast(context, l.exportFailed);
      if (!mounted) return;
      setState(() {
        _backupFailed = true;
        _backupResult = l.exportFailed;
      });
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<_BackupCounts> _loadBackupCounts() async {
    final db = ref.read(databaseProvider);
    return _BackupCounts(
      calendars: (await db.select(db.calendars).get()).length,
      todos: (await db.select(db.todos).get()).length,
      events: (await db.select(db.events).get()).length,
      attachments: (await db.select(db.attachments).get()).length,
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Restoring is an upsert, so it is offered as a merge and says so: nothing
  /// on this device is removed by it.
  Future<void> _mergeBackup() async {
    if (_backupBusy) return;
    final l = AppLocalizations.of(context)!;
    setState(() {
      _backupBusy = true;
      _backupFailed = false;
      _backupResult = null;
      _backupFileName = null;
      _backupBytes = null;
      _backupCounts = null;
      _backupProgress = 0;
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
      if (mounted) showSpecToast(context, l.restoreFailed);
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
      showSpecToast(context, AppLocalizations.of(context)!.noCalendarToImport);
      return;
    }
    setState(() {
      _importMode = true;
      _availableCalendars = calendars;
      _targetCalendarId ??= calendars.first.id;
      _targetCalendarName ??= calendars.first.name;
      _importResultSummary = null;
      _importError = null;
      _importFailedCount = 0;
      _importFailedRows = const [];
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
      showSpecToast(context, AppLocalizations.of(context)!.importFailed);
      return;
    }
    if (!mounted) return;
    setState(() {
      _pickedFile = file;
      _fileContent = content;
      _importError = null;
      _importResultSummary = null;
      _importFailedCount = 0;
      _importFailedRows = const [];
    });
    await _updatePreview();
  }

  Future<void> _updatePreview() async {
    if (_fileContent == null || _targetCalendarId == null) return;
    final db = ref.read(databaseProvider);
    setState(() => _importBusy = true);
    try {
      final preview = await IcsService(
        db,
      ).previewIcs(_fileContent!, _targetCalendarId!);
      if (mounted) {
        setState(() {
          _importPreview = preview;
          _importError = null;
          _importBusy = false;
          _importResultSummary = null;
          _importFailedCount = 0;
          _importFailedRows = const [];
        });
      }
    } catch (e) {
      debugPrint('ics: preview failed: $e');
      if (mounted) {
        setState(() {
          _importBusy = false;
          _importError = '$e';
          _importPreview = null;
        });
      }
    }
  }

  Future<void> _executeImport() async {
    if (_fileContent == null || _targetCalendarId == null || _importBusy) {
      return;
    }
    final l = AppLocalizations.of(context)!;
    final db = ref.read(databaseProvider);
    setState(() {
      _importBusy = true;
      _importError = null;
      _importResultSummary = null;
      _importFailedCount = 0;
      _importFailedRows = const [];
    });
    try {
      final imported = await IcsService(
        db,
      ).importIcsDetailed(_fileContent!, _targetCalendarId!);
      final created = imported.events + imported.todos - imported.updated;
      final summary = l.importResultSummary(
        created,
        imported.updated,
        imported.failed,
      );
      if (!mounted) return;
      setState(() {
        _importBusy = false;
        _importResultSummary = summary;
        _importFailedRows = _importPreview?.skipped ?? const [];
        _importFailedCount = imported.failed;
      });
    } catch (error) {
      debugPrint('ics: import failed: $error');
      if (!mounted) return;
      setState(() {
        _importBusy = false;
        _importResultSummary = null;
        _importError = '$error';
      });
    }
  }

  /// The importer already skips rows it cannot parse and keeps going. This
  /// retries the write for the rows that can be written; a whole-file parse
  /// failure has no rows to skip and stays disabled.
  Future<void> _skipErrorRows() async {
    if (_importError != null) return;
    await _executeImport();
  }

  Future<void> _showImportReport(AppLocalizations l) async {
    final skipped = _importFailedRows.isEmpty && _importPreview != null
        ? _importPreview!.skipped
        : _importFailedRows;
    await showDialog<void>(
      context: context,
      builder: (ctx) => DsDialog(
        title: l.importReportTitle,
        width: 460,
        actions: [
          const Spacer(),
          DsButton(
            label: l.close,
            tone: DsButtonTone.ghost,
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_importError != null)
              Text(
                l.importReportError(_importError!),
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.55,
                  color: SpecTokens.red,
                  fontFamilyFallback: AppTypography.fallback,
                ),
              )
            else if (skipped.isEmpty)
              Text(
                _importFailedCount > 0
                    ? l.importFailedRows(_importFailedCount)
                    : l.importReportEmpty,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.55,
                  color: SpecTokens.muted,
                  fontFamilyFallback: AppTypography.fallback,
                ),
              )
            else ...[
              Text(
                l.importReportSkipped(skipped.length),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: SpecTokens.ink,
                  fontFamilyFallback: AppTypography.fallback,
                ),
              ),
              const SizedBox(height: 8),
              for (final row in skipped)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          row.summary.isEmpty
                              ? (row.kind == IcsPreviewKind.event
                                    ? l.events
                                    : l.todos)
                              : row.summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: SpecTokens.ink2,
                            fontFamilyFallback: AppTypography.fallback,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        row.kind == IcsPreviewKind.event ? l.events : l.todos,
                        style: const TextStyle(
                          fontSize: 10,
                          color: SpecTokens.faint,
                          fontFamilyFallback: AppTypography.fallback,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// Export always writes every calendar: a partial export that silently
  /// skipped calendars would look complete and not be.
  Future<void> _exportIcs(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context)!;
    final db = ref.read(databaseProvider);
    try {
      if ((await (db.select(db.calendars)).get()).isEmpty) {
        if (!context.mounted) return;
        showSpecToast(context, l.nothingToExport);
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
        if (context.mounted) showSpecToast(context, l.exportedTo(path));
      }
    } catch (error) {
      debugPrint('ics: export failed: $error');
      if (context.mounted) showSpecToast(context, l.exportFailed);
    }
  }
}

class _BackupCounts {
  const _BackupCounts({
    required this.calendars,
    required this.todos,
    required this.events,
    required this.attachments,
  });

  final int calendars;
  final int todos;
  final int events;
  final int attachments;
}

/// The failure surface for an .ics import. Public so the two actions can be
/// tested without driving the file picker.
class ImportFailurePanel extends StatelessWidget {
  const ImportFailurePanel({
    super.key,
    required this.error,
    required this.skipped,
    required this.onReport,
    required this.onSkip,
    this.failedCount,
    this.summary,
  });

  final String? error;
  final List<IcsPreviewItem> skipped;
  final VoidCallback onReport;
  final VoidCallback? onSkip;

  /// Rows the import actually failed on. When the importer fails rows that
  /// the preview could not flag, [skipped] may be shorter — the count still
  /// has to tell the truth.
  final int? failedCount;

  /// Created / updated / skipped summary, retained on a partial failure so
  /// the red surface also says what did get written.
  final String? summary;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final count = failedCount ?? skipped.length;
    final message = error != null
        ? l.importReportError(error!)
        : [
            if (summary != null && summary!.isNotEmpty) summary!,
            l.importFailedRows(count),
          ].join('\n');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InlineAlert(title: l.importErrorTitle, isRed: true, message: message),
        if (onSkip == null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              l.importCannotSkip,
              style: const TextStyle(
                fontSize: 10.5,
                height: 1.5,
                color: SpecTokens.faint,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            DsButton(
              label: l.importSeeReport,
              tone: DsButtonTone.secondary,
              small: true,
              onPressed: onReport,
            ),
            DsButton(label: l.importSkipRows, small: true, onPressed: onSkip),
          ],
        ),
      ],
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

    return DsDialog(
      title: l.backupConflictTitle(widget.conflicts.length),
      width: 480,
      actions: [
        const Spacer(),
        DsButton(
          label: l.cancel,
          tone: DsButtonTone.ghost,
          onPressed: () => Navigator.pop(context, null),
        ),
        const SizedBox(width: AppSpacing.s2),
        DsButton(
          label: l.backupApplyResolutions,
          onPressed: () => Navigator.pop(context, _choices),
        ),
      ],
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
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: ds.ink3,
                                  ),
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
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              ChoiceChip(
                                label: Text(l.backupKeepLocal),
                                selected:
                                    _choices[c.key] ==
                                    BackupConflictResolution.keepLocal,
                                onSelected: (val) {
                                  if (val) {
                                    setState(
                                      () => _choices[c.key] =
                                          BackupConflictResolution.keepLocal,
                                    );
                                  }
                                },
                              ),
                              ChoiceChip(
                                label: Text(l.backupKeepRemote),
                                selected:
                                    _choices[c.key] ==
                                    BackupConflictResolution.keepRemote,
                                onSelected: (val) {
                                  if (val) {
                                    setState(
                                      () => _choices[c.key] =
                                          BackupConflictResolution.keepRemote,
                                    );
                                  }
                                },
                              ),
                              ChoiceChip(
                                label: Text(l.mergeConflict),
                                selected:
                                    _choices[c.key] ==
                                    BackupConflictResolution.merge,
                                onSelected: (val) {
                                  if (val) {
                                    setState(
                                      () => _choices[c.key] =
                                          BackupConflictResolution.merge,
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                          if (_choices[c.key] ==
                              BackupConflictResolution.merge) ...[
                            const SizedBox(height: 4),
                            Text(
                              l.backupMergeHint,
                              style: TextStyle(fontSize: 10, color: ds.ink3),
                            ),
                          ],
                          if (c.associatedSkippedCount > 0 &&
                              _choices[c.key] ==
                                  BackupConflictResolution.keepLocal) ...[
                            const SizedBox(height: 4),
                            Text(
                              l.backupConflictSkipAssociated(
                                c.associatedSkippedCount,
                              ),
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
    );
  }
}

/// Decodes raw bytes from a Web-uploaded ICS file as strict UTF-8.
String decodeWebIcsBytes(List<int> bytes) => utf8.decode(bytes);

/// Decodes raw bytes from an uploaded ICS file as strict UTF-8.
String decodeIcsBytes(List<int> bytes) => decodeWebIcsBytes(bytes);
