import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/domain/providers/account_provider.dart';
import 'package:dayspark/domain/providers/sync_client_provider.dart';
import 'package:dayspark/domain/sync/sync_engine.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import '../settings_ui.dart';

/// Spec section 8: 同步 (Sync).
/// Shows server, current account, last sync time, and logout.
class SyncSection extends ConsumerWidget {
  const SyncSection({super.key, this.onGoToAccount});

  final VoidCallback? onGoToAccount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final account = ref.watch(accountAuthProvider);
    final status = ref.watch(syncStatusProvider);
    final server = ref.watch(syncSettingsProvider).valueOrNull?.baseUrl;

    return account.when(
      data: (state) {
        if (state.email == null) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InlineAlert(message: l.syncLoggedOutBanner),
              const SizedBox(height: 12),
              SettingsRows(
                children: [
                  SettingsRow(
                    label: l.serverUrl,
                    subtitle: l.syncSectionDesc,
                    value: server ?? 'sync.dayspark.local',
                  ),
                  SettingsRow(
                    label: l.userAccount,
                    subtitle: l.login,
                    value: l.login,
                    chevron: SettingsChevron.right,
                    onTap: onGoToAccount,
                  ),
                ],
              ),
            ],
          );
        }

        return SettingsRows(
          children: [
            SettingsRow(
              label: l.serverUrl,
              value: server ?? 'sync.dayspark.local',
            ),
            SettingsRow(
              label: l.userAccount,
              value: state.email,
            ),
            SettingsRow(
              label: l.lastSync(''),
              value: _statusText(l, status),
            ),
            SettingsRow(
              label: l.logout,
              danger: true,
              chevron: SettingsChevron.right,
              onTap: state.busy ? null : () => _confirmLogout(context, ref, l),
            ),
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          l.accountLoadFailed,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }

  static String _statusText(AppLocalizations l, SyncStatus status) {
    return switch (status.phase) {
      SyncPhase.idle =>
        status.lastSyncAt == null ? l.notSynced : l.syncedAt(_format(status.lastSyncAt!)),
      SyncPhase.pushing => l.syncing,
      SyncPhase.pulling => l.syncPulling,
      SyncPhase.error => l.syncPhaseError,
    };
  }

  static String _format(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static Future<void> _confirmLogout(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => DsDialog(
        title: l.logout,
        actions: [
          const Spacer(),
          DsButton(
            label: l.cancel,
            tone: DsButtonTone.ghost,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          const SizedBox(width: 8),
          DsButton(
            label: l.logout,
            tone: DsButtonTone.danger,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
        child: Text(l.syncLoggedOutBanner),
      ),
    );
    if (confirmed == true) {
      await ref.read(accountAuthProvider.notifier).logout();
    }
  }
}
