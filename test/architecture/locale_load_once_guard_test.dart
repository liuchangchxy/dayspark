// 守卫：根 build 不得调用 localeProvider.notifier.load()。
//
// load() 写 state → 根部重建 → 又调 load() → 无限循环。
// provider 已经在创建时 ..load()，build 里再调就是 bug。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String? _resolveRepoRoot([Directory? from]) {
  var dir = (from ?? Directory.current).absolute;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        Directory('${dir.path}/lib').existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

void main() {
  test('main.dart 根 build 里不能出现 localeProvider.notifier).load(', () {
    final root = _resolveRepoRoot();
    expect(root, isNotNull, reason: '找不到仓库根（pubspec.yaml + lib/）');
    final source = File('$root/lib/main.dart').readAsStringSync();

    // Match the pattern: localeProvider.notifier).load(
    // This catches ref.read(localeProvider.notifier).load() in any form.
    final pattern = RegExp(r'localeProvider\.notifier\)\.load\s*\(');
    expect(
      pattern.hasMatch(source),
      isFalse,
      reason:
          'localeProvider.notifier.load() 不应出现在 build() 里——'
          'provider 创建时已 ..load()，build 里调会导致无限重建循环',
    );
  });
}
