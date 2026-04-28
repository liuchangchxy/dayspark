import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';

import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/core/utils/file_reader.dart';
import 'package:dayspark/domain/providers/sync_provider.dart';
import 'package:dayspark/domain/providers/accounts_provider.dart';
import 'package:dayspark/domain/providers/feature_flags_provider.dart';
import 'package:dayspark/data/remote/caldav/sync_service.dart';
import 'package:dayspark/domain/providers/ai_provider.dart';
import 'package:dayspark/domain/providers/theme_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/mcp_provider.dart';
import 'package:dayspark/domain/services/ics_service.dart';
import 'package:dayspark/l10n/app_localizations.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final syncStatus = ref.watch(syncStatusProvider);
    final lastSync = ref.watch(lastSyncTimeProvider);
    final syncError = ref.watch(syncErrorProvider);
    final isSyncing = syncStatus == SyncStatus.syncing;
    final flagsAsync = ref.watch(featureFlagsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          onPressed: () => context.pop(),
        ),
        title: Text(l.settings),
      ),
      body: ListView(
        children: [
          // ── CalDAV Accounts (single unified section) ──
          if (flagsAsync.valueOrNull?.isEnabled(FeatureFlag.caldavSync) ??
              false) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                l.caldavAccounts,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            ref
                .watch(accountsProvider)
                .when(
                  data: (accounts) {
                    if (accounts.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          l.noAccounts,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      );
                    }
                    return Column(
                      children: accounts.map((account) {
                        return ListTile(
                          leading: const Icon(CupertinoIcons.cloud),
                          title: Text(account.name),
                          subtitle: Text(
                            '${account.username}@${account.serverUrl}',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isSyncing)
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              else
                                IconButton(
                                  icon: const Icon(CupertinoIcons.refresh),
                                  onPressed: () => _triggerSync(context, ref),
                                ),
                              IconButton(
                                icon: Icon(
                                  CupertinoIcons.delete,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                                onPressed: () => _confirmRemoveAccount(
                                  context,
                                  ref,
                                  account,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
            if (syncError != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  syncError,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            if (lastSync != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  l.lastSync(DateFormatters.formatRelativeTime(lastSync)),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ListTile(
              leading: const Icon(CupertinoIcons.plus_circle),
              title: Text(l.addAccount),
              onTap: () => _showAddAccountDialog(context, ref),
            ),
            const Divider(),
          ], // end CalDAV section
          // ── AI Config ──
          if (flagsAsync.valueOrNull?.isEnabled(FeatureFlag.aiAssistant) ??
              false) ...[
            ListTile(
              leading: const Icon(CupertinoIcons.chat_bubble_2),
              title: Text(l.aiConfig),
              subtitle: _buildAiSubtitle(ref),
              onTap: () => _showAiConfigDialog(context, ref),
            ),
            const Divider(),
          ],

          // ── Notifications ──
          ListTile(
            leading: const Icon(CupertinoIcons.bell),
            title: Text(l.notifications),
            subtitle: Text(l.defaultReminderTimes),
            onTap: () => _showReminderDefaultsDialog(context, ref),
          ),
          const Divider(),

          // ── Import / Export ──
          ListTile(
            leading: const Icon(CupertinoIcons.arrow_down_doc),
            title: Text(l.importExport),
            subtitle: Text(l.calendarData),
            onTap: () => _showIcsDialog(context, ref),
          ),
          const Divider(),

          // ── Appearance ──
          ListTile(
            leading: const Icon(CupertinoIcons.paintbrush),
            title: Text(l.appearance),
            subtitle: Text(l.theme),
            onTap: () => _showThemeDialog(context, ref),
          ),

          // ── MCP Server (desktop only) ──
          if (!kIsWeb)
            ListTile(
              leading: const Icon(CupertinoIcons.desktopcomputer),
              title: const Text('MCP Server'),
              subtitle: ref.watch(mcpRunningProvider)
                  ? const Text('Running on localhost:3001')
                  : const Text('Allow AI agents to access your data'),
              trailing: Switch(
                value: ref.watch(mcpRunningProvider),
                onChanged: (v) async {
                  try {
                    await ref.read(toggleMcpServerProvider)();
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l.mcpServerError('$e'))),
                      );
                    }
                  }
                },
              ),
            ),

          ListTile(
            leading: const Icon(CupertinoIcons.info),
            title: Text(l.about),
            subtitle: const Text('DaySpark v0.7.0'),
          ),
          const Divider(),

          // ── Feature Toggles ──
          flagsAsync.when(
            data: (flags) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    l.advancedFeatures,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(CupertinoIcons.sparkles),
                  title: Text(l.aiAssistant),
                  value: flags.isEnabled(FeatureFlag.aiAssistant),
                  onChanged: (v) => ref.read(setFeatureFlagProvider)(
                    FeatureFlag.aiAssistant,
                    v,
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(CupertinoIcons.paperclip),
                  title: Text(l.attachments),
                  value: flags.isEnabled(FeatureFlag.attachments),
                  onChanged: (v) => ref.read(setFeatureFlagProvider)(
                    FeatureFlag.attachments,
                    v,
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(CupertinoIcons.cloud),
                  title: Text(l.caldavAccount),
                  value: flags.isEnabled(FeatureFlag.caldavSync),
                  onChanged: (v) => ref.read(setFeatureFlagProvider)(
                    FeatureFlag.caldavSync,
                    v,
                  ),
                ),
              ],
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildAiSubtitle(WidgetRef ref) {
    final aiConfigured = ref.watch(isAiConfiguredProvider);
    return aiConfigured.when(
      data: (configured) => Text(configured ? '✓' : ''),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const Text(''),
    );
  }

  Future<void> _triggerSync(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context)!;
    try {
      await ref.read(triggerSyncAllAccountsProvider)();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.syncFailed('$e'))));
      }
    }
  }

  void _showReminderDefaultsDialog(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.notifications),
        content: Text(l.defaultReminderTimes),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.ok),
          ),
        ],
      ),
    );
  }

  void _showAddAccountDialog(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final nameController = TextEditingController(text: '');
    final urlController = TextEditingController();
    final userController = TextEditingController();
    final passController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.addAccount),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: l.accountName,
                  hintText: l.accountNameHint,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                decoration: InputDecoration(
                  labelText: l.serverUrl,
                  hintText: 'https://caldav.example.com/',
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: userController,
                decoration: InputDecoration(labelText: l.username),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passController,
                decoration: InputDecoration(labelText: l.password),
                obscureText: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final url = urlController.text.trim();
              final user = userController.text.trim();
              final pass = passController.text;
              if (url.isEmpty || user.isEmpty || pass.isEmpty) return;

              await ref.read(addAccountProvider)(
                name: name.isEmpty ? 'Default' : name,
                serverUrl: url,
                username: user,
                password: pass,
              );

              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: Text(l.add),
          ),
        ],
      ),
    );
  }

  void _confirmRemoveAccount(
    BuildContext context,
    WidgetRef ref,
    dynamic account,
  ) {
    final l = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.removeAccountTitle),
        content: Text(l.removeAccountConfirm(account.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () async {
              await ref.read(deleteAccountProvider)(account.id);
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(l.remove),
          ),
        ],
      ),
    );
  }

  void _showThemeDialog(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l.theme),
        children: [
          SimpleDialogOption(
            onPressed: () {
              ref
                  .read(themeModeProvider.notifier)
                  .setThemeMode(ThemeMode.system);
              Navigator.of(ctx).pop();
            },
            child: ListTile(
              leading: const Icon(CupertinoIcons.sun_max),
              title: Text(l.themeSystem),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              ref
                  .read(themeModeProvider.notifier)
                  .setThemeMode(ThemeMode.light);
              Navigator.of(ctx).pop();
            },
            child: ListTile(
              leading: const Icon(CupertinoIcons.sun_max),
              title: Text(l.themeLight),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.dark);
              Navigator.of(ctx).pop();
            },
            child: ListTile(
              leading: const Icon(CupertinoIcons.moon),
              title: Text(l.themeDark),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
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
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(l.exportedTo(path))));
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

  void _showAiConfigDialog(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final config = ref.read(aiConfigProvider).value;
    final keyController = TextEditingController(text: config?.apiKey ?? '');
    final urlController = TextEditingController(
      text: config?.baseUrl ?? 'https://api.openai.com/v1',
    );
    final modelController = TextEditingController(
      text: config?.model ?? 'gpt-4o-mini',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.aiConfig),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: keyController,
                decoration: InputDecoration(
                  labelText: l.apiKey,
                  hintText: 'sk-...',
                ),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                decoration: InputDecoration(
                  labelText: l.baseUrl,
                  hintText: 'https://api.openai.com/v1',
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: modelController,
                decoration: InputDecoration(
                  labelText: l.model,
                  hintText: 'gpt-4o-mini',
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (config != null)
            TextButton(
              onPressed: () async {
                await ref.read(deleteAiConfigProvider)();
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error,
              ),
              child: Text(l.remove),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () async {
              final key = keyController.text.trim();
              final url = urlController.text.trim();
              final model = modelController.text.trim();
              if (key.isEmpty) return;

              await ref.read(saveAiConfigProvider)(
                apiKey: key,
                baseUrl: url.isEmpty ? 'https://api.openai.com/v1' : url,
                model: model.isEmpty ? 'gpt-4o-mini' : model,
              );
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: Text(l.save),
          ),
        ],
      ),
    );
  }
}
