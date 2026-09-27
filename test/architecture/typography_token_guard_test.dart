// 字号守卫：DESIGN.md 字阶只认 {10, 12, 14, 16, 20}。
// `fontSize:` 后跟数字面量不在字阶里即红；token/变量引用不参与判定。
// 已知限制：`fontSize:` 写在注释里也会红（宁枉勿纵，见 web_platform_guard 同款披露）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const List<double> _scale = [10, 12, 14, 16, 20];

final RegExp _fontSize = RegExp(r'fontSize\s*:\s*(\d+(?:\.\d+)?)');
final RegExp _commentOnly = RegExp(r'^\s*//');

/// 返回该行源码中的违规说明，无违规返回 null。
String? fontSizeViolation(String line) {
  if (_commentOnly.hasMatch(line)) return null;
  final m = _fontSize.firstMatch(line);
  if (m == null) return null;
  final v = double.parse(m.group(1)!);
  return _scale.contains(v) ? null : '${m.group(1)} not in type scale';
}

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
    expect(fontSizeViolation('fontSize: 13,'), isNotNull);
    expect(fontSizeViolation('fontSize: 11,'), isNotNull);
    expect(fontSizeViolation('fontSize: 7,'), isNotNull);
    expect(fontSizeViolation('const TextStyle(fontSize: 12)'), isNull);
    expect(fontSizeViolation('fontSize: 16,'), isNull);
    expect(
      fontSizeViolation(
        'fontSize: Theme.of(context).textTheme.bodySmall?.fontSize,',
      ),
      isNull,
    );
  });

  test('lib/** 字号全在字阶内', () {
    final root = resolveRepoRoot();
    expect(root, isNotNull, reason: '找不到仓库根（pubspec.yaml + lib/）');
    final bad = <String>[];
    for (final entity in Directory('$root/lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final rel = entity.path.substring(root!.length + 1);
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final v = fontSizeViolation(lines[i]);
        if (v != null) bad.add('$rel:${i + 1}: $v');
      }
    }
    expect(bad, isEmpty, reason: 'off-scale 字号：\n${bad.join('\n')}');
  });
}
