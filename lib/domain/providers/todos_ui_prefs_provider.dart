import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _sixThingsKey = 'six_things_mode';
const _hideCompletedKey = 'hide_completed';

/// Six Things is a toggle the user flips and expects to see immediately.
///
/// It used to be a FutureProvider that the setter invalidated, so every tap
/// went back to `loading` and the list flashed to the full length before
/// collapsing again. The preference is now held in state: the tap updates it
/// first, persistence follows.
class SixThingsModeNotifier extends Notifier<bool> {
  @override
  bool build() {
    Future.microtask(_load);
    return false;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getBool(_sixThingsKey);
      if (stored != null) state = stored;
    } catch (error) {
      debugPrint('six things preference: $error');
    }
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_sixThingsKey, enabled);
    } catch (error) {
      debugPrint('six things preference: $error');
    }
  }
}

final sixThingsModeProvider = NotifierProvider<SixThingsModeNotifier, bool>(
  SixThingsModeNotifier.new,
);

final hideCompletedProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_hideCompletedKey) ?? false;
});

final setHideCompletedProvider = Provider<Future<void> Function(bool)>((ref) {
  return (bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hideCompletedKey, enabled);
    ref.invalidate(hideCompletedProvider);
  };
});
