import 'package:flutter/foundation.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:dayspark/data/file_reader.dart';

import 'package:dayspark/domain/providers/feature_flags_provider.dart';
import 'package:dayspark/domain/providers/ai_provider.dart';
import 'package:dayspark/domain/providers/theme_provider.dart';
import 'package:dayspark/domain/providers/default_tab_provider.dart';
import 'package:dayspark/domain/providers/locale_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/services/ics_service.dart';
import 'package:dayspark/infrastructure/platform/alarm_service.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/ai_config_dialog.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  static const _repo = 'liuchangchxy/dayspark';

  static final systemAlarmProvider = StateProvider<bool>((ref) {
    return false;
  });

  static bool _loaded = false;
  static String? _cachedVersion;

  static Future<void> loadSystemAlarmSetting(WidgetRef ref) async {
    ref.read(systemAlarmProvider.notifier).state =
        await AlarmService.isEnabled();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Load persisted settings once on first build
    if (!_loaded) {
      _loaded = true;
      Future.microtask(() => loadSystemAlarmSetting(ref));
      PackageInfo.fromPlatform().then(
        (i) => _cachedVersion = 'DaySpark v${i.version}',
      );
    }

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
          ListTile(
            leading: const Icon(CupertinoIcons.color_filter),
            title: Text(l.themeColor),
            subtitle: _themeColorPreview(ref),
            onTap: () => _showColorPicker(context, ref),
          ),
          ListTile(
            leading: const Icon(CupertinoIcons.globe),
            title: Text(l.language),
            subtitle: Text(
              ref.watch(localeProvider) == null
                  ? l.languageSystem
                  : ref.watch(localeProvider)?.languageCode == 'zh'
                      ? l.languageZh
                      : l.languageEn,
            ),
            onTap: () => _showLanguageDialog(context, ref),
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
            ],
          ),

          // ── System Alarm ──
          if (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.windows) ...[
            const Divider(),
            SwitchListTile(
              secondary: const Icon(CupertinoIcons.alarm),
              title: Text(l.systemAlarm),
              subtitle: Text(l.systemAlarmDesc),
              value: ref.watch(systemAlarmProvider),
              onChanged: (v) async {
                await AlarmService.setEnabled(v);
                ref.read(systemAlarmProvider.notifier).state = v;
              },
            ),
            const Divider(),
          ],

          // ── About ──
          ListTile(
            leading: const Icon(CupertinoIcons.info),
            title: Text(l.about),
            subtitle: Text(_cachedVersion ?? ''),
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

  Widget _buildAiSubtitle(WidgetRef ref) {
    final aiConfigured = ref.watch(isAiConfiguredProvider);
    return aiConfigured.when(
      data: (configured) => Text(configured ? '✓' : ''),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const Text(''),
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

  static const _presetColors = [
    Color(0xFF2563EB), // Blue (default)
    Color(0xFF7C3AED), // Purple
    Color(0xFFDB2777), // Pink
    Color(0xFFDC2626), // Red
    Color(0xFFEA580C), // Orange
    Color(0xFFCA8A04), // Yellow
    Color(0xFF16A34A), // Green
    Color(0xFF0891B2), // Cyan
    Color(0xFF4F46E5), // Indigo
    Color(0xFF64748B), // Slate
  ];

  Widget _themeColorPreview(WidgetRef ref) {
    final color = ref.watch(themeColorProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color ?? const Color(0xFF2563EB),
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }

  void _showColorPicker(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final current = ref.read(themeColorProvider);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.themeColor),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _presetColors.asMap().entries.map((entry) {
            final i = entry.key;
            final color = entry.value;
            final selected = (current ?? const Color(0xFF2563EB)) == color;
            return Semantics(
              label: 'Color ${i + 1}',
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: InkWell(
                onTap: () {
                  ref.read(themeColorProvider.notifier).setColor(color);
                  Navigator.of(ctx).pop();
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: selected
                        ? Border.all(
                            color: Theme.of(ctx).colorScheme.onSurface,
                            width: 3,
                          )
                        : null,
                  ),
                  child: selected
                      ? Icon(
                          CupertinoIcons.checkmark,
                          color: ThemeData.estimateBrightnessForColor(color) ==
                                  Brightness.dark
                              ? Colors.white
                              : Colors.black,
                          size: 20,
                        )
                      : null,
                ),
              ),
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(themeColorProvider.notifier).setColor(null);
              Navigator.of(ctx).pop();
            },
            child: Text(l.resetColor),
          ),
        ],
      ),
    );
  }

  void _showLanguageDialog(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final current = ref.read(localeProvider);
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l.language),
        children: [
          SimpleDialogOption(
            onPressed: () {
              ref.read(localeProvider.notifier).setLocale(null);
              Navigator.of(ctx).pop();
            },
            child: ListTile(
              leading: Icon(
                current == null ? CupertinoIcons.checkmark : null,
                size: 20,
              ),
              title: Text(l.languageSystem),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              ref.read(localeProvider.notifier).setLocale(const Locale('zh'));
              Navigator.of(ctx).pop();
            },
            child: ListTile(
              leading: Icon(
                current?.languageCode == 'zh' ? CupertinoIcons.checkmark : null,
                size: 20,
              ),
              title: Text(l.languageZh),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              ref.read(localeProvider.notifier).setLocale(const Locale('en'));
              Navigator.of(ctx).pop();
            },
            child: ListTile(
              leading: Icon(
                current?.languageCode == 'en' ? CupertinoIcons.checkmark : null,
                size: 20,
              ),
              title: Text(l.languageEn),
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
