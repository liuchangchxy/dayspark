import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:dayspark/data/file_downloader.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/attachments_provider.dart';
import 'package:dayspark/domain/services/attachment_files.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/core/theme/app_typography.dart';

class AttachmentList extends ConsumerStatefulWidget {
  final String parentType;
  final int parentId;

  const AttachmentList({
    super.key,
    required this.parentType,
    required this.parentId,
  });

  @override
  ConsumerState<AttachmentList> createState() => _AttachmentListState();
}

class _AttachmentListState extends ConsumerState<AttachmentList> {
  /// Ids with a fetch in flight — the row shows a spinner instead of letting
  /// a second tap start a second download.
  final Set<int> _busy = <int>{};

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final attachmentsAsync = widget.parentType == 'event'
        ? ref.watch(eventAttachmentsProvider(widget.parentId))
        : ref.watch(todoAttachmentsProvider(widget.parentId));

    return attachmentsAsync.when(
      data: (attachments) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                l.attachments,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(CupertinoIcons.paperclip, size: 20),
                tooltip: l.addAttachment,
                onPressed: () => _pickFile(context),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (attachments.isEmpty)
            Text(
              l.noAttachments,
              style: TextStyle(
                fontSize: AppTypography.caption.fontSize,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            ...attachments.map((a) => _row(context, a)),
        ],
      ),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _row(BuildContext context, Attachment a) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final busy = _busy.contains(a.id);
    return ListTile(
      dense: true,
      leading: const Icon(CupertinoIcons.doc_text, size: 20),
      title: Text(
        a.fileName,
        style: TextStyle(fontSize: AppTypography.body.fontSize),
      ),
      subtitle: Text(
        _subtitle(context, a),
        style: TextStyle(
          fontSize: AppTypography.caption.fontSize,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
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
            ),
          IconButton(
            icon: const Icon(CupertinoIcons.xmark, size: 16),
            tooltip: l.delete,
            onPressed: busy ? null : () => _delete(a),
          ),
        ],
      ),
      contentPadding: EdgeInsets.zero,
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
    try {
      await ref.read(createAttachmentProvider)(
        parentType: widget.parentType,
        parentId: widget.parentId,
        fileName: file.name,
        mimeType: attachmentMimeType(
          stored: file.extension,
          fileName: file.name,
        ),
        bytes: file.bytes,
        sourcePath: file.path,
      );
    } catch (e) {
      if (context.mounted) _toast(context, l.attachmentFailed('$e'));
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
      if (context.mounted) _toast(context, l.attachmentFailed('$e'));
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
