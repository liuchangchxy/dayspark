// 启动顺序守卫：Alarm.init() 会恢复所有已存闹钟；有 12 个时真机实测
// 0.64-0.80 s，曾经写在 runApp() 之前，直接把首帧推迟掉。这里把「不得在
// runApp 前 await」和「必须在首帧后的回调里启动」固化成可执行的棘轮，
// 防止以后顺手把 init 挪回启动路径。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final RegExp _awaitedInit = RegExp(r'await\s+AlarmService\.init\s*\(');

/// True when startup still blocks on the alarm plugin's restore pass.
bool blocksOnAlarmInit(String source) => _awaitedInit.hasMatch(source);

/// True when init is started after runApp, from a post-frame callback.
bool startsAlarmInitAfterFirstFrame(String source) {
  final runApp = source.indexOf('runApp(');
  final postFrame = source.indexOf('addPostFrameCallback');
  final init = source.indexOf('AlarmService.init()');
  if (runApp < 0 || postFrame < 0 || init < 0) return false;
  return runApp < init && postFrame < init && !blocksOnAlarmInit(source);
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
  test('守卫自证：阻塞样本红、首帧后样本绿', () {
    expect(blocksOnAlarmInit('  await AlarmService.init();'), isTrue);
    expect(
      startsAlarmInitAfterFirstFrame(
        'await AlarmService.init();\nrunApp(app);',
      ),
      isFalse,
      reason: 'runApp 之前 await 必须判红',
    );
    expect(
      startsAlarmInitAfterFirstFrame(
        'runApp(app);\n'
        'WidgetsBinding.instance.addPostFrameCallback((_) {\n'
        '  unawaited(AlarmService.init());\n'
        '});',
      ),
      isTrue,
    );
  });

  test('main.dart：Alarm init 不在 runApp 前阻塞', () {
    final root = resolveRepoRoot();
    expect(root, isNotNull, reason: '找不到仓库根（pubspec.yaml + lib/）');
    final source = File('$root/lib/main.dart').readAsStringSync();

    expect(
      blocksOnAlarmInit(source),
      isFalse,
      reason: 'Alarm.init() 必须在首帧后执行，不能挡住 runApp()',
    );
    expect(
      startsAlarmInitAfterFirstFrame(source),
      isTrue,
      reason: 'Alarm.init() 应由 addPostFrameCallback 启动',
    );
  });
}
