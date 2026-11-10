import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:dayspark/domain/providers/ai_provider.dart';
import 'package:dayspark/domain/providers/feature_flags_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/widgets/ai_config_dialog.dart';

class AiSection extends ConsumerWidget {
  const AiSection({super.key});

  static const _repo = 'liuchangchxy/dayspark';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final flagsAsync = ref.watch(featureFlagsProvider);
    final enabled =
        flagsAsync.valueOrNull?.isEnabled(FeatureFlag.aiAssistant) ?? true;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DsSettingRow(
          label: l.aiAssistant,
          value: enabled ? l.aiConfigured : l.aiNotConfiguredShort,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DsIconButton(
                icon: CupertinoIcons.book,
                size: 15,
                compact: true,
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
          DsSettingRow(
            label: l.aiConfig,
            value: _aiSubtitle(context, ref),
            onTap: () => showAiConfigDialog(context, ref),
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
}
