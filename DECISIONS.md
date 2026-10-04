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

### [2026-09-23] MCP 工具面按 P2 现实收缩至 event+task（17 个，非 18/22）
- **触发背景**：计划标题写「18 = 13读+5写」、更早的规划散文写 22 工具，但 P3 冻结表本身只枚举 17 个名字（7 读 + 10 写）；且 P2 同步只覆盖 event/todo——calendars/tags/reminders 实体未同步，为其做工具只会产出读不到正确真值的假面。
- **核心决策**：**冻结表胜出**——恰好实现表内 17 个名字（`get_events` 而非散文里的 `list_events`），不发明第 18 个；calendar/tag/reminder 工具**明确不做**，待 P2.5 实体同步落地后增量扩展工具面（标题 miscount 记为计划文本错误，非实现偏差）。
- **对应 SPEC 章节**：SPEC.md 3.3 规则 1、3.4 P3 行
- **影响范围**：`server/lib/src/mcp/tools.dart`、`tools/list` 冻结集测试、ROADMAP P3 行遗留注记。

### [2026-09-23] MCP 写通路复用 LWW/nextSeq 内部 op（AI = 一台虚拟设备）
- **触发背景**：AI 写入必须与设备写入在同一存储与冲突语义下收敛，否则要为 MCP 单开第二套写路径和第二套冲突规则。
- **核心决策**：每个 `tools/call` 写工具落 `applyInternalOp`（P3 前置任务导出的缝）：同一 `records` 表、同一字段级 LWW、同一 `nextSeq` 单调水位线、同一 `_notifySeq` SSE 广播——**AI 即一台虚拟设备的 push**，设备经既有 pull/SSE 自动可见；`idempotency_key` 直接作 opId，同 key 异 body 拒绝。
- **对应 SPEC 章节**：SPEC.md 3.2、3.3
- **影响范围**：`server/lib/src/mcp/tools.dart`、`server/lib/src/sync/`（导出缝）、e2e 矩阵 ①–③。

### [2026-09-23] CLI = HTTP MCP 客户端（dogfood 工具面），不直连 REST
- **触发背景**：`dayspark` CLI 需要远程操作同步后端；可选直连既有 REST（`/sync/pull` 等）或走 MCP。
- **核心决策**：CLI 用 `/auth/login` 取登录 token 后**以 MCP 客户端身份**调 `POST /mcp`（`task list` → `list_tasks`、`event add` → `create_event`…），不直连 REST 记录端点——CLI 成为冻结工具面的常驻 dogfood 者，工具名/参数/错误 hint 的任何回归会在 CLI 测试里先炸；凭证存 `~/.dayspark/credentials.json`（chmod 600，token 永不打印）。
- **对应 SPEC 章节**：SPEC.md 第 2 节（数据流图 CLI→MCP）、3.4 P3 行
- **影响范围**：`tool/dayspark_cli/`、`docs/qa/p3-mcp-qa.md`。

### [2026-09-23] MCP 协议子集与 OAuth 2.1 均手写（无状态子集 vs SDK）
- **触发背景**：计划技术栈写明「MCP 协议自实现无状态子集，若 `dart_mcp` SDK 快速验证适配 server 端 streamable 可换用——**默认手写**」；OAuth 2.1 同理需选 SDK 或自实现。
- **核心决策**：**两处均选手写**（`dart_mcp` 适配性评估未实际发生，按计划默认路径走）——MCP 侧：需要 `isError` 工具结果承载业务错误（严格 SDK 会返回 −32602）、单消息子集拒 batch 数组、401 `WWW-Authenticate` 挑战形状自定义，这三点都是 spec 允许但 SDK 默认行为不同的偏差，协议测试逐条对拍 `initialize`/`tools/list` 形状兜底；OAuth 侧：只需 RFC 8414/9728/7591/6749/7009 的**无状态子集**（PKCE-S256 强制、code sha256 单次、refresh 轮换复用 P2 家族吊销、argon2id 客户端密钥），引入 OAuth SDK 会带上会话/CSRF 框架并绕开既有 hash/rotation 设施，收益不成比例。
- **对应 SPEC 章节**：SPEC.md 3.3 规则 6、4.2
- **影响范围**：`server/lib/src/mcp/endpoint.dart`、`server/lib/src/oauth/`、`server/test/mcp_protocol_test.dart`、`server/test/oauth_test.dart`。
- **后续（2026-09-24）**：spike 实测完成 → 见下条「MCP 转正手写版」。其中「严格 SDK 会返回 −32602」这一前提**已被实测推翻**，真正的阻塞是传输 / 协议版本 / OAuth。

### [2026-09-23] AI 删除姿态 = trash 软删（可恢复），无永久删除工具
- **触发背景**：工具面写操作需要删除语义；对照 AllisWell「无删除姿态」（仅设计吸收，PolyForm NC 禁抄码）与本项目既有回收站（事件/待办均软删 + 恢复 + 清空）。
- **核心决策**：只提供 `trash_event`/`trash_task`（写 `deletedAt` 进回收站，`destructiveHint:true`），**不提供**任何 `delete_*`/`empty_trash` 工具；永久删除保留给 App UI 回收站人工操作——与冻结需求「对齐回收站语义」一致，AI 幻觉误删可全量恢复。
- **对应 SPEC 章节**：SPEC.md 3.3 规则 5
- **影响范围**：`server/lib/src/mcp/tools.dart` 注解矩阵、`docs/CONSTRAINTS.md` MCP 章节。

### [2026-09-24] Apple bundle id / App Group 家族原子统一到 `com.dayspark.app` / `group.com.dayspark.app`
- **触发背景**：P4 平台补齐——iOS/Mac 资产仍散在 `dev.opencal.*` bundle id 与 `group.com.calendarTodoApp` 组名下，与项目更名后的 `com.dayspark.app` 族不一致，App Group 不统一会让小组件宿主/扩展读写不同 suite。
- **核心决策**：一次原子迁移全部资产——bundle id（Runner/Widget 扩展/RunnerTests × iOS+macOS）、App Group（6 份 entitlements + Swift `suiteName`/`appGroupId` + Dart `setAppGroupId`）同改同验；降级路径仅允许组名回退旧值（bundle 改名保留）。终态 grep：旧组名/旧 bundle id 零残留。
- **对应 SPEC 章节**：SPEC.md 1.1 需求 2、3.4 P4 行
- **影响范围**：`ios/**`、`macos/**`、`lib/main.dart`、`docs/CONSTRAINTS.md` Home Widget 章节、CI（+iOS simulator job）。

### [2026-09-24] 小组件快照文案走预本地化（snapshot pre-localization），原生零 intl
- **触发背景**：widget v2 要求 l10n/去硬编码英文，但 Kotlin/Swift 渲染层没有可靠的 intl 运行时，逐端维护翻译表必然漂移。
- **核心决策**：`ui` 块由 Dart 在构建快照时用 `AppLocalizations.delegate.load(解析后的 locale)` 解析成**成品字符串**写入（解析顺序：显式参数 → `app_locale` prefs → 平台 locale），原生只 `setText`；locale 切换靠下一次快照写入生效，与数据刷新同一通路，不新增同步机制。arb（zh+en 成对）是唯一文案源。
- **对应 SPEC 章节**：SPEC.md 3.4 P4 行（小组件 v2 l10n）、第 2 节小组件层
- **影响范围**：`lib/infrastructure/platform/home_widget_service.dart`（`ui` 键 + 6 个新 arb key）、三端原生渲染（T3）、golden schema 测试。

### [2026-09-24] 六件事收敛：默认 OFF + 复用既有拖拽排序管线（前缀语义）
- **触发背景**：Todo清单 UX 批 A 要把今天待办收敛为 Ivy Lee 六槽；可选方案有独立六槽存储、第二套排序管线、直接替换待执行面。
- **核心决策**：**默认 OFF** 的 DateStrip chip 开关（`six_things_mode` prefs，设置区同步开关）；折叠态 = 现有 `dateTodos`（已按 sortOrder 排序）的**前缀 `sublist(0,6)`**——`SliverReorderableList` → `_onReorderItem` → `reorderTodosProvider` 既有单管线原样复用，重排索引与全列表 1:1 映射，无第二套持久化。仅作用于今天视图（`selectedDate == today`）；逾期带独立置顶不占六槽；「更多 (N)/收起」折叠行保证可逆。
- **对应 SPEC 章节**：SPEC.md 3.4 P4 行（Todo清单 UX 批）、1.1 需求 8（克制）
- **影响范围**：`lib/ui/widgets/todo/date_strip.dart`、home todos tab、`lib/domain/providers/todos_ui_prefs_provider.dart`、settings TodosSection、`test/ui/pages/home/home_todos_tab_test.dart`。

### [2026-09-24] 节气/调休数据选 `lunar ^1.7.8`（6tail，纯 Dart）
- **触发背景**：月视图需要节气微标签 + 法定班/休角标；候选需 macOS/CI 兼容（无原生库）、算法稳定、维护活跃。
- **核心决策**：采用纯 Dart `lunar: ^1.7.8`——无 platform 目录/无 FFI/无 `.so`（GLIBC 检查不适用，macOS 按构造兼容）；`Lunar.fromDate().getJie()/getQi()` 取节气、`HolidayUtil.getHolidayByYmd` 取班/休，包一层 `ChineseCalendarService` 按天 memoize（365 天 ≈12ms）。已知边界：**法定调休数据内嵌止于 2026**，2027+ 班/休角标静默消失（节气为算法不受影响），升级 lunar 前为预期行为。
- **对应 SPEC 章节**：SPEC.md 3.4 P4 行（节气）
- **影响范围**：`pubspec.yaml`、`lib/domain/services/chinese_calendar_service.dart`、`marked_month_day_header.dart`、24 个节气 l10n key、对应单测。

### [2026-09-24] time-sensitive 通知：保留 entitlement + 代码，设备门留 keep/remove 降级预案
- **触发背景**：iOS 事件提醒需要 `interruptionLevel: .timeSensitive` 真正生效；接线 `Runner.entitlements` 后发现个人免费 team 不支持 Time Sensitive Notifications capability，device/TestFlight 构建在 profile 创建阶段失败（fail-closed）。
- **核心决策**：**保留** entitlement + 双路径（schedule/snooze）代码不动；记录明确降级预案——上真机/TestFlight 前二选一：付费 team 开 capability（保留），或从 `Runner.entitlements` 删除该单行（`interruptionLevel` 无 entitlement 时系统优雅降级为普通优先级，Dart 零改动）。模拟器/CI 不受影响；macOS 故意不加对应 capability（系统降级）。
- **对应 SPEC 章节**：SPEC.md 3.4 P4 行（通知全清单验收）
- **影响范围**：`ios/Runner/Runner.entitlements`、`lib/infrastructure/platform/notification_service.dart`、`docs/CONSTRAINTS.md` Notifications 章节、`docs/qa/p4-manual-qa.md` §六。

### [2026-09-24] Linux `APPLICATION_ID` 迁移到 `com.dayspark.app.dayspark`（接受一次性重钉 caveat）
- **触发背景**：T1 review 结转——Linux 端 GTK application-id 仍是 `dev.opencal.calendar_todo_app`，与全局 `com.dayspark.app` 族不一致。
- **核心决策**：`linux/CMakeLists.txt` `APPLICATION_ID` 改为 `com.dayspark.app.dayspark`（Linux 不允许纯域名倒置与 bundle id 完全同名时的惯例后缀写法）。**接受迁移 caveat**：存量安装升级后被桌面环境视为**不同应用**——旧 id 键控的固定启动器/Dock 条目可能失配、旧 id 下的 gsettings 遗留；应用数据走 XDG 标准路径**无损失**，对用户是一次性的重新固定启动器操作。
- **对应 SPEC 章节**：SPEC.md 1.1 需求 2、3.4 P4 行
- **影响范围**：`linux/CMakeLists.txt:10`、桌面文件/window class 关联、发版说明（需提示 Linux 用户重钉启动器）。

### [2026-09-24] macOS 签名：keychain-access-groups 整键删除（非清空数组）
- **触发背景**：2026-09-24 用户实测 macOS 启动 SIGKILL（taskgate `Invalid Signature`）——T1 曾按上游 README 把 `keychain-access-groups` 填成 `$(AppIdentifierPrefix)com.dayspark.app`；adhoc/teamless 下前缀展开为裸 bundle id，taskgate 拒绝 spawn。
- **核心决策**：对照实验证明**空数组同样崩**（填值版与 `<array/>` 版均 exit 137、crash report 同症状；仅整键删除存活 ≥7s）→ 决定**整键从 DebugProfile/Release entitlements 删除**并留 dict 内 WHY 注释（偏离 coordinator 最初「改回 empty array」的字面指令，按其根因意图执行）。`flutter_secure_storage` 落 default partition 不受影响；仅真实 Developer-ID/Team 签名构建才可加回。
- **对应 SPEC 章节**：SPEC.md 3.4 P4 行（平台补齐）
- **影响范围**：`macos/Runner/{DebugProfile,Release}.entitlements`、`docs/CONSTRAINTS.md` Apple Signing 章节、CI macOS adhoc DMG 可启动性。

### [2026-09-24] MCP 转正手写版：官方 SDK spike 实测不能承载（关闭「换官方 SDK」指令）
- **触发背景**：用户指令「先限时 spike 评估 `dart_mcp` server 端成熟度 → 能承载 17 工具+OAuth+Streamable HTTP 则迁移（工具层不动只换协议壳），不能则写 DECISIONS 转正手写版；**禁止裸换**」。spike 两路：官方 SDK 外部调研 + 仓库内换壳影响面测绘（壳 / 接缝 / 工具层三层边界）。
- **核心决策**：**不迁移，手写版转正**。证据（pub.dev API 与源码均一手核验）：
  ① 已发布最新版 `dart_mcp` **0.5.2（2026-06-29）服务端 Streamable HTTP 尚未发版**，只存在于未发布的 main `0.6.0-wip`（issue #162 仍 open）；
  ② main 的 HTTP handler `streamable_http.dart:921` 为 `_supportedVersions = {ProtocolVersion.v2026_07_28}`，而该修订**删除 initialize 握手与协议级 session**（官方 spec changelog 原文：「Make MCP stateless: remove the initialize/notifications/initialized handshake」「Remove protocol-level sessions and the Mcp-Session-Id header」）——DaySpark 跑 2025-06-18 + initialize；
  ③ handler 只吃 `dart:io HttpRequest`，**无 shelf 适配**，接入即绕开既有 shelf 中间件与 401 挑战链；
  ④ `README`「Authorization is not supported at this time」→ 自研 OAuth 2.1 AS（DCR/PKCE/token/双轨）**100% 仍需保留**。
  净收益仅「工具/资源注册 API」（本已是最薄的一层），代价是未发版依赖 + 协议降级 + dart:io 耦合 + 0.2→0.6 每个 minor 均 BREAKING。内部测绘另证：壳↔工具接缝不是可插拔端口（一组 plain Dart 类型 + 函数值字段 `ScopeChecker`），故「只换壳」本就需新写适配层 + scope 门重找挂点。
- **修正一条错误前提**：2026-09-23 条把「严格 SDK 会返回 −32602」列为阻塞理由，**实测推翻**——SDK 的参数校验失败、未知工具、以及工具实现抛出的异常都统一转成 `isError: true` 的 tool result（`tools_support.dart`，catch 处注释 "converted into failed tool call responses"），与本项目「业务错误走工具结果」同向。真正阻塞在**传输 / 协议版本 / OAuth**，将来重看勿再引用旧理由。
- **复核触发条件**（四条同时满足才值得重开）：官方 Streamable HTTP **服务端**上 pub.dev 且稳定 → 支持 2025-06-18 或提供明确前向兼容路径 → 有 shelf 适配（或可注入自定义 401 挑战）→ 主流客户端普遍协商其支持的协议版本。
- **对应 SPEC 章节**：SPEC.md 3.3 规则 4/6、4.2
- **影响范围**：本条 + 2026-09-23 条的后续指针；`docs/START_HERE.md` 队列 3 收口；`server/lib/src/mcp/*`、`tool/mcp_stdio_wrapper`、`tool/dayspark_cli` 均**保持不动**。
- **附带产出**：换壳测试兜底的精确边界 = 壳测试 `mcp_protocol_test` 16 例（随壳重写）/ 行为守卫 `mcp_tools_test` 47 + CLI 13 + e2e 5（e2e 是唯一真 socket，不可豁免）/ `oauth_test` 54 应原地绿；另修一处活漂移 `mcpServerVersion`（0.23.0 → 0.24.0，并纳入版本守卫）。
- **备查（不建议采用）**：第三方 `mcp_server` 2.2.3（依赖 shelf、覆盖 2024-11-05→2025-11-25）与 `mcp_dart` 2.4.2 更贴近需求，但均不做授权服务器、均属 pre-1.0 第三方依赖（与钉 kalender 同类风险）。

### [2026-09-24] 派生态失效统一到"记录缝"：显式 scope（非 Zone 缓冲 / 非执行器拦截）+ 允许物化回写
- **触发背景**：闹钟/小组件的派生态失效靠三条临时通道（provider 内联手调、UI save 后手写补丁、小组件 `tableUpdates`），合起来仍留 7 处盲区，其中 3 处是用户可见缺陷——远端改期不重挂（P2.5 #1）、远端删除不撤已排队通知（幽灵响铃）、事件回收站恢复不重挂。根因不是"少调了几次"，而是没有单一失效机制。
- **核心决策**：把失效统一到 **post-commit 领域事件**，发点唯一 = `RecordScope.run`（`lib/domain/records/record_scope.dart`，写入即登记、`db.transaction` 返回后才 `publish`；回滚 = 零发布）。
  - **为何选 A 显式 scope（`tx` 随 body 传入）而非 B Zone 环境缓冲**：B 漏调 `record()` 完全静默（与当年淘汰 tableUpdates-only 是同一个错误的一半）；A 的漏传**不编译**（`tx` 是必填参数），绕开写入口则守卫 G1 红。Zone 的 `_scopeKey` 只用于探测嵌套，登记永远显式。
  - **为何 C（`QueryExecutor.interceptWith` 拦截）降级为可选 tripwire、不做机制**：无 row id、`runBatched` 不透明，且挡不住"写对了但没登记"；一旦成机制就要长期背着这份脆弱性。
  - **为何允许物化回写 `reminders.triggerTime`**：行内时刻是下一次位移的锚——不回写会让第 2 次改期起按上一段位移漂移（首审 P1，极端时会把正确通知撤掉且不再排 = 永不响）。回写仍走缝（`ReminderWriter.materializeTrigger`）但**登记为空**：它不是新的领域事实，登记会让事件在总线上绕一圈回到重排器自己。**锚点归属按 D12**：只有"我们自己物化过的行"（`_materialized[id]` 与行内值同一瞬间）才敢拿会话内锚点 reference 当位移基准，否则退回事件自述的 `previousReference`（这是陈旧事件重复施加位移的防线）。
  - **为何撤除通道①（provider 内联 `cancel`/`schedule`，14 处调用点）**：与缝并行会让同一 id 在同一时刻被排/撤两次（T3b 实测 `Actual: [2, 2]`）。三条临时通道 → 一条缝；`rescheduleRemindersProvider` 随之删除，其能力由 `ReminderWriter.referenceChanged` 承载。
  - **远端 tombstone 为何不删提醒行（T4 明确不改的一个既有行为）**：pre-T4 的 applier 落 tombstone 时**根本不动提醒行**——提醒行在本地一直保留；T4 只是给这条路径补上 `removed` + `reminderIds` 登记（撤销 OS 通知），行仍保留为惰性。因此"远端保留 / 本地硬删"的**分歧是既有的**（真正的异类是 `EventWriter.softDelete` 连带硬删行），不是 v0.25.0 引入的新行为；T4 选择两侧都不动（`applyRemoteTombstone` 不删行、也不改本地软删），把统一与否留给产品拍板 → `docs/ROADMAP.md` Pending Items P3 #5。**（2026-09-25 已拍板并实施：统一为"保留"，见本文件末条。）**
  - **两件零调用者的"逃生门"复核结论（T4 收尾）**：`scheduleReminderProvider` 保留（T2 简报定义的"保留一个版本"逃生门：重排器错杀 snooze 时可回退到通知服务直调；删除属于回滚路径变更，另立一项）；`ReminderWriter.referenceChanged` 保留（**T4 applier 不用它**——远端改期走 `EventWriter/TodoWriter.applyRemote`，由 writer 自己"写前读旧值 + 写 + 登记"，比"写一格、再另调一格登记"更紧；`referenceChanged` 与 R1a/R1b/R1c 三条测试留档，钉住"只登记位移"这一格的语义）。两者清理记入 ROADMAP Pending Items P3。
- **对应 SPEC 章节**：SPEC.md 3.5（规则 1/2/4/5）、第 2 节记录缝模块
- **影响范围**：`lib/domain/records/**`（新增缝/总线/写入口/重排器）、`lib/domain/providers/record_bus_provider.dart`、全部写路径 provider、`lib/domain/services/ics_service.dart`、`lib/domain/sync/{sync_applier,sync_engine}.dart`、`test/architecture/record_seam_guard_test.dart`、`tool/record_seam_baseline.txt`、`docs/CONSTRAINTS.md` 架构与小组件章节、`docs/ROADMAP.md` P2.5 #1 关单。

### [2026-09-25] 事件软删**保留**提醒行（与待办侧对称）：回收站恢复能重挂提醒
- **触发背景**：债务2 收尾时暴露的不对称——待办软删保留提醒行（恢复可重挂），事件软删（`EventWriter.softDelete`）却**连带硬删**提醒行，用户把事件丢进回收站再恢复，提醒永久沉默。远端 tombstone 一贯保留行，故本地侧是唯一的异类。
- **核心决策**：**统一为"保留"**。`EventWriter.softDelete` 去掉 `db.delete(db.reminders)…go()`，父行只置 `deletedAt`、提醒行保留为惰性。
  - **为何连带把登记从 `removed` 改回 `applied`**：`removed` 的语义是"记录已不存在"（硬删时用它 + `reminderIds` 撤通知）。软删后记录仍在回收站里，用 `removed` 是语义谎言；改 `applied` 后由重排器读父行 `deletedAt != null` 走 **`inactive` 档**撤 OS 通知——这正是待办侧的既有范式（T3b 当初改成 `removed` 是"行被删了、`applied` 撤不掉任何东西"这一事实的必然结果；行一旦保留，这个理由就消失了）。
  - **为何硬删路径不动**：`hardDeleteEventWithChildren` / `emptyEventTrash`（及待办的 `permanentDelete` / `emptyTrash`）仍**硬删**提醒行并发 `removed` + `reminderIds`——永久删除后留下惰性行就是永久垃圾，且真删后没有任何"重读父行"的路径可撤销通知。
  - **残留（有意不动，已披露）**：远端 tombstone 仍登记 `removed` + `reminderIds`。两侧现在都保留行、用户可见行为一致，差别只剩登记格（远端删除不是用户在本机做过的动作、也不知本机有哪些行）；改它要动 T4 已钉死的断言面（`applier_test.dart:288` 等），超出本次"一行改法"的范围。
- **一处既有断言被本决策证伪（据实记录）**：`test/domain/providers/events_provider_test.dart:215-216` 的 `expect(reminders, isEmpty)` 钉的正是被推翻的旧行为，按裁定改为 `expect(reminders.map((r) => r.id), [reminderId])`（点名具体 id，强度不降）。**更正**：T4 的 R2 曾"更正"称"不存在 `expect(reminders, isEmpty)` 这条断言"——那是错的，断言存在，只是在 provider 测试里而非缝测试里；事实是"改一条"而非"补一条"。
- **反向验证**：5 处逐条改坏实现均已红（软删重新删行 → S10/S14/S15 + provider 断言 4 红；登记回 `removed` → S14 红；去掉 `previousReference` → S14 红；`_readParent` 一律 `active` → S10/S14/S15 红；DAO 层去掉两处硬删 → 对应 DAO 测试红）。
- **对应 SPEC 章节**：SPEC.md 3.5 规则 4
- **影响范围**：`lib/domain/records/writers/event_writer.dart`（`softDelete` + 两处注释）、`test/domain/records/record_write_seam_test.dart`（S14/S15）、`test/domain/providers/events_provider_test.dart`（改 1 条断言）、`test/data/local/database/daos/events_dao_test.dart`（新增 1 条钉 `emptyEventTrash` 硬删行——此前零覆盖）、`docs/{ROADMAP,CONSTRAINTS,changelog}.md`。

### [2026-09-26] 事故：v0.25.0 的 Web 产物白屏（`dart:io Platform` 在 dart2js 里是抛异常 stub）
- **症状**：`flutter build web --release` 产物在浏览器里恒为白屏（截图唯一颜色数 = 1）；Flutter 宿主元素（`flutter-view`/`flt-glass-pane`）已挂载、无网络失败，控制台只有一条无信息量的 minified 堆栈。
- **根因链（1 级）**：`main.dart:52 await AlarmService.init()`（**缺 `kIsWeb` 守卫**）→ `alarm_service.dart:10 if (!Platform.isAndroid && !Platform.isIOS) return;` → `dart:io` 的 `Platform._operatingSystem` 在 dart2js 产物里是**无条件抛异常**的 stub（产物 `main.dart.js:8138`；行号属当次产物，同日复建后为 `:8130`，同一 `Platform._operatingSystem` UnsupportedError）→ `main()` 在 `runApp` **之前**中断 → 组件树从未构建 → 白屏。
- **陷阱（修复时已遵守）**：不要用 `defaultTargetPlatform` 替代 `Platform.isX`，web 上它按浏览器 UA 返回 `android`/`iOS`，会去调不存在的原生实现。
- **如何验证**：① 对照组——最小 Flutter 应用在**同一**无头管线正常出图（排除环境因素）；② 把产物里该 stub 中立化后应用立刻出图（228 色、异常 0）；③ 判据用「唯一颜色数 > 1」而非字节数。
- **如何防复发**：`lib/infrastructure/platform/` 内平台判断一律 `kIsWeb` 先行；CI 加 web 冒烟截图断言（纯白即红）。
- **同类隐患（同批修）**：`notification_service.dart:116` 的 `Platform.isAndroid`（被上游 `.catchError` 吞掉 → web 上通知静默不初始化）；`notifications_section.dart:37/53` 用 `defaultTargetPlatform`（Android 手机浏览器上会显示出「系统闹钟」开关，点开即踩同一抛错）。
- **对应 SPEC 章节**：SPEC.md §5（边缘情况与边界防御）
- **影响范围**：`lib/infrastructure/platform/alarm_service.dart`、`notification_service.dart`、设置页通知区；**Web 平台全部用户（v0.25.0 起）**
- **修复（2026-09-26 当天完成，v0.25.1+26）**：没有就地补一行守卫，而是按"单点收敛 + 机械守卫"修（决定见下一条 ADR）——`lib/core/utils/platform_target.dart` 成为全仓 `Platform.*` 唯一读点（`kIsWeb` 短路在前），`alarm_service.dart`(5 处) / `notification_service.dart`(3 处，含原本已有 `kIsWeb \|\|` 的两处) 改用 `isAndroid`/`isIOS`/`isNativeMobile`，`notifications_section.dart` 补 `!kIsWeb`；静态守卫 `test/architecture/web_platform_guard_test.dart` + CI 冒烟断言 `tool/web_smoke.dart`（纯白即红）双闸防复发。
- **修复反证（正-反-正，2026-09-26）**：抽掉 `platform_target.dart` 的 `!kIsWeb &&` → ① 守卫测试红（`kIsWeb 短路必须先于 Platform.*`）② 重建产物冒烟判「白屏：唯一颜色数 1 < 2」并复现 `main.dart.js` minified 堆栈（与事故症状一致）；恢复后 ① 守卫绿 ② 冒烟绿（约 400 色 / 着墨比约 15.5% / 未捕获异常 0；唯一颜色数逐次略有浮动）。
- **状态**：✅ 已修复并交付（v0.25.1+26，本地实测见上；登记于 `docs/START_HERE.md` 队列 #0 与 `docs/ROADMAP.md` P1 → 均已关单）

### [2026-09-26] 决策：`Platform.*` 单点收敛 + CI web 冒烟断言（v0.25.1）
- **背景**：白屏事故当天修复（见上条）。症状一个、根因一行，但"能一路发到用户手里"本身是流程缺口：CI 只验证了构建成功，没人打开产物看一眼。
- **决定**：① **结构式修复**而非就地补守卫——`lib/core/utils/platform_target.dart` 成为全仓 `Platform.*` 唯一读点（`kIsWeb` 短路在前），配静态守卫测试（白名单 + 必须与 `kIsWeb` 同行 + 扫描器自证 + 受守卫站点计数），与既有 `record_seam_guard_test`（单写入口 + 守卫）同构；② 给 CI 加一条"打开看一眼"的机械断言 `tool/web_smoke.dart`——静态服务 `build/web` + headless Chrome(CDP) 截图 + 手写 PNG 解码，判据 = 唯一颜色数 + 着墨比，**同时挂 `ci.yml` 与 `release.yml` 的 `build-web`**（v0.25.0 正是从 release 链路发出去的，发布门必须也挡）。
- **备选与否决**：就地逐点加 `!kIsWeb &&`（改动更小，但 8 处散落、下次照样漏）否；`defaultTargetPlatform` 替代 `Platform.isX` 否（web 上按 UA 返回 android/iOS → 调不存在的原生实现）；引 npm/puppeteer 截图否（新增 CI 依赖链，且本仓库零依赖脚本已有先例 `tool/check_version_consistency.sh`）。
- **代价与边界（据实披露）**：`web_smoke` 只保证"渲染出了内容"，不保证内容正确；`--fail-on-errors` 默认关闭（页面有未捕获异常只打印，需要时手动收紧），以免 CI 抖动；PNG 解码只支持 8 位非隔行（= Chrome 截图形态），其它形态明确抛错而非静默降级。**判据是启发式，两个已知误判已实测**：内容稀疏但真实渲染的页面（标题+段落，着墨比 0.385%）会被判白屏；纯 CSS 渐变底的空白页（着墨比 89%）会被放行——本 App 首屏余量约 31 倍（15.5% vs 0.5% 阈值），且生成的 `index.html` 无 CSS 背景，故 pre-`runApp` 抛错仍落在纯白上。**判据不止"不白"**：初版只说"唯一颜色数 + 着墨比"，独立审查当场演示了一个假绿——把宿主探测降级成诊断后，一张**根本不是 App** 的 502 占位页（有内容、非纯白）会被判 PASS。补上四道正身信号：① 产物目录自检（`index.html` + Flutter 引导脚本 + `main.dart.*` 齐件，否则当场拒）；② 主文档（**仅主框架**：`type == 'Document'` 也含 iframe，故按 `Page.navigate` 返回的 `frameId` 过滤）状态必须 2xx/304（`Network.responseReceived`）；③ Flutter 主脚本必须加载成功；④ 宿主元素必须存在（`flt-glass-pane` / `flutter-view` / `flt-scene-host`，换渲染器时用 `--allow-missing-host` 显式放行）。红色控制已跑：非 Flutter 占位页 → `不是 Flutter web 产物`；产物文件齐全但引擎没启动（真 `index.html` + 真 `flutter_bootstrap.js` + 零字节 `main.dart.js`）→ `未探测到 Flutter 宿主元素`。静态服务的路径判定同时从"前缀比较"改成"拒绝点段"，补掉 `..%2f`（pathSegments 把 `%2f` 解成段内斜杠）的目录穿越。
- **影响范围**：新增 `lib/core/utils/platform_target.dart`、`test/architecture/web_platform_guard_test.dart`、`test/core/utils/platform_target_test.dart`、`tool/web_smoke.dart`、`test/tool/web_smoke_test.dart`、`test/ui/pages/settings/notifications_section_test.dart`（native 侧闸门可见性回归）；改 `lib/infrastructure/platform/{alarm_service,notification_service}.dart`、`lib/ui/pages/settings/settings_sections/notifications_section.dart`、`.github/workflows/{ci,release}.yml`、`docs/{ROADMAP,CONSTRAINTS,START_HERE,changelog}.md`；版本 `0.25.1+26`（app 用例 316 → 345）。
- **对应 SPEC 章节**：SPEC.md §5（边缘情况与边界防御）

### [2026-10-01] 吸收 vibe-coding-starter 经验：i18n 三道门禁 + 门禁总账 + 通知切语言修复
- **触发背景**：以 vibe-coding-starter（`0cae2f4`）为蓝本对照，发现本地三处短板：① ARB 中英 274/274 齐平，但**没有任何门禁守着它**；② `lib/` 目前无裸文案，同样无门禁防止变脏；③ 通知属于"字典之外的出口"——文案在排期时烘焙进 OS，切语言后不刷新（真 bug）。
- **核心决策**：
  1. **两道 l10n 守卫落地**（`test/architecture/`）：`l10n_parity_guard_test.dart`（ARB 键双向对齐，漏译与废弃键都报）+ `no_raw_text_guard_test.dart`（`lib/` 非注释行不得含中文，豁免走白名单且必须写 WHY、并反向校验无死豁免）。两者都自带违规/合规样本自证。
  2. **通知切语言修复**：`ReminderReconciler.onLocaleChanged()` —— 以「上次排期实际用的语言」`_stringsLocale` 为判据（而不是让调用方猜"这是不是首次回调"，那会引入"监听是否先于 load 注册"的次序假设）；只清 `_applied` 中值非 null 的条目（保留"已知无通知"标记，省掉无谓 cancel）；因 `_reconcileParent` 开头有"父状态没变就早退"的常规优化，**必须加 `force` 旁路**——语言切换恰恰是"数据没变但平台侧必须重做"的场景。
  3. **出口清单** `docs/l10n-outlets.md`：把通知 / 小组件 / 服务端错误 / AI 输出 / 原生资源逐条列出，标明文案来源、语言取自、切换时如何刷新、覆盖手段；并显式登记三个已知缺口（原生通知渠道名、AI 语言约束是启发式、裸文案守卫是事后扫描）。
  4. **门禁总账** `docs/GATES.md`：19 条门禁逐条列出守什么/挂在哪/**红过没**。判据取自 `TESTING.md` §一.7「一条没红过的门禁视为不存在」——本表把"12 条未记录"如实暴露出来，而非假装都验过。
  5. **`docs/process/` 五件重取更新**（原四件停在 `d339922`）：补入契约防线、规范即测试、门禁即证据、测试层级与证据报告、正交验证、溯源验收、漂移守卫、棘轮基线、异步排查，并新增第五件 `LOCALIZATION.md`（五个返工源 → 三层强制 + 可执行配方）。
  6. **pre-commit 从"只跑 analyze"扩到三门**：`dart analyze` + `tool/guard_test_tampering.py` + `tool/scan_hardcoded_paths.py`（都很快）。`check_whitespace.py` 进 CI 不进钩子。
- **顺带修正（门禁抓出来的真问题）**：
  - `lib/core/l10n/rrule_text_delegate.dart`（纯中文 delegate）**无任何引用**，是死代码，已被 `LocaleAwareRRuleTextDelegate` 取代 → 删除；留在仓库里会被后来者当成"现成的中文方案"重新接上。
  - `tool/scan_hardcoded_paths.py` 原实现用 `os.walk` 扫文件系统，会把 `ios/Pods` 里 sqlite 源码的 `/home/fred/data.db` 示例判为违规 → 改为只扫 `git ls-files` 跟踪的文件（**上游 starter 有同样的问题，待回流**）。
- **变异实证（五条，全部当场跑通）**：① 删 `app_zh.arb` 的 `todoReminder` → `zh 漏译 1 个键：todoReminder`；② `lib/` 写入 `Text('你好')` → `about_section.dart: 第 26 行`；③ 写入 `/home/chang/secret` → `file:line` 报出；④ 删掉一条既有 `expect(schedules, isEmpty)` → 防篡改门禁报出断言原文；⑤ `.gitignore` 加行尾空格 → 报出 `file:line`。
- **代价与边界（据实披露）**：
  - 通知切语言时会对**所有已排期通知**重下一次平台调用——语言切换是低频用户动作，可接受；但极端情况下（数百条提醒）会有一小段平台调用抖动。
  - `_stringsLocale` 只记 `languageCode`：`zh` 与 `zh-Hans` 视为同一语言。当前只支持中英，无影响；将来加地区变体需改判据。
  - 裸文案守卫**只拦新写的**，拦不住"该加的 key 没加"——后者靠键对齐门禁，且要等 key 加进 en 之后才生效。
  - `rrule_generator` 的 `RRuleTextDelegate` 只收裸字符串，接不进 ARB，故 `LocaleAwareRRuleTextDelegate` 内联中英两套——**加第三种语言必须改代码**（已记入 `docs/CONSTRAINTS.md`）。
- **影响范围**：新增 `test/architecture/{l10n_parity,no_raw_text}_guard_test.dart`、`docs/{GATES.md,l10n-outlets.md,docs/qa/TEST_EVIDENCE_TEMPLATE.md}`、`docs/process/LOCALIZATION.md`；改 `lib/domain/records/reminder_reconciler.dart`、`lib/domain/providers/{record_bus_provider,reminders_provider}.dart`、`docs/process/{TESTING,REVIEWING,EXECUTION}.md`、`tool/scan_hardcoded_paths.py`、`scripts/setup-hooks.sh`、`.github/workflows/ci.yml`、`CLAUDE.md`、`AGENTS.md`、`docs/CONSTRAINTS.md`；删 `lib/core/l10n/rrule_text_delegate.dart`。
- **对应 SPEC 章节**：SPEC.md §1.1 冻结需求 8 条之外的行为规范；i18n 属工程执行层，不改变产品契约。

### [2026-10-01] 决策：月初月视图显示上个月 = 设计意图，不是 bug
- **触发背景**：10-01 点"月"渲染的是 9 月，`marked_month_day_header_test` 因此每月约 4 天假红。定位后发现根因是 `_anchorFromRange`（week 分支取 `range.start`）把 `_anchorDate` 从"今天"改成了"本周周一"。
- **备选与否决**：
  - (a) 改 `_anchorFromRange` 让切月视图显示"今天所在月"——**否**：锚点跟随**所在周**是本项目的一贯语义，为迁就一个直觉单独改 month 分支会让 week/month 两个分支语义分裂；
  - (b) 认为现状是 bug、改产品——**否**，理由同上。
- **核心决策**：**接受现状**。锚点跟随"当前可见周的第一天"是设计意图；月初头几天看到上个月是正确行为。
- **连带约定**：`_anchorFromRange` 的 week 分支（`range.start`）不得为了"看起来更符合直觉"单独改动；要改必须连同 `marked_month_day_header_test` 一起改，并更新 `docs/CONSTRAINTS.md` 的裁定。
- **同时修掉的**：测试原先按 `DateTime.now().month` 算期望值 → 改为按 anchor 规则算，消除每月约 4 天的假红（假红会掩盖真实回归）。
- **影响范围**：`test/ui/widgets/calendar/marked_month_day_header_test.dart`、`docs/CONSTRAINTS.md`、`docs/START_HERE.md`、`docs/GATES.md`。**产品代码零改动。**
- **对应 SPEC 章节**：不涉及业务契约，属交互语义裁定。

### [2026-10-01] 决策：不开 `enforce_admins`，直推 main 继续绕过必需检查（已知并接受）
- **触发背景**：2026-10-01 连续三次推送 main，远端都回了 `Bypassed rule violations: Changes must be made through a pull request / Required status check "test" is expected`。查得分支保护配置为：PR 必需 ✓、必需检查 `["test"]` ✓、**`enforce_admins: false`**——管理员可绕过。首次推送后 main 确实红了几分钟。
- **备选与否决**：
  - (a) 开 `enforce_admins` + 批准数保持 1 —— **否**：GitHub 不允许自己批准自己的 PR，而本仓库协作者只有作者一人 → **主分支会对本人彻底关死**；
  - (b) 开 `enforce_admins` + 批准数改 0 —— **否（本次）**：虽能避免锁死，但等于把"外部 PR 必须先经作者审阅"这条保护一并撤掉；用户权衡后选择先不动；
  - (c) **保持现状**。
- **核心决策**：**保持现状（c）**。已知并接受：直推 main 会绕过必需状态检查，CI 属于**事后验证**而非事前卡口。
- **因此的责任分配（必须遵守）**：
  1. **推送前本地必须跑完 `dart analyze .` + `flutter test`**，并以输出为证——CI 不再是你的安全网；
  2. 每次推送后**必须回看那次 CI 的结论**（`gh run list --branch main --limit 1`）；红了要立刻修，而不是等下一次推送顺带发现；
  3. `build-macos` 等构建 job 偶发失败先按偶发处理，但要用 `gh run rerun --failed` 证明确属偶发（2026-10-01 有一次 `cdn.cocoapods.org` DNS 失败，重跑即过）。
- **复核触发条件**：若将来增加第二个协作者，应重新评估 (a)/(b)——那时"自己批不了自己的 PR"不再是障碍。
- **影响范围**：仅流程约定，无代码改动。落点：本条目 + `CLAUDE.md` CI 规则段。

### [2026-10-01] P5-a 设备注册交付 + P5-b 选型（C+D 为主，A 可选）
- **触发背景**：P5 是产品定位里唯一未兑现的核心承诺——「App 一关就收不到远端变更」。摸底发现地基全在（outbox / LWW / 幂等 / SSE / 单写缝），缺的是两件：设备身份没落地、后台无通道。
- **诊断（实测）**：客户端 `deviceId` 早已生成并随 push body 上报；服务端 `Devices` 表也早已建好——**但没有任何一处写入它**，`applyInternalOp` 不接收 deviceId，`x-device-id` 头客户端从不发。所谓"devices 表半出生"，指的就是这个。
- **P5-a 核心决策**：
  1. 设备归属落在 **`SyncOps.deviceId`** 而非 `Records`：`Records` 是"当前状态"（已有 `lastOpId` 表达"谁最后写的"），设备归属是**逐 op 的历史**，SyncOps 本就是 append-only 的 op 账本。**代价**：服务端 schemaVersion 3 → 4，需要迁移。
  2. `x-device-id` 头优先、push body 回退：头覆盖所有认证端点，body 是客户端一直在用的老路径，两者都留。
  3. 注册挂在 **provider**（登录态 + baseUrl 就绪即上报）而不是只塞进登录成功那一行——只挂登录的话，**升级前已经登录过的设备永远不会被登记**，而它们恰恰最该出现在设备列表里。
  4. 跨账号 deviceId 冲突返回 **409 不重绑**：deviceId 按安装铸造、永不复用；静默重绑会让一个账号认领另一个账号的设备行——将来那行上会挂唤醒通道，值得偷。
- **P5-b 选型（用户拍板）**：**C（后台拉取：WorkManager / BGAppRefreshTask）+ D（回前台补同步）为主；A（FCM/APNs）做可选开关、默认关。** 否决 B（自托管推送 UnifiedPush/ntfy）：Android 好但 iOS 无对应实现，只覆盖一半平台还要多维护一条通道。A 不是不能做，而是会把「何时、哪台设备有变更」这类元数据交给 Google/Apple——**这个判断该由用户做**，所以默认关并在设置里明确告知。
- **据实披露的边界**：C 是"尽力而为"，iOS `BGAppRefreshTask` 由系统决定配额，可能数小时一次，**UI 不得承诺"实时"**；桌面三平台本就常驻，D 基本够用；Web 关掉标签页同样只能靠 D。
- **顺带补齐**：服务端此前**没有任何迁移测试**（客户端早有 `migration_test.dart`），而 v4 是服务端第一次被迫迁移。已补 `server/test/migration_test.dart`：用裸 sqlite3 把库倒回 v3 形状再打开，验数据保留、新列补上且旧行为空串（不凭空造归属）、迁移后写入仍可用、重复打开幂等。
- **影响范围**：`server/lib/src/{schema,db,routes/devices,routes/sync,sync/idempotency,data/record_writer}.dart`、`server/lib/server.dart`、`packages/dayspark_contracts/lib/src/device_dto.dart` + barrel、`lib/core/utils/device_label.dart`、`lib/domain/sync/sync_api_client.dart`、`lib/domain/providers/sync_client_provider.dart`、`lib/main.dart`、`lib/ui/pages/settings/settings_sections/account_section.dart`、`lib/l10n/*.arb`（+5 键）；新增测试 4 个文件。**版本号未动**（发版另行确认）。

### [2026-10-04] Todo 时间安排采用 TaskAllocation 与 occurrence 级本地时区语义
- **触发背景**：用户确认日历与 Todo 通过独立时间安排连接；需冻结 `dueDate` 与执行安排的边界、完成/取消生命周期、busy-time 语义及重复 Todo 跨设备身份，避免把 UI 或同步实现误当产品契约。
- **核心决策**：
  1. 保留现有 `Todo` 与 `Event` 为独立一等领域记录；新增概念命名 `TaskAllocation`。不改名、不合并现有实体；Calendar 是时间投影，首页导航不由本决策规定，Todo 页面仍是任务状态管理主要入口。
  2. 一个 Todo 可拥有多个 Allocation；`dueDate` 与 Allocation 完全独立。改期/取消 Allocation 不修改 `dueDate`；单独取消 Allocation 不影响 Todo。
  3. Allocation 状态为 `active`、`cancelledByUser`、`invalidatedByCompletion`。用户取消保留历史、普通 Calendar 隐藏；Todo 完成时，已结束与进行中的 Allocation 保持原状态，满足 `startAt >= completedAt` 的未来安排改为 `invalidatedByCompletion`。完成撤销不自动恢复这些安排，用户须显式重新安排。
  4. Todo 进回收站期间 Allocation 及状态保留，但隐藏且不占 busy time；恢复后仅原 `active` Allocation 恢复投影。Todo 永久删除时 Allocation 随父项永久删除并同步 tombstone。
  5. 仅 `active` Allocation 且父 Todo 未取消、未进回收站时占用 busy time；Todo 已完成时按完成时刻执行失效边界校验，正在进行的 Allocation 仍占用至原结束时刻。首版 Allocation 无独立 Reminder；Todo Reminder 维持现有语义。
  6. 重复 Todo 的 Allocation 绑定单一 occurrence，不自动套用整个系列。occurrence 使用本地钟点语义；有 `startDate` 时优先作为 recurrence anchor，否则以 `dueDate` 为 anchor；两者均无则不允许创建 occurrence 级 Allocation。跨设备 identity 由 Todo 同步 ID、本地 recurrence 日期时间和系列 IANA 时区确定；UTC recurrence-id 仅为迁移过渡，不是长期协议。
- **对应 SPEC 章节**：SPEC.md §1.1 第 1 条、§3.1–§3.3、§3.5、§4.1、§5。
- **影响范围**：后续实施需覆盖客户端 Drift schema / migration、Todo 与 Allocation Writers/Providers、Calendar Projection、outbox/applier、`dayspark_contracts` RecordType、服务端记录解析与 LWW、MCP `find_free_time` 和 Allocation 工作流。首版不改首页导航、Reminder 结构或 Widget JSON/原生消费端。
- **重要实现约束**：现有 Todo 未保存重复系列 IANA 时区。新重复 Todo 必须持久化该值并同步；旧重复 Todo 不得按设备当前时区静默推断，未明确保存时不得创建 occurrence Allocation。服务端 generic per-field LWW 不能单独保证跨记录完成失效；完成 Todo 与未来 Allocation 状态变更必须有原子、可收敛的写入路径。

### [2026-10-04] TaskAllocation 分阶段实施、兼容门控与完成边界精度
- **触发背景**：TaskAllocation 产品契约已冻结；先用普通非重复 Todo 验证本地领域模型和 Calendar 投影，避免重复规则、同步协议及外部写入口扩大第一条纵切片。
- **核心裁定**：
  1. Phase 1 只实现普通非重复 Todo → 创建 TaskAllocation → Calendar 显示 → 改期 → 取消。范围不含重复 Todo、`recurrenceTimeZone`、occurrence identity、跨设备同步、Allocation MCP 写工具、Widget、Allocation Reminder、Today/Timeline、自动排程、estimate 或 actual duration；不改首页导航。
  2. Phase 1 的重复 Todo 安排入口必须隐藏或明确拒绝。新建、改期、取消 Allocation 均不得改写 Todo `dueDate`；用户取消保留 Allocation 记录并置为 `cancelledByUser`；普通 Calendar 只投影 `active` 项。
  3. 旧客户端兼容采用服务端 capability 门控。服务端不得向未声明支持 `task_allocation` 的客户端返回该 RecordType；旧客户端仍可同步 Event/Todo，但不能读写 Allocation。capability / protocol contract 必须进入 `dayspark_contracts` 与测试，不以散落的版本号分支替代。发布顺序：支持解析的新客户端 → 服务端按 capability 开启下发 → 开放 MCP/外部写入口。
  4. Allocation `startAt/endAt` 与 Todo `completedAt` 比较前统一为 UTC instant 并截断到毫秒，禁止四舍五入。`endAt <= completedAt` 保留历史；`startAt < completedAt < endAt` 保持 active 至原结束；`startAt >= completedAt` 失效，包含相等边界。
- **代价与边界**：Phase 1 暂不验证 Allocation 的同步或 busy-time 效果，不能据此宣称跨设备与空闲时段功能完成；后续阶段必须在开放外部写入前完成对应契约与兼容测试。
- **对应 SPEC 章节**：SPEC.md §3.1、§3.2、§3.5。
- **实施计划**：`docs/superpowers/plans/2026-10-04-task-allocation.md`。

### [2026-10-04] TaskAllocation 同步协议与删除/完成收敛
- **触发背景**：Phase 2 需要把本地 TaskAllocation 扩展到跨设备；现有 RecordType 解码对未知类型 fail-fast，pull 原始分页 cursor 与 capability 过滤尚未存在；Todo 软删和永久删除都用同一种未区分的 delete tombstone。
- **核心裁定**：
  1. 能力名固定为 `task_allocation_v1`。客户端通过认证的 `/sync/capabilities` discovery 确认服务端支持后才发送 Allocation outbox；push 与 pull 均声明 capabilities。旧服务端 discovery 404 时客户端仍同步 Event/Todo，并保留 Allocation outbox。服务端缺省 capabilities 视为空集合，未知 capability 忽略。
  2. 服务端在原始有界 seq 页上先读后过滤；pull `nextCursor`、`hasMore` 与 push piggyback watermark 都按扫描到的原始记录推进，不按过滤后列表推进，确保旧客户端越过隐藏 Allocation。
  3. 为 Todo hard-delete op 增加 `hardDelete: true` tombstone payload marker；历史无标记 tombstone 仍进回收站。只有显式标记才在新客户端物理删除 Todo 及关联 Allocation。Todo 永久删除/清空回收站先捕获 Allocation sync identity、再在同一 DB transaction 内 enqueue Allocation 与 Todo tombstone，最后删本地行。
  4. TaskAllocation 保留 `todoSyncId` 为逻辑父引用，`todoId` 可空；父项先到时允许 unresolved 行存在，Calendar 查询通过父 Todo inner join 隐藏，父项到达后按 UUID 解析绑定。
  5. 服务端对已完成父 Todo 的 Allocation upsert 强制执行 UTC 毫秒完成边界；父 Todo 完成时同事务为未来 active Allocation 写失效状态。服务端对 terminal `state` 保持单调，避免迟到改期激活取消/失效项；hard-delete 父项对相关 Allocation 写 tombstone，后到 upsert 不得复活。
- **并发边界**：字段级 LWW 继续合并独立时间字段与单字段状态；终态单调与 completed-parent invariant 是领域约束，不依赖客户端时钟或请求抵达“正常顺序”。
- **对应 SPEC 章节**：SPEC.md §3.5 规则 6、§4.1.1、§4.2、§5。
- **实施计划**：`docs/superpowers/plans/2026-10-04-task-allocation.md` Phase 2。
