import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/theme/spec_tokens.dart';
import 'package:dayspark/domain/providers/ai_provider.dart';
import 'package:dayspark/domain/providers/feature_flags_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/ai_config_dialog.dart';
import '../settings_ui.dart';

class AiSection extends ConsumerWidget {
  const AiSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final flagsAsync = ref.watch(featureFlagsProvider);
    final enabled =
        flagsAsync.valueOrNull?.isEnabled(FeatureFlag.aiAssistant) ?? true;
    final configured = ref.watch(isAiConfiguredProvider).valueOrNull ?? false;
    final config = ref.watch(aiConfigProvider).value;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsRows(
          children: [
            SettingsRow(
              label: l.aiEnableFull,
              subtitle: l.aiEnableDesc,
              trailing: Switch(
                value: enabled,
                onChanged: (v) => ref.read(setFeatureFlagProvider)(
                  FeatureFlag.aiAssistant,
                  v,
                ),
              ),
            ),
            if (enabled)
              SettingsRow(
                label: l.aiModelRow,
                value: config == null ? l.aiNotConfiguredShort : null,
                chevron: SettingsChevron.right,
                onTap: () => showAiConfigDialog(context, ref),
                trailing: config == null
                    ? null
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            maskApiKey(config.apiKey),
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: SpecTokens.ink2,
                              fontFamilyFallback: AppTypography.fallback,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l.aiKeyLocalOnly,
                            style: const TextStyle(
                              fontSize: 9.5,
                              color: SpecTokens.faint,
                              fontFamilyFallback: AppTypography.fallback,
                            ),
                          ),
                        ],
                      ),
              ),
            if (enabled && configured)
              SettingsRow(
                label: l.openAssistant,
                value: l.settingsValueOpen,
                chevron: SettingsChevron.right,
                onTap: () => context.push('/ai-chat'),
              ),
          ],
        ),
        if (enabled && !configured)
          InlineAlert(
            title: l.aiUnconfiguredAlertTitle,
            message: l.aiUnconfiguredAlertBody,
          ),
        if (!enabled) InlineAlert(message: l.aiOffAlertBody),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 14, 0, 0),
          child: Text(
            l.aiPrivacyFooter,
            style: const TextStyle(
              fontSize: 11,
              height: 1.55,
              color: SpecTokens.faint,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
        ),
      ],
    );
  }
}
