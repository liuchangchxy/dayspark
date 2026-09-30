// 圆角守卫：DESIGN.md 圆角只认 {8, 10, 12, 16}（16 为最大值），胶囊走 999。
// `BorderRadius.circular(N)` / `Radius.circular(N)` 的 N 不在集合里即红。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const List<double> _radii = [8, 10, 12, 16];

const Map<String, List<String>> _allowlist = {};

final RegExp _radius = RegExp(
  r'(?:BorderRadius|Radius)\.circular\(\s*(\d+(?:\.\d+)?)',
);
final RegExp _commentOnly = RegExp(r'^\s*//');

String? radiusViolation(String line) {
  if (_commentOnly.hasMatch(line)) return null;
  final m = _radius.firstMatch(line);
  if (m == null) return null;
  final v = double.parse(m.group(1)!);
  return _radii.contains(v) ? null : '${m.group(1)} not in radius scale';
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
    expect(
      radiusViolation('borderRadius: BorderRadius.circular(6),'),
      isNotNull,
    );
    expect(
      radiusViolation('borderRadius: BorderRadius.circular(28),'),
      isNotNull,
    );
    expect(radiusViolation('borderRadius: BorderRadius.circular(12),'), isNull);
    expect(radiusViolation('shape: const CircleBorder(),'), isNull);
  });

  test('lib/** 圆角全在规范内', () {
    final root = resolveRepoRoot();
    expect(root, isNotNull, reason: '找不到仓库根（pubspec.yaml + lib/）');
    final bad = <String>[];
    for (final entity in Directory('$root/lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final rel = entity.path.substring(root!.length + 1);
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final v = radiusViolation(lines[i]);
        if (v == null) continue;
        if ((_allowlist[rel] ?? []).any((a) => lines[i].contains(a))) continue;
        bad.add('$rel:${i + 1}: $v');
      }
    }
    expect(bad, isEmpty, reason: 'off-scale 圆角：\n${bad.join('\n')}');
  });
}
