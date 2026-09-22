import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/domain/providers/account_provider.dart';
import 'package:dayspark/domain/providers/sync_client_provider.dart';
import 'package:dayspark/domain/sync/sync_engine.dart';
import 'package:dayspark/l10n/app_localizations.dart';

class AccountSection extends ConsumerStatefulWidget {
  const AccountSection({super.key});

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
      final settings = await ref.read(syncSettingsProvider.future);
      if (!_urlPrefilled && mounted && settings.baseUrl != null) {
        _serverUrlController.text = settings.baseUrl!;
        _urlPrefilled = true;
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
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(l.account, style: Theme.of(context).textTheme.titleSmall),
        ),
        ...account.when(
          data: (state) => state.email == null
              ? _buildLoggedOut(l, state)
              : _buildLoggedIn(l, state),
          loading: () => const [SizedBox.shrink()],
          error: (_, __) => _buildLoggedOut(l, const AccountAuthState()),
        ),
      ],
    );
  }

  List<Widget> _buildLoggedOut(AppLocalizations l, AccountAuthState state) {
    final error = state.error;
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _serverUrlController,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: l.serverUrl,
                hintText: 'https://sync.example.com',
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: l.email,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passwordController,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: l.password,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorText(l, error),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (state.busy)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: OutlinedButton(
                      onPressed: state.busy
                          ? null
                          : () => _submit(registering: true),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      child: Text(l.register),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: FilledButton(
                      onPressed: state.busy
                          ? null
                          : () => _submit(registering: false),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      child: Text(l.login),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildLoggedIn(AppLocalizations l, AccountAuthState state) {
    final status = ref.watch(syncStatusProvider);
    final engine = ref.watch(syncEngineProvider);
    return [
      ListTile(
        leading: const Icon(CupertinoIcons.person_crop_circle),
        title: Text(state.email!),
        subtitle: Text(_statusText(l, status)),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: Tooltip(
                message: l.syncTooltip,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: OutlinedButton.icon(
                    onPressed: engine == null
                        ? null
                        : () => unawaited(engine.requestRound()),
                    icon: const Icon(CupertinoIcons.refresh, size: 18),
                    label: Text(l.syncNow),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: OutlinedButton(
                onPressed: state.busy
                    ? null
                    : () => unawaited(
                        ref.read(accountAuthProvider.notifier).logout(),
                      ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                ),
                child: Text(l.logout),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
    ];
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

  String _statusText(AppLocalizations l, SyncStatus status) {
    final phase = switch (status.phase) {
      SyncPhase.idle => l.syncPhaseIdle,
      SyncPhase.pushing => l.syncing,
      SyncPhase.pulling => l.syncPulling,
      SyncPhase.error => l.syncPhaseError,
    };
    final last = status.lastSyncAt;
    if (last == null) return phase;
    return '$phase · ${l.lastSync(DateFormatters.formatRelativeTime(last, l))}';
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
