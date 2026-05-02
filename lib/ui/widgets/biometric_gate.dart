import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/domain/providers/biometric_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';

class BiometricGate extends ConsumerStatefulWidget {
  final Widget child;

  const BiometricGate({super.key, required this.child});

  @override
  ConsumerState<BiometricGate> createState() => _BiometricGateState();
}

class _BiometricGateState extends ConsumerState<BiometricGate>
    with WidgetsBindingObserver {
  bool _authenticated = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initAuth();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _initAuth() async {
    final available = ref.read(isBiometricAvailableProvider).valueOrNull ?? false;
    if (!available) {
      setState(() {
        _initialized = true;
        _authenticated = true;
      });
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('biometric_lock_enabled') ?? false;
    ref.read(biometricLockEnabledProvider.notifier).state = enabled;

    if (!enabled) {
      setState(() {
        _initialized = true;
        _authenticated = true;
      });
      return;
    }

    final ok = await _authenticate();
    if (mounted) {
      setState(() {
        _initialized = true;
        _authenticated = ok;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final enabled = ref.read(biometricLockEnabledProvider);
      if (enabled && _authenticated) {
        setState(() => _authenticated = false);
        _authenticate();
      }
    }
  }

  Future<bool> _authenticate() async {
    final l = AppLocalizations.of(context);
    final auth = LocalAuthentication();
    try {
      return await auth.authenticate(
        localizedReason: l?.biometricPrompt ?? 'Unlock DaySpark',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Scaffold(
        body: Center(child: CupertinoActivityIndicator()),
      );
    }

    final enabled = ref.watch(biometricLockEnabledProvider);
    if (!enabled || _authenticated) {
      return widget.child;
    }

    final l = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: GestureDetector(
          onTap: () async {
            final ok = await _authenticate();
            if (ok && mounted) {
              setState(() => _authenticated = true);
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.lock,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                l?.biometricLock ?? 'Biometric Lock',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                l?.biometricPrompt ?? 'Unlock DaySpark',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
