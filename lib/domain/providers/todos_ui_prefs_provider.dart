import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _sixThingsKey = 'six_things_mode';
const _hideCompletedKey = 'hide_completed';

final sixThingsModeProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_sixThingsKey) ?? false;
});

final setSixThingsModeProvider =
    Provider<Future<void> Function(bool)>((ref) {
      return (bool enabled) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_sixThingsKey, enabled);
        ref.invalidate(sixThingsModeProvider);
      };
    });

final hideCompletedProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_hideCompletedKey) ?? false;
});

final setHideCompletedProvider =
    Provider<Future<void> Function(bool)>((ref) {
      return (bool enabled) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_hideCompletedKey, enabled);
        ref.invalidate(hideCompletedProvider);
      };
    });
