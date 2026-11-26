import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/theme/spec_tokens.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:dayspark/domain/providers/account_provider.dart';
import 'package:dayspark/domain/providers/sync_client_provider.dart';
import 'package:dayspark/domain/sync/sync_engine.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/design/spec_toast.dart';
import '../settings_ui.dart';

/// Spec section 8: 同步 (Sync).
/// Shows server, account, last sync, failures, conflicts and logout.
class SyncSection extends ConsumerStatefulWidget {
  const SyncSection({super.key, this.onGoToAccount});

  final VoidCallback? onGoToAccount;

  @override
  ConsumerState<SyncSection> createState() => _SyncSectionState();
}

class _SyncSectionState extends ConsumerState<SyncSection> {
  bool _showConflicts = false;
  final Map<String, SyncConflictResolution> _choices = {};

  @override
  Widget build(BuildContext context) {
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
                    onTap: widget.onGoToAccount,
                  ),
                ],
              ),
            ],
          );
        }

        if (_showConflicts && status.conflicts.isNotEmpty) {
          return _conflictScreen(l, status);
        }

        final pending = ref.watch(pendingSyncOpsProvider).valueOrNull ?? 0;
        final conflicts = ref.watch(syncConflictCountProvider);
        final rejected = ref.watch(syncRejectedCountProvider);
        final latestConflict = status.latestConflict;
        final failed = status.phase == SyncPhase.error;
        final engine = ref.watch(syncEngineProvider);

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (failed)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: InlineAlert(
                  title: l.syncPhaseError,
                  isRed: true,
                  message: _failureText(l, status, pending),
                ),
              ),
            SettingsRows(
              children: [
                SettingsRow(
                  label: l.serverUrl,
                  value: failed
                      ? l.syncServerUnreachable
                      : (server ?? 'sync.dayspark.local'),
                ),
                SettingsRow(label: l.userAccount, value: state.email),
                SettingsRow(
                  label: l.lastSync(''),
                  value: _statusText(l, status),
                ),
                if (failed || pending > 0)
                  SettingsRow(
                    label: l.localStatus,
                    subtitle: l.syncPendingBoth(pending, 0),
                    value: l.localPriority,
                  ),
                if (conflicts > 0)
                  SettingsRow(
                    label: l.syncConflicts,
                    subtitle: latestConflict == null
                        ? null
                        : l.syncConflictLast(_shortId(latestConflict.recordId)),
                    value: l.syncConflictCount(conflicts),
                    chevron: SettingsChevron.right,
                    onTap: () => setState(() => _showConflicts = true),
                  ),
                if (rejected > 0)
                  SettingsRow(
                    label: l.syncServerRejections,
                    subtitle: status.rejectedCodes.isEmpty
                        ? null
                        : l.syncRejected(status.rejectedCodes.join(', ')),
                    value: l.syncRejectedTotal(rejected),
                  ),
                if (failed)
                  SettingsRow(
                    label: l.retryNow,
                    subtitle: l.syncRetryDesc,
                    value: l.retryNow,
                    chevron: SettingsChevron.right,
                    onTap: engine == null
                        ? null
                        : () => unawaited(engine.requestRound()),
                  ),
                SettingsRow(
                  label: l.logout,
                  danger: true,
                  chevron: SettingsChevron.right,
                  onTap: state.busy
                      ? null
                      : () => _confirmLogout(context, ref, l),
                ),
              ],
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
      error: (error, _) {
        debugPrint('sync: account state error: $error');
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l.accountLoadFailed,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
              const SizedBox(width: 8),
              DsButton(
                label: l.retry,
                tone: DsButtonTone.secondary,
                small: true,
                onPressed: () => ref.invalidate(accountAuthProvider),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _conflictScreen(AppLocalizations l, SyncStatus status) {
    final conflicts = status.conflicts;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _showConflicts = false),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      CupertinoIcons.chevron_left,
                      size: 14,
                      color: SpecTokens.muted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l.syncConflictBack,
                      style: const TextStyle(
                        fontSize: 12,
                        color: SpecTokens.muted,
                        fontFamilyFallback: AppTypography.fallback,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            l.syncConflictTitle,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: SpecTokens.ink,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Text(
            l.syncConflictDesc,
            style: const TextStyle(
              fontSize: 11,
              height: 1.55,
              color: SpecTokens.faint,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Text(
            l.syncConflictMergeHint,
            style: const TextStyle(
              fontSize: 10,
              height: 1.5,
              color: SpecTokens.faint,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
        ),
        for (final conflict in conflicts)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _ConflictCard(
              conflict: conflict,
              choice:
                  _choices[conflict.recordId] ??
                  SyncConflictResolution.keepLocal,
              onChoice: (choice) =>
                  setState(() => _choices[conflict.recordId] = choice),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: DsButton(
              label: l.syncConflictApply,
              onPressed: () => _applyChoices(l, conflicts),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _applyChoices(
    AppLocalizations l,
    List<SyncConflict> conflicts,
  ) async {
    final resolve = ref.read(resolveSyncConflictProvider);
    final failures = <String>[];
    for (final conflict in conflicts) {
      final choice =
          _choices[conflict.recordId] ?? SyncConflictResolution.keepLocal;
      if (choice == SyncConflictResolution.keepRemote &&
          !conflict.hasServerCopy) {
        failures.add(l.syncConflictRemoteUnavailable);
        continue;
      }
      try {
        await resolve(conflict.recordId, choice);
      } catch (error) {
        debugPrint('sync: resolve conflict failed: $error');
        failures.add(l.syncConflictApplyFailed('$error'));
      }
    }
    if (!mounted) return;
    _choices.clear();
    setState(() => _showConflicts = false);
    if (failures.isEmpty) {
      showSpecToast(context, l.syncConflictApplied);
    } else {
      showSpecToast(context, failures.first, danger: true);
    }
  }

  static String _statusText(AppLocalizations l, SyncStatus status) {
    return switch (status.phase) {
      SyncPhase.idle =>
        status.lastSyncAt == null
            ? l.notSynced
            : l.syncedAt(_format(status.lastSyncAt!)),
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

  static String _failureText(
    AppLocalizations l,
    SyncStatus status,
    int pending,
  ) {
    final failedAt = status.lastErrorAt;
    final reason = status.lastError ?? l.syncFailedBanner;
    final when = failedAt == null
        ? reason
        : l.syncFailedAt(
            DateFormatters.formatRelativeTime(failedAt, l),
            reason,
          );
    final pendingLine = pending > 0 ? '\n${l.syncPendingUploads(pending)}' : '';
    return '$when$pendingLine';
  }

  static String _shortId(String id) => id.length <= 8 ? id : id.substring(0, 8);

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

class _ConflictCard extends StatelessWidget {
  const _ConflictCard({
    required this.conflict,
    required this.choice,
    required this.onChoice,
  });

  final SyncConflict conflict;
  final SyncConflictResolution choice;
  final ValueChanged<SyncConflictResolution> onChoice;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final local = _describe(l, conflict.type, conflict.localPayload);
    final server = conflict.serverDeleted
        ? l.deleted
        : _describe(l, conflict.type, conflict.serverPayload);
    final hasServerCopy = conflict.hasServerCopy;
    return IoCard(
      title: _title(l, conflict),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            local.isEmpty && server.isEmpty
                ? l.syncConflictLocalServer
                : '${l.syncConflictLocal}: $local\n${l.syncConflictServer}: $server',
            style: const TextStyle(
              fontSize: 10.5,
              height: 1.55,
              color: SpecTokens.muted,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              DsChip(
                label: l.keepLocal,
                selected: choice == SyncConflictResolution.keepLocal,
                onTap: () => onChoice(SyncConflictResolution.keepLocal),
              ),
              DsChip(
                label: conflict.serverDeleted ? l.acceptDeletion : l.keepServer,
                selected: choice == SyncConflictResolution.keepRemote,
                onTap: hasServerCopy
                    ? () => onChoice(SyncConflictResolution.keepRemote)
                    : null,
              ),
              // The sync layer carries whole record versions, not a field
              // merge. The chip is visible so the choice is not hidden, and
              // the tooltip explains why it cannot be selected.
              Tooltip(
                message: l.syncConflictMergeHint,
                child: Opacity(
                  opacity: 0.45,
                  child: DsChip(label: l.mergeConflict),
                ),
              ),
            ],
          ),
          if (!hasServerCopy)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                l.syncConflictRemoteUnavailable,
                style: const TextStyle(
                  fontSize: 10,
                  height: 1.45,
                  color: SpecTokens.faint,
                  fontFamilyFallback: AppTypography.fallback,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _title(AppLocalizations l, SyncConflict conflict) {
    final payload = conflict.localPayload ?? conflict.serverPayload;
    if (payload != null) {
      for (final key in const ['summary', 'name', 'fileName']) {
        final value = payload[key];
        if (value is String && value.isNotEmpty) return value;
      }
    }
    return l.syncConflictRecord(
      _shortId(conflict.recordId),
      conflict.type?.name ?? 'record',
    );
  }

  static String _shortId(String id) => id.length <= 8 ? id : id.substring(0, 8);

  static String _describe(
    AppLocalizations l,
    RecordType? type,
    Map<String, Object?>? payload,
  ) {
    if (payload == null) return '';
    final parts = <String>[];
    void add(String label, Object? value) {
      if (value == null || '$value'.isEmpty) return;
      parts.add('$label $value');
    }

    String? time(Object? value) {
      if (value is! String) return null;
      final parsed = DateTime.tryParse(value);
      return parsed == null
          ? value
          : DateFormatters.formatDateTime(parsed.toLocal());
    }

    switch (type) {
      case RecordType.event:
        add(l.startTime, time(payload['startDt']));
        add(l.endTime, time(payload['endDt']));
      case RecordType.todo:
        add(l.deadlineRow, time(payload['dueDate']));
        add(l.priority, payload['priority']);
      case RecordType.reminder:
        add(l.reminder, time(payload['triggerTime']));
      case RecordType.tag:
        add(l.tags, payload['name']);
      case RecordType.attachment:
        add(l.attachments, payload['fileName']);
      case RecordType.taskAllocation:
        add(l.startTime, time(payload['startAt']));
        add(l.endTime, time(payload['endAt']));
      case RecordType.taskInstanceState:
      case RecordType.tagAssociation:
      case null:
        break;
    }
    if (parts.isEmpty) {
      final deletedAt = payload['deletedAt'];
      if (deletedAt != null) parts.add(l.deleted);
    }
    return parts.join(' · ');
  }
}
