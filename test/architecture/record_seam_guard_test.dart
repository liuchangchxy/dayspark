// 单写入口守卫（棘轮）。已知限制（本轮显式接受，不假装覆盖）：
// * 跨 DB 嵌套：只用 Zone 探测"是否已在 RecordScope 里"，跨库嵌套不拦（生产单 DB 不可达）。
// * 别名调用：`final dao = db.todosDao; dao.markComplete(..)` 这类经别名的方法调用漏网；当前 lib/** 无此写法。
// * 行号不进基线哈希：同文件内内容完全相同的两处写入互换位置不会被发现（语义等价，无风险）。
// * fail-fast 面稍宽：RecordScope.run 会拒绝任何 drift 连接 zone（transaction/exclusively/runWithInterceptor，
//   三者共用 #DatabaseConnectionUser 键），后两者在当前 lib/** 零使用；一旦使用会得到响亮的 StateError。
// * 规则 (a) 是行局部正则：把写入拆到多行（`await db` / `.into(` / `db.todos,` / `)` 各占一行）可逃逸；
//   CI 不跑 `dart format --check`，所以这种写法不会被折叠掩盖 —— 依赖人的自觉 + 审查。
// * 已知幽灵事件窗口（已裁定不响亮化）：scope **内层**的外来 db.transaction（savepoint）回滚而外层提交时，
//   仍会留下幽灵事件。收紧会误伤合法的嵌套 savepoint（DAO 自带事务的 updateSortOrders/emptyTrash），
//   兜底靠 SPEC §3.5 规则 1「消费端必须容忍重读无此 id」。
// * 基线格式：<仓库相对路径> TAB <违规条数> TAB <sha256(按文件序拼接的违规行内容)>；# 开头为注释。
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const List<String> _recordWriteDirs = <String>[
  'lib/domain/records/',
  'lib/data/local/database/daos/',
];
const List<String> _recordWriteFiles = <String>['lib/domain/sync/sync_outbox.dart'];
const List<String> _busDirs = <String>['lib/domain/records/'];
const List<String> _busAccessFiles = <String>[
  'lib/domain/providers/record_bus_provider.dart',
];

// 已删通道符号（G3）：写入路径接缝后这些不再是合法入口，lib/ui/ 必须零出现。
const Set<String> _deletedChannelSymbols = <String>{
  'rescheduleRemindersProvider',
  'clearRemindersProvider',
  'tableUpdates',
};

// G4：RecordScope.run 站点数。增删站点必须显式改这个常量，好在 diff 里被审查者看见。
const int _scopeRunSites = 22;

const Set<String> _readOnlyDaoMethods = <String>{
  'watchPending',
  'watchCompleted',
  'watchByDueDate',
  'watchOverdue',
  'watchPendingByTags',
  'watchInbox',
  'watchDeleted',
  'watchAllNotDeleted',
  'watchSubtasks',
  'watchByDateRange',
  'watchDeletedEvents',
  'getOverduePending',
  'searchTodos',
  'searchEvents',
};

const String _baselineRelativePath = 'tool/record_seam_baseline.txt';
const String _bypassWriteMessage = '这条写入绕过了单写入口，派生态会静默失效';
const String _bypassPublishMessage =
    '这条发布绕过了唯一发点（RecordScope），事件会脱离"写入即登记"的绑定';

final RegExp _rawWrite = RegExp(
  r'\b(?:into|update|delete)\s*\(\s*(?:db|_db)\.(?:events|todos|reminders)\b',
);
final RegExp _daoCall = RegExp(r'\b(?:todosDao|eventsDao)\.([A-Za-z]\w*)\s*\(');
final RegExp _publishCall = RegExp(r'\.publish\s*\(');
final RegExp _busAccess = RegExp(r'RecordBus\.of\s*\(');

class GuardHit {
  const GuardHit(this.path, this.line, this.source, this.message);

  final String path;
  final int line;
  final String source;
  final String message;
}

class BaselineEntry {
  const BaselineEntry(this.count, this.hash);

  final int count;
  final String hash;
}

class Baseline {
  const Baseline(this.entries, this.problems);

  final Map<String, BaselineEntry> entries;
  final List<String> problems;
}

bool _inDirs(String path, List<String> dirs) =>
    dirs.any((dir) => path.startsWith(dir));

String stripCommentsAndStrings(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final ch = source[i];
    final next = i + 1 < source.length ? source[i + 1] : '';
    if (ch == '/' && next == '/') {
      while (i < source.length && source[i] != '\n') {
        i++;
      }
      continue;
    }
    if (ch == '/' && next == '*') {
      i += 2;
      while (i < source.length &&
          !(source[i] == '*' && i + 1 < source.length && source[i + 1] == '/')) {
        if (source[i] == '\n') out.write('\n');
        i++;
      }
      i += 2;
      continue;
    }
    final isRaw = ch == 'r' && (next == "'" || next == '"');
    if (ch == "'" || ch == '"' || isRaw) {
      final quote = isRaw ? next : ch;
      final triple = quote == "'" ? "'''" : '"""';
      final isTriple = !isRaw && source.startsWith(triple, i);
      final delimiter = isTriple ? triple : quote;
      i += (isRaw ? 1 : 0) + delimiter.length;
      out.write("''");
      while (i < source.length) {
        if (!isRaw && source[i] == r'\') {
          i += 2;
          continue;
        }
        if (source.startsWith(delimiter, i)) {
          i += delimiter.length;
          break;
        }
        if (source[i] == '\n') out.write('\n');
        i++;
      }
      continue;
    }
    out.write(ch);
    i++;
  }
  return out.toString();
}

List<GuardHit> findViolations(String path, String source) {
  final code = stripCommentsAndStrings(source).split('\n');
  final original = source.split('\n');
  final hits = <GuardHit>[];
  final recordPath = _inDirs(path, _recordWriteDirs) || _recordWriteFiles.contains(path);
  final busPath = _inDirs(path, _busDirs);

  for (var i = 0; i < code.length; i++) {
    final line = code[i];
    final shown = i < original.length ? original[i].trim() : line.trim();
    if (!recordPath) {
      if (_rawWrite.hasMatch(line)) {
        hits.add(GuardHit(path, i + 1, shown, _bypassWriteMessage));
      }
      for (final match in _daoCall.allMatches(line)) {
        // Deny by default：不在只读名单里的 DAO 方法一律视为写，新增 mutator 无法漏网。
        if (!_readOnlyDaoMethods.contains(match.group(1))) {
          hits.add(GuardHit(path, i + 1, shown, _bypassWriteMessage));
        }
      }
    }
    if (!busPath && _publishCall.hasMatch(line)) {
      hits.add(GuardHit(path, i + 1, shown, _bypassPublishMessage));
    }
    if (!busPath &&
        !_busAccessFiles.contains(path) &&
        _busAccess.hasMatch(line)) {
      hits.add(GuardHit(path, i + 1, shown, _bypassPublishMessage));
    }
  }
  return hits;
}

String hashHits(List<GuardHit> hits) =>
    sha256.convert(utf8.encode(hits.map((h) => h.source).join('\n'))).toString();

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

Baseline readBaseline(String root) {
  final problems = <String>[];
  final entries = <String, BaselineEntry>{};
  final file = File('$root/$_baselineRelativePath');
  if (!file.existsSync()) {
    problems.add('基线文件不存在：$_baselineRelativePath（棘轮必须有账本才能收紧）');
    return Baseline(entries, problems);
  }
  for (final raw in file.readAsLinesSync()) {
    if (raw.trim().isEmpty || raw.trimLeft().startsWith('#')) continue;
    final parts = raw.split('\t');
    if (parts.length != 3) {
      problems.add(
        '基线行格式错误（需要 路径<TAB>条数<TAB>sha256 三段，用 TAB 分隔）：$raw',
      );
      continue;
    }
    final count = int.tryParse(parts[1]);
    if (count == null) {
      problems.add('基线行的条数不是整数：$raw');
      continue;
    }
    entries[parts[0]] = BaselineEntry(count, parts[2]);
  }
  return Baseline(entries, problems);
}

Map<String, List<GuardHit>> scanLib(String root) {
  final found = <String, List<GuardHit>>{};
  final files =
      Directory('$root/lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final full = file.path.replaceAll('\\', '/');
    final path = full.startsWith('$root/') ? full.substring(root.length + 1) : full;
    final hits = findViolations(path, file.readAsStringSync());
    if (hits.isNotEmpty) found[path] = hits;
  }
  return found;
}

List<String> deletedSymbolHits(String root) {
  final hits = <String>[];
  final dir = Directory('$root/lib/ui');
  if (!dir.existsSync()) return hits;
  final files =
      dir.listSync(recursive: true).whereType<File>().where(
            (f) => f.path.endsWith('.dart'),
          ).toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final full = file.path.replaceAll('\\', '/');
    final path = full.startsWith('$root/')
        ? full.substring(root.length + 1)
        : full;
    final lines = stripCommentsAndStrings(file.readAsStringSync()).split('\n');
    for (var i = 0; i < lines.length; i++) {
      for (final symbol in _deletedChannelSymbols) {
        if (lines[i].contains(symbol)) {
          hits.add('$path:${i + 1} 已删通道符号 $symbol 不得再出现在 UI 层');
        }
      }
    }
  }
  return hits;
}

Map<String, int> scopeRunSites(String root) {
  final counts = <String, int>{};
  final files =
      Directory('$root/lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final full = file.path.replaceAll('\\', '/');
    final path = full.startsWith('$root/')
        ? full.substring(root.length + 1)
        : full;
    final count = RegExp(
      r'RecordScope\.run\(',
    ).allMatches(stripCommentsAndStrings(file.readAsStringSync())).length;
    if (count > 0) counts[path] = count;
  }
  return counts;
}

String _reject(String path, int line, String message, String detail, String source) =>
    '$path:$line $detail$message\n    $source';

void main() {
  group('matcher selftest', () {
    test('7 违规样本必须命中，合规样本必须不命中', () {
      const homePage = 'lib/ui/pages/home/home_page.dart';
      const provider = 'lib/domain/providers/other_provider.dart';

      expect(
        findViolations(homePage, 'await db.into(db.events).insert(companion);'),
        hasLength(1),
      );
      expect(
        findViolations(provider, 'await db.todosDao.markComplete(id);'),
        hasLength(1),
      );
      expect(
        findViolations(
          'lib/domain/sync/sync_engine.dart',
          'await db.eventsDao.upsert(row);',
        ),
        hasLength(1),
      );
      expect(
        findViolations(provider, 'await db.todosDao.updateSortOrders(ids);'),
        hasLength(1),
      );
      expect(
        findViolations(provider, 'await db.todosDao.compactOrphanSubtasks();'),
        hasLength(1),
      );
      expect(
        findViolations(
          provider,
          'await (db.delete(db.reminders)..where((r) => r.parentId.equals(id))).go();',
        ),
        hasLength(1),
      );
      expect(
        findViolations(provider, 'RecordBus.of(db).publish(scope.drain());'),
        hasLength(2),
      );
      expect(
        findViolations(provider, 'bus.publish(batch);'),
        hasLength(1),
      );

      const compliant = '''
        final rows = await db.select(db.events).get();
        final reminders = await db.select(db.reminders).get();
        await db.update(db.calendars).write(companion);
        final pending = db.todosDao.watchPending();
        final overdue = await db.todosDao.getOverduePending();
        // seam note: db.update(db.todos) 这处已改经写入口
        final note = 'db.into(db.events)';
      ''';
      expect(findViolations(provider, compliant), isEmpty);

      expect(
        findViolations(
          'lib/domain/records/writers/todo_writer.dart',
          'await db.into(db.events).insert(companion);',
        ),
        isEmpty,
      );
      expect(
        findViolations(
          'lib/domain/records/record_scope.dart',
          'RecordBus.of(db).publish(scope.drain());',
        ),
        isEmpty,
      );
      expect(
        findViolations(
          'lib/data/local/database/daos/events_dao.dart',
          'await (delete(events)..where((t) => t.id.equals(id))).go();',
        ),
        isEmpty,
      );
      expect(
        findViolations(
          'lib/domain/sync/sync_outbox.dart',
          'await db.update(db.todos).write(companion);',
        ),
        isEmpty,
      );
      expect(
        findViolations(
          'lib/domain/providers/record_bus_provider.dart',
          'final bus = RecordBus.of(ref.watch(databaseProvider));',
        ),
        isEmpty,
      );
      expect(
        findViolations(
          'lib/domain/providers/record_bus_provider.dart',
          'bus.publish(batch);',
        ),
        hasLength(1),
      );
    });

    test('resolveRepoRoot 从任意嵌套目录向上找仓库根，不依赖调用点 CWD', () {
      final probe = Directory.systemTemp.createTempSync('seam_root_probe');
      addTearDown(() => probe.deleteSync(recursive: true));
      File('${probe.path}/pubspec.yaml').writeAsStringSync('name: probe\n');
      final nested = Directory('${probe.path}/lib/domain/records')
        ..createSync(recursive: true);

      expect(resolveRepoRoot(nested), probe.path);
      expect(resolveRepoRoot(Directory.current), isNotNull);
      final nowhere = Directory('${probe.path}/lib/domain/records');
      expect(resolveRepoRoot(Directory(nowhere.parent.parent.parent.parent.path)), isNull);
    });

    test('stripCommentsAndStrings 剥离注释与字符串，保留行数', () {
      const source = '''
        // db.update(db.todos)
        final url = 'https://x/db.into(db.events)';
        /* db.delete(db.todos)
           db.into(db.events) */
        final r = r'db.into(db.todos)';
        await db.into(db.todos).insert(c);''';
      final stripped = stripCommentsAndStrings(source);
      expect(stripped.split('\n'), hasLength(source.split('\n').length));
      expect(findViolations('lib/ui/pages/x.dart', source), hasLength(1));
    });
  });

  group('single write seam ratchet', () {
    test('每条 events/todos/reminders 写入都在白名单内，或已登记在棘轮基线', () {
      final root = resolveRepoRoot();
      if (root == null || !Directory('$root/lib').existsSync()) {
        fail(
          '仓库根解析失败（CWD=${Directory.current.path}）：'
          '需要从 CWD 向上能找到同时含 pubspec.yaml 与 lib/ 的目录',
        );
      }
      final baseline = readBaseline(root);
      final current = scanLib(root);
      final problems = <String>[...baseline.problems];

      for (final entry in current.entries) {
        final allowed = baseline.entries[entry.key];
        if (allowed == null) {
          for (final hit in entry.value) {
            problems.add(
              _reject(hit.path, hit.line, hit.message, '未登记在棘轮基线中；', hit.source),
            );
          }
          continue;
        }
        if (entry.value.length > allowed.count) {
          for (final hit in entry.value.skip(allowed.count)) {
            problems.add(
              _reject(
                hit.path,
                hit.line,
                hit.message,
                '超出基线（${entry.key} 基线 ${allowed.count} 条，实际 ${entry.value.length} 条）；',
                hit.source,
              ),
            );
          }
          continue;
        }
        if (entry.value.length < allowed.count) {
          problems.add(
            '${entry.key} 违规条数已从基线 ${allowed.count} 降到 ${entry.value.length} —— '
            '请同步收紧 $_baselineRelativePath，基线不能腐烂成永久豁免',
          );
          continue;
        }
        final actual = hashHits(entry.value);
        if (actual != allowed.hash) {
          problems.add(
            '${entry.key} 违规条数没变（${allowed.count} 条）但内容变了（等量置换）：'
            '基线哈希 ${allowed.hash.substring(0, 12)}…，实际 ${actual.substring(0, 12)}… —— '
            '请显式更新 $_baselineRelativePath，让这次替换出现在 diff 里',
          );
        }
      }
      for (final path in baseline.entries.keys) {
        if (!current.containsKey(path)) {
          problems.add(
            '$path 的基线条目已不存在（文件已迁移或删除）—— '
            '请从 $_baselineRelativePath 删除该条目',
          );
        }
      }

      expect(problems, isEmpty, reason: problems.join('\n'));
    });
  });

  group('deleted channels and scope sites', () {
    test('G3：已删通道符号在 lib/ui/ 零出现', () {
      final root = resolveRepoRoot();
      if (root == null) {
        fail('仓库根解析失败（CWD=${Directory.current.path}）');
      }
      expect(
        deletedSymbolHits(root),
        isEmpty,
        reason:
            '写路径接缝后这三条通道只保留 provider 本体（逃生门），UI 层不得再直呼；'
            '改期由提交后的领域事件驱动',
      );
    });

    test('G4：RecordScope.run 站点数与常量一致', () {
      final root = resolveRepoRoot();
      if (root == null) {
        fail('仓库根解析失败（CWD=${Directory.current.path}）');
      }
      final sites = scopeRunSites(root);
      final total = sites.values.fold<int>(0, (sum, count) => sum + count);
      expect(
        total,
        _scopeRunSites,
        reason: '站点增删必须显式改 _scopeRunSites（当前分布：$sites）',
      );
    });
  });
}
