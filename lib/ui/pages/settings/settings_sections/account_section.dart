import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/domain/providers/account_provider.dart';
import 'package:dayspark/domain/providers/sync_client_provider.dart';
import 'package:dayspark/domain/sync/sync_engine.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/ui/design/ds.dart';
import '../settings_ui.dart';

class AccountSection extends ConsumerStatefulWidget {
  const AccountSection({super.key, this.showHeader = false});

  /// True when the section is rendered on its own rather than inside a
  /// labelled group card.
  final bool showHeader;

  @override
  ConsumerState<AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends ConsumerState<AccountSection> {
  final _serverUrlController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  var _urlPrefilled = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      try {
        final settings = await ref.read(syncSettingsProvider.future);
        if (!_urlPrefilled && mounted && settings.baseUrl != null) {
          _serverUrlController.text = settings.baseUrl!;
          _urlPrefilled = true;
        }
      } catch (e) {
        debugPrint('account: server URL prefill error: $e');
      }
    });
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final account = ref.watch(accountAuthProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showHeader)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: Text(
              l.account,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: context.ds.ink,
              ),
            ),
          ),
        // A failure to read the account is not the same as being logged out:
        // showing the sign-in form would invite a second login over a session
        // that still exists.
        ...account.when(
          data: (state) => [
            state.email == null
                ? _buildLoggedOut(l, state)
                : _buildLoggedIn(l, state),
          ],
          loading: () => const [
            Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ],
          error: (error, _) {
            debugPrint('account: state error: $error');
            return [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.accountLoadFailed,
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => ref.invalidate(accountAuthProvider),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      child: Text(l.retry),
                    ),
                  ],
                ),
              ),
            ];
          },
        ),
      ],
    );
  }

  Widget _buildLoggedOut(AppLocalizations l, AccountAuthState state) {
    final ds = context.ds;
    final error = state.error;
    return SettingsRows(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Text(
            l.syncExplanation,
            style: TextStyle(fontSize: 12, height: 1.55, color: ds.ink3),
          ),
        ),
        _FieldRow(
          label: l.serverUrl,
          child: DsTextField(
            controller: _serverUrlController,
            hint: 'https://sync.example.com',
            keyboardType: TextInputType.url,
          ),
        ),
        _FieldRow(
          label: l.email,
          child: DsTextField(
            controller: _emailController,
            hint: 'you@example.com',
            keyboardType: TextInputType.emailAddress,
          ),
        ),
        _FieldRow(
          label: l.password,
          child: DsTextField(
            controller: _passwordController,
            obscureText: true,
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Text(
              _errorText(l, error),
              style: TextStyle(fontSize: 12, color: ds.danger),
            ),
          ),
        if (state.busy)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Row(
            children: [
              Expanded(
                child: DsButton(
                  label: l.register,
                  tone: DsButtonTone.secondary,
                  expand: true,
                  onPressed: state.busy
                      ? null
                      : () => _submit(registering: true),
                ),
              ),
              const SizedBox(width: AppSpacing.s2),
              Expanded(
                child: DsButton(
                  label: l.login,
                  expand: true,
                  onPressed: state.busy
                      ? null
                      : () => _submit(registering: false),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLoggedIn(AppLocalizations l, AccountAuthState state) {
    final status = ref.watch(syncStatusProvider);
    final engine = ref.watch(syncEngineProvider);
    final server = ref.watch(syncSettingsProvider).valueOrNull?.baseUrl;
    return SettingsRows(
      children: [
        SettingsRow(label: state.email!, value: _statusText(l, status)),
        if (server != null) SettingsRow(label: l.serverUrl, value: server),
        SettingsRow(
          label: l.connectedDevices,
          chevron: SettingsChevron.right,
          onTap: () => _showDevicesDialog(context),
        ),
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
                  : () => unawaited(engine.requestRound()),
            ),
          ),
        ),
        SettingsRow(
          label: l.logout,
          danger: true,
          chevron: SettingsChevron.right,
          onTap: state.busy ? null : () => _confirmLogout(l),
        ),
      ],
    );
  }

  /// Logging out stops sync on a device that may be the only place the data
  /// lives, so it is confirmed rather than fired on the first tap.
  Future<void> _confirmLogout(AppLocalizations l) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => DsDialog(
        title: l.signOutConfirm,
        width: 420,
        actions: [
          const Spacer(),
          DsButton(
            label: l.cancel,
            tone: DsButtonTone.ghost,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          const SizedBox(width: AppSpacing.s2),
          DsButton(
            label: l.signOut,
            tone: DsButtonTone.danger,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
        child: Text(
          l.signOutBody,
          style: TextStyle(fontSize: 14, height: 1.55, color: context.ds.ink2),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(accountAuthProvider.notifier).logout();
  }

  Future<void> _submit({required bool registering}) async {
    final notifier = ref.read(accountAuthProvider.notifier);
    final serverUrl = _serverUrlController.text;
    final email = _emailController.text;
    final password = _passwordController.text;
    if (registering) {
      await notifier.register(
        serverUrl: serverUrl,
        email: email,
        password: password,
      );
    } else {
      await notifier.login(
        serverUrl: serverUrl,
        email: email,
        password: password,
      );
    }
    final state = ref.read(accountAuthProvider).valueOrNull;
    if (state?.email != null) _passwordController.clear();
  }

  /// 已连接设备：列出本账号注册过的设备与最后活跃时间。
  ///
  /// 加载失败与"一台都没有"必须分开表达——把失败画成空白会让人以为设备丢了。
  void _showDevicesDialog(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (ctx) => DsDialog(
        title: l.connectedDevices,
        width: 460,
        actions: [
          const Spacer(),
          DsButton(
            label: l.ok,
            tone: DsButtonTone.ghost,
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
        child: Consumer(
          builder: (ctx, ref, _) {
            final devices = ref.watch(connectedDevicesProvider);
            return switch (devices) {
              AsyncData(:final value) when value.isEmpty => Text(
                l.devicesEmpty,
                style: TextStyle(fontSize: 13, color: context.ds.ink3),
              ),
              AsyncData(:final value) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final d in value)
                    DsSettingRow(
                      label: d.name ?? l.deviceUnknownName,
                      value: l.deviceLastSeen(
                        DateFormatters.formatRelativeTime(d.lastSeen, l),
                      ),
                    ),
                ],
              ),
              AsyncError() => Text(l.devicesLoadFailed),
              _ => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
            };
          },
        ),
      ),
    );
  }

  String _statusText(AppLocalizations l, SyncStatus status) {
    final phase = switch (status.phase) {
      SyncPhase.idle => l.syncPhaseIdle,
      SyncPhase.pushing => l.syncing,
      SyncPhase.pulling => l.syncPulling,
      SyncPhase.error => l.syncPhaseError,
    };
    final last = status.lastSyncAt;
    final base = last == null
        ? phase
        : '$phase · ${l.lastSync(DateFormatters.formatRelativeTime(last, l))}';
    // Rejected op verdicts would otherwise vanish (ops are dropped, the
    // round succeeds) — surface the raw codes on the status line.
    if (status.lastRejected.isEmpty) return base;
    return '$base · ${l.syncRejected(status.lastRejected.join(', '))}';
  }

  String _errorText(AppLocalizations l, AccountAuthError error) {
    return switch (error) {
      AccountAuthError.invalidUrl => l.serverUrlInvalid,
      AccountAuthError.invalidEmail => l.emailInvalid,
      AccountAuthError.passwordRequired => l.passwordRequired,
      AccountAuthError.passwordTooShort => l.passwordTooShort,
      AccountAuthError.emailExists => l.emailAlreadyRegistered,
      AccountAuthError.invalidCredentials => l.invalidCredentials,
      AccountAuthError.failed => l.authFailed,
    };
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption.copyWith(
                fontSize: 14,
                color: ds.ink2,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}
