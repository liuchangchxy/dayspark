import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum FeatureFlag { aiAssistant, attachments, caldavSync, notifications }

class FeatureFlags {
  final Map<FeatureFlag, bool> _flags;

  FeatureFlags(this._flags);

  bool isEnabled(FeatureFlag flag) => _flags[flag] ?? true;

  FeatureFlags withFlag(FeatureFlag flag, bool enabled) {
    return FeatureFlags({..._flags, flag: enabled});
  }
}

final featureFlagsProvider = FutureProvider<FeatureFlags>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return FeatureFlags({
    for (final flag in FeatureFlag.values)
      flag: prefs.getBool('feature_${flag.name}') ?? true,
  });
});

final setFeatureFlagProvider =
    Provider<Future<void> Function(FeatureFlag, bool)>((ref) {
      return (FeatureFlag flag, bool enabled) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('feature_${flag.name}', enabled);
        ref.invalidate(featureFlagsProvider);
      };
    });
