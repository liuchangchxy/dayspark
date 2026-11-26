import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/domain/providers/ai_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/pages/settings/settings_ui.dart';

/// Show the AI configuration dialog. Used by both Settings and AI Chat pages.
Future<void> showAiConfigDialog(BuildContext context, WidgetRef ref) async {
  final l = AppLocalizations.of(context)!;
  final config = ref.read(aiConfigProvider).value;
  final rawKey = config?.apiKey ?? '';
  final maskedKey = maskApiKey(rawKey);
  final keyController = TextEditingController(text: maskedKey);

  // Find which preset matches the current base URL
  final currentUrl = config?.baseUrl ?? '';
  final matched = kAiPresets.indexWhere((p) => p.baseUrl == currentUrl);
  final selectedPresetIndex = currentUrl.isEmpty ? 0 : matched;
  await showDialog(
    context: context,
    builder: (ctx) => _AiConfigDialog(
      l: l,
      initialConfig: config,
      keyController: keyController,
      initialPresetIndex: selectedPresetIndex,
      ref: ref,
      originalKey: rawKey,
    ),
  );
}

class _AiConfigDialog extends ConsumerStatefulWidget {
  final AppLocalizations l;
  final AiConfig? initialConfig;
  final TextEditingController keyController;
  final int initialPresetIndex;
  final WidgetRef ref;
  final String originalKey;

  const _AiConfigDialog({
    required this.l,
    this.initialConfig,
    required this.keyController,
    required this.initialPresetIndex,
    required this.ref,
    required this.originalKey,
  });

  @override
  ConsumerState<_AiConfigDialog> createState() => _AiConfigDialogState();
}

class _AiConfigDialogState extends ConsumerState<_AiConfigDialog> {
  late int _presetIndex;
  late TextEditingController _urlController;
  late TextEditingController _modelController;

  List<String> _detectedModels = [];
  bool _detecting = false;
  bool _detectFailed = false;
  bool _saving = false;
  String? _actionError;
  String? _keyErrorTitle;
  String? _keyErrorBody;

  @override
  void initState() {
    super.initState();
    _presetIndex = widget.initialPresetIndex;
    final initial = widget.initialConfig;
    _urlController = TextEditingController(
      text: (initial == null || initial.baseUrl.isEmpty)
          ? 'https://api.openai.com/v1'
          : initial.baseUrl,
    );
    _modelController = TextEditingController(
      text: widget.initialConfig?.model ?? 'gpt-4o-mini',
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _modelController.dispose();
    widget.keyController.dispose();
    super.dispose();
  }

  String get _baseUrl => _urlController.text.trim();

  Future<void> _detectModels() async {
    final key = _resolvedKey();
    final url = _baseUrl;
    if (key.isEmpty || url.isEmpty) return;

    setState(() {
      _detecting = true;
      _detectFailed = false;
    });

    try {
      final models = await fetchModels(url, key);
      if (mounted) {
        setState(() {
          _detectedModels = models;
          _detecting = false;
        });
      }
    } catch (e) {
      debugPrint('ai_config: detectModels error: $e');
      if (mounted) {
        setState(() {
          _detectFailed = true;
          _detecting = false;
        });
      }
    }
  }

  /// A masked field means "keep the stored key"; an empty field means nothing
  /// was ever entered.
  String _resolvedKey() {
    final typed = widget.keyController.text.trim();
    if (typed.isEmpty || typed.contains('••••')) return widget.originalKey;
    return typed;
  }

  void _selectPreset(int index) {
    setState(() {
      _presetIndex = index;
      if (index >= 0 && index < kAiPresets.length) {
        _urlController.text = kAiPresets[index].baseUrl;
      }
      _detectedModels = [];
    });
  }

  Future<void> _pickModel() async {
    final current = _modelController.text;
    final picked = await showDsSheet<String>(
      context: context,
      title: widget.l.selectModel,
      body: Builder(
        builder: (sheetContext) {
          final ds = sheetContext.ds;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final model in _detectedModels)
                DsSettingRow(
                  label: model,
                  selected: model == current,
                  trailing: model == current
                      ? Icon(
                          CupertinoIcons.checkmark,
                          size: 15,
                          color: ds.primary,
                        )
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(model),
                ),
            ],
          );
        },
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _modelController.text = picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    final l = widget.l;
    final key = _resolvedKey();
    if (key.isEmpty) {
      setState(() {
        _keyErrorTitle = l.aiKeyCheckFailedTitle;
        _keyErrorBody = l.aiKeyMissing;
      });
      return;
    }
    final url = _baseUrl.isEmpty ? 'https://api.openai.com/v1' : _baseUrl;
    final model = _modelController.text.trim();

    setState(() {
      _saving = true;
      _keyErrorTitle = null;
      _keyErrorBody = null;
      _actionError = null;
    });

    final check = await ref.read(validateAiKeyProvider)(
      baseUrl: url,
      apiKey: key,
    );
    if (!mounted) return;
    if (!check.ok) {
      setState(() {
        _saving = false;
        _keyErrorTitle = l.aiKeyCheckFailedTitle;
        _keyErrorBody = check.unauthorized
            ? l.aiKeyCheck401Body
            : l.aiKeyCheckFailedBody(check.failureLabel);
      });
      return;
    }

    try {
      await ref.read(saveAiConfigProvider)(
        apiKey: key,
        baseUrl: url,
        model: model.isEmpty ? 'gpt-4o-mini' : model,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      debugPrint('ai_config: save error: $error');
      if (mounted) {
        setState(() {
          _saving = false;
          _actionError = l.actionFailedRetry;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l;
    final config = widget.initialConfig;
    final ds = context.ds;

    return DsDialog(
      title: l.aiModelDialogTitle,
      width: 520,
      sheetOnMobile: true,
      actions: [
        if (config != null)
          DsButton(
            label: l.remove,
            tone: DsButtonTone.danger,
            onPressed: _saving
                ? null
                : () async {
                    try {
                      await ref.read(deleteAiConfigProvider)();
                      if (context.mounted) Navigator.of(context).pop();
                    } catch (error) {
                      debugPrint('ai_config: delete error: $error');
                      if (mounted) {
                        setState(() => _actionError = l.actionFailedRetry);
                      }
                    }
                  },
          ),
        const Spacer(),
        DsButton(
          label: l.cancel,
          tone: DsButtonTone.ghost,
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: AppSpacing.s2),
        DsButton(
          label: _saving ? l.aiKeyChecking : l.save,
          loading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_keyErrorBody != null)
            InlineAlert(
              title: _keyErrorTitle,
              message: _keyErrorBody!,
              isRed: true,
            ),
          DsField(
            label: l.aiProvider,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < kAiPresets.length; i++)
                  DsChip(
                    label: kAiPresets[i].name,
                    selected: _presetIndex == i,
                    onTap: () => _selectPreset(i),
                  ),
                DsChip(
                  label: l.customProvider,
                  selected: _presetIndex < 0,
                  onTap: () => _selectPreset(-1),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
          DsField(
            label: l.baseUrl,
            // The spec keeps the Base URL editable for every provider, not
            // only the custom preset.
            child: DsTextField(
              controller: _urlController,
              hint: 'https://api.openai.com/v1',
              keyboardType: TextInputType.url,
              onChanged: (_) => setState(() => _detectedModels = []),
            ),
          ),
          if (_keyErrorBody != null) const SizedBox(height: AppSpacing.s2),
          DsField(
            label: l.apiKey,
            child: DsTextField(
              controller: widget.keyController,
              hint: 'sk-...',
              obscureText: true,
              onChanged: (_) {
                setState(() {
                  _detectedModels = [];
                  _keyErrorBody = null;
                  _keyErrorTitle = null;
                });
              },
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  l.model,
                  style: AppTypography.small.copyWith(
                    color: ds.ink2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              DsButton(
                label: _detecting ? l.detectingModels : l.detectModels,
                tone: DsButtonTone.ghost,
                icon: CupertinoIcons.search,
                small: true,
                loading: _detecting,
                onPressed: _detecting || _saving ? null : _detectModels,
              ),
            ],
          ),
          if (_detectFailed) ...[
            const SizedBox(height: AppSpacing.s1),
            Text(
              l.modelDetectFailed,
              style: AppTypography.caption.copyWith(color: ds.danger),
            ),
          ],
          const SizedBox(height: AppSpacing.s1),
          if (_detectedModels.isNotEmpty)
            DsSettingRow(
              label: l.selectModel,
              value: _detectedModels.contains(_modelController.text)
                  ? _modelController.text
                  : null,
              onTap: _saving ? null : _pickModel,
            )
          else
            DsTextField(
              controller: _modelController,
              hint: 'gpt-4o-mini',
              enabled: !_saving,
            ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            l.aiBaseUrlHelp,
            style: AppTypography.caption.copyWith(color: ds.ink3),
          ),
          if (_actionError != null) ...[
            const SizedBox(height: AppSpacing.s2),
            InlineAlert(message: _actionError!, isRed: true),
          ],
        ],
      ),
    );
  }
}
