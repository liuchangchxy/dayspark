import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/data/file_downloader.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/attachments_provider.dart';
import 'package:dayspark/domain/services/attachment_files.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_row.dart';

/// A file the form is holding. [id] is set for a row that is already stored,
/// so the form can tell an add from a keep when it commits.
class DraftAttachment {
  const DraftAttachment({
    required this.fileName,
    this.id,
    this.mimeType,
    this.bytes,
    this.sourcePath,
    this.fileSize = 0,
    this.serverFileRef,
  });

  final int? id;
  final String fileName;
  final String? mimeType;
  final List<int>? bytes;
  final String? sourcePath;
  final int fileSize;
  final String? serverFileRef;

  static DraftAttachment fromRow(Attachment row) => DraftAttachment(
    id: row.id,
    fileName: row.fileName,
    mimeType: row.mimeType,
    fileSize: row.fileSize,
    serverFileRef: row.serverFileRef,
  );

  @override
  bool operator ==(Object other) =>
      other is DraftAttachment &&
      other.id == id &&
      other.fileName == fileName &&
      other.mimeType == mimeType &&
      other.sourcePath == sourcePath &&
      other.bytes == bytes;

  @override
  int get hashCode => Object.hash(id, fileName, mimeType, sourcePath, bytes);
}

/// Files attached to one object.
///
/// Pass [draft] to hold them in a form instead of writing immediately: the form
/// then owns the list and decides when an add or a removal reaches the
/// database. Omit it to act on the stored rows directly.
class AttachmentList extends ConsumerStatefulWidget {
  const AttachmentList({
    super.key,
    required this.parentType,
    this.parentId,
    this.draft,
    this.onDraftChanged,
    this.enabled = true,
  }) : assert(
         draft != null || parentId != null,
         'either a parent row or a draft list is required',
       );

  final String parentType;
  final int? parentId;
  final List<DraftAttachment>? draft;
  final ValueChanged<List<DraftAttachment>>? onDraftChanged;
  final bool enabled;

  @override
  ConsumerState<AttachmentList> createState() => _AttachmentListState();
}

class _AttachmentListState extends ConsumerState<AttachmentList> {
  /// Ids with a fetch in flight — the row shows a spinner instead of letting
  /// a second tap start a second download.
  final Set<int> _busy = <int>{};

  bool get _isDraft => widget.draft != null;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(
          l.attachments,
          action: widget.enabled
              ? TextButton.icon(
                  onPressed: () => _pickFile(context),
                  icon: const Icon(CupertinoIcons.paperclip, size: 13),
                  label: Text(l.addAttachment),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : null,
        ),
        if (_isDraft)
          _draftBody(context)
        else
          ref
              .watch(
                widget.parentType == 'event'
                    ? eventAttachmentsProvider(widget.parentId!)
                    : todoAttachmentsProvider(widget.parentId!),
              )
              .when(
                data: (rows) => rows.isEmpty
                    ? _empty(context, l)
                    : Column(
                        children: [for (final row in rows) _row(context, row)],
                      ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => _empty(context, l),
              ),
      ],
    );
  }

  Widget _draftBody(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final items = widget.draft!;
    if (items.isEmpty) return _empty(context, l);
    return Column(
      children: [
        for (final item in items)
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.doc_text,
                  size: 18,
                  color: context.semantic.textSecondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    item.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body,
                  ),
                ),
                if (widget.enabled)
                  IconButton(
                    icon: const Icon(CupertinoIcons.xmark, size: 16),
                    tooltip: l.removeAttachment,
                    onPressed: () => widget.onDraftChanged!(
                      [...items]..removeWhere((other) => other == item),
                    ),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _empty(BuildContext context, AppLocalizations l) => Text(
    l.noAttachments,
    style: AppTypography.caption.copyWith(color: context.semantic.textTertiary),
  );

  Widget _row(BuildContext context, Attachment a) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final busy = _busy.contains(a.id);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.doc_text,
            size: 18,
            color: context.semantic.textSecondary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body,
                ),
                Text(
                  _subtitle(context, a),
                  style: AppTypography.caption.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (busy)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton(
              icon: const Icon(CupertinoIcons.arrow_down_doc, size: 18),
              tooltip: l.openAttachment,
              onPressed: () => _open(context, a),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
          if (widget.enabled)
            IconButton(
              icon: const Icon(CupertinoIcons.xmark, size: 16),
              tooltip: l.removeAttachment,
              onPressed: busy ? null : () => _delete(a),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
        ],
      ),
    );
  }

  /// Size plus where the blob lives: a row whose upload never landed is
  /// still usable on this device, but peers cannot fetch it — hiding that
  /// would look like a sync bug later.
  String _subtitle(BuildContext context, Attachment a) {
    final l = AppLocalizations.of(context)!;
    final size = a.fileSize > 0 ? _formatSize(a.fileSize) : '';
    if (a.serverFileRef != null) return size;
    return size.isEmpty
        ? l.attachmentLocalOnly
        : '${l.attachmentLocalOnly} · $size';
  }

  Future<void> _pickFile(BuildContext context) async {
    final l = AppLocalizations.of(context)!;
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final mimeType = attachmentMimeType(
      stored: file.extension,
      fileName: file.name,
    );
    if (_isDraft) {
      widget.onDraftChanged!([
        ...widget.draft!,
        DraftAttachment(
          fileName: file.name,
          mimeType: mimeType,
          bytes: file.bytes,
          sourcePath: file.path,
          fileSize: file.size,
        ),
      ]);
      return;
    }
    try {
      await ref.read(createAttachmentProvider)(
        parentType: widget.parentType,
        parentId: widget.parentId!,
        fileName: file.name,
        mimeType: mimeType,
        bytes: file.bytes,
        sourcePath: file.path,
      );
    } catch (e) {
      if (context.mounted) _toast(context, l.attachmentFailed);
    }
  }

  Future<void> _open(BuildContext context, Attachment a) async {
    final l = AppLocalizations.of(context)!;
    setState(() => _busy.add(a.id));
    try {
      final bytes = await ref.read(loadAttachmentBytesProvider)(a.id);
      if (bytes == null) {
        if (context.mounted) _toast(context, l.attachmentUnavailable);
        return;
      }
      final mimeType = attachmentMimeType(
        stored: a.mimeType,
        fileName: a.fileName,
      );
      if (ref.read(isWebProvider)) {
        // No filesystem on web: hand the bytes to the browser download.
        ref.read(webBytesDownloaderProvider)(
          bytes: Uint8List.fromList(bytes),
          filename: a.fileName,
          mimeType: mimeType,
        );
        return;
      }
      try {
        await Share.shareXFiles([
          XFile.fromData(
            Uint8List.fromList(bytes),
            name: a.fileName,
            mimeType: mimeType,
          ),
        ], subject: a.fileName);
      } on UnimplementedError {
        if (context.mounted) _toast(context, l.attachmentReady(a.fileName));
      }
    } catch (e) {
      if (context.mounted) _toast(context, l.attachmentFailed);
    } finally {
      if (mounted) setState(() => _busy.remove(a.id));
    }
  }

  Future<void> _delete(Attachment a) async {
    await ref.read(deleteAttachmentProvider)(a.id);
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
