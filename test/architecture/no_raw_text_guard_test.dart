// 裸文案守卫：lib/ 下（除 l10n/）不得出现面向用户的中文字面量。
// 中文是主语言，所以「裸写中文」就是「绕过字典」的最典型形态——它在开发期
// 看得见、切到英文就露馅，而且往往等到用户投诉才发现。
//
// 豁免走白名单且必须写 WHY；白名单按文件路径匹配，并反向校验豁免项仍然成立
// （豁免对象消失却留着条目 = 死豁免，同样报红）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final RegExp _cjk = RegExp(r'[一-鿿]');
final RegExp _comment = RegExp(r'^\s*(//|///|\*|/\*)');

/// 文件 → 豁免理由。只收「不是面向用户文案」的几类。
const Map<String, String> _allowlist = {
  'lib/domain/records/record_scope.dart':
      '开发者断言消息（ArgumentError），面向维护者不面向用户',
  'lib/domain/records/record_bus.dart':
      '开发者断言消息（ArgumentError），面向维护者不面向用户',
  'lib/domain/providers/theme_provider.dart':
      'AppAccent 自带 zhName/enName 双名、由 nameFor(locale) 选取——已是封闭类型双语，不经字典',
  'lib/core/l10n/locale_aware_rrule_delegate.dart':
      'rrule_generator 的 RRuleTextDelegate 只收裸字符串（第三方接口限制），'
          '故中英两套在此内联并由 _isChinese 选取——见 docs/CONSTRAINTS.md',
  'lib/ui/widgets/calendar/marked_month_day_header.dart':
      '节气名是 lunar 包的返回值（数据键），值走 l10n 的 termXxx——查表输入不是文案',
};

/// 违规行：非注释且含中文。
bool isRawTextLine(String line) =>
    !_comment.hasMatch(line) && _cjk.hasMatch(line);

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

/// 只扫 **git 跟踪**的文件。
///
/// 走文件系统会把本机生成物一起扫进来（例如 `lib/oss_licenses.dart` 是
/// gitignore 的生成文件，CI 的干净检出里根本不存在）——于是本地绿、CI 红，
/// 或者反过来：白名单条目在本地有对象、在 CI 看就是「死豁免」。
/// 跟踪文件恰好等于「这个项目自己写的文件」，这才是本守卫的扫描面。
Map<String, List<int>> scanRoot(String root) {
  final listed = Process.runSync(
    'git',
    const ['ls-files', '-z', 'lib'],
    workingDirectory: root,
  ).stdout as String;
  final hits = <String, List<int>>{};
  for (final rel in listed.split('\u0000')) {
    if (rel.isEmpty || !rel.endsWith('.dart')) continue;
    if (rel.startsWith('lib/l10n/')) continue;
    final file = File('$root/$rel');
    if (!file.existsSync()) continue;
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      if (isRawTextLine(lines[i])) {
        hits.putIfAbsent(rel, () => []).add(i + 1);
      }
    }
  }
  return hits;
}

/// 拼出被测行，避免在样本里嵌套引号。
String _line(String call) => '  $call,';

void main() {
  test('守卫自证：违规样本红、合规样本绿', () {
    expect(isRawTextLine(_line("Text('保存')")), isTrue, reason: '裸中文必须被抓到');
    expect(isRawTextLine('  // 中文注释'), isFalse, reason: '注释不是文案');
    expect(isRawTextLine('  /// 中文文档注释'), isFalse, reason: '文档注释不是文案');
    expect(isRawTextLine('  Text(l.save),'), isFalse, reason: '走字典不得报红');
    expect(isRawTextLine(_line('Text("Save")')), isFalse, reason: '英文不是本守卫的目标（主语言是中文）');
  });

  test('lib/ 下无未豁免的裸中文文案', () {
    final root = resolveRepoRoot();
    expect(root, isNotNull, reason: '找不到仓库根（pubspec.yaml + lib/）');

    final hits = scanRoot(root!);
    final violations = hits.entries
        .where((e) => !_allowlist.containsKey(e.key))
        .map((e) => '${e.key}: 第 ${e.value.join(', ')} 行')
        .toList();
    expect(
      violations,
      isEmpty,
      reason: '发现裸中文文案——请走 l10n 字典，或把文件加进 _allowlist 并写明 WHY：\n'
          '${violations.join('\n')}',
    );
  });

  test('白名单无死豁免', () {
    final root = resolveRepoRoot();
    expect(root, isNotNull);
    final hits = scanRoot(root!);
    final stale = _allowlist.keys.where((path) => !hits.containsKey(path)).toList();
    expect(
      stale,
      isEmpty,
      reason: '这些文件已不再含中文，豁免条目应删除：\n${stale.join('\n')}',
    );
  });
}
