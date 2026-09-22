import 'package:flutter/foundation.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import 'package:dayspark/data/file_reader.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/services/ics_service.dart';
import 'package:dayspark/l10n/app_localizations.dart';

class ImportExportSection extends ConsumerWidget {
  const ImportExportSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(l.data, style: Theme.of(context).textTheme.titleSmall),
        ),
        ListTile(
          leading: const Icon(CupertinoIcons.arrow_down_doc),
          title: Text(l.importExport),
          subtitle: Text(l.calendarData),
          onTap: () => _showIcsDialog(context, ref),
        ),
      ],
    );
  }

  void _showIcsDialog(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.importExport),
        content: Text(l.importExportDesc),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                final db = ref.read(databaseProvider);
                final cals = await (db.select(db.calendars)).get();
                if (cals.isEmpty) return;
                final service = IcsService(db);
                final content = await service.exportCalendar(cals.first.id);
                final path = await service.saveIcsToFile(
                  content,
                  'calendar_export_${DateTime.now().millisecondsSinceEpoch}.ics',
                );
                if (context.mounted) {
                  try {
                    await Share.shareXFiles(
                      [XFile(path)],
                      subject: 'DaySpark Calendar Export',
                    );
                  } on UnimplementedError {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l.exportedTo(path))),
                      );
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
                  icsContent = String.fromCharCodes(file.bytes!);
                } else {
                  icsContent = await readFileNative(file.path!);
                }

                final db = ref.read(databaseProvider);
                final cals = await (db.select(db.calendars)).get();
                if (cals.isEmpty) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l.noCalendarToImport)),
                    );
                  }
                  return;
                }

                final service = IcsService(db);
                final imported = await service.importIcs(
                  icsContent,
                  cals.first.id,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        l.importedResult(imported.events, imported.todos),
                      ),
                    ),
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
    );
  }
}
