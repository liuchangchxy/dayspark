import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dayspark/domain/providers/attachments_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';

class AttachmentList extends ConsumerWidget {
  final String parentType;
  final int parentId;

  const AttachmentList({
    super.key,
    required this.parentType,
    required this.parentId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final attachmentsAsync = parentType == 'event'
        ? ref.watch(eventAttachmentsProvider(parentId))
        : ref.watch(todoAttachmentsProvider(parentId));

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
                onPressed: () => _pickFile(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (attachments.isEmpty)
            Text(
              l.noAttachments,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            )
          else
            ...attachments.map(
              (a) => ListTile(
                dense: true,
                leading: const Icon(CupertinoIcons.doc_text, size: 20),
                title: Text(a.fileName, style: const TextStyle(fontSize: 13)),
                subtitle: a.fileSize > 0
                    ? Text(
                        _formatSize(a.fileSize),
                        style: const TextStyle(fontSize: 11),
                      )
                    : null,
                trailing: IconButton(
                  icon: const Icon(CupertinoIcons.xmark, size: 16),
                  onPressed: () => ref.read(deleteAttachmentProvider)(a.id),
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
        ],
      ),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Future<void> _pickFile(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final filePath = kIsWeb ? '' : file.path ?? '';

    await ref.read(createAttachmentProvider)(
      parentType: parentType,
      parentId: parentId,
      filePath: filePath,
      fileName: file.name,
      mimeType: file.extension,
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
