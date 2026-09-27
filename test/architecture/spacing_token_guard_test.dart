// 间距守卫：DESIGN.md 规定基础单位 4px，所有间距为 4 的倍数。
// spacing 上下文（EdgeInsets.* / SizedBox( / Wrap spacing/runSpacing）里出现
// 非 4 倍数的数字面量即红。跨行调用按括号配平抓整个 span，不止看单行。
// 已知限制（据实披露，不假装覆盖）：
// * 只认数字面量 —— `AppSpacing.sm` 这类 token 引用不参与判定（那正是我们想要的写法）。
// * `letterSpacing`/`wordSpacing` 因大小写不在匹配面；真有人写 `spacing:` 给文字用，
//   报错信息带行号，人工看一眼即可。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final RegExp _callStart = RegExp(r'(EdgeInsets\s*\.\s*\w+\s*\(|SizedBox\s*\()');
final RegExp _wrapSpacing = RegExp(
  r'(?:runSpacing|spacing)\s*:\s*(\d+(?:\.\d+)?)',
);
final RegExp _number = RegExp(r'\d+(?:\.\d+)?');

bool _isOffScale(String literal) {
  final v = double.parse(literal);
  return v != 0 && v % 4 != 0;
}

/// 返回该文件源码中所有违规点的 `<行号>: <说明>`。
/// 只查调用的顶层参数：嵌套子组件里的数字（strokeWidth、fontSize、alpha…）
/// 不归间距管，自有各自的规范。
List<String> spacingViolations(String src) {
  final hits = <String>[];
  for (final m in _callStart.allMatches(src)) {
    var depth = 0;
    var end = -1;
    for (var i = m.start; i < src.length; i++) {
      if (src[i] == '(') depth++;
      if (src[i] == ')') {
        depth--;
        if (depth == 0) {
          end = i;
          break;
        }
      }
    }
    if (end < 0) continue;
    final span = src.substring(m.start, end + 1);
    var d = 0;
    var token = '';
    void flushToken() {
      if (token.isNotEmpty && d == 1 && _number.hasMatch(token)) {
        final v = token;
        if (_isOffScale(v)) {
          final line = src.substring(0, m.start).split('\n').length;
          hits.add('$line: $v in ${span.split('\n').first.trim()}…');
        }
      }
      token = '';
    }

    for (var i = 0; i < span.length; i++) {
      final c = span[i];
      if (c == '(' || c == '[') {
        d++;
        token = '';
      } else if (c == ')' || c == ']') {
        flushToken();
        d--;
      } else if (c == ',' || c == ':' || c == ' ') {
        flushToken();
      } else {
        token += c;
      }
    }
    flushToken();
  }
  for (final m in _wrapSpacing.allMatches(src)) {
    if (_isOffScale(m.group(1)!)) {
      final line = src.substring(0, m.start).split('\n').length;
      hits.add('$line: ${m.group(1)} in ${m.group(0)}');
    }
  }
  return hits;
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
      spacingViolations(
        'padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),',
      ),
      isNotEmpty,
    );
    expect(
      spacingViolations(
        'padding: const EdgeInsets.symmetric(\n  horizontal: 10,\n  vertical: 6,\n),',
      ),
      isNotEmpty,
    );
    expect(spacingViolations('spacing: 6,'), isNotEmpty);
    expect(
      spacingViolations(
        'padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),',
      ),
      isEmpty,
    );
    expect(spacingViolations('const SizedBox(width: 8),'), isEmpty);
    expect(
      spacingViolations('borderRadius: BorderRadius.circular(6),'),
      isEmpty,
    );
    expect(spacingViolations('fontSize: 11,'), isEmpty);
    expect(
      spacingViolations(
        'const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))',
      ),
      isNotEmpty,
    );
    expect(
      spacingViolations(
        'const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))',
      ),
      isEmpty,
    );
  });

  test('lib/** 无 off-scale 间距面量', () {
    final root = resolveRepoRoot();
    expect(root, isNotNull, reason: '找不到仓库根（pubspec.yaml + lib/）');
    final bad = <String>[];
    for (final entity in Directory('$root/lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final rel = entity.path.substring(root!.length + 1);
      final src = entity.readAsStringSync();
      for (final v in spacingViolations(src)) {
        bad.add('$rel:$v');
      }
    }
    expect(bad, isEmpty, reason: 'off-scale 间距：\n${bad.join('\n')}');
  });
}
