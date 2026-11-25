import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/theme/spec_tokens.dart';
import 'package:dayspark/domain/providers/sync_client_provider.dart';
import 'package:dayspark/domain/sync/sync_engine.dart';
import 'package:dayspark/l10n/app_localizations.dart';

/// Shell-level sync state line: offline, failed, or conflicts pending
/// review. Hidden while sync is not configured or not logged in.
///
/// [short] uses the one-line mobile copy (`syncOfflineShort` /
/// `syncFailedShort` / `syncConflictShort`); the desktop banner keeps the
/// longer explanatory line.
class SyncStatusBanner extends ConsumerWidget {
  const SyncStatusBanner({super.key, this.short = false});

  final bool short;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(syncActiveProvider)) return const SizedBox.shrink();
    final l = AppLocalizations.of(context)!;
    final status = ref.watch(syncStatusProvider);
    final online = ref.watch(syncOnlineProvider).valueOrNull;
    final pending = ref.watch(pendingSyncOpsProvider).valueOrNull ?? 0;
    final conflicts = ref.watch(syncConflictCountProvider);

    if (online == false) {
      return _SyncBanner(
        message: short
            ? l.syncOfflineShort
            : pending > 0
            ? l.syncOfflinePending(pending)
            : l.syncOfflineBanner,
      );
    }
    if (status.phase == SyncPhase.error) {
      return _SyncBanner(
        title: l.syncPhaseError,
        message: short
            ? l.syncFailedShort
            : pending > 0
            ? l.syncPendingUploads(pending)
            : l.syncFailedBanner,
        isRed: true,
        action: TextButton(
          onPressed: () {
            final engine = ref.read(syncEngineProvider);
            if (engine != null && engine.isRunning) {
              unawaited(engine.requestRound());
            } else {
              ref.invalidate(syncEngineProvider);
            }
          },
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            foregroundColor: SpecTokens.red,
          ),
          child: Text(
            l.retryNow,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
        ),
      );
    }
    if (conflicts > 0) {
      return _SyncBanner(
        message: short ? l.syncConflictShort : l.syncConflictCount(conflicts),
        isRed: true,
      );
    }
    return const SizedBox.shrink();
  }
}

class _SyncBanner extends StatelessWidget {
  const _SyncBanner({
    required this.message,
    this.title,
    this.isRed = false,
    this.action,
  });

  final String message;
  final String? title;
  final bool isRed;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final borderColor = isRed ? SpecTokens.red : SpecTokens.ink;
    final background = isRed ? SpecTokens.redSoft : SpecTokens.wash;
    final textColor = isRed ? const Color(0xFF7C231B) : SpecTokens.ink2;

    return Container(
      decoration: BoxDecoration(
        color: background,
        border: Border(
          left: BorderSide(color: borderColor, width: isRed ? 3 : 2),
          bottom: const BorderSide(color: SpecTokens.hair),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Text(
                    title!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                      fontFamilyFallback: AppTypography.fallback,
                    ),
                  ),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.45,
                    color: textColor,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
              ],
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}
