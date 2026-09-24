# 债务2 — 统一事件缝（post-commit 领域事件 record-applied / record-removed）

> 来源：`docs/START_HERE.md` 队列第 1 项（= §3 A 的 D2，2026-09-24 架构评审产出）。评审原文明细未入库；下面的事实全部**从代码重建并逐条核验**（含 drift 2.31.0 源码级核实）。

## Context — 为什么要做

派生态（闹钟/通知、小组件快照）的失效目前靠**三条临时通道**，各覆盖一部分写入路径，合起来仍留 7 处盲区。其中三处已是用户可见缺陷：

- **远端改期不重挂本机提醒** → 闹钟停在旧时间（已登记 `docs/ROADMAP.md:578` P2.5 #1，T5 评审强制结转）
- **远端删除不取消已排队的闹钟/通知** → 幽灵响铃（**未登记**，本次勘察新发现）
- **事件回收站恢复不重挂提醒** → 事件提醒永久沉默（待办侧有，事件侧漏；**未登记**）

根因不是"少调了几次"，而是**没有单一失效机制**：闹钟侧连 choke point 都没有；小组件侧虽有 Drift `tableUpdates` 兜住本地写，但它是表级、无行身份、且盖不住跨进程写。`docs/process/ARCHITECTURE.md` 的三判据里，这笔债判的正是「**坏了能看见**：派生状态有统一失效机制」。

**目标**：把失效统一到 **post-commit 领域事件**（`record-applied` / `record-removed`），使"改了记录 → 派生态追上"成为不可绕过的路径。

## 现状证据

### 三条临时通道

| # | 通道 | 入口 | 覆盖 | 漏 |
|---|------|------|------|---|
| ① | provider 内联手调 | 调度 `reminders_provider.dart:107,119`；`notifService.cancel` **11 处**散在 `events_provider.dart:99,145,171`、`todos_provider.dart:132,169,284,320`、`reminders_provider.dart:143,158,243` | 本地勾选/删除/清空回收站 | applier、ICS、事件恢复、overdue 批量改期 |
| ② | UI save 后手写补丁 | `event_edit_page.dart:94`、`todo_edit_page.dart:106,114`、`home_page.dart:405`（注释自认 patch） | 仅"改时间"三类入口 | 新建实体、其余任何入口 |
| ③ | 写驱动 `tableUpdates` + 启动/定时/前台兜底（**仅小组件**） | `home_widget_provider.dart:47-78`；冷启动 `home_page.dart:111`；午夜 `:117-137`；恢复前台 `:139-146` | 小组件侧全部**进程内** Drift 写 | 闹钟侧零兜底；locale/theme/跨午夜/恢复前台（`home_page.dart:141-146` 只刷 overdue，**连小组件都不刷**）；**跨进程写** |

### 七处盲区

| # | 写入路径 | 位置 | 后果 |
|---|---------|------|------|
| 1 | **同步 applier**（MCP/AI 远端写入、push 回显、piggyback、pull） | `sync_applier.dart:34-141` ← `sync_engine.dart:334-344` ← `:220,229,249,265` | 改期不挂提醒（P2.5#1）；删除**不取消**已排队闹钟（幽灵响铃） |
| 2 | ICS 导入 | `ics_service.dart:103,115`（裸 insert，无事务/无 outbox） | 无提醒生成；widget 靠 ③ 侥幸覆盖 |
| 3 | 事件回收站恢复 | `events_provider.dart:122-129` | 恢复**不重挂** → 事件提醒永不响 |
| 4 | overdue 批量改期 | `todos_provider.dart:39-49` | 按旧时间响 |
| 5 | 账号切换元数据重写 | `account_provider.dart:174-178` | 无派生影响（应零调度调用） |
| 6 | 无写入的状态变化 | locale/theme/跨午夜/恢复前台 | 快照 `ui`/`theme`/`todayEvents` 保持旧值 |
| 7 | **跨进程写**：`bin/dayspark.dart` 直开同一库文件 | `bin/dayspark.dart:50` `openDatabaseFile(dbPath)` + `todoAdd/todoComplete/todoDelete/eventAdd` | 进程内钩子**结构上盖不住**；只能靠重算兜底 |
| 8 | 本地新建实体不挂提醒 | `event_create_page.dart:82-96`、`todo_create_page.dart:99-113` | **产品决策**，非失效问题 → 非目标 |

### 决定方案形状的六条事实（均已核验）

1. **drift `TableUpdate` 只有 `{table, kind}`，无 row id**（`drift-2.31.0/lib/src/runtime/api/stream_updates.dart:87-117`）→ tableUpdates **结构上不可能**驱动逐记录闹钟重排。
2. **`tableUpdates` 本来就是 post-commit**（`connection_user.dart:495-525`：`transaction.complete()` 先于 `disposeChildStreams()`）→ 通道③ 的毛病是**覆盖面**，不是时序。替换时不能把这条时序优势丢掉。
3. **applier 自身无事务**，提交点是外层 `sync_engine.dart:213-252`（push）与 `:263-268`（pull）；事件必须发在这两处**返回之后**，挂 `_applyRemote`（`:334`）等于发在提交前。
4. **写前参考时间只在写之前存在**：重排公式 `newTrigger = newRef − (oldRef − oldTrigger)`，提交后行里只剩 `newRef`，`oldRef` 永久丢失。这正是本方案必须把缝放在**写入口本身**而非旁挂观察者的根本原因（也解释了现有 `rescheduleRemindersProvider({oldReferenceTime, newReferenceTime})` 为何由调用方传旧值）。applier 已在 `sync_applier.dart:36-38` 读过 existing → 零额外查询成本。
5. **Alarm/通知 id 空间是 `reminder.id`**（`CONSTRAINTS.md:72-76` 的偏移作用于 reminder id），且事件软删会**同时删掉 reminder 行**（`events_provider.dart:101-103`）→ `removed` 事件必须**随事件携带 reminderIds**，事后推不出来。
6. **snooze 在 `reminder.id` 上重排且行内 `triggerTime` 必然在过去**（`home_page.dart:230`、`notification_service.dart:225-270`）→ 取消规则必须**按原因分档**，否则必然吃掉活跃 snooze（会直接踩手工清单第 2 条）。

**服务端同形模板**（照抄时序）：`server/lib/src/data/record_writer.dart:20-34` `applyInternalOp` = 事务前取 seq → `transaction` → 事务后比对 → **仅真正推进时**调**注入的** `notify`。注释：*notify fires AFTER commit and only when the feed actually advanced*。

**可复用**：`SyncEngine._statusController`（`sync_engine.dart:69-98,388-391`）+ Riverpod 桥（`sync_client_provider.dart:133-147`）是现成「broadcast Stream → Riverpod」范式；`home_widget_provider.dart:53-67` 已有合并去重 + 最多一个 in-flight 的队列；`FeatureFlag`（`feature_flags_provider.dart:4`）可用于双跑灰度。

## 范围（用户已拍板）

**做**：覆盖全部**进程内**写入路径（provider + ICS + 账号重置 + 同步 applier），顺带关 `ROADMAP.md:578` P2.5 #1。

**不做 / 记账**：
- P2.5 #2（ICS 接 outbox、`syncId` 回填）→ 另立一项
- 盲区 #8（新建实体默认提醒）→ **产品决策**，本次只记账不改行为
- locale/theme/跨午夜 → 只改为经由**同一消费端 API** 触发，不新增触发器
- **跨进程写（`bin/dayspark.dart`）**：缝盖不住 → 靠冷启动/恢复前台**重算**兜底；CLI 侧接入另立一项
- 更深的根因（`reminders.triggerTime` 是"派生态存进了表"，改存 `offsetMinutes` 可让所有写入路径无需携带旧值，与 D1 一并收敛）→ 写入 ROADMAP Pending Items，不扩本次范围

## 设计

### 核心：写入即登记，提交后发布（唯一发点）

```dart
// lib/domain/records/record_change.dart —— T1 交付形态（T2/T3/T4 照此写，勿照抄简报里的 ❌ 写法）
sealed class RecordChange { RecordType type; int localId; }
final class RecordApplied  extends RecordChange { DateTime? previousReference; } // 写前 startDt/dueDate；create 为 null
final class RecordRemoved  extends RecordChange { List<int> reminderIds; }       // 硬删前抓下的通知 id
final class RecordsBulkChanged extends RecordChange { String reason; }           // 'identity-reset'/'baseline'：仅身份字段被重写

// ❌ 简报 §3 的冻结写法在 Dart 3.13 下不可编译（位置 super 参数与位置 super 初始化器互斥）：
//    const RecordsBulkChanged(super.type, {required this.reason}) : super(0);
// ✅ 可编译且调用形态不变（R1 已改，T1 已交付）：
//    const RecordsBulkChanged(RecordType type, {required this.reason}) : super(type, 0);
// 批量边界 = 事务边界，交付形态是裸 `List<RecordChange>`（无 RecordChanges{changes, committedAt} 包装，
// 因此消费端拿不到 committedAt；`RecordChangeKind` 已在 R1 删除，全仓零引用）。
```

- **粒度**：per-record + per-transaction batch（批量边界 = 事务边界，无需人为设计）。
- **不携带 after 值**：消费端提交后重读行即真相；在事件里复刻业务字段等于把 D1 债务提前复制到事件层。事件只带"重读拿不回来的信息"（`previousReference`、`reminderIds`）。
- **不做事件溯源**：不持久化、不重放。崩溃窗口由冷启动/前台**重算**（幂等）兜底。

```dart
// lib/domain/records/record_scope.dart —— 唯一发点
static Future<T> run<T>(AppDatabase db, Future<T> Function(RecordScope tx) body) async {
  final joined = _current;                       // Zone 仅用于探测嵌套，登记永远显式
  if (joined != null) return body(joined);       // 内层并入最外层，绝不提前发布
  final scope = RecordScope._();     // 交付形态：scope 不持有 db（写入口签名收 db 参数）
  final result = await runZoned(() => db.transaction(() => body(scope)),
                                zoneValues: {_scopeKey: scope});
  RecordBus.of(db).publish(scope._drain());      // 只在提交后到达
  return result;
}
```

**发点选型（三选一，取 A）**：

| 方案 | 漏发风险 | 改动面 | fail-fast | 判定 |
|---|---|---|---|---|
| **A 显式 scope 随 body 传入** | 低（登记是写的副产品） | 24 处事务 + ~16 写方法 | **能**：漏传不编译；绕开写入口则守卫红 | **采用** |
| B Zone 环境缓冲（零签名改动） | **高**：漏调 `record()` 完全静默 | 最小 | 不能 | 否决（与当年淘汰 tableUpdates-only 是同一个错误的一半，见 `docs/superpowers/research/alliswell-outbox-comparison.md`） |
| C `QueryExecutor.interceptWith` 拦截 | 最低 | 中 | 能但脆弱（无 row id、`runBatched` 不透明） | **降级为可选 tripwire**，不做机制 |

**依赖前提**：`db.transaction()` 只在 commit 成功后才 resolve（已核验 `connection_user.dart:504-521`），故"返回 = 已提交"。这条要写进 SPEC 并由 T1 的"回滚零发布"测试钉死。

**引擎接入**：`sync_engine.dart:213-252` 与 `:263-268` 改 `RecordScope.run`，`tx` 逐层传到 `_applyRemote(record, tx)` → `SyncApplier.apply(record, tx)`——**签名变化即编译期强制**，applier 拿不到 `tx` 就写不出登记。`_baselineSweep`（`:364`）只改 `syncId` → 发 `bulkChanged(reason:'baseline')` 或干脆不发。

**首次全量同步的调用风暴**：提醒行不同步（P2.5#5），远端新建记录在本机没有 reminder 行 → 重排器对它们零平台调用，风暴上限 = 本机本来就设过提醒的记录数。

### 消费端 1：`ReminderReconciler`（`lib/domain/records/reminder_reconciler.dart`）

把 11 处 cancel/schedule 收敛为**一条幂等规则**：按当前行状态重算该 parent 的期望触发集合，与"上次实际交给 OS 的集合"（`Map<int, DateTime?> _applied`）求差，只动差集。

**⚠️ 派生文物化写（R2 后新增，T3/T4 实现者必读）：期望时刻必须回写 `reminders.triggerTime`。** 行内 `triggerTime` 是下一次位移的**锚**：不回写，第 2 次改期就会按"上一段位移"漂移（首审 P1：甚至会在漂移落进过去时 cancel 掉正确的通知且不再排 = 永不响）。写法：

- `lib/domain/records/writers/reminder_writer.dart` 的 `materializeTrigger`：**只写** `triggerTime`，不建行、不删行、不动父行；经 `RecordScope.run` 但**登记为空**（无 `tx.applied/removed`）→ 空批被 `publish` 丢弃，不发事件、不产生回环。
- 顺序固定为**先物化、再对外动作**（schedule/cancel）：物化失败时本趟对外动作被 `_safely` 记日志后跳过、且本父**不写状态缓存**，下一次事件（同 reference 亦可）会重试；反向（先排后写）会让锚点在崩溃/写失败后永久陈旧。
- **位移基准（D12 锚点归属规则）**：`desired = nextTrigger(reference: 当前 reference, previousReference: basis, storedTrigger: 行内值)`，其中 `basis` 只在**我们自己物化过的行**（`_materialized[id]` 与行内值同一瞬间）取"会话内已知的锚点 reference"，否则退回事件自述的 `previousReference`（新建 / 后挂提醒行 / 重启后第一眼 —— 即 `nextTrigger` 规则 2/3 的原意）。若一律信事件自述，陈旧事件会**重复施加位移**。
- **精度**：比较与回写都按**瞬间**（`isAtSameMomentAs`），且把期望时刻**归一到落库精度**（drift 的 `dateTime` 是 unix 秒）——否则事件里带亚秒/UTC 值时会每次 reconcile 都回写一行（写放大且永不收敛）。

- `nextTrigger` 必须是**纯函数**（唯一需要手工算边界处：DST / 负 Δ / Δ=0），用**人工手算的 `DateTime` 字面量**表驱动测试（防自证向量）。
- **取消分档**（否则必然吃掉 snooze）：

| 期望为空的原因 | 动作 |
|---|---|
| `removed`／`inactive`（父 trashed、已完成、reference 为 null） | `cancel(id)`（含 snooze） |
| `pastDue` 且 `_applied` 在未来 | `cancel(id)`（否则旧闹钟在新时间点仍是幽灵响铃） |
| `pastDue` 且 `_applied` 已过去 | **不动**（保护活跃 snooze 与已触发通知） |

- **幂等**：`previousReference == 当前 reference` 且父状态未变 → 直接 return，**零平台调用**（用测试断言"0 次"钉住，覆盖 `reorderTodos`、纯文案编辑、身份重写）。
- 装配：`lib/domain/providers/record_bus_provider.dart` 的 `Provider<void>`，`main.dart:76` 旁一行，与 `homeWidgetAutoRefreshProvider` 同构。
- **冷启动/恢复前台做全量重算**（跨进程写的唯一兜底）：**保守门只作用于 `pastDue` 档**——该档不论冷启动与否都不 cancel 本次会话没调度过的 id（snooze 把 OS 时刻排到未来、行内 `triggerTime` 仍停在过去，按行判会误杀活跃 snooze）；**`removed`/`inactive` 档的父行状态（trashed / 已完成 / 参考时间为空）是权威的，冷启动、`_applied` 为空时也必须 cancel**（含 snooze，见 `CONSTRAINTS.md:90`——"进回收站 → 提醒不响"本就覆盖 snooze）。补排只看"期望在未来"：`nextTrigger` 规则 2 返回过去时刻时落入 `pastDue` 档，**不得 schedule**。

### 消费端 2：小组件刷新器

`home_widget_provider.dart` **只换驱动源，队列逻辑原样保留**：删 `db.tableUpdates(...).listen(...)`（`:69-76`）→ 改为 `RecordBus.of(db).changes.listen((_) => refresh())`（批次内容不参与，组件是全量重算）；另补三处非记录刺激：resume 分支补 `refresh()`（`home_page.dart:141-146`）、midnight 定时器补 `refresh()`、locale/theme 经同一 `refresh()`。`pendingTaps` 消费时机不变（仍在每次 flush 内）。

### 防漏（双层机械化守卫）

结构性前提：`events`/`todos`/`reminders` 行写入收敛到 `lib/domain/records/writers/`，DAOs 的 mutator 只被写入口调用 → "登记"与"写"在同一函数体内，物理上无法只做一件。

同一套规则实现两次：`tool/check_record_seam.sh --selftest`（CI `test` job 首步，紧跟 `check_version_consistency.sh`）+ `test/architecture/record_seam_guard_test.dart`（进 `flutter test` → 也进 pre-commit）。

| 编号 | 规则 |
|---|---|
| G1 | `lib/**` 中 `(into\|update\|delete)(db\|_db).(events\|todos)` 与 DAO mutator 只允许出现在白名单（`lib/domain/records/**`、`lib/data/local/database/daos/**`、`sync_outbox.dart`） |
| G2 | `SyncOutbox.enqueue*` 只允许出现在 `lib/domain/records/record_scope.dart`（保证"入 outbox"与"发事件"同生） |
| G3 | 已删通道符号在 `lib/ui/` 零出现（`rescheduleRemindersProvider`/`clearRemindersProvider`/`db.tableUpdates`） |
| G4 | `RecordScope.run(` 站点数 == 常量（**T3 收尾实测 22**：T1 的 updateTodo 切片 1 + T3 迁移 20 + 重排器的物化 1；T3b 删掉 `rescheduleRemindersProvider` 后少 1；**T4 接入 sync_engine 三处后实测 25** = push 事务 + pull 事务 + `_baselineSweep`——简报原写 24 只数了 push/pull 两处，但 §1 #5 要求 `_baselineSweep` 也"仍经 `RecordScope.run` 包事务"（它经 `SyncOutbox` 改 `events/todos` 的 `syncId`，属 SPEC 3.5 规则 1 的"一切记录写入"），故以实测 25 为准），增删必须显式改常量 → diff 里逼审查者看一眼。常量与扫描器在 `test/architecture/record_seam_guard_test.dart` 的 `_scopeRunSites` —— 以那里的实测为准 |
| G5 | 小组件快照顶层键恒为 10（v2 契约） |

**诚实披露失败模式**：这条缝的漏发**不是运行期异常，而是静默过期**；防线是编译期 + 守卫，不是运行期自检。不要假装有运行期 fail-fast，那会变成空转门禁（REVIEWING 攻击 3）。

## 任务分解（4 个任务，线性依赖）

### T1 — 缝与总线（无行为变化，基座）✅ 已完成（`fe3ba53`）
新建 `lib/domain/records/{record_change,record_bus,record_scope}.dart` + `writers/`（本任务先做 `updateTodo` 一条纵向切片）+ `record_bus_provider.dart` + 两个守卫。
**先红测试**：①发布在提交之后（body 内批次 0，await 后 1）②body 抛异常 → 零发布且行未写 ③嵌套 run 并入最外层、内层抛则零发布 ④`applied` 携带 `previousReference`、create 为 null ⑤`removed` 携带 `reminderIds`（无提醒行 → 空列表非 null）⑥`bulkChanged` 一条粗粒度无 localId；守卫 fixture 必须能命中。
**验收**：`updateTodoProvider` 改经写入口；G1–G5 绿且 `--selftest` 能红；现有 `todos_provider_test.dart`(802 行) 全绿。

### T2 — 两个消费端 ✅ 已完成（`c423693`）
`reminder_reconciler.dart` + 装配 + 小组件换驱动源 + resume/midnight/locale/theme 触发。
**先红测试**（10 条）：`nextTrigger` 表驱动（DST/负Δ/Δ=0/落在过去）；改 due date → **断言绝对时刻**；清空 due → cancel 全部；完成/取消完成；进回收站/恢复；`pastDue+applied 在未来 → cancel` 与 `pastDue+已过去 → 不动`（**成对**）；幂等 0 调用；reorder/文案编辑 0 调用；批量 5 条每父一次；payload 恒为 `parentType:parentId:reminderId` 且第三段为 reminder.id。
**验收**：手工"改 due date"项通过；`home_widget_provider_test.dart` 三条全绿；删掉 `tableUpdates` 后组件仍刷新。

### T3 — 本地写路径全量接入 ✅ 已完成（`130e78e`，含 T3b 撤除通道① + Fix R1）
`events_provider`(6 事务) + `todos_provider`(余 10) + `moveOverdueToToday` + `account_provider`(→bulkChanged) + `ics_service`（包一次 `run`，仍 insert、不发 outbox，仅发 applied）+ 删 ②-1/②-2/②-3 三处 UI 补丁 + 更新 G1/G4 白名单与计数。
**先红测试**：更新事件改 start → 重排；`moveOverdueToToday` 3 条 → 每条按时移重排；`restoreEventProvider` → 重挂；ICS 2 正常+1 畸形 → 2 行 2 applied 无 removed；ICS 导入 → 快照含新事件；身份重写 → bulkChanged 且 0 调度；`lib/ui/` 出现已删符号 → 红。

### T4 — applier/engine 接入 + 关单 ✅ 已完成（本工作区，未提交：报告见 `.superpowers/sdd/2026-09-24-d2-event-seam/task-4-report.md`）
引擎两处事务改 `RecordScope.run`；`_applyRemote`/`SyncApplier.apply` 加 `tx` 必填；applier 六个写点改走 writer；`_baselineSweep` 不登记；文档收口 + 版本号。
**先红测试**：pull 改期 → 按新时间重排（**这就是 P2.5#1 的红**）；pull tombstone → cancel 全部提醒（幽灵响铃的红）；push conflict 走 serverRecord → 重排；piggyback → 重排；批次中途抛 → 零平台调用（发布边界）；baseline sweep → 0 调度。
**验收**：`ROADMAP.md:578` 关单；手工"远端改期"项通过；`two_device_sync_test.dart` 全绿。

## 验证

- `dart analyze .` 零 issue（**不用 `flutter analyze`**：中文路径下其 LSP 会崩，本会话已实测 exit 255；`dart analyze .` 是 CLAUDE/AGENTS 指定的门）
- `flutter test` 100% 通过且 **`skipped=0`**；六套测试全绿（app / server / contracts / wrapper / CLI / Kotlin）
- 两个守卫脚本绿且 `--selftest` 能红；`check_version_consistency.sh` 绿（版本同步后）
- **每条新测试必须做过反向验证**：删掉对应实现 → 该测试重新变红（防空转）
- 手工 3 项：改 due date / 回收站恢复 / 远端改期（其中"远端改期"与"远端删除不再响"两项**需补进 `CONSTRAINTS.md:84-95` 的 12 项清单**，否则新能力不在验收门内）
- 文档收口：`SPEC.md`（§2 新增第 5 条模块 + §3.5 新功能 E + 边界规则）、`CONSTRAINTS.md`（重写 `:170-175`，新增两条带 Why/Date）、`ROADMAP.md`（P2.5#1 关单 + Pending Items）、`DECISIONS.md`（ADR：为何显式 scope 而非 Zone/拦截器）、`changelog.md` 双语、`CLAUDE.md` 版本

## 风险与回退

| 风险 | 缓解 | 回退 |
|---|---|---|
| **小组件覆盖倒退**（最可能真出事） | G1 守卫 + resume/cold start 重算 | `home_widget_provider` 只换触发器 → 单一 hunk 可把 listen 目标换回；必要时用 `FeatureFlag.recordSeam` 双跑一版（总线 + tableUpdates 并存）再摘 |
| **重排器错杀 snooze / 重排已完成待办** | 分档 cancel + 成对测试 | 关闭 `recordSeam` 时恢复 `notificationServiceProvider` 直调路径 → **T2 只删调用点、保留 `scheduleReminderProvider` 本体一个版本**作逃生门 |
| **发布时序搞错**（提交前发/回滚后发） | 发点唯一 + 引擎两处改 `run` 使嵌套不可能 + 三条回滚测试 | T1–T3 可独立交付（缝是纯增量），T4 推后不影响其余收益 |

## 待披露的 Rulings

1. **工期修正**：债务自报"半天"，按本方案（24 处写入口 + ~16 writer + 重排器 + 守卫 + 测试）实际 **2–3 个开发日** —— 判错代价：排期错位
2. **缝盖不住跨进程写**（`bin/dayspark.dart`）→ 靠重算兜底，CLI 接入另立一项 —— 判错代价：CLI 写入后闹钟/组件可能过期到下次重算
3. **不做事件持久化/重放**（崩溃窗口靠重算幂等兜底）—— 判错代价：极端崩溃序列下派生态短暂不一致
4. **降级方案 C（执行器拦截）不做机制、只留可选 tripwire** —— 判错代价：漏发只剩 CI 守卫一道防线
5. **`triggerTime` 作为派生态存表**（更深的根因）本次不修，记入 ROADMAP —— 判错代价：后续写入路径仍需携带"写前旧值"
6. **手工验收降级为 3 项抽查**（其余 9 项记豁免，沿用 P2/P4 先例）—— 判错代价：未被抽查的通知链场景本次不覆盖

## DoD

P0/P1 清零（本方案 P1 候选 = 幽灵响铃、远端改期，须有"红→绿"实证）+ 测试 100% 且 `skipped=0` + 上述守卫全绿 + 手工 3 项通过 + 文档收口 + Rulings 披露。
