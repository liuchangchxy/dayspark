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
  - **远端 tombstone 为何不删提醒行（T4 明确不改的一个既有行为）**：pre-T4 的 applier 落 tombstone 时**根本不动提醒行**——提醒行在本地一直保留；T4 只是给这条路径补上 `removed` + `reminderIds` 登记（撤销 OS 通知），行仍保留为惰性。因此"远端保留 / 本地硬删"的**分歧是既有的**（真正的异类是 `EventWriter.softDelete` 连带硬删行），不是 v0.25.0 引入的新行为；T4 选择两侧都不动（`applyRemoteTombstone` 不删行、也不改本地软删），把统一与否留给产品拍板 → `docs/ROADMAP.md` Pending Items P3 #5。
  - **两件零调用者的"逃生门"复核结论（T4 收尾）**：`scheduleReminderProvider` 保留（T2 简报定义的"保留一个版本"逃生门：重排器错杀 snooze 时可回退到通知服务直调；删除属于回滚路径变更，另立一项）；`ReminderWriter.referenceChanged` 保留（**T4 applier 不用它**——远端改期走 `EventWriter/TodoWriter.applyRemote`，由 writer 自己"写前读旧值 + 写 + 登记"，比"写一格、再另调一格登记"更紧；`referenceChanged` 与 R1a/R1b/R1c 三条测试留档，钉住"只登记位移"这一格的语义）。两者清理记入 ROADMAP Pending Items P3。
- **对应 SPEC 章节**：SPEC.md 3.5（规则 1/2/4/5）、第 2 节记录缝模块
- **影响范围**：`lib/domain/records/**`（新增缝/总线/写入口/重排器）、`lib/domain/providers/record_bus_provider.dart`、全部写路径 provider、`lib/domain/services/ics_service.dart`、`lib/domain/sync/{sync_applier,sync_engine}.dart`、`test/architecture/record_seam_guard_test.dart`、`tool/record_seam_baseline.txt`、`docs/CONSTRAINTS.md` 架构与小组件章节、`docs/ROADMAP.md` P2.5 #1 关单。
