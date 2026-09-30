// l10n 键对齐守卫：app_en.arb 与 app_zh.arb 的键集必须双向完全一致。
// 漏译（主语言有、目标语言无）在运行期只会静默回退到主语言，肉眼极难发现；
// 废弃键（删了调用点却留着 key）则会随时间累积成死字典。
// 两者都在这里物理拦下——这是「新增功能不漏翻」的唯一自动化保障。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const List<String> _locales = ['en', 'zh'];

/// 元数据键（`@foo` / `@@locale`）描述消息本身，不参与对齐。
Set<String> messageKeys(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

/// 返回 [missing, stale]：目标语言缺失的键、目标语言多余的键。
List<Set<String>> diffKeys(Set<String> base, Set<String> target) => [
  base.difference(target),
  target.difference(base),
];

String? resolveRepoRoot([Directory? from]) {
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
  test('守卫自证：违规样本红、合规样本绿', () {
    final base = {'a', 'b', 'c'};
    final target = {'a', 'c', 'd'};
    final result = diffKeys(base, target);
    expect(result[0], {'b'}, reason: '漏译必须被抓到');
    expect(result[1], {'d'}, reason: '废弃键必须被抓到');
    expect(diffKeys(base, base).every((s) => s.isEmpty), isTrue, reason: '齐平不得报红');
    expect(
      messageKeys({'@@locale': 'en', 'a': 'A', '@a': {'x': 1}}),
      {'a'},
      reason: '元数据键不得参与对齐',
    );
  });

  test('en 与 zh 的字典键集双向对齐', () {
    final root = resolveRepoRoot();
    expect(root, isNotNull, reason: '找不到仓库根（pubspec.yaml + lib/）');

    final byLocale = <String, Set<String>>{};
    for (final locale in _locales) {
      final file = File('$root/lib/l10n/app_$locale.arb');
      expect(file.existsSync(), isTrue, reason: '缺少 ${file.path}');
      byLocale[locale] = messageKeys(
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
      );
    }

    final base = byLocale['en']!;
    final failures = <String>[];
    for (final locale in _locales.where((l) => l != 'en')) {
      final diff = diffKeys(base, byLocale[locale]!);
      if (diff[0].isNotEmpty) {
        failures.add('$locale 漏译 ${diff[0].length} 个键：${(diff[0].toList()..sort()).join(', ')}');
      }
      if (diff[1].isNotEmpty) {
        failures.add('$locale 残留废弃键 ${diff[1].length} 个：${(diff[1].toList()..sort()).join(', ')}');
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}
