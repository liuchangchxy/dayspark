import 'dart:io';

import 'package:dayspark/core/utils/platform_target.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('platform_target', () {
    // 覆盖边界（据实披露，别当它证明了更多）：VM 上 kIsWeb 恒为 false，
    // 所以这里证明的是"非 web 平台语义零变化"；web 分支与"两个 getter 互相接错线"
    // 都不在本测试射程内（同平台上两值皆为 false），后者由
    // test/architecture/web_platform_guard_test.dart 的逐字钉住负责。
    test('VM 上（kIsWeb == false）与 Platform.* 原表达式逐位等价', () {
      expect(isAndroid, Platform.isAndroid);
      expect(isIOS, Platform.isIOS);
      expect(isNativeMobile, Platform.isAndroid || Platform.isIOS);
    });

    test('home_widget 仅支持非 Web Android 和 iOS', () {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        expect(
          homeWidgetPlatformOn(isWeb: false, platform: platform),
          platform,
        );
      }
      for (final platform in [
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.fuchsia,
      ]) {
        expect(homeWidgetPlatformOn(isWeb: false, platform: platform), isNull);
      }
      expect(
        homeWidgetPlatformOn(isWeb: true, platform: TargetPlatform.android),
        isNull,
      );
    });
  });
}
