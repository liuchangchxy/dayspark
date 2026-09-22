import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/domain/providers/feature_flags_provider.dart';
import 'package:dayspark/domain/providers/sync_client_provider.dart';
import 'package:dayspark/domain/sync/sync_api_client.dart';
import 'package:dayspark/domain/sync/sync_config.dart';

enum AccountAuthError {
  invalidUrl,
  invalidEmail,
  passwordRequired,
  passwordTooShort,
  emailExists,
  invalidCredentials,
  failed,
}

class AccountAuthState {
  const AccountAuthState({this.email, this.busy = false, this.error});

  /// Non-null only while tokens are configured — the logged-in signal.
  final String? email;
  final bool busy;
  final AccountAuthError? error;

  AccountAuthState copyWith({String? email, bool? busy, AccountAuthError? error}) {
    return AccountAuthState(
      email: email ?? this.email,
      busy: busy ?? this.busy,
      error: error,
    );
  }
}

/// Builds the auth client for a server base URL — the test seam that
/// swaps dio out for a fake without touching the network.
final accountAuthApiFactoryProvider = Provider<AuthApi Function(String baseUrl)>((
  ref,
) {
  return (baseUrl) => AuthSyncApiClient(
    transport: DioSyncTransport(baseUrl: baseUrl),
    tokens: ref.read(syncTokenStoreProvider),
  );
});

const _accountEmailKey = 'account_email';

class AccountAuthNotifier extends AsyncNotifier<AccountAuthState> {
  @override
  Future<AccountAuthState> build() async {
    var configured = false;
    try {
      configured = await ref.read(syncTokenStoreProvider).isConfigured();
    } catch (_) {
      // Secure storage unavailable (tests / web cold start) = logged out.
    }
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_accountEmailKey);
    return AccountAuthState(email: configured ? email : null);
  }

  Future<void> login({
    required String serverUrl,
    required String email,
    required String password,
  }) =>
      _authenticate(
        registering: false,
        serverUrl: serverUrl,
        email: email,
        password: password,
      );

  Future<void> register({
    required String serverUrl,
    required String email,
    required String password,
  }) =>
      _authenticate(
        registering: true,
        serverUrl: serverUrl,
        email: email,
        password: password,
      );

  Future<void> _authenticate({
    required bool registering,
    required String serverUrl,
    required String email,
    required String password,
  }) async {
    final previous = state.valueOrNull ?? const AccountAuthState();
    final normalizedUrl = _normalizeServerUrl(serverUrl);
    final validation = _validate(
      normalizedUrl: normalizedUrl,
      email: email,
      password: password,
      requireStrongPassword: registering,
    );
    if (validation != null) {
      state = AsyncData(previous.copyWith(error: validation));
      return;
    }
    state = const AsyncData(AccountAuthState(busy: true));
    final trimmedEmail = email.trim();
    try {
      final api = ref.read(accountAuthApiFactoryProvider)(normalizedUrl!);
      final session = registering
          ? await api.register(email: trimmedEmail, password: password)
          : await api.login(email: trimmedEmail, password: password);
      await ref
          .read(syncTokenStoreProvider)
          .saveTokens(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
          );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_accountEmailKey, trimmedEmail);
      await PrefsSyncConfigStore(prefs).save(
        SyncConfig(baseUrl: normalizedUrl),
      );
      await ref.read(setFeatureFlagProvider)(FeatureFlag.sync, true);
      await _restartEngine();
      state = AsyncData(AccountAuthState(email: trimmedEmail));
    } on SyncApiException catch (e) {
      state = AsyncData(previous.copyWith(error: _mapApiError(e)));
    } catch (_) {
      state = AsyncData(previous.copyWith(error: AccountAuthError.failed));
    }
  }

  Future<void> logout() async {
    state = const AsyncData(AccountAuthState(busy: true));
    await ref.read(syncTokenStoreProvider).clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accountEmailKey);
    await ref.read(setFeatureFlagProvider)(FeatureFlag.sync, false);
    // T5 carry: engine only runs when tokens exist — invalidate so the
    // old instance stops and the next build comes up unauthenticated
    // (syncStatusProvider watches it and resets to a fresh status).
    ref.invalidate(syncEngineProvider);
    state = const AsyncData(AccountAuthState());
  }

  Future<void> _restartEngine() async {
    ref.invalidate(syncSettingsProvider);
    await ref.read(syncSettingsProvider.future);
    ref.invalidate(syncEngineProvider);
    final engine = ref.read(syncEngineProvider);
    // The provider's own start() kicks the first round once tokens exist;
    // requestRound here covers the manual Sync-now expectation directly.
    if (engine != null) await engine.requestRound();
  }

  AccountAuthError? _validate({
    required String? normalizedUrl,
    required String email,
    required String password,
    required bool requireStrongPassword,
  }) {
    if (normalizedUrl == null) return AccountAuthError.invalidUrl;
    if (!_isEmail(email.trim())) return AccountAuthError.invalidEmail;
    if (password.isEmpty) return AccountAuthError.passwordRequired;
    if (requireStrongPassword && password.length < 8) {
      return AccountAuthError.passwordTooShort;
    }
    return null;
  }

  AccountAuthError? _mapApiError(SyncApiException e) {
    if (e.statusCode == 409) return AccountAuthError.emailExists;
    if (e.statusCode == 401) return AccountAuthError.invalidCredentials;
    return AccountAuthError.failed;
  }
}

/// Returns the URL with trailing slashes stripped, or null when it is
/// not an absolute http(s) address.
String? _normalizeServerUrl(String raw) {
  var url = raw.trim();
  if (url.isEmpty) return null;
  url = url.replaceAll(RegExp(r'/+$'), '');
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return null;
  if (!uri.isScheme('http') && !uri.isScheme('https')) return null;
  return url;
}

bool _isEmail(String value) => value.isNotEmpty && value.contains('@');

final accountAuthProvider =
    AsyncNotifierProvider<AccountAuthNotifier, AccountAuthState>(
      AccountAuthNotifier.new,
    );
