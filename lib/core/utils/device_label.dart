import 'package:flutter/foundation.dart';

/// 人类可读的设备名，用于设备注册与「已连接设备」列表。
///
/// 用 `defaultTargetPlatform` 而不是 `Platform.*`：后者在 dart2js 下无条件抛，
/// 而 `lib/core/utils/platform_target.dart` 的守卫严格限制了 `Platform.*` 的
/// 出现位置与站点数，没必要为一个展示名去动那道守卫。
///
/// **`kIsWeb` 必须排在最前**：web 上 `defaultTargetPlatform` 会按 UA 返回
/// android/iOS，先判 web 才不会把浏览器会话标成手机。
String deviceDisplayName() {
  if (kIsWeb) return 'Web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'Android',
    TargetPlatform.iOS => 'iOS',
    TargetPlatform.macOS => 'macOS',
    TargetPlatform.windows => 'Windows',
    TargetPlatform.linux => 'Linux',
    TargetPlatform.fuchsia => 'Fuchsia',
  };
}
