import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/core/utils/file_reader.dart';
import 'package:dayspark/domain/providers/sync_provider.dart';
import 'package:dayspark/domain/providers/accounts_provider.dart';
import 'package:dayspark/domain/providers/feature_flags_provider.dart';
import 'package:dayspark/data/remote/caldav/sync_service.dart';
import 'package:dayspark/domain/providers/ai_provider.dart';
import 'package:dayspark/domain/providers/theme_provider.dart';
import 'package:dayspark/domain/providers/default_tab_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/mcp_provider.dart';
import 'package:dayspark/domain/services/ics_service.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/ai_config_dialog.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  static const _repo = 'liuchangchxy/dayspark';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
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
          // ── Appearance ──
          ListTile(
            leading: const Icon(CupertinoIcons.paintbrush),
            title: Text(l.appearance),
            subtitle: Text(l.theme),
            onTap: () => _showThemeDialog(context, ref),
          ),

          // ── Tab Order ──
          ListTile(
            leading: const Icon(CupertinoIcons.square_split_2x1),
            title: Text(l.defaultTab),
            subtitle: Text(
              ref.watch(defaultTabProvider) == AppTab.calendar
                  ? l.calendarFirst
                  : l.todosFirst,
            ),
            onTap: () => _showDefaultTabDialog(context, ref),
          ),

          const Divider(),

          // ── Data ──
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

          const Divider(),

          // ── Advanced Features (ExpansionTile) ──
          ExpansionTile(
            leading: const Icon(CupertinoIcons.lab_flask),
            title: Text(l.advancedFeatures),
            initiallyExpanded:
                flagsAsync.valueOrNull?.isEnabled(FeatureFlag.aiAssistant) ==
                    true ||
                flagsAsync.valueOrNull?.isEnabled(FeatureFlag.caldavSync) ==
                    true,
            children: [
              // AI Assistant
              SwitchListTile(
                secondary: const Icon(CupertinoIcons.sparkles),
                title: Row(
                  children: [
                    Expanded(child: Text(l.aiAssistant)),
                    _tutorialLink(context, 'ai-setup'),
                  ],
                ),
                value:
                    flagsAsync.valueOrNull?.isEnabled(
                      FeatureFlag.aiAssistant,
                    ) ??
                    true,
                onChanged: (v) => ref.read(setFeatureFlagProvider)(
                  FeatureFlag.aiAssistant,
                  v,
                ),
              ),
              if (flagsAsync.valueOrNull?.isEnabled(FeatureFlag.aiAssistant) ??
                  true)
                ListTile(
                  leading: const SizedBox(width: 24),
                  title: Text(l.aiConfig),
                  subtitle: _buildAiSubtitle(ref),
                  trailing: const Icon(CupertinoIcons.right_chevron, size: 16),
                  onTap: () => showAiConfigDialog(context, ref),
                ),

              const Divider(indent: 16, endIndent: 16),

              // CalDAV Sync
              SwitchListTile(
                secondary: const Icon(CupertinoIcons.cloud),
                title: Row(
                  children: [
                    Expanded(child: Text(l.caldavAccount)),
                    _tutorialLink(context, 'caldav-setup'),
                  ],
                ),
                value:
                    flagsAsync.valueOrNull?.isEnabled(FeatureFlag.caldavSync) ??
                    false,
                onChanged: (v) =>
                    ref.read(setFeatureFlagProvider)(FeatureFlag.caldavSync, v),
              ),
              if (flagsAsync.valueOrNull?.isEnabled(FeatureFlag.caldavSync) ??
                  false) ...[
                _buildCaldavSection(context, ref),
              ],

              if (!kIsWeb) ...[
                const Divider(indent: 16, endIndent: 16),

                // MCP Server
                SwitchListTile(
                  secondary: const Icon(CupertinoIcons.desktopcomputer),
                  title: Row(
                    children: [
                      Expanded(child: const Text('MCP Server')),
                      _tutorialLink(context, 'mcp-setup'),
                    ],
                  ),
                  subtitle: ref.watch(mcpRunningProvider)
                      ? const Text('Running on localhost:3001')
                      : const Text('Allow AI agents to access your data'),
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
              ],
            ],
          ),

          const Divider(),

          // ── About ──
          ListTile(
            leading: const Icon(CupertinoIcons.info),
            title: Text(l.about),
            subtitle: const Text('DaySpark v0.10.0'),
            onTap: () => context.push('/about'),
          ),
        ],
      ),
    );
  }

  Widget _tutorialLink(BuildContext context, String docName) {
    return IconButton(
      icon: Icon(
        CupertinoIcons.book,
        size: 16,
        color: Theme.of(context).colorScheme.primary,
      ),
      tooltip: AppLocalizations.of(context)!.tutorial,
      onPressed: () => launchUrl(
        Uri.parse('https://github.com/$_repo/blob/main/docs/$docName.md'),
        mode: LaunchMode.externalApplication,
      ),
    );
  }

  Widget _buildCaldavSection(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final syncStatus = ref.watch(syncStatusProvider);
    final lastSync = ref.watch(lastSyncTimeProvider);
    final syncError = ref.watch(syncErrorProvider);
    final isSyncing = syncStatus == SyncStatus.syncing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                      leading: const SizedBox(width: 24),
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
                              child: CircularProgressIndicator(strokeWidth: 2),
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
                            onPressed: () =>
                                _confirmRemoveAccount(context, ref, account),
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
          contentPadding: const EdgeInsets.only(left: 24, right: 16),
          title: Text(l.addAccount),
          onTap: () => _showAddAccountDialog(context, ref),
        ),
      ],
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
            onPressed: () {
              launchUrl(
                Uri.parse(
                  'https://github.com/liuchangchxy/dayspark/blob/main/docs/caldav-setup.md',
                ),
                mode: LaunchMode.externalApplication,
              );
            },
            child: Text(l.setupGuide),
          ),
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
                  await Share.shareXFiles([
                    XFile(path),
                  ], subject: 'DaySpark Calendar Export');
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

  void _showDefaultTabDialog(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l.defaultTab),
        children: [
          SimpleDialogOption(
            onPressed: () {
              ref
                  .read(defaultTabProvider.notifier)
                  .setDefaultTab(AppTab.calendar);
              Navigator.of(ctx).pop();
            },
            child: ListTile(
              leading: const Icon(CupertinoIcons.calendar),
              title: Text(l.calendarFirst),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              ref.read(defaultTabProvider.notifier).setDefaultTab(AppTab.todos);
              Navigator.of(ctx).pop();
            },
            child: ListTile(
              leading: const Icon(CupertinoIcons.checkmark_rectangle),
              title: Text(l.todosFirst),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}
