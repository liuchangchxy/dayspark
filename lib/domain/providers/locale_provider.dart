import 'dart:ui' show Locale;

import 'package:flutter/widgets.dart'
    show WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key for the user-selected language code. Also read by
/// notification scheduling, which cannot take a BuildContext.
const appLocalePrefKey = 'app_locale';

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale?>((ref) {
  return LocaleNotifier();
});

class LocaleNotifier extends StateNotifier<Locale?> {
  LocaleNotifier() : super(null);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(appLocalePrefKey);
    if (code != null) {
      state = Locale(code);
    }
  }

  Future<void> setLocale(Locale? locale) async {
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove(appLocalePrefKey);
    } else {
      await prefs.setString(appLocalePrefKey, locale.languageCode);
    }
    state = locale;
  }
}

/// 解析当前生效的 App 语言：显式传入 → 持久化的 app locale → 系统 locale。
///
/// 供**拿不到 BuildContext** 的消费端使用——「文案已烘焙进系统的出口」正是这一类：
/// 通知（排期时写死）与 AI（prompt 里要声明回答语言）。UI 侧直接用
/// `AppLocalizations.of(context)` 即可，不要绕这一趟。
Future<Locale> resolveAppLocale({Locale? override}) async {
  if (override != null) return override;
  final prefs = await SharedPreferences.getInstance();
  final code = prefs.getString(appLocalePrefKey);
  if (code != null) return Locale(code);
  return WidgetsBinding.instance.platformDispatcher.locale;
}

/// 给模型看的语言名。
///
/// prompt 里写 `zh` 这种代码，模型未必稳定识别；写语言全名最稳。
/// 新增语言时在这里加一条——它是**封闭映射**，漏了会落到 languageCode 兜底。
String languageNameFor(Locale locale) {
  switch (locale.languageCode) {
    case 'zh':
      return 'Chinese (Simplified)';
    case 'en':
      return 'English';
    default:
      return locale.languageCode;
  }
}
