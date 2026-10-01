// 服务端 schema 迁移。
//
// 客户端早有 migration_test，服务端一直没有——而 v4（SyncOps.deviceId）正是
// 服务端第一次真正需要迁移的场景：它跑在用户自己的 NAS 上，那个 SQLite 文件里
// 是他们全部的日程与待办。迁移写错 = 数据没了，且没有备份可回。
//
// 做法：用当前 schema 建库、灌数据，再用裸 sqlite3 把库"倒回" v3 的形状
// （删掉 v4 才有的列、把 user_version 拨回 3），然后用当前代码重新打开 ——
// 走的就是真实升级路径。降级这步刻意不借 drift 内部 API：借了就等于用被测对象
// 去搭被测环境。
import 'dart:io';

import 'package:dayspark_server/src/db.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late File dbFile;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('dayspark-migrate-');
    dbFile = File('${tmp.path}/dayspark.db');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('v3 → v4：数据保留，device_id 列补上且旧行为空', () async {
    var db = AppDatabase(NativeDatabase(dbFile));
    await db.customStatement(
      '''
      INSERT INTO users (id, email, password_hash, created_at)
      VALUES ('u1', 'a@example.com', 'h', 0)
      ''',
    );
    await db.customStatement(
      '''
      INSERT INTO records (user_id, id, type, payload_json, rev, deleted,
                           server_ts, seq, last_op_id)
      VALUES ('u1', 'r1', 'todo', '{}', 1, 0, 0, 1, 'op-1')
      ''',
    );
    await db.customStatement(
      '''
      INSERT INTO sync_ops (op_id, user_id, device_id, result_json, created_at)
      VALUES ('op-1', 'u1', 'dev-old', '{}', 0)
      ''',
    );
    await db.close();

    // 倒回 v3：去掉 v4 才有的列，并把版本号拨回去。
    final raw = sqlite3.open(dbFile.path);
    raw.execute('ALTER TABLE sync_ops DROP COLUMN device_id');
    raw.execute('PRAGMA user_version = 3');
    raw.dispose();

    // 用当前代码重新打开 → 走 onUpgrade(3 → 4)。
    db = AppDatabase(NativeDatabase(dbFile));
    final users =
        await db.customSelect('SELECT COUNT(*) AS c FROM users').getSingle();
    final records =
        await db.customSelect('SELECT COUNT(*) AS c FROM records').getSingle();
    expect(users.read<int>('c'), 1, reason: '用户数据必须保留');
    expect(records.read<int>('c'), 1, reason: '记录数据必须保留');

    final old = await db
        .customSelect("SELECT device_id FROM sync_ops WHERE op_id = 'op-1'")
        .getSingle();
    expect(
      old.read<String>('device_id'),
      '',
      reason: '迁移前的 op 没有设备归属，应为空串而不是猜一个',
    );

    // 迁移后写入仍然可用，新列真的能落值。
    await db.customStatement(
      '''
      INSERT INTO sync_ops (op_id, user_id, device_id, result_json, created_at)
      VALUES ('op-2', 'u1', 'dev-new', '{}', 0)
      ''',
    );
    final fresh = await db
        .customSelect("SELECT device_id FROM sync_ops WHERE op_id = 'op-2'")
        .getSingle();
    expect(fresh.read<String>('device_id'), 'dev-new');

    await db.close();
  });

  test('每次打开都是幂等的：迁移不会二次执行', () async {
    var db = AppDatabase(NativeDatabase(dbFile));
    await db.customStatement(
      '''
      INSERT INTO users (id, email, password_hash, created_at)
      VALUES ('u1', 'a@example.com', 'h', 0)
      ''',
    );
    await db.close();

    // 连续开三次：若迁移不幂等，第二次就会因为列已存在而炸。
    for (var i = 0; i < 3; i++) {
      db = AppDatabase(NativeDatabase(dbFile));
      final users =
          await db.customSelect('SELECT COUNT(*) AS c FROM users').getSingle();
      expect(users.read<int>('c'), 1, reason: '第 ${i + 1} 次打开后数据仍在');
      await db.close();
    }
  });
}
