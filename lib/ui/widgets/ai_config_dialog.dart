import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/domain/providers/ai_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/ui/design/ds.dart';

/// Show the AI configuration dialog. Used by both Settings and AI Chat pages.
Future<void> showAiConfigDialog(BuildContext context, WidgetRef ref) async {
  final l = AppLocalizations.of(context)!;
  final config = ref.read(aiConfigProvider).value;
  final rawKey = config?.apiKey ?? '';
  final maskedKey = rawKey.length > 4
      ? '••••${rawKey.substring(rawKey.length - 4)}'
      : rawKey;
  final keyController = TextEditingController(text: maskedKey);

  // Find which preset matches the current base URL
  final currentUrl = config?.baseUrl ?? '';
  var selectedPresetIndex = kAiPresets.indexWhere(
    (p) => p.baseUrl == currentUrl,
  );
  final isCustom = selectedPresetIndex < 0 && currentUrl.isNotEmpty;

  await showDialog(
    context: context,
    builder: (ctx) => _AiConfigDialog(
      l: l,
      initialConfig: config,
      keyController: keyController,
      initialPresetIndex: selectedPresetIndex,
      isCustom: isCustom,
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
  final bool isCustom;
  final WidgetRef ref;
  final String originalKey;

  const _AiConfigDialog({
    required this.l,
    this.initialConfig,
    required this.keyController,
    required this.initialPresetIndex,
    required this.isCustom,
    required this.ref,
    required this.originalKey,
  });

  @override
  ConsumerState<_AiConfigDialog> createState() => _AiConfigDialogState();
}

class _AiConfigDialogState extends ConsumerState<_AiConfigDialog> {
  late int _presetIndex;
  late bool _isCustom;
  late TextEditingController _urlController;
  late TextEditingController _modelController;

  List<String> _detectedModels = [];
  bool _detecting = false;
  bool _detectFailed = false;

  @override
  void initState() {
    super.initState();
    _presetIndex = widget.initialPresetIndex;
    _isCustom = widget.isCustom;
    _urlController = TextEditingController(
      text: widget.initialConfig?.baseUrl ?? 'https://api.openai.com/v1',
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

  String get _baseUrl {
    if (_isCustom || _presetIndex < 0) return _urlController.text.trim();
    return kAiPresets[_presetIndex].baseUrl;
  }

  String get _providerLabel {
    if (_isCustom) return widget.l.customProvider;
    final index = _presetIndex >= 0 ? _presetIndex : 0;
    return kAiPresets[index].name;
  }

  Future<void> _detectModels() async {
    final key = widget.keyController.text.trim();
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

  Future<void> _pickProvider() async {
    final l = widget.l;
    final current = _isCustom
        ? kAiPresets.length
        : (_presetIndex >= 0 ? _presetIndex : 0);
    final picked = await showDsSheet<int>(
      context: context,
      title: l.aiProvider,
      body: Builder(
        builder: (sheetContext) {
          final ds = sheetContext.ds;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < kAiPresets.length; i++)
                DsSettingRow(
                  label: kAiPresets[i].name,
                  selected: current == i,
                  trailing: current == i
                      ? Icon(
                          CupertinoIcons.checkmark,
                          size: 15,
                          color: ds.primary,
                        )
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(i),
                ),
              DsSettingRow(
                label: l.customProvider,
                selected: current == kAiPresets.length,
                trailing: current == kAiPresets.length
                    ? Icon(
                        CupertinoIcons.checkmark,
                        size: 15,
                        color: ds.primary,
                      )
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(kAiPresets.length),
              ),
            ],
          );
        },
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (picked == kAiPresets.length) {
        _isCustom = true;
      } else {
        _isCustom = false;
        _presetIndex = picked;
        _urlController.text = kAiPresets[picked].baseUrl;
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

  @override
  Widget build(BuildContext context) {
    final l = widget.l;
    final config = widget.initialConfig;
    final ds = context.ds;

    return DsDialog(
      title: l.aiConfig,
      width: 520,
      actions: [
        if (config != null)
          DsButton(
            label: l.remove,
            tone: DsButtonTone.danger,
            onPressed: () async {
              await ref.read(deleteAiConfigProvider)();
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        const Spacer(),
        DsButton(
          label: l.cancel,
          tone: DsButtonTone.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: AppSpacing.s2),
        DsButton(
          label: l.save,
          onPressed: () async {
            var key = widget.keyController.text.trim();
            if (key.startsWith('••••') || key.isEmpty) {
              key = widget.originalKey;
            }
            final url = _baseUrl;
            final model = _modelController.text.trim();
            if (key.isEmpty) return;

            await ref.read(saveAiConfigProvider)(
              apiKey: key,
              baseUrl: url.isEmpty ? 'https://api.openai.com/v1' : url,
              model: model.isEmpty ? 'gpt-4o-mini' : model,
            );
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DsSettingRow(
            label: l.aiProvider,
            value: _providerLabel,
            onTap: _pickProvider,
          ),
          const SizedBox(height: AppSpacing.s3),
          DsField(
            label: l.baseUrl,
            help:
                'Format: http://host:port/v1 (e.g., http://192.168.1.100:11434/v1)',
            child: DsTextField(
              controller: _urlController,
              hint: 'https://api.openai.com/v1',
              keyboardType: TextInputType.url,
              enabled: _isCustom,
              onChanged: (_) => setState(() => _detectedModels = []),
            ),
          ),
          DsField(
            label: l.apiKey,
            child: DsTextField(
              controller: widget.keyController,
              hint: 'sk-...',
              obscureText: true,
              onChanged: (_) => setState(() => _detectedModels = []),
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
                onPressed: _detecting ? null : _detectModels,
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
              onTap: _pickModel,
            )
          else
            DsTextField(
              controller: _modelController,
              hint: 'gpt-4o-mini',
            ),
        ],
      ),
    );
  }
}
