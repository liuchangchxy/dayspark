# 决策与演进时间线 (DECISIONS.md)

> 本文档用于以微日志（Lightweight ADR）的形式记录项目的重大架构调整、需求变更及背后的原因。
> **目的**：防止数周或数月后遗忘"当初为什么把那个逻辑改成这样"，杜绝需求反复横跳。

---

## 变更记录模板格式
```markdown
### [YYYY-MM-DD] [变更标题]
- **触发背景**：用户反馈 / 性能瓶颈 / 测试异常
- **核心决策**：将原本的 XXX 规则改为 YYY
- **对应 SPEC 章节**：SPEC.md 第 X.X 节
- **影响范围**：[列出涉及的模块或文件]
```

---

## 历史决策流

### [2026-09-22] 路线甲：DaySpark 重生，不 fork 外部项目
- **触发背景**：项目需重大重构为"自托管的开源 Todo清单"，在"fork 现成项目改造"与"原项目重生"之间选型。
- **核心决策**：走路线甲——保留 DaySpark 现有数据模型/UI/l10n/测试资产原地重构，不 fork 任何外部项目。
- **对应 SPEC 章节**：SPEC.md 第 1 节（系统定位）
- **影响范围**：全局架构与代码库归属。

### [2026-09-22] 日历视图换 kalender 库
- **触发背景**：自研日/周/月视图累积 DST、GlobalKey、重叠布局、全天系列等深层 bug，定制成本高。
- **核心决策**：采用 kalender 库（钉 `^0.17.x` minor，pre-1.0 禁止跨 minor 升级）替换手写视图；`event_tile` 保留为 tileContent 渲染。
- **对应 SPEC 章节**：SPEC.md 第 2 节（客户端层）、3.4 P1 行
- **影响范围**：`lib/ui/widgets/calendar/*`、日历相关测试、`docs/CONSTRAINTS.md` 日历章节。

### [2026-09-22] 推进顺序：地基优先（P1→P2→P3→P4）
- **触发背景**：四阶段重构需要明确依赖顺序：同步后端与 MCP 都依赖干净的客户端地基。
- **核心决策**：P1 客户端地基重构 → P2 同步后端 → P3 MCP/CLI → P4 平台补齐。
- **对应 SPEC 章节**：SPEC.md 第 3.4 节（P1–P4 功能矩阵）
- **影响范围**：全部排期与任务依赖。

### [2026-09-22] 后端语言选 Dart
- **触发背景**：同步后端需与客户端共享记录模型、DTO、错误码等契约。
- **核心决策**：后端用 Dart（shelf + drift + SQLite），通过共享 package `dayspark_contracts` 消除跨语言契约漂移。
- **对应 SPEC 章节**：SPEC.md 第 2 节（核心模块划分）、4.2（接口契约）
- **影响范围**：`server/`、`packages/dayspark_contracts/`、客户端 sync 层。

### [2026-09-22] 外部项目吸收清单（代码/设计分级）
- **触发背景**：多份竞品与先例调研（SP / ByWave / AllisWell / Todoist MCP），需明确"能抄什么、只能看什么"。
- **核心决策**：
  - ByWave **代码**可吸收（RRULE 三范围语义、webhook、设备配对——MIT）
  - SP **设计**可吸收（小组件 JSON 快照契约、时间轴映射）
  - AllisWell **仅设计**（字段级 LWW、MCP 工具面/无删除姿态/OAuth2.1、小组件单写入路径——PolyForm NC 禁止代码合并）
  - Todoist MCP 哲学：工作流工具 > API 映射，22 工具甜点区
- **对应 SPEC 章节**：SPEC.md 第 3.2、3.3 节
- **影响范围**：P2 同步协议、P3 MCP 工具面、P4 小组件契约。

### [2026-09-22] 删除客户端 CalDAV 同步层与客户端内 MCP server
- **触发背景**：自研 CalDAV 层（约 1201 行）维护成本高且与新同步协议路线冲突；客户端内 MCP server 实现不可靠且数据面应以后端为准。
- **核心决策**：P1 删除 `lib/data/remote/caldav/`、workmanager 后台同步、`lib/infrastructure/mcp/`（工具清单存档为 P3 规格）；`ical_converter` 抽出到 `domain/services/ical/` 保留 ICS 导入导出能力；DB schema v8 删 CalDAV 列与 Accounts 表。
- **对应 SPEC 章节**：SPEC.md 3.4 P1 行；1.1 冻结需求 3（同步改走自研协议）
- **影响范围**：同步服务、providers、settings UI、main.dart、schema/migration 测试。

### [2026-09-22] 番茄钟 / CalDAV 导出层 / E2EE 移出本次范围
- **触发背景**：范围控制，避免四阶段重构被低优先级功能稀释。
- **核心决策**：番茄钟+数据复盘、CalDAV 导出层、E2EE 一律标记为 P5+ 以后，不进本计划执行。
- **对应 SPEC 章节**：SPEC.md 第 3.4 节（明确出范围行）
- **影响范围**：排期与需求边界。

### [2026-09-22] CI Flutter 版本钉子移除，统一 channel stable
- **触发背景**：P1 首推 CI 失败——macOS/Windows job 钉 3.41.7 缺少 `onReorderItem` 参数（本地与其余 job 均为 3.47+/stable），编译报错 No named parameter。
- **核心决策**：移除 ci.yml 与 release.yml 中全部 `flutter-version: 3.41.7`，五平台统一 `channel: stable`；推翻 2026-05-16「统一到 3.41.7」的决定（其动因 Windows AOT/MSB8066 已由通知 stub 方案解决）。
- **对应 SPEC 章节**：SPEC.md 3.4 P1 行（全平台构建验证）。
- **影响范围**：.github/workflows/ci.yml、release.yml；Windows/macOS 构建将在新 stable 上首次验证。

### [2026-09-23] 契约包 dayspark_contracts 作为协议 SSOT
- **触发背景**：同步后端与客户端需共享 push/pull/SSE 的 DTO、错误码与 JSON 形状，跨进程各写一份必然漂移。
- **核心决策**：新增独立 package `packages/dayspark_contracts`，作为协议唯一真理源（SSOT）——客户端与 `server/` 都只依赖它；契约变更必须先改包与 37 项契约测试，再动两端实现。
- **对应 SPEC 章节**：SPEC.md 3.2、4.1、4.2
- **影响范围**：`packages/dayspark_contracts/`、`server/`（path 依赖）、客户端 sync 层、CI `server-test` job。

### [2026-09-23] LWW 裁定：set 键到达序字段合并 + 水位线游标语义
- **触发背景**：T3 实现需把 SPEC「字段级 LWW / 同秒 opId 破平 / cursor 单调」落成可测规则；T3 评审又暴露封顶 piggyback + head cursor 的静默缺口（C1 Critical）。
- **核心决策**：① LWW = op **set 过的键**按服务器到达序取胜、未 set 键保留服务器值，delete vs update 用 `server_ts`、同秒 opId 字典序破平；客户端只发 dirty 字段（`SyncSnapshot` diff）。② `PushResponse.cursor` = **已投递水位线**（封顶时为最后一条已投递 seq；空 piggyback 保留请求 cursor，不回退、不跳 head），配合「≤cursor 已全部见过」语义保证无损续拉。
- **对应 SPEC 章节**：SPEC.md 3.2 规则 3/4、5.2（冲突防御）
- **影响范围**：`server/lib/src/sync/lww.dart`、`server/lib/src/routes/sync.dart`、`packages/dayspark_contracts`、客户端 `sync_payload.dart`/`SyncEngine`、e2e 矩阵例 ④⑤。

### [2026-09-23] 密码哈希选 argon2id（argon2_web），KAT 先证后用
- **触发背景**：T2 选哈希算法：brief 首选 `argon2` 包 SDK 约束 `<3.0.0` 不兼容 Dart 3.13；`dargon2`/`fargon2` 为 FFI 原生插件（Xcode/CI 风险），均不可用。
- **核心决策**：采用纯 Dart `argon2_web ^0.3.0`，参数 argon2id v=19, t=3, m=32 MiB, p=1, 16B 盐, 32B key；采用前在 scratch 包跑通包自带 KAT + pointycastle argon2i v1.0 + 官方 argon2i v1.3 + **RFC 9106 argon2id 全向量**；PBKDF2-SHA256 100k 回退预案保留但**未启用**。
- **对应 SPEC 章节**：SPEC.md 第 2 节（同步后端）、1.1 需求 6（自托管）
- **影响范围**：`server/lib/src/auth.dart`、`docs/CONSTRAINTS.md` Sync 章节、server 测试。

### [2026-09-23] Outbox 显式入队（provider 出口），不做全库 watcher
- **触发背景**：T5 需要「本地变更 → outbox」的入队通路；AllisWell 的同事务 outbox（行+op 同生共死）值得对照，但其为 PolyForm NonCommercial 仅可研究、禁止抄码；drift 下 provider/DAO 分散，事务级 hook 不可行。
- **核心决策**：**显式 enqueue 出口**——写路径在 provider 出口与业务写同事务显式入队（漏 enqueue 的写路径由 e2e 矩阵兜底；已知缺口：ICS 导入，记入 ROADMAP P2.5）；对照结论仅设计层吸收（同事务原子性语义等价），不复制其代码。
- **对应 SPEC 章节**：SPEC.md 3.2、5.1（离线/断网）
- **影响范围**：`lib/domain/providers/*`、`lib/domain/sync/sync_outbox.dart`（含 AllisWell 对照注释）、`test/domain/sync/outbox_test.dart`。

### [2026-09-23] e2e 抓出的丢更新修复：脏字段推送（SyncSnapshot + dirtyFields）
- **触发背景**：T7 双设备 e2e 矩阵例 ④ 变红：B 离线改 `summary+startDt`、A 同时改 `description`，B 上线后 A 的 description 被改回旧值——客户端全量 payload 使「op set 键到达序」退化为整条记录覆写。
- **核心决策**：无 schema 变更修复——新增 `SyncSnapshot`/`SyncSnapshotStore`（上次 apply 的服务端 payload，与游标同居 prefs）+ `dirtyFields` 值差分；仅推送脏字段，空 diff 视为已收敛丢弃 op；所有 apply 点（push applied/conflict、piggyback、pull）统一写快照。
- **对应 SPEC 章节**：SPEC.md 3.2 规则 4、5.2
- **影响范围**：`lib/domain/sync/{sync_config,sync_payload,sync_engine}.dart`、`engine_test`/e2e 例 ④、`docs/CONSTRAINTS.md` Sync 章节。
