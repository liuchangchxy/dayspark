import 'dart:io';

import 'package:flutter/foundation.dart';

/// Web-safe platform predicates. `dart:io`'s `Platform.*` throws
/// unconditionally in dart2js, so every read must short-circuit on `kIsWeb`.
/// Only file in `lib/` allowed to mention `Platform.*` — guard:
/// `test/architecture/web_platform_guard_test.dart`.
bool get isAndroid => !kIsWeb && Platform.isAndroid;

bool get isIOS => !kIsWeb && Platform.isIOS;

bool get isNativeMobile => isAndroid || isIOS;

bool get isWindows => !kIsWeb && Platform.isWindows;

TargetPlatform? homeWidgetPlatformOn({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  if (isWeb) return null;
  if (platform == TargetPlatform.android || platform == TargetPlatform.iOS) {
    return platform;
  }
  return null;
}

TargetPlatform? get homeWidgetPlatform =>
    homeWidgetPlatformOn(isWeb: kIsWeb, platform: defaultTargetPlatform);

bool get supportsHomeWidget => homeWidgetPlatform != null;
