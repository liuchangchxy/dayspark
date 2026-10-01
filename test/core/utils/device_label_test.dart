import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/core/utils/device_label.dart';

void main() {
  test('设备名非空且落在已知集合内', () {
    final name = deviceDisplayName();
    expect(name, isNotEmpty);
    expect(
      name,
      anyOf(
        'Web', 'Android', 'iOS', 'macOS', 'Windows', 'Linux', 'Fuchsia',
      ),
    );
  });

  test('debugDefaultTargetPlatformOverride 生效时跟着变（说明读的是平台而非写死）', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(deviceDisplayName(), 'iOS');
  });

  test('kIsWeb 必须优先于平台判断（web 上 defaultTargetPlatform 会按 UA 返回手机平台）', () {
    // 纯逻辑断言：源码里 kIsWeb 那一行必须在 switch 之前。
    // 这条守的是「浏览器会话被标成 Android」这个具体错法。
    final source = _readSource();
    final webIndex = source.indexOf('if (kIsWeb)');
    final switchIndex = source.indexOf('switch (defaultTargetPlatform)');
    expect(webIndex, isNonNegative, reason: 'kIsWeb 分支必须存在');
    expect(switchIndex, isNonNegative, reason: '平台分支必须存在');
    expect(webIndex, lessThan(switchIndex), reason: 'kIsWeb 必须在最前');
  });
}

String _readSource() {
  // 从任意嵌套目录向上找仓库根，和其余守卫同一套做法。
  var dir = Directory.current.absolute;
  while (true) {
    final candidate = File('${dir.path}/lib/core/utils/device_label.dart');
    if (candidate.existsSync()) return candidate.readAsStringSync();
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('找不到 lib/core/utils/device_label.dart');
    }
    dir = parent;
  }
}
