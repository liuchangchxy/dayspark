import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/domain/providers/ai_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';

/// Show the AI configuration dialog. Used by both Settings and AI Chat pages.
Future<void> showAiConfigDialog(BuildContext context, WidgetRef ref) async {
  final l = AppLocalizations.of(context)!;
  final config = ref.read(aiConfigProvider).value;
  final keyController = TextEditingController(text: config?.apiKey ?? '');

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

  const _AiConfigDialog({
    required this.l,
    this.initialConfig,
    required this.keyController,
    required this.initialPresetIndex,
    required this.isCustom,
    required this.ref,
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
  String? _detectError;

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
    super.dispose();
  }

  String get _baseUrl {
    if (_isCustom || _presetIndex < 0) return _urlController.text.trim();
    return kAiPresets[_presetIndex].baseUrl;
  }

  Future<void> _detectModels() async {
    final key = widget.keyController.text.trim();
    final url = _baseUrl;
    if (key.isEmpty || url.isEmpty) return;

    setState(() {
      _detecting = true;
      _detectError = null;
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
      if (mounted) {
        setState(() {
          _detectError = e.toString();
          _detecting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l;
    final config = widget.initialConfig;

    return AlertDialog(
      title: Text(l.aiConfig),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Provider dropdown
            Text(l.aiProvider, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            DropdownButton<int>(
              value: _isCustom
                  ? kAiPresets.length
                  : (_presetIndex >= 0 ? _presetIndex : 0),
              isExpanded: true,
              items: [
                ...kAiPresets.asMap().entries.map(
                  (e) =>
                      DropdownMenuItem(value: e.key, child: Text(e.value.name)),
                ),
                DropdownMenuItem(
                  value: kAiPresets.length,
                  child: Text(l.customProvider),
                ),
              ],
              onChanged: (val) {
                setState(() {
                  if (val == kAiPresets.length) {
                    _isCustom = true;
                  } else {
                    _isCustom = false;
                    _presetIndex = val!;
                    _urlController.text = kAiPresets[val].baseUrl;
                  }
                  _detectedModels = [];
                });
              },
            ),
            const SizedBox(height: 12),

            // Base URL (always visible, editable for custom)
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: l.baseUrl,
                hintText: 'https://api.openai.com/v1',
              ),
              keyboardType: TextInputType.url,
              enabled: _isCustom,
              onChanged: (_) => setState(() => _detectedModels = []),
            ),
            const SizedBox(height: 12),

            // API Key
            TextField(
              controller: widget.keyController,
              decoration: InputDecoration(
                labelText: l.apiKey,
                hintText: 'sk-...',
              ),
              obscureText: true,
              onChanged: (_) => setState(() => _detectedModels = []),
            ),
            const SizedBox(height: 12),

            // Model: dropdown if detected, text field otherwise
            Row(
              children: [
                Text(l.model, style: Theme.of(context).textTheme.labelMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: _detecting ? null : _detectModels,
                  icon: _detecting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(CupertinoIcons.search, size: 14),
                  label: Text(_detecting ? l.detectingModels : l.detectModels),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (_detectError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _detectError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            if (_detectedModels.isNotEmpty)
              DropdownButton<String>(
                value: _detectedModels.contains(_modelController.text)
                    ? _modelController.text
                    : null,
                isExpanded: true,
                hint: Text(l.selectModel),
                items: _detectedModels
                    .map(
                      (m) => DropdownMenuItem(
                        value: m,
                        child: Text(m, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _modelController.text = val);
                  }
                },
              )
            else
              TextField(
                controller: _modelController,
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
              if (context.mounted) Navigator.of(context).pop();
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l.remove),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () async {
            final key = widget.keyController.text.trim();
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
          child: Text(l.save),
        ),
      ],
    );
  }
}
