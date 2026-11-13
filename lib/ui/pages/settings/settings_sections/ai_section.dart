import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:dayspark/domain/providers/ai_provider.dart';
import 'package:dayspark/domain/providers/feature_flags_provider.dart';
import 'package:dayspark/domain/providers/locale_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/widgets/ai_config_dialog.dart';
import '../settings_ui.dart';

class AiSection extends ConsumerWidget {
  const AiSection({super.key});

  static const _repo = 'liuchangchxy/dayspark';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final flagsAsync = ref.watch(featureFlagsProvider);
    final enabled =
        flagsAsync.valueOrNull?.isEnabled(FeatureFlag.aiAssistant) ?? true;
    final locale = ref.watch(localeProvider);
    return SettingsRows(
      children: [
        SettingsRow(
          // The group heading already says "AI Assistant", and the row below
          // reports whether a key is configured. What this switch owns is
          // whether the assistant is on, so that is what it is called.
          label: l.aiEnable,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DsIconButton(
                icon: CupertinoIcons.book,
                size: 15,
                tooltip: l.tutorial,
                onPressed: () => launchUrl(
                  Uri.parse(
                    'https://github.com/$_repo/blob/main/docs/ai-setup.md',
                  ),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              Switch(
                value: enabled,
                onChanged: (v) => ref.read(setFeatureFlagProvider)(
                  FeatureFlag.aiAssistant,
                  v,
                ),
              ),
            ],
          ),
        ),
        if (enabled)
          SettingsRow(
            label: l.aiConfig,
            value: _aiSubtitle(context, ref),
            chevron: SettingsChevron.right,
            onTap: () => showAiConfigDialog(context, ref),
          ),
        SettingsRow(
          label: l.language,
          value: locale == null
              ? l.languageSystem
              : locale.languageCode == 'zh'
              ? l.languageZh
              : l.languageEn,
          chevron: SettingsChevron.down,
          onTap: () => _showLanguageDialog(context, ref),
        ),
      ],
    );
  }

  String _aiSubtitle(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final configured = ref.watch(isAiConfiguredProvider).valueOrNull ?? false;
    if (!configured) return l.aiNotConfiguredShort;
    final config = ref.watch(aiConfigProvider).value;
    if (config == null) return l.aiNotConfiguredShort;
    final preset = kAiPresets
        .where((item) => item.baseUrl == config.baseUrl)
        .firstOrNull;
    return preset == null ? config.model : '${preset.name} · ${config.model}';
  }

  void _showLanguageDialog(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final current = ref.read(localeProvider);
    final currentTag = current == null
        ? 'system'
        : current.languageCode == 'zh'
        ? 'zh'
        : 'en';
    showSettingsChoice<String>(
      context: context,
      title: l.language,
      current: currentTag,
      options: [
        ('system', l.languageSystem),
        ('zh', l.languageZh),
        ('en', l.languageEn),
      ],
      onSelected: (tag) => ref
          .read(localeProvider.notifier)
          .setLocale(tag == 'system' ? null : Locale(tag)),
    );
  }
}
