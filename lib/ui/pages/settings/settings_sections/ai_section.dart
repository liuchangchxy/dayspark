import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:dayspark/domain/providers/ai_provider.dart';
import 'package:dayspark/domain/providers/feature_flags_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/ai_config_dialog.dart';

class AiSection extends ConsumerWidget {
  const AiSection({super.key});

  static const _repo = 'liuchangchxy/dayspark';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final flagsAsync = ref.watch(featureFlagsProvider);
    return ExpansionTile(
      leading: const Icon(CupertinoIcons.lab_flask),
      title: Text(l.advancedFeatures),
      initiallyExpanded:
          flagsAsync.valueOrNull?.isEnabled(FeatureFlag.aiAssistant) == true,
      children: [
        SwitchListTile(
          secondary: const Icon(CupertinoIcons.sparkles),
          title: Row(
            children: [
              Expanded(child: Text(l.aiAssistant)),
              _tutorialLink(context, 'ai-setup'),
            ],
          ),
          value:
              flagsAsync.valueOrNull?.isEnabled(FeatureFlag.aiAssistant) ??
              true,
          onChanged: (v) =>
              ref.read(setFeatureFlagProvider)(FeatureFlag.aiAssistant, v),
        ),
        if (flagsAsync.valueOrNull?.isEnabled(FeatureFlag.aiAssistant) ?? true)
          ListTile(
            leading: const SizedBox(width: 24),
            title: Text(l.aiConfig),
            subtitle: _buildAiSubtitle(ref),
            trailing: const Icon(CupertinoIcons.right_chevron, size: 16),
            onTap: () => showAiConfigDialog(context, ref),
          ),
      ],
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
}
