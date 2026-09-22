# P2 — Sync Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** NAS 可部署的 Dart 同步后端 + DaySpark 客户端同步引擎，实现双设备（含离线/冲突）秒级一致——落地冻结需求 P0-3「跨设备同步」。

**Architecture:** 契约先行 `packages/dayspark_contracts`（客户端/服务端共 import）；服务端 `server/`（shelf + drift/SQLite 单文件 + SSE 只发信号）；协议 = 服务器单调游标 + opId 幂等 push（逐条部分失败）+ 服务器时间戳字段级 LWW + tombstone；客户端 = Drift outbox（与业务写同事务语义）+ pull applier + SSE 监听 + 断网重连。MCP/CLI 不在本阶段（P3）。

**Tech Stack:** Dart 3 / shelf / drift + sqlite3 / dart_jsonwebtoken + 密码哈希（见 Task 1 决策）/ SSE / 客户端复用 Riverpod+Drift / connectivity_plus 回归 / Docker 多阶段构建

**Spec:** 主计划 `/Users/chang/.claude/plans/snug-bubbling-parnas.md`（Phase 2 协议规格 9 行 = 权威）；需求 = `SPEC.md` 1.1 冻结需求 3 + 3.4 P2 行；本计划为其展开。

## Global Constraints（继承主计划 + CLAUDE.md）

- `dart analyze .` 零 issue；`flutter test` 全绿 + `server`/`contracts` 各自 `dart test` 全绿；禁止 suppress 类旗标
- 版本 feature 只改 x：P1 结束于 `0.21.0+24` → P2 发布时 `0.22.0+24`；未过用户确认禁止 push/tag（SDD 分支开发期允许本地 commit，push 仅在 Phase 收尾用户点头后）
- 协议硬规则（写死，违反即 bug）：**cursor = 服务器单调序号（禁时间戳）**；**LWW 只用服务器 `serverTs`**；**push 逐条结果绝不整批回滚**；**tombstone ≥45 天才 GC**；**SSE 只发 `{cursor}` 不发载荷**；opId 幂等 = DB 唯一约束
- 契约包是协议唯一真相源：DTO/错误码/字段表只定义一次，server 与 app 共同 import；改契约必须同步两端测试
- Dart 代码风格同 CLAUDE.md（single quotes、trailing commas、显式返回类型、debugPrint、无 docstring/emoji、WHY 注释仅非显然处）
- 客户端 schema 若改表：schemaVersion 8→9 + onUpgrade + build_runner + make-migrations + migration_test 更新（Task 5 预计要加 outbox 表）

---

### Task 1: dayspark_contracts 共享契约包

**Files:**
- Create: `packages/dayspark_contracts/pubspec.yaml`（name: dayspark_contracts, no flutter dep, pure dart）
- Create: `packages/dayspark_contracts/lib/dayspark_contracts.dart`（barrel）
- Create: `packages/dayspark_contracts/lib/src/{record_dto,sync_api,errors}.dart`
- Test: `packages/dayspark_contracts/test/*.dart`
- Modify: `pubspec.yaml`（app 侧 `path: packages/dayspark_contracts`）

**Interfaces（Produces — 后续任务依赖的精确形状）:**
- `class SyncRecord { String id; RecordType type; // enum: event|todo
  Map<String, dynamic> payload; int rev; bool deleted; DateTime serverTs; }`
- `class PushOp { String opId; OpType op; // upsert|delete
  String recordId; RecordType type; Map<String, dynamic>? fields; int? baseRev; }`
- `class PushRequest { String deviceId; List<PushOp> ops; int? cursor; }`
- `class OpResult { String opId; OpStatus status; // applied|conflict|rejected|duplicate
  SyncRecord? serverRecord; String? code; }`
- `class PushResponse { List<OpResult> results; List<SyncRecord> piggyback; int cursor; }`
- `class PullResponse { List<SyncRecord> changes; int nextCursor; bool hasMore; }`
- 错误码常量：`errUnauthorized/errValidation/errConflict/errRateLimited`
- JSON 双向：`toJson/fromJson` 全部字段，DateTime = UTC ISO-8601

- [ ] **Step 1: 写契约失败测试**（序列化 roundtrip、未知字段容忍、枚举非法值抛错）
- [ ] **Step 2: 跑 `dart test` 验证失败**
- [ ] **Step 3: 最小实现契约**
- [ ] **Step 4: `dart test` 全绿 + app 侧 `flutter pub get` 解析 path 依赖 + `dart analyze .` 零**
- [ ] **Step 5: Commit** `feat(contracts): 同步协议契约包`

### Task 2: 服务端骨架 + 存储 + 认证

**Files:**
- Create: `server/pubspec.yaml`、`server/bin/server.dart`、`server/lib/server.dart`
- Create: `server/lib/src/{config,db,schema,auth,routes/health,routes/auth}.dart`
- Create: `server/Dockerfile`（本任务仅生成可跑的本地版，精化在 Task 7）
- Test: `server/test/{health,auth}_test.dart`

**表（drift）:** `users(id, email unique, password_hash, created_at)`、`refresh_tokens(id, user_id, token_hash unique, family_id, expires_at, revoked_at)`、`devices(id, user_id, device_id unique, name, last_seen)`、`records(user_id, id, type, payload_json, rev, deleted, server_ts, PK(user_id,id))`、`sync_ops(op_id unique, user_id, result_json, created_at)`、`revisions(user_id, seq)`（每用户单调游标，行锁串行化）

**Interfaces:**
- Consumes: Task 1 的 DTO
- Produces: `POST /health` → `{ok:true,version}`；`POST /auth/register|login|refresh`（argon2id 哈希；access JWT 15min；refresh 轮换 + family 撤销）；`Authorization: Bearer` 中间件 `requireAuth` → `AuthContext(userId, deviceId)`；DB 层 `Future<int> nextSeq(String userId)`（事务内行锁 +1）

- [ ] Step 1: 失败测试：register→login→refresh 轮换（旧 refresh 失效）+ health
- [ ] Step 2: 验证失败
- [ ] Step 3: 实现 schema/骨架/auth（密码哈希选型：优先 `argon2` 纯 Dart 包，若 Xcode/CI 兼容存疑则 `crypto` + PBKDF2-SHA256 100k 轮，报告写明选型理由）
- [ ] Step 4: `dart test` 绿；本地 `dart run bin/server.dart` + curl health 手验
- [ ] Step 5: Commit `feat(server): 骨架、SQLite schema 与 JWT 认证`

### Task 3: 同步核心 push/pull + LWW

**Files:**
- Create: `server/lib/src/routes/sync.dart`、`server/lib/src/sync/{lww,idempotency}.dart`
- Test: `server/test/sync_test.dart`（本计划最高风险测试集）

**协议实现要点（主计划权威，逐条落地）:**
- `POST /sync/push`：逐 op 先查 `sync_ops(op_id)` → duplicate 直接回放旧结果；新 op 校验 → **字段级 LWW**：对 `fields` 每字段比较 `baseRev` 与当前 rev，记录级 delete vs update 用 `server_ts` 比较，同秒用 opId 字典序破平 → 写 `records`（`server_ts=now UTC`，rev=old+1）→ `nextSeq` → 存 `sync_ops` → 响应逐条 `{status, serverRecord?}` + **piggyback**：`seq > 请求 cursor` 的最近 ≤100 条 changes + 当前 cursor
- `GET /sync/pull?cursor=&limit=`：`seq > cursor` 顺序返回（含 tombstone `deleted:true`），`hasMore`
- 时钟：只信服务器 `now()`；拒绝客户端时间参与裁决

- [ ] Step 1: 失败测试矩阵（≥8 例）：① 幂等重放同 opId ② 字段级冲突（A 改 title B 改 start 并发→各字段胜者正确）③ 记录级 update vs delete ④ 部分失败（3 op 中 1 非法 → 逐条 status 不回滚）⑤ piggyback 携带远端变更 ⑥ pull 游标分页+hasMore ⑦ tombstone 经 pull 传播 ⑧ 同秒破平
- [ ] Step 2: 验证全红
- [ ] Step 3: 实现 lww + routes
- [ ] Step 4: `dart test` 全绿
- [ ] Step 5: Commit `feat(server): push/pull 同步核心、字段级 LWW 与幂等`

### Task 4: SSE 失效通道

**Files:**
- Create: `server/lib/src/routes/stream.dart`
- Test: `server/test/stream_test.dart`

- `GET /sync/stream?cursor=`（auth）：长连接，**只推** `data: {"cursor":N}`；N = 该 user 最新 seq；push 落库后广播。心跳注释行 `: ping` 每 25s。连接鉴权失败即断。

- [ ] Step 1: 失败测试：订阅后另连接 push → 收到 cursor 信号且 payload 无记录体；心跳存在
- [ ] Step 2: 验证失败 → Step 3: 实现 → Step 4: 全绿 → Step 5: Commit `feat(server): SSE 失效通道`

### Task 5: 客户端同步引擎（outbox + applier + 监听）

**Files:**
- Modify: schema（`schemaVersion 8→9`）: Create `table SyncOutbox { opId PK, recordId, type, op, payloadJson, baseRev?, createdAt }`（含 `recordId+op` 合并语义：同记录连续 upsert 合并为最新 payload，delete 清除同记录 pending upsert——写 WHY 注释）
- Create: `lib/domain/sync/{sync_outbox,sync_engine,sync_applier,sse_listener}.dart`
- Create/Modify: `lib/domain/providers/sync_client_provider.dart`（engine 单例：前台循环 push→pull、SSE 触发 pull、指数退避 1→60s、`connectivity_plus` 恢复即触发）
- Modify: `events_provider/todos_provider` 及 DAO mutation 出口 → **同一 Drift 事务内写 outbox**（仿 P1 widget 的 tableUpdates 单点则事务语义不成立——**改用显式出口**：provider mutation 函数统一走 `SyncOutbox.enqueue(tx, ...)` helper；报告中与 AllisWell 同事务设计对照）
- Modify: pull applier 覆盖 event/todo/tag 轻量先行：**P2 范围 = event + todo 两类**（tag/reminder/attachment 留 P2.5 缩略说明）；applier 写库前若 outbox 有该记录 pending op → 按协议：本地 op 仍 push，push 结果 conflict 时以 serverRecord 为准落库并丢弃本地 op（停车再基）
- Test: `test/domain/sync/*`（outbox 合并语义、applier LWW 落库、engine 状态机用 fake server）

**Interfaces:** Consumes Task 1 DTO；Produces `syncStatusProvider`（idle|pushing|pulling|error + lastError + lastSyncAt）

- [ ] Step 1: 迁移失败测试（v8→v9 表存在 + v1→v9 数据保持）+ outbox 合并单测
- [ ] Step 2: 验证失败 → Step 3: build_runner + make-migrations + 引擎实现 → Step 4: `flutter test` 全绿（迁移测试含新表）→ Step 5: Commit `feat(sync): 客户端 outbox 同步引擎`

### Task 6: 账号/服务器设置 UI + 登录流

**Files:**
- Create: `lib/ui/pages/settings/settings_sections/account_section.dart`（P1 预留的 section 文件位）
- Modify: `settings_page.dart` 组装；`feature_flags` 增 `sync`（默认 off，登录成功后 on）；l10n zh+en 新 key（服务器地址/登录/注册/登出/同步状态/lastSync 复用）
- Test: widget 测试（section 渲染 + 登录成功置位）

- [ ] Step 1: l10n key 成对 + 失败 widget 测试 → Step 2: 验证失败 → Step 3: 实现 UI（服务器 URL 校验、email/password、注册/登录双动作、状态行 + 手动"立即同步"按钮复用 P1 的 syncTooltip key）→ Step 4: `flutter gen-l10n` + analyze 零 + `flutter test` 绿 → Step 5: Commit `feat(ui): 账号与同步设置`

### Task 7: 双设备 e2e + Docker 部署

**Files:**
- Create: `test/integration/two_device_sync_test.dart`（同进程两个 Riverpod container + 两个 outbox 对真 server 实例：矩阵 = 创建/编辑/删除/离线编辑后上线/并发冲突，断言双方最终一致）
- Create: `server/Dockerfile`（精化：多阶段 `dart compile exe` 静态产物 + scratch/alpine + volume `/data`）、`server/docker-compose.yml`、`docs/DEPLOY.md`（NAS 部署、反代/Tailscale 出门访问建议、备份 = 拷 sqlite 文件）
- Modify: `tool/check_glibc_note` —— Dart 静态产物无 glibc 问题，报告注明

- [ ] Step 1: e2e 失败测试（矩阵 5 例）→ Step 2: 验证红 → Step 3: 跑通 + 修引擎缺陷 → Step 4: e2e 绿 → Step 5: 本地 `docker build`（本机有 docker；无 docker 则 Dockerfile lint + 报告标 manual）→ Step 6: Commit `feat(deploy): Docker 部署与双设备 e2e`

### Task 8: 全量验证 + 文档 + 版本

- [ ] `dart analyze .` 零 · `flutter test` 全绿 · `cd server && dart analyze . && dart test` 零/绿
- [ ] 本地双开验证手工脚本说明写入 `docs/qa/p2-manual-qa.md`（模拟器+桌面各一实例，真实登录互推）
- [ ] 文档：`docs/changelog.md` 顶部 P2 双语条目；`docs/ROADMAP.md` 需求 3 ✅ + P2 行；`docs/CONSTRAINTS.md` 同步协议硬规则章节（cursor/LWW/tombstone/SSE 四条 + Why + Date）；`SPEC.md` 3.4 P2 行状态；`DECISIONS.md` 追加（契约包、event/todo 先行、哈希选型）；`CLAUDE.md` 版本行 + 架构表加 server 层
- [ ] `pubspec.yaml` → `0.22.0+24`
- [ ] Commit `docs: v0.22.0 文档与版本` — **停下等用户确认再谈 push**

---

## Verification（Phase 收尾门）

1. 三套 analyze/test 全零全绿（app + server + contracts）
2. e2e 五矩阵绿
3. 用户手工双设备 QA（`docs/qa/p2-manual-qa.md`）
4. push 后 ci.yml 全绿（新增 server 目录不入 app CI job；server 测试进 ci.yml = Task 8 顺带加一个 `server-test` job——**允许触碰 ci.yml**，push 验证）
5. Docker 镜像本地 build 成功（或 manual 标注）

## 风险与回退

- 同事务 outbox 不可行（provider/DAO 分散）→ 显式 enqueue 出口（Task 5 已选）；漏 enqueue 的写路径由 e2e 矩阵兜底
- argon2 纯 Dart 性能/兼容问题 → PBKDF2 回退（Task 2 预案）
- SSE 在部分 NAS 反代不稳 → engine 保底定时 pull（15s 前台轮询降级，写 WHY）
- drift 客户端 v9 迁移与 P1 v8 连续性：migration_test 必须 v1→v9 一条链绿
