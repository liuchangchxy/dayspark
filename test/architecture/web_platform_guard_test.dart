// Web 平台守卫：`dart:io` 的 `Platform.*` 在 dart2js 产物里是**一调用就抛**的 stub
// （v0.25.0 Web 白屏根因，见 DECISIONS.md 事故条目），因此 `lib/**` 里只允许
// `lib/core/utils/platform_target.dart` 读它，且每次读取必须与 `kIsWeb` 同行
// （短路在前才安全）。已知限制（据实披露，不假装覆盖）：
// * 以 `//` 开头的整行注释不参与匹配 —— 注释里写 `Platform.isAndroid` 不红；
//   行尾注释里的出现仍会红（宁枉勿纵，代码行才是危险面）。
// * 字符串字面量里的 `Platform.isAndroid`（如调试文案）会误报：改词即可，报错带可读行号。
// * `myPlatform.isWindows` 之类经别名的不匹配（正则要求 `Platform` 前是非标识符字符）；
//   本仓库 `lib/**` 无此写法。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _allowlistRelativePath = 'lib/core/utils/platform_target.dart';

/// 守卫的保证是"常见写法必红"，不是"证明没人碰过 Platform"。
const int _expectedGuardedReads = 2;

final RegExp _platformRead = RegExp(
  r'(?<![A-Za-z0-9_])Platform\s*\.\s*(is[A-Za-z]+|operatingSystem)\b',
);
final RegExp _commentOnly = RegExp(r'^\s*//');

bool isViolationLine(String line) =>
    !_commentOnly.hasMatch(line) && _platformRead.hasMatch(line);

bool isGuardedRead(String line) =>
    _platformRead.hasMatch(line) && line.contains('kIsWeb');

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

/// 返回 `<仓库相对路径>:<行号>: <源码>` 形式的违规清单，键为仓库相对路径。
Map<String, List<String>> platformHits(String root) {
  final hits = <String, List<String>>{};
  final libDir = Directory('$root/lib');
  if (!libDir.existsSync()) return hits;
  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final rel = entity.path.substring(root.length + 1);
    if (rel == _allowlistRelativePath) continue;
    final found = <String>[];
    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      if (isViolationLine(lines[i])) {
        found.add('$rel:${i + 1}: ${lines[i].trim()}');
      }
    }
    if (found.isNotEmpty) hits[rel] = found;
  }
  return hits;
}

/// 白名单文件里"读了 `Platform` 却没和 `kIsWeb` 同行"的行。
List<String> unguardedAllowlistedReads(String root) {
  final file = File('$root/$_allowlistRelativePath');
  if (!file.existsSync()) return const <String>[];
  final found = <String>[];
  final lines = file.readAsLinesSync();
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (isViolationLine(line) && !isGuardedRead(line)) {
      found.add('$_allowlistRelativePath:${i + 1}: ${line.trim()}');
    }
  }
  return found;
}

void main() {
  group('scanner selftest', () {
    test('违规样本必须命中', () {
      const violating = <String>[
        'if (!Platform.isAndroid && !Platform.isIOS) return;',
        '    if ( Platform . isIOS ) {',
        'warningNotificationOnKill: Platform.isIOS,',
        'final os = Platform.operatingSystem;',
        'if (Platform.isWindows) doThing();',
        'if (x) return; // Platform.isAndroid 行尾注释仍算违规',
        '  Platform.isMacOS ? a : b;',
      ];
      for (final line in violating) {
        expect(isViolationLine(line), isTrue, reason: '应命中：$line');
      }
    });

    test('合规样本不得误伤', () {
      const compliant = <String>[
        '// Platform.isAndroid 整行注释不参与匹配',
        '    //Platform.isIOS',
        '/// Platform.operatingSystem docs',
        'if (defaultTargetPlatform == TargetPlatform.android) return;',
        'final isWin = myPlatform.isWindows;',
        'if (!isNativeMobile) return;',
      ];
      for (final line in compliant) {
        expect(isViolationLine(line), isFalse, reason: '不得命中：$line');
      }
    });

    test('kIsWeb 同行才叫受守卫（白名单文件的判据可红可绿）', () {
      expect(
        isGuardedRead('bool get isIOS => !kIsWeb && Platform.isIOS;'),
        isTrue,
      );
      expect(isGuardedRead('bool get isIOS => Platform.isIOS;'), isFalse);
    });
  });

  group('web platform guard', () {
    test('lib/** 里 Platform.* 只允许出现在 platform_target.dart', () {
      final root = resolveRepoRoot();
      if (root == null) {
        fail('仓库根解析失败（CWD=${Directory.current.path}）');
      }
      final hits = platformHits(root);
      final flat = hits.values.expand((lines) => lines).toList();
      expect(
        flat,
        isEmpty,
        reason:
            'web 产物里 Platform.* 一调用就抛（v0.25.0 白屏根因）。'
            '请改用 lib/core/utils/platform_target.dart 的 isAndroid / isIOS / '
            'isNativeMobile，不要用 defaultTargetPlatform 替代'
            '（web 上按浏览器 UA 返回 android/iOS）：\n${flat.join('\n')}',
      );
    });

    test('platform_target.dart 的三个 getter 必须逐字接对平台', () {
      final root = resolveRepoRoot();
      if (root == null) {
        fail('仓库根解析失败（CWD=${Directory.current.path}）');
      }
      final source = File('$root/$_allowlistRelativePath').readAsStringSync();
      // 同一平台上 Platform.isAndroid 与 isIOS 都是 false，所以"值等价"的断言抓不到
      // 接错线（isAndroid => Platform.isIOS 照样绿）——这里只能逐字钉住配对。
      expect(
        source,
        contains('bool get isAndroid => !kIsWeb && Platform.isAndroid;'),
      );
      expect(source, contains('bool get isIOS => !kIsWeb && Platform.isIOS;'));
      expect(
        source,
        contains('bool get isNativeMobile => isAndroid || isIOS;'),
      );
    });

    test(
      'platform_target.dart 每次 Platform 读取都与 kIsWeb 同行，且站点数为 $_expectedGuardedReads',
      () {
        final root = resolveRepoRoot();
        if (root == null) {
          fail('仓库根解析失败（CWD=${Directory.current.path}）');
        }
        final file = File('$root/$_allowlistRelativePath');
        expect(
          file.existsSync(),
          isTrue,
          reason: '白名单文件不存在 —— 守卫不能静默失效，改名/搬走必须同步改本测试',
        );

        final unguarded = unguardedAllowlistedReads(root);
        expect(
          unguarded,
          isEmpty,
          reason:
              'kIsWeb 短路必须先于 Platform.*，否则 web 上照样抛：\n'
              '${unguarded.join('\n')}',
        );

        final guardedCount = file.readAsLinesSync().where(isGuardedRead).length;
        expect(
          guardedCount,
          _expectedGuardedReads,
          reason: '受守卫的读取站点增删必须显式改 _expectedGuardedReads，好在 diff 里被看见',
        );
      },
    );
  });
}
