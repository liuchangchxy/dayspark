import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

final biometricLockEnabledProvider = StateProvider<bool>((ref) => false);

final isBiometricAvailableProvider = FutureProvider<bool>((ref) async {
  final auth = LocalAuthentication();
  try {
    return await auth.canCheckBiometrics && await auth.isDeviceSupported();
  } catch (_) {
    return false;
  }
});
