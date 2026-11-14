import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/domain/providers/cloud_sync_provider.dart';
import 'package:dayspark/domain/sync/cloud/cloud_sync_settings.dart';
import 'package:dayspark/domain/sync/cloud/cloud_webdav_config.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import '../settings_ui.dart';

/// Source picker + WebDAV credentials. The six hosted drives are deliberately
/// absent from the choices: each needs an app registered with the provider
/// before the app can even ask for a token (docs/cloud-sync-providers.md).
class CloudSyncSection extends ConsumerWidget {
  const CloudSyncSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final source = ref.watch(cloudSyncSourceProvider).valueOrNull;
    final config = ref.watch(cloudWebDavConfigProvider).valueOrNull;
    final engine = ref.watch(cloudSyncEngineProvider);
    final active = source ?? CloudSyncSource.daysparkServer;
    return SettingsRows(
      children: [
        SettingsRow(
          label: l.syncSource,
          subtitle: l.cloudSyncUnavailable,
          value: active == CloudSyncSource.daysparkServer
              ? l.syncSourceServer
              : l.syncSourceWebDav,
          chevron: SettingsChevron.down,
          onTap: () => _chooseSource(context, ref, active, config),
        ),
        if (active == CloudSyncSource.webdav)
          SettingsRow(
            label: l.webDavAddress,
            value: config == null ? l.syncSourceUnset : config.documentUri.host,
            chevron: SettingsChevron.right,
            onTap: () => _editWebDav(context, ref, config),
          ),
        if (active == CloudSyncSource.webdav &&
            config != null &&
            config.isComplete)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Tooltip(
              message: l.syncTooltip,
              child: DsButton(
                label: l.syncNow,
                icon: CupertinoIcons.refresh,
                tone: DsButtonTone.secondary,
                expand: true,
                onPressed: engine == null
                    ? null
                    : () => unawaited(
                        ref.read(cloudSyncControllerProvider).syncNow(),
                      ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _chooseSource(
    BuildContext context,
    WidgetRef ref,
    CloudSyncSource current,
    CloudWebDavConfig? config,
  ) async {
    final l = AppLocalizations.of(context)!;
    await showSettingsChoice<CloudSyncSource>(
      context: context,
      title: l.syncSource,
      current: current,
      options: [
        (CloudSyncSource.daysparkServer, l.syncSourceServer),
        (CloudSyncSource.webdav, l.syncSourceWebDav),
      ],
      onSelected: (next) async {
        await ref.read(cloudSyncControllerProvider).selectSource(next);
        if (next == CloudSyncSource.webdav &&
            (config == null || !config.isComplete) &&
            context.mounted) {
          await _editWebDav(context, ref, config);
        }
      },
    );
  }

  Future<void> _editWebDav(
    BuildContext context,
    WidgetRef ref,
    CloudWebDavConfig? config,
  ) async {
    final saved = await showDialog<CloudWebDavConfig>(
      animationStyle: AnimationStyle.noAnimation,
      context: context,
      builder: (_) => _WebDavDialog(initial: config),
    );
    if (saved == null) return;
    await ref.read(cloudSyncControllerProvider).saveWebDav(saved);
  }
}

class _WebDavDialog extends StatefulWidget {
  const _WebDavDialog({this.initial});

  final CloudWebDavConfig? initial;

  @override
  State<_WebDavDialog> createState() => _WebDavDialogState();
}

class _WebDavDialogState extends State<_WebDavDialog> {
  late final TextEditingController _address = TextEditingController(
    text: widget.initial?.baseUrl ?? '',
  );
  late final TextEditingController _username = TextEditingController(
    text: widget.initial?.username ?? '',
  );
  late final TextEditingController _password = TextEditingController(
    text: widget.initial?.password ?? '',
  );
  late final TextEditingController _path = TextEditingController(
    text:
        widget.initial?.documentPath ??
        CloudWebDavConfig.defaultDocumentPath,
  );
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    _username.dispose();
    _password.dispose();
    _path.dispose();
    super.dispose();
  }

  void _submit(AppLocalizations l) {
    final address = _address.text.trim();
    final uri = Uri.tryParse(address);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      setState(() => _error = l.serverUrlInvalid);
      return;
    }
    Navigator.of(context).pop(
      CloudWebDavConfig(
        baseUrl: address,
        documentPath: _path.text.trim().isEmpty
            ? CloudWebDavConfig.defaultDocumentPath
            : _path.text.trim(),
        username: _username.text.trim().isEmpty ? null : _username.text.trim(),
        password: _password.text.isEmpty ? null : _password.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return DsDialog(
      title: l.syncSourceWebDav,
      width: 460,
      actions: [
        const Spacer(),
        DsButton(
          label: l.cancel,
          tone: DsButtonTone.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: AppSpacing.s2),
        DsButton(label: l.save, onPressed: () => _submit(l)),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DsField(
            label: l.webDavAddress,
            help: l.webDavHelp,
            child: DsTextField(
              controller: _address,
              hint: 'https://dav.example.com/remote.php/dav/files/me',
              keyboardType: TextInputType.url,
              autofocus: true,
            ),
          ),
          DsField(
            label: l.webDavUsername,
            child: DsTextField(
              controller: _username,
              textInputAction: TextInputAction.next,
            ),
          ),
          DsField(
            label: l.password,
            child: DsTextField(
              controller: _password,
              obscureText: true,
              onSubmitted: (_) => _submit(l),
            ),
          ),
          DsField(
            label: l.webDavDocumentPath,
            child: DsTextField(controller: _path),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s2),
              child: Text(
                _error!,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
