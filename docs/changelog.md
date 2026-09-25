# DaySpark User Feedback Log / 用户反馈记录

**TL;DR / 快速了解**
- 本文件记录所有用户反馈及其修复，按版本倒序排列
- 最新版本 / Latest: **v0.25.0+25** — Debt 2 unified event seam: every in-process record write now publishes a post-commit domain event (record-applied/record-removed); remote reschedule re-arms local reminders, remote delete cancels queued notifications, event-trash restore re-arms (incl. after a local soft delete — reminder rows are now kept, symmetric with todos); three ad-hoc invalidation channels collapsed into one seam with a single-write-entry guard and an emptied ratchet baseline / 债务2 统一事件缝：进程内一切记录写入改为"写入即登记、提交后发布"的领域事件；远端改期重挂本机提醒、远端删除撤销已排队通知、事件回收站恢复重挂（含本地软删后再恢复：提醒行改为保留，与待办侧对称）；三条临时通道收敛为一条缝 + 单写入口守卫 + 棘轮基线收敛为空
- 上一版本 / Previous: **v0.24.0+24** — P4 platform parity + todo UX: Apple bundle/App Group unification, widget v2 three variants + pendingTaps + quick-add deep link, six-things/hide-completed, solar-term/holiday month markers, settings IA terminal, calendar debts, time-sensitive notifications (device-gate caveat), adhoc keychain signing fix / P4 平台补齐与待办体验：Apple 资产统一、小组件 v2 三变体 + 勾选队列 + 快速添加、六件事/隐藏已完成、节气调休月标记、设置 IA 终态、日历体验清欠、time-sensitive 通知（设备门 caveat）、adhoc keychain 签名修复
- 最新流程改进 / Pipeline: **SPEC/DECISIONS/AGENTS + pre-commit analyze gate** — 2026-09-22
- 查看 `docs/ROADMAP.md` 获取功能全景，`docs/CONSTRAINTS.md` 获取技术约束

---

## v0.25.0+25 — Unified Event Seam / 统一事件缝（债务 2）

### Features / 新功能

| # | Feature / 功能 |
|---|------|
| 1 | **Single invalidation seam for derived state / 派生态单一失效缝** — 进程内一切 `events`/`todos`/`reminders` 行写入收敛到单写入口 `RecordScope.run` + `lib/domain/records/writers/**`：**写入即登记**（`applied` / `removed` / `bulkChanged`），**提交后**才发布（事务回滚 = 零发布）；三条临时通道（provider 内联手调、UI save 后手写补丁、小组件 `tableUpdates`）收敛为一条缝，`rescheduleRemindersProvider` 与全部内联 `cancel`/`schedule` 调用点撤除。新增两个消费端：`ReminderReconciler`（四档取消 + 位移锚点归属 + 幂等零调用）与小组件刷新器（驱动源 → 领域事件总线）。 / **派生态单一失效缝** — 写入路径统一登记 + 提交后发布；三条临时通道 → 一条缝，两个消费端接管闹钟重排与组件刷新 |
| 2 | **Remote schedule edits re-arm local reminders / 远端改期重挂本机提醒** — 同步落地（pull / push conflict / piggyback，含 MCP 与 AI 的远端写入）经 applier 写入时登记 `applied(previousReference: 写前 startDt/dueDate)`，重排器按 Δ 搬迁提醒时刻并把新触发时刻**物化回写** `reminders.triggerTime`（行内值是下一次位移的锚）。 / **远端改期重挂** — 四种同步落地分支统一重排，远端改期不再让本机闹钟停在旧时间 |
| 3 | **Mechanical anti-escape guards / 机械防漏守卫** — `record_seam_guard_test.dart`（G1 写入白名单 / G3 已删通道符号 / G4 `RecordScope.run` 站点数 == 常量）+ `tool/record_seam_baseline.txt` 棘轮账本：未登记的写入即红，**条目失效 / 条数变少 / 等量置换也红**（逼审查者看 diff）。基线已收敛为空 = 全仓零豁免。 / **机械防漏守卫** — 写入白名单 + 站点计数 + 棘轮基线（收敛为空） |

### Bug Fixes / 修复

| # | Issue / 问题 | Fix / 修复 |
|---|------|----------|
| 1 | **远端删除不撤销已排队通知 → 幽灵响铃** — 同步 applier 把远端 tombstone 落到本机软删后，此前排给 OS 的提醒/闹钟仍在原时刻响（债务2 勘察新发现的未登记缺陷） | 远端 tombstone 落地时登记 `removed(type, id, reminderIds: 写前抓下的全部 id)`，重排器第一档无条件 `cancel` 这些 id；reminder 行保留为惰性（远端删除不是用户在本机做过的动作，不连带销毁本机数据）。 / Ghost ringing fixed: remote tombstones now cancel every queued notification for that record |
| 2 | **远端改期后本机闹钟停在旧时间（P2.5 #1）** — `pull`/`piggyback` 应用的 start/due 变更不会重排本机提醒，跨设备改期后本机按旧时刻响 | 引擎两处事务改经 `RecordScope.run`、applier 六个写点走 writer 并携带写前参考时间；重排器按 Δ 重排 + 物化回写，绝对时刻 `newTrigger = 新参考 − (旧参考 − 旧触发)`。 / Local alarms now follow remote schedule edits |
| 3 | **远端删除后本机 `deletedAt` 已置但提醒行仍在** — tombstone 只改父行，提醒副作用无人接手 | 与修复 1 同一刀：登记 `removed` + 携带 reminderIds，撤通知不再依赖父行重读。 / Covered by fix 1 |
| 4 | **事件进回收站再恢复，提醒永远不响** — 事件软删连带硬删提醒行（与待办侧不对称），`restoreEventProvider` 不重建行，用户恢复事件后提醒永久沉默 | 统一为**保留**：`EventWriter.softDelete` 不再删提醒行、登记改回 `applied`（`previousReference` = 写前 `startDt`），OS 通知由重排器读父行 `deletedAt != null` 走 `inactive` 档撤销；恢复时同一批 id 按行内 `triggerTime`（Δ=0）重新排上（触发时刻已成过去的按 `pastDue` 档保持惰性、不补响，与待办侧同）。硬删路径（`hardDeleteEventWithChildren` / `emptyEventTrash`）仍硬删行。 / **Deleted-then-restored events re-arm their reminders** — soft delete keeps reminder rows (symmetric with todos); restore re-schedules the same ids |

### Infrastructure / 基础设施

| # | Change / 变更 |
|---|------|
| 1 | **Version guard's first real use** — `tool/check_version_consistency.sh` 在本次版本号变更中首次实战（五处一致 + `--selftest` 能红）；`test/architecture/record_seam_guard_test.dart` 的 `_scopeRunSites` 随站点增删显式改常量（22 → 25）。 / **版本守卫首次实战** + 守卫常量随站点收敛 |
| 2 | **Full verification** — root `dart analyze .` 0 issue、`flutter test` 316/316（`skipped=0`）；server / contracts / wrapper / CLI / Kotlin 五套本任务未触碰，跑一遍确认无意外。 / **全量验证** — app 316 全绿 + 五套回归确认 |

---

## v0.24.0+24 — P4 Platform Parity + Todo UX / P4 平台补齐与待办体验

### Features / 新功能

| # | Feature / 功能 |
|---|------|
| 1 | **Apple asset unification** — bundle id `dev.opencal.*` → `com.dayspark.app*`（Runner/扩展/测试 target）、App Group `group.com.calendarTodoApp` → `group.com.dayspark.app`（entitlements + Swift suiteName + Dart `setAppGroupId` 原子同改），`dayspark` URL scheme 双端注册，CI 新增 iOS simulator 编译门。 / **Apple 资产统一** — bundle id 与 App Group 全量迁入 `com.dayspark.app` / `group.com.dayspark.app` 族（宿主/组件/代码原子同改），双端注册 `dayspark` scheme，CI 加 iOS simulator 构建门 |
| 2 | **Widget v2, three variants** — Today / Upcoming / 月点阵 × Android/iOS/macOS 全部改读 versioned `widget_snapshot` v2（+`monthDots` 10 键契约）；**pendingTaps** 勾选队列（原生只入队、app 经既有 toggle 单一写路径消费，同 todoId last-wins）；**`dayspark://quick-add` 快速添加 deep link**（interactivity 回调只导航）；`ui` 块按 locale 预本地化（原生零硬编码英文）+ `theme` 暗色样式；macOS home_widget 方法通道 shim。 / **小组件 v2 三变体** — Today/Upcoming/月点阵 × 三端改读 v2 快照（含 `monthDots`）；`pendingTaps` 勾选队列走既有单一写路径；`dayspark://quick-add` 快速添加通路；文案预本地化 + 暗色主题；macOS 方法通道 shim |
| 3 | **Six things + hide-completed** — 今天视图 Ivy Lee 六槽收敛（DateStrip chip，**默认 OFF**）+「更多 (N)/收起」折叠，复用既有拖拽排序前缀语义；设置 → 待办区六件事/隐藏已完成双开关（`hide_completed` 持久化，ON 隐藏三视图已完成分组）。 / **六件事 + 隐藏已完成** — 今天视图六槽收敛（默认 OFF，chip + 设置开关）与「更多/收起」折叠，复用既有拖拽管线；隐藏已完成过滤全部待办视图 |
| 4 | **Solar-term & holiday month markers** — 接入纯 Dart `lunar ^1.7.8`：月视图日期头渲染节气微标签（24 个 zh/en l10n key）+ 法定班/休角标（数据止于 2026，2027+ 班/休静默降级、节气算法不受影响）；月视图非当月日期整格淡化。 / **节气/调休月标记** — 接入 `lunar ^1.7.8`：节气微标签 + 班/休角标（法定数据止于 2026，2027+ 角标静默降级），非当月日期淡化 |
| 5 | **Settings IA terminal** — 一级精简为外观组（语言/默认标签/主题色等）→ 功能组（待办/数据/账号/AI/通知）→ 折叠「高级」收纳关于 + 开源许可；危险/低频项不再平铺一级。 / **设置 IA 终态** — 一级 = 外观组 → 功能组 → 折叠「高级」（关于 + 许可），低频项全部入高级 |

### Bug Fixes / 修复

| # | Issue / 问题 | Fix / 修复 |
|---|------|----------|
| 1 | **macOS adhoc 启动 SIGKILL（2026-09-24 用户实测崩溃）— `keychain-access-groups` 填 `$(AppIdentifierPrefix)` 在 adhoc/teamless 签名下展开为裸 bundle id，taskgate 以 `Invalid Signature` 拒绝 spawn（`codesign --verify` 仍通过）** | 实验证明**空数组同样崩**（exit 137 复现）→ 整键从 `macos/Runner/{DebugProfile,Release}.entitlements` 删除并留 WHY 注释；重建后直跑存活 ≥7s。约束见 `docs/CONSTRAINTS.md` macOS 签名章节 / Root cause proven by experiment: even an empty array crashes — key removed entirely; launch gate re-verified |
| 2 | **P1 日历遗留 (b) 类欠账** — 日/周从 00:00 起滚、事件 tile 桌面无 click 光标、空白槽无语义节点、月视图非当月日期不淡化 | `initialTimeOfDay` 08:00、事件 tile `MouseRegion(click)` ×2、空白槽 `Semantics(button)`（day/week）、非当月 header `Opacity 0.3` / Four calendar debts cleared (scroll/cursor/semantics/dim) |
| 3 | **iOS time-sensitive 通知从未真正生效 — `Runner.entitlements` 文件存在但 pbxproj 无 `CODE_SIGN_ENTITLEMENTS`（inert）；接线后个人 team 拒绝 capability，device/TestFlight 构建 fail-closed** | 补齐 Runner Debug/Release/Profile 三配置接线 + schedule/snooze 两路径 `interruptionLevel: .timeSensitive`；**设备门 caveat**：真机/TestFlight 前须付费 team 保留或删该 entitlement 行（代码优雅降级），模拟器/CI 不受影响 / Entitlement wired on all 3 configs + time-sensitive on both schedule paths; device-gate caveat recorded (keep-vs-remove decision before TestFlight) |

### Infrastructure / 基础设施

| # | Change / 变更 |
|---|------|
| 1 | **Hygiene bucket（P1–P3 评审结转）** — tool 测试（`mcp_stdio_wrapper` + `dayspark_cli`）进 ci.yml `server-test` job；MCP `WINDOW` hint 去 cursor 承诺措辞；工具内部错误 `$e` → 不透明 `INTERNAL` + stderr 日志（recurrence 解析同款）；consent/error HTML 加 `X-Frame-Options: DENY` + `frame-ancestors 'none'`；RFC 7591 补 `client_secret_expires_at`/`client_id_issued_at`；`response_mode` 非 `query` 拒绝；Linux `APPLICATION_ID` → `com.dayspark.app.dayspark`（存量安装视为新应用，需重钉启动器，数据无损）。 / **卫生桶（P1–P3 评审结转）** — tool 测试进 CI、`$e` 脱敏、consent 防帧头、RFC 7591 两字段、`response_mode` 校验、Linux APPLICATION_ID 迁移 caveat |
| 2 | **Windows 通知 stub 上游复查** — pub.dev 3.1.1（2026-06-14）无 gen_snapshot AOT 修复记录且 platform-interface 版本冲突，`patches/flutter_local_notifications_windows` override **保留**，记 ROADMAP 跟进。 / **Windows 通知 stub 上游复查** — 上游无 AOT 修复且依赖冲突，override 保留，跟进记 ROADMAP |
| 3 | **Full verification** — root `dart analyze .` 0, `flutter test` 217/217, server 195/195, contracts 37/37, wrapper 9/9, CLI 20/20, Kotlin 7/7; manual QA checklist `docs/qa/p4-manual-qa.md`. / **全量验证** — 根 analyze 0、flutter 217、server 195、contracts 37、wrapper 9、CLI 20、Kotlin 7 全绿；手工验收清单见 `docs/qa/p4-manual-qa.md` |

---

## v0.23.0+24 — Server MCP + CLI / 服务端 MCP 与命令行

### Features / 新功能

| # | Feature / 功能 |
|---|------|
| 1 | **Server MCP endpoint (`POST /mcp`)** — stateless Streamable-HTTP MCP in-process with the sync backend: **17 frozen tools** (7 read + 10 write: `get_events`/`get_event`/`list_tasks`/`get_task`/`search`/`find_free_time`/`list_trash` + create/update/trash event·task, complete/reopen/snooze task, batch create) + **3 resources** (`dayspark://today`/`overdue`/`inbox`); errors-as-tool-results with code/message/hint. / **服务端 MCP 端点（`POST /mcp`）** — 与同步后端同进程的无状态 Streamable HTTP MCP：**17 个冻结工具**（7 读 + 10 写）+ **3 个资源**（today/overdue/inbox）；业务错误以工具结果返回（code/message/hint） |
| 2 | **OAuth 2.1 authorization server, two-track** — RFC 8414/9728 discovery, RFC 7591 DCR, PKCE-S256-only authorize + minimal consent page, token rotation reusing the P2 family-revoke machinery, RFC 7009 revoke; scopes `mcp:read`/`mcp:write` double-gated over tools AND resources; **track claim** — CLI login tokens vs Agent OAuth tokens never cross (`track:"oauth"` rejected on `/sync/*`). / **OAuth 2.1 授权服务器（双轨）** — 发现文档、动态注册、PKCE-S256、最小同意页、复用 P2 家族吊销的 token 轮换、撤销端点；`mcp:read`/`mcp:write` 对工具与资源双门校验；**track 声明**——CLI 登录 token 与 Agent OAuth token 互不越界 |
| 3 | **MCP stdio wrapper (`tool/mcp_stdio_wrapper`)** — stdio↔HTTP line bridge feeding local agents (Claude Code / Codex) from `POST /mcp`; network failure surfaces JSON-RPC −32002 instead of hanging; exit 78 when `DAYSPARK_MCP_URL` missing. / **MCP stdio 桥（`tool/mcp_stdio_wrapper`）** — stdio↔HTTP 行协议桥，本地 Agent（Claude Code/Codex）经此接 `/mcp`；网络失败回 −32002 不挂死；缺 `DAYSPARK_MCP_URL` 退出码 78 |
| 4 | **`dayspark` CLI (`tool/dayspark_cli`)** — thin HTTP **MCP client** (dogfoods the frozen tool surface) over `/auth/login` + `credentials.json` (chmod 600, tokens never logged): `task list/add/done/trash`, `event list/add`, `login/logout/status`. / **`dayspark` CLI（`tool/dayspark_cli`）** —以 `/auth/login` 取 token 后**以 MCP 客户端身份**调用冻结工具面的薄封装（dogfood），凭证文件 600 权限、token 永不打印 |

### Bug Fixes / 修复

| # | Issue / 问题 | Fix / 修复 |
|---|------|----------|
| 1 | **OAuth discovery and 401 challenge advertised `http://` origins behind an HTTPS reverse proxy — connectors following discovery got non-followable URLs / 反代 HTTPS 后 OAuth 发现文档与 401 challenge 仍广告 `http://` 源，connector 拿到无法跟随的 URL** | Trust first value of `X-Forwarded-Proto` when present (direct-exposure behavior byte-identical when absent); `DEPLOY.md` already ships the nginx `proxy_set_header`. / 有该头时取首个值生效（缺头时行为与原来逐字节一致）；`DEPLOY.md` 已含 nginx `proxy_set_header` 配置 |

### Infrastructure / 基础设施

| # | Change / 变更 |
|---|------|
| 1 | **MCP write path = P2 LWW/`nextSeq` internal-op seam** — every AI write lands in `applyInternalOp` (AI acts as one virtual device); device pull/SSE converge automatically; e2e matrix ①–⑤ (create propagate, complete converge, disjoint-field concurrent merge, OAuth full chain, scope demotion) all green. / **MCP 写通路 = P2 LWW/`nextSeq` 内部 op 缝** — AI 写全部走 `applyInternalOp`（AI 即一台虚拟设备），设备经 pull/SSE 自动收敛；e2e 矩阵 ①–⑤ 全绿 |
| 2 | **Body-size cap 256KB on `/mcp` + OAuth POSTs** → 413 contracts envelope (review carry, heap-DoS guard); exactly-256KB still parses. / **`/mcp` 与 OAuth POST 请求体 256KB 上限** → 413 contracts 信封（评审结转，防堆 DoS）；恰好 256KB 仍可解析 |
| 3 | **CI tool-package resolve steps** — `dart pub get` in `tool/mcp_stdio_wrapper` + `tool/dayspark_cli` (root analyze scans their tests), mirroring the contracts/server pattern. / **CI tool 包解析步骤** — 两个 tool 包各加 `dart pub get`（根 analyze 会扫到其测试），沿用 contracts/server 模式 |
| 4 | **Full verification** — root `dart analyze .` 0, `flutter test` 174/174, server analyze 0 + 187/187, contracts 0 + 37/37, wrapper 0 + 9/9, CLI 0 + 20/20; manual Inspector/Claude Code/Codex/ChatGPT checklist at `docs/qa/p3-mcp-qa.md`. / **全量验证** — 根 analyze 0、flutter test 174 全绿、server 0+187、contracts 0+37、wrapper 0+9、CLI 0+20；手工四客户端 QA 清单见 `docs/qa/p3-mcp-qa.md` |

---

## v0.22.0+24 — Sync Backend / 同步后端

### Features / 新功能

| # | Feature / 功能 |
|---|------|
| 1 | **Sync server (Docker)** — Dart shelf backend (`server/`: auth/JWT with refresh rotation, `POST /sync/push` idempotent per-op, `GET /sync/pull` watermark cursor, field-level LWW, tombstones, `GET /sync/stream` SSE cursor-only signal), drift/SQLite single-file storage, single-container deploy on NAS via `docker compose` (`docs/DEPLOY.md`). / **同步服务端（Docker）** — Dart shelf 后端（JWT 认证与刷新轮换、幂等逐条 push、水位线游标 pull、字段级 LWW、墓碑、SSE 只发 cursor 信号），drift/SQLite 单文件存储，NAS 上 `docker compose` 单容器部署 |
| 2 | **Client sync engine** — schema v9 `sync_outbox` (explicit same-transaction enqueue at provider exits) + pull/piggyback applier (event + todo) + `SyncEngine` rounds + SSE listener with reconnect/foreground triggers; offline-first, seconds-level convergence. / **客户端同步引擎** — schema v9 出站队列（provider 出口显式同事务入队）+ pull/piggyback 应用器（event/todo）+ 引擎轮次 + SSE 监听（断网恢复/回前台触发），离线优先、秒级收敛 |
| 3 | **Dual-device e2e matrix** — 5 cases against a real server inside `flutter test`: create propagate, edit converge, delete tombstone, offline field-disjoint conflict merge, alternating edits with monotonic cursors. / **双设备 e2e 矩阵** — 在 `flutter test` 内对真 server 跑 5 例：创建传播、编辑收敛、删除墓碑、离线不相交字段合并、交替编辑游标单调 |
| 4 | **Account & sync settings** — settings `account_section`: server URL / register / login / logout, sync status display, engine invalidation on auth change. / **账号与同步设置** — 设置页账号区：服务器地址 / 注册 / 登录 / 登出、同步状态展示、登录态变化驱动引擎失效重建 |

### Bug Fixes / 修复

| # | Issue / 问题 | Fix / 修复 |
|---|------|----------|
| 1 | **Lost-update on concurrent field-disjoint edits (caught by e2e case ④) — client pushed full payloads, so field-level LWW degraded to record-level overwrite and a remote description edit was reverted / e2e 例 ④ 抓到的并发丢更新——客户端全量推送使字段级 LWW 退化为整条覆写，他端 description 被改回旧值** | Client sends dirty fields only: `SyncSnapshot` store (last applied server payload, in prefs alongside cursor) + `dirtyFields` diff; empty diff = converged, op dropped. No schema change. / 客户端只发脏字段：`SyncSnapshot`（上次应用的服务端 payload，与游标同居 prefs）+ `dirtyFields` 求差；空 diff 视为收敛丢弃 op。无 schema 变更 |

### Infrastructure / 基础设施

| # | Change / 变更 |
|---|------|
| 1 | **JWT fail-fast** — container refuses to start without `JWT_SECRET` (`REQUIRE_JWT_SECRET=1` → `Config.fromEnv` throws; compose also errors on missing var); secrets never baked into the image. / **JWT 快速失败** — 缺 `JWT_SECRET` 容器拒绝启动（compose 同样报错），密钥绝不烧进镜像 |
| 2 | **`dayspark_contracts` protocol package** — shared DTOs/error codes between client and server (SSOT), 37 contract tests. / **`dayspark_contracts` 协议包** — 客户端与服务端共享 DTO/错误码（SSOT），37 项契约测试 |
| 3 | **CI `server-test` job** — `dart analyze` + `dart test` in `server/` plus contracts tests in `packages/dayspark_contracts`, independent of the Flutter jobs. / **CI `server-test` 任务** — `server/` analyze+test 与 contracts 测试，独立于 Flutter job |
| 4 | **Docker image** — multi-stage build (dart:stable → debian:trixie-slim), system `libsqlite3-0`, `/health` + HEALTHCHECK, 173 MB. / **Docker 镜像** — 多阶段构建（dart:stable → debian:trixie-slim）、系统 libsqlite3-0、/health + HEALTHCHECK、173 MB |
| 5 | **Full verification** — root `dart analyze .` 0, `flutter test` 167/167, server analyze 0 + 44/44, contracts analyze 0 + 37/37; manual dual-device QA checklist at `docs/qa/p2-manual-qa.md`. / **全量验证** — 根 analyze 0、flutter test 167 全绿、server 0+44、contracts 0+37；手工双设备 QA 清单见 `docs/qa/p2-manual-qa.md` |

---

## v0.21.0+24 — Phase 1 Foundation Refactor / Phase 1 基础重构

### Breaking Changes / 不兼容变更

| # | Change / 变更 |
|---|------|
| 1 | **DB schema v7→v8** — CalDAV sync columns (`caldav_*`, `sync_token`) and `accounts` table dropped with the sync-layer removal; automatic migration on upgrade, migration test covers v1→v8. / **数据库 schema v7→v8** — CalDAV 同步列与 accounts 表随同步层移除，升级自动迁移，迁移测试覆盖 v1→v8 |

### Features / 新功能

| # | Feature / 功能 |
|---|------|
| 1 | **kalender calendar views** — day/week/month views rebuilt on `kalender ^0.17.0` (pinned minor), replacing hand-rolled views; fixes DST wall-clock drift, GlobalKey collisions, overlapping layout, all-day series classification. / **kalender 日历视图** — 日/周/月视图基于 kalender（钉 0.17.x）重建，修复 DST 漂移、GlobalKey 冲突、重叠布局、全天系列分类问题 |
| 2 | **Event trash bin** — soft-deleted events get their own trash section with restore / permanent delete / empty-all (parity with todos). / **事件回收站** — 事件软删除后可恢复/永久删除/清空，与待办对齐 |
| 3 | **Android exact-alarm guidance tile** — shown in settings when exact alarm permission is missing (fallback; `USE_EXACT_ALARM` normally grants it). / **精确定时权限引导** — 权限缺失时设置页显示引导入口（兜底） |
| 4 | **Widget data path repair** — App Group wiring (`setAppGroupId` + macOS Runner entitlements), write-driven refresh, versioned snapshot dual-write; widget reflects todo/event edits without restart. / **小组件数据通路修复** — App Group 接通、写驱动刷新、版本化快照双写，编辑后组件即时更新 |
| 5 | **Settings/home slimming** — settings page split into `settings_sections/{appearance,import_export,ai,notifications,about}`, home page initState side effects extracted to named methods (zero behavior change). / **设置页与首页瘦身** — 设置页拆分为 sections、首页 initState 副作用抽为命名方法，零行为变更 |
| 6 | **Governance baseline** — `SPEC.md` / `DECISIONS.md` / `AGENTS.md` as cross-tool truth sources + pre-commit `dart analyze` gate. / **治理基线** — SPEC/DECISIONS/AGENTS 真理源文档 + pre-commit analyze 卡口 |

### Removals / 移除

| # | Removed / 移除 | Reason / 原因 |
|---|------|------|
| 1 | **CalDAV sync layer** (accounts, sync queue, providers, settings UI, client sync service) / **CalDAV 同步层** | Replaced by planned self-hosted sync backend (Phase 2, contracts-first: push/pull/SSE + LWW) / 由 Phase 2 自托管同步后端替代 |
| 2 | **Client-side MCP server** / **客户端 MCP** | Rebuilt as server-side MCP with OAuth 2.1 + 22 tools in Phase 3 / Phase 3 以服务端 MCP + OAuth 2.1 重建 |

### Bug Fixes / 修复

| # | Issue / 问题 | Fix / 修复 |
|---|------|------|
| 1 | Reminders never fired on device (missing Android receivers, UTC timezone scheduling, hardcoded English notification text) / 真机提醒不响、文案硬编码 | Added 3 Android receivers (ScheduledNotification / Boot / Action), local-timezone init before `runApp`, notification text routed through l10n / 补 3 个 receiver + 本地时区初始化 + 文案接 l10n |
| 2 | Snoozed notification could not be cancelled / 延后的通知取消不到 | Snooze schedules on `reminder.id` with payload `parentType:parentId:reminderId` (same id space as `cancel()`); legacy 2-segment payload still parsed / snooze 改用 reminder.id、payload 三段式，旧格式兼容 |
| 3 | Completing a todo from a notification left remaining reminders firing; due-date edits and deletes didn't reschedule/cancel / 通知上完成后提醒仍响、改期/删除不重排 | Mark Complete routes through `toggleTodoProvider` (cancel chain); due-date change reschedules, cleared due date clears reminders; delete/empty-trash/hard-delete cancel first / 动作改走 toggle provider，改期重排、清空到期清提醒、删除先 cancel |
| 4 | Restore from trash was a no-op / 回收站恢复无效 | `restoreTodoProvider` wrote `Value.absent()` (Drift skips absent columns) → explicit `Value(null)`; restore cascades to child todos / 改为显式写 null + 子任务级联恢复 |
| 5 | Deleting a parent todo left children alive; event trash missing / 删父任务子任务残留、事件无回收站 | Soft-delete cascades to direct children; `events_dao` gains watch/restore/hardDelete/empty with FK-order child cleanup / 级联软删直接子任务；events_dao 补回收站全套（FK 顺序清子表） |
| 6 | Soft-deleted events/todos still exported to ICS / 回收站内容仍被导出 | Export queries filter `deletedAt.isNull()` / 导出过滤软删 |
| 7 | New-event FAB created at midnight, not the browsed date / 新建日程不落在浏览日期 | FAB prefills `viewedDateProvider` (week-view Monday anchor) / FAB 预填当前浏览日期 |
| 8 | Dragging/resizing an event left notifications at the old time / 拖拽事件后旧提醒不挪 | `onEventChanged` reads old start from DB, calls `rescheduleRemindersProvider` after write / 落库后按新时间重排提醒 |
| 9 | Family providers leaked instances (search, event range, tag lists) / family 泄漏 | Converted to `autoDispose.family` (static range-key contract kept) / 改 autoDispose，静态 range key 契约保留 |
| 10 | About-page update check crashed on odd version strings / 版本比较崩溃 | `int.tryParse` with fallback → treat as no-update / tryParse 兜底，失败视为无更新 |
| 11 | Widget showed stale/empty data (macOS host app lacked App Group entitlement, refresh write paths bypassed) / 小组件数据不更新 | macOS Runner entitlements gained `application-groups`; single `tableUpdates` choke point drives coalesced refresh; cold-start refresh kept in home initState / macOS Runner 补 App Group、tableUpdates 单点写驱动刷新 |
| 12 | Widget todo slots showed subtasks first and NULL due dates on top; iOS legacy payload mismatch / 小组件待办排序错、iOS 解码不匹配 | NULL due dates sink, subtasks filtered, legacy payload keys aligned with iOS Swift decoder, versioned `widget_snapshot` dual-written / NULL 沉底、子任务过滤、legacy 键对齐 Swift 解码器、双写 versioned 快照 |
| 13 | Child restore/delete asymmetry, cascade trash gaps, drag `onReorderItem` migration debt (batch from prior-version bug backlog) / 恢复删除不对称、级联回收站缺口、拖拽 API 迁移欠账 | `onReorderItem` migrated (manual `newIndex-1` removed), child cascade delete/restore symmetric / 三处 onReorderItem 迁移，级联删/恢复对称 |
| 14 | Local APK release build broken — Java 25 incompatible with Gradle 8.14; then `home_widget 0.9.1` floating Android deps drifted (`glance-appwidget:1.+` resolved to 1.3.0-alpha02 requiring compileSdk 37 vs AGP cap 36; `work-runtime-ktx:2.+` JVM-11 bytecode vs plugin jvmTarget 1.8) / 本地 APK 构建失败——Java 25 与 Gradle 8.14 不兼容，home_widget 浮动依赖漂移 | Pointed Flutter at local JDK 17 (`flutter config --jdk-dir`); upgraded `home_widget` → **0.9.4** (upstream 0.9.2 #418 pins dep versions, within existing `^0.9.1`); kept Flutter migrator flags in `android/gradle.properties` / 指向 JDK 17、升级 home_widget 0.9.4、保留 migrator flags |

### Infrastructure / 基础设施

| # | Change / 变更 |
|---|------|
| 1 | **l10n cleanup** — dead keys removed, placeholders fixed, Semantics labels added, `flutter gen-l10n` regenerated. / **l10n 清理** — 死 key 删除、placeholder 补齐、Semantics 补充 |
| 2 | **Toolchain baseline** — local Flutter 3.47.3 vs CI pin 3.41.7 drift documented in `docs/CONSTRAINTS.md`; setup-hooks install script. / **工具链基线** — 本地/CI 版本漂移记录入 CONSTRAINTS，setup-hooks 安装脚本 |
| 3 | **Full verification** — `dart analyze .` 0 issues, `flutter test` 127/127, web + APK release build smoke. / **全量验证** — analyze 0、测试 127 全绿、web+APK release 构建冒烟 |

---

## v0.20.5+24 — Security: Remove Signing Keys from Repo / 从仓库移除签名密钥

### Fix / 修复

| # | Issue / 问题 | Fix / 修复 |
|---|------|----------|
| 1 | **Android signing keys exposed in git repo / Android 签名密钥暴露在仓库中** — `android/app/release-keystore.jks` and `key.properties` (with plaintext passwords) were tracked by git and pushed to GitHub. Anyone with access could sign fake APKs. / `android/app/release-keystore.jks` 和 `key.properties`（含明文密码）被 git 追踪并已推送到 GitHub，可用于伪造签名 APK | Generated **new keystore** with random password. Removed both files from git tracking. Added to `.android/.gitignore`. CI now injects keystore from **GitHub Secrets** (`ANDROID_KEYSTORE`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`) at build time. / 生成新 keystore + 新密码，移出 git 追踪，加入 gitignore；CI 改为从 GitHub Secrets 还原签名 |

### Cleanup / 清理

| # | Action / 操作 | Size / 大小 |
|---|------|------|
| 1 | Removed local build artifacts / 清理本地构建缓存 | `build/` (6.3 GB) + `.dart_tool/` (1.7 GB) + `.opencode/node_modules/` (57 MB) = **~8 GB** |

---

## Pipeline Change / 流程改进 — 2026-05-16

### Changes / 变更

| # | Change / 变更 |
|---|------|
| 1 | **CI 全平台改为 release 构建** — `ci.yml` 中 Android/macOS/Windows/Linux 全部从 `--debug` 改为 `--release`，release-only 构建问题（AOT 编译、R8 混淆、tree-shaking）在每次 push/PR 阶段即可暴露 / CI now builds all platforms in release mode, catching release-only bugs before tagging |
| 2 | **Release 默认为 Draft** — `release.yml` 添加 `draft: true`，打 tag 后自动上传产物到 Draft Release，人工下载验收后点 Publish 才公开 / Releases are draft by default — build artifacts are uploaded to a draft release, requiring manual review before publishing |
| 3 | **`v1.0.0` tag 删除** — 违反"1.0 之前不跳版"规则，本地 + 远程均已清除 / `v1.0.0` tag deleted from local and remote (violated "no 1.0 before ready" rule) |
| 4 | **`v0.20.1` tag 补打** — 该版本有完整 release commit 但遗漏了 tag，现已补上 / `v0.20.1` tag added for existing release commit (was missing) |
| 5 | **release.yml 移除 `--verbose`** — Windows AOT 排查添加的诊断标志，问题已修，清理回 clean 状态 / Removed `--verbose` diagnostic flag from Windows build (AOT issue fixed) |
| 6 | **DB migration 支持** — `build.yaml` + `dart run drift_dev make-migrations` 生成 v7  schema 快照；编写 `migration_test.dart` 验证 v1→v7 数据完整性，3 项测试全绿 / DB migration support: schema snapshots, build.yaml, migration test passes v1→v7 |

### Motivation / 动机
- 之前 release-only bug 只在打 tag 发版时暴露，导致 prerelease 版本经常有构建崩溃，缺乏打磨感 / Release-only bugs only surfaced on tag push, making pre-releases feel unpolished

---

## v0.20.5 Windows Release Fix + CI Fix / v0.20.5 Windows 发版修复 + CI 修复

### Fixes / 修复

| # | Issue / 问题 | Fix / 修复 |
|---|------|----------|
| 1 | **Windows release build crashes** — `gen_snapshot` AOT crash on `NativeLaunchDetails` FFI struct (exit code -1073740791, "Class with illegal cid"). Tried: `base class → final class`, removing getter, Flutter 3.41.5→3.41.7. All failed. Root cause: Dart VM bug in AOT serialization of FFI structs passed by value in callbacks. / **Windows release 构建崩溃** | Replaced `flutter_local_notifications_windows` with pure-Dart stub (no FFI, no native DLL). Windows notifications temporarily disabled but release builds succeed. / 替换为纯 Dart stub 实现 |
| 2 | **CI flutter analyze fails** — 48 info-level lint warnings from patched plugin cause exit code 1. / **CI analyze 失败** | `analysis_options.yaml` excludes `patches/**` directory. / 排除补丁包目录 |
| 3 | **Flutter version inconsistency** — release.yml Windows used 3.41.5, CI used latest, macOS used 3.41.7. / **Flutter 版本不一致** | Unified all Windows builds to 3.41.7. / 统一到 3.41.7 |

### Trade-off / 权衡
- Windows 平台暂时不支持本地通知（stub 实现所有方法为空操作）
- 其他 4 平台（Android/macOS/Linux/Web）通知功能不受影响
- 等 Dart VM 修复 FFI AOT bug 后可恢复完整功能

---

## v0.20.2 CI Hardening + Code Review Skill / v0.20.2 CI 加固 + 代码审查 Skill

### Features / 新功能

- **dayspark-code-review skill** — 60 条领域特定审查规则，嵌入 release-prep 流程。
- **代码审查自动化** — release-prep 阶段 2.5 自动加载，BLOCKER 不修完不能发版。

### Fixes / 修复

| # | Issue / 问题 | Fix / 修复 |
|---|------|----------|
| 1 | Windows release build fails with MSB8066 / Windows release 构建失败 | Flutter 3.41.9 release 模式 MSB8066 → 锁定到 3.41.7（与 macOS 一致） |
| 2 | CI gen-l10n causes undefined_method errors / CI 上 gen-l10n 后 analyze 报 undefined_method | 补齐 6 个缺失的 ARB key（subtaskHint/reminderLabel/rateLimited/connectionTimedOut/updateCheckFailed/gitHub）中英双语 |
| 3 | Web build crashes: dart:ffi not available / Web 构建 dart:ffi 不可用 | 将 CLI 专用的 NativeDatabase 调用从 app_database.dart 拆到 app_database_file.dart |
| 4 | 26 empty catch blocks across codebase / 26 处空 catch | 全部改为 `catch (e) { debugPrint(...) }` |
| 5 | Border radius inconsistency / 圆角不一致 | 22 处非标值统一到 6/8/12 |
| 6 | dart:io Platform imports in UI files / UI 文件 dart:io 残留 | 替换为 `defaultTargetPlatform` |
| 7 | GestureDetector remnants / GestureDetector 残留 | 月视图 + 子任务页 3 处 → InkWell |

## v0.20.1 Comprehensive UI Fixes / v0.20.1 大规模 UI 修复

### Summary / 概览

47 issues identified via code review, all fixed. Categorized by severity and cross-cutting concern.

通过代码审查发现 47 个 UI 问题，全部修复。按严重程度和横切关注点分类。

### Accessibility / 无障碍

| # | Issue / 问题 | Fix / 修复 |
|---|------|----------|
| 1 | Zero Semantics across entire app / 全应用无无障碍标签 | Added `Semantics(button:,label:,hint:)` to 30+ interactive elements across 7 files |
| 2 | Decorative icons not excluded / 装饰性图标未排除 | Wrapped empty state icon, tag dots with `ExcludeSemantics` |
| 3 | Color picker purely visual, no text label / 颜色选择器仅视觉 | Added `Semantics(label:)` to each color circle in settings + tags pages |
| 4 | Attachment delete button missing tooltip / 附件删除无 tooltip | Added `tooltip: l.delete` |

### Desktop Experience / 桌面端体验

| # | Issue / 问题 | Fix / 修复 |
|---|------|----------|
| 5 | No platform-adaptive scroll physics / 无平台自适应滚动动效 | Created `AppScrollBehavior`: `BouncingScrollPhysics` on iOS/macOS, `ClampingScrollPhysics` elsewhere |
| 6 | No keyboard shortcuts / 无键盘快捷键 | Added `CallbackShortcuts` with Escape→pop in main.dart framework |
| 7 | No hover/cursor feedback / 无悬停/光标反馈 | Added `MouseRegion(cursor: click)` to 17+ interactive elements |
| 8 | LongPressDraggable on desktop (should be Draggable) / 桌面端长按拖拽 | `_buildDraggableEvent` helper: `Draggable` on desktop, `LongPressDraggable` on mobile |
| 9 | `context.findRenderObject()` in drag callbacks / 拖拽回调不稳定 | Replaced with `GlobalKey` map in week/day calendar views |
| 10 | Chat bubble 75% screen width on desktop / 气泡宽度过大 | Capped at 600px: `min(screen*0.75, 600)` |

### Platform Compatibility / 平台兼容

| # | Issue / 问题 | Fix / 修复 |
|---|------|----------|
| 11 | `dart:io Platform` import crashes Web build / Web 构建崩溃 | Replaced with `defaultTargetPlatform` from `flutter/foundation.dart` |
| 12 | Hardcoded weekday labels only handle zh/en / 星期标签硬编码中英 | `DateFormat.E()` handles all locales properly |
| 13 | `showTodayButton` minimumSize zero hurts touch / 按钮触摸过小 | Removed `minimumSize: Size.zero` and `shrinkWrap` |

### Touch Targets / 触摸目标

| # | Issue / 问题 | Fix / 修复 |
|---|------|----------|
| 14 | Color picker circles 32x32px (GestureDetector, no ripple) / 颜色圈太小 | Replaced with `InkWell + borderRadius:20 + MouseRegion` (2 files) |
| 15 | Date strip cells ~34px touch height / 日期触摸高度不足 | Vertical padding 4→10; chips padding 5→8 |
| 16 | Calendar nav chevrons visualDensity.compact / 导航箭头密度紧凑 | Removed `visualDensity.compact` from 3 IconButtons |
| 17 | EventTile padding horizontal:4 vertical:2 / 事件卡片内边距过紧 | Increased to h:6 v:4; added `onTap` + InkWell wrapper |
| 18 | 6+ GestureDetector→InkWell replacements / 多处 GestureDetector 替换 | Date cells, chips, color circles, event tiles |

### i18n / 国际化

| # | Issue / 问题 | Fix / 修复 |
|---|------|----------|
| 19 | `'+N more'` hardcoded in month view / 月视图数字硬编码 | New key `nMore(int count)` |
| 20 | `'Subtask text'` hardcoded hint / 子任务提示硬编码 | New key `subtaskHint` |
| 21 | `_reminderLabel` returns `'min'/'h'` hardcoded / 提醒标签硬编码 | New key `reminderLabel(int minutes)` |
| 22 | `_friendlyError()` 3 error messages hardcoded / 错误信息硬编码 | New keys: `rateLimited`, `connectionTimedOut`, `updateCheckFailed` |
| 23 | `Text('GitHub')` hardcoded in feedback page / 反馈页 GitHub 硬编码 | New key `gitHub` |
| 24 | Share subject hardcoded English / 分享标题硬编码 | Used l10n key for share subject |

### Performance / 性能

| # | Issue / 问题 | Fix / 修复 |
|---|------|----------|
| 25 | Search fires on every keystroke / 搜索每次按键触发 | Added 300ms debounce `Timer` |
| 26 | Month view O(n×42) event filtering on every build / 月视图循环过滤 | Added events-by-date cache map, compute once per grid |
| 27 | `PackageInfo.fromPlatform()` called every build / 每次构建调 API | Cached in `_cachedVersion` static field |

### Visual Consistency / 视觉一致性

| # | Issue / 问题 | Fix / 修复 |
|---|------|----------|
| 28 | Chat bubble `BorderRadius.circular(16)` vs app 6-8px / 圆角不一致 | Changed to `BorderRadius.circular(8)` |
| 29 | Update prompt `BorderRadius.circular(12)` / 更新提示圆角不一致 | Changed to `BorderRadius.circular(6)` |
| 30 | Light tag colors at alpha 0.3 nearly invisible / 浅色标签选中不可见 | Theme-aware alpha: 0.4 light / 0.3 dark |
| 31 | Today indicator alpha 0.12 near-invisible on dark theme / 今天指示器颜色弱 | Changed to alpha 0.3 |
| 32 | Color list duplicated in 2 dialog methods (DRY) / 颜色列表重复 | Extracted to top-level `_tagColors` constant |
| 33 | User-Agent version hardcoded 0.19 / 版本号硬编码 | Dynamic from `PackageInfo.version` |

### Code Quality / 代码质量

| # | Issue / 问题 | Fix / 修复 |
|---|------|----------|
| 34 | Side effects in `build()` — home_page connectivity listener / build 方法副作用 | Moved to `initState()` via `ref.listenManual()` |
| 35 | Side effects in `build()` — settings 4× Future.microtask / 设置页副作用 | Added `_loaded` guard flag |
| 36 | GestureDetector nested inside InkWell (gesture arena conflict) / 手势冲突 | Replaced with inner InkWell |
| 37 | `FutureBuilder` with uncached Future in settings_page / 未缓存 Future | Replaced with cached static field |

### Build / Architecture / 构建与架构

| # | Change / 变更 |
|---|------|
| 38 | New file: `lib/core/utils/platform_scroll_behavior.dart` — `AppScrollBehavior` |
| 39 | `lib/main.dart` — Wrapped app with `ScrollConfiguration` + `CallbackShortcuts` + `Focus` |
| 40 | `lib/l10n/app_localizations.dart` — 6 new abstract methods |
| 41 | `lib/l10n/app_localizations_en.dart` — 6 new overrides |
| 42 | `lib/l10n/app_localizations_zh.dart` — 6 new overrides |

### Changed Files Summary / 变更文件统计

**20 files touched** across lib/ (pages, widgets, core, l10n):

| Category / 类别 | Files / 文件 |
|------|------|
| Core infrastructure | `main.dart`, `platform_scroll_behavior.dart` (new) |
| Pages (7) | `home_page.dart`, `settings_page.dart`, `about_page.dart`, `feedback_page.dart`, `search_page.dart`, `tags_page.dart`, `ai_chat_page.dart` |
| Calendar widgets (5) | `month_calendar_view.dart`, `week_calendar_view.dart`, `day_calendar_view.dart`, `calendar_section.dart`, `event_tile.dart` |
| Todo widgets (2) | `date_strip.dart`, `todo_list_tile.dart` |
| Other widgets (3) | `wheel_time_picker.dart`, `tag_chips.dart`, `attachment_list.dart` |
| l10n (5) | `app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_zh.dart`, `app_en.arb`, `app_zh.arb` |

---

## v0.20.0 Bug Fixes + Subtask + Terminal CLI + Headless MCP / v0.20.0 修复 + 子任务 + 命令行 + Headless MCP

### Breaking Changes / 不兼容变更
- **DB schema v6→v7** — Added `parentId` column to todos table for subtask support. Automatic migration on upgrade. / 数据库 schema 升级到 v7，待办表新增 `parentId` 列。

### New Features / 新功能
- **Subtask support** — Todo edit page shows subtask list with "Add subtask" button. Subtasks navigate to their own edit page. / 子任务功能，待办编辑页可添加和管理子任务。
- **Terminal CLI** (`bin/dayspark.dart`) — Full CRUD from the command line: `todo add/list/complete/delete`, `event add/list`, `search`. Shares the same SQLite database as the GUI app. / 全新命令行界面，不启动图形界面即可管理待办和日程。
- **Headless MCP auto-start** — Settings toggle to auto-start MCP server on app launch. Enable once, always available for external tools (opencode, etc.). / MCP 服务器可设置为"启动时自动开启"。
- **Windows Inno Setup installer** — Release now produces `DaySpark-*-Setup.exe` instead of a raw zip. / Windows 发版打包为正规安装包。

### Bug Fixes / 修复

| # | Issue / 问题 | Fix / 修复 |
|---|------|------|
| 1 | Linux alarm / notification doesn't work | Added Linux init to NotificationService; hide system alarm switch on non-Android/iOS |
| 2 | Settings switches (system alarm, sync) lag / 设置开关卡顿 | Fixed provider never loading from SharedPreferences; platform-gate alarm switch |
| 3 | Check update returns 403 / 检查更新 403 | Added User-Agent header, 10s timeout, friendly error messages for rate-limit / timeout |
| 4 | Export fails on Linux (`Share.shareXFiles`) / Linux 导出失败 | Fallback to SnackBar with saved file path when sharing not supported |
| 5 | New events not showing in calendar / 新建日程不显示 | Fixed date filter: `date.isBefore(end)` → `!end.isBefore(date)` in month/week/day views |
| 6 | Todo checklist no sequence number / 待办无序号 | Added `index` parameter; uncompleted items show number badge instead of blank checkbox |
| 7 | Todo All-view can't drag reorder / 全视图不能拖拽 | Changed `SliverList` → `SliverReorderableList` |
| 8 | Todo alarm reminder UI missing / 待办闹钟提示缺失 | Added reminder section (15min/30min/1h/2h/24h + None) to both create and edit pages |
| 9 | RRULE text always Chinese / 重复文本硬编码中文 | Created `LocaleAwareRRuleTextDelegate` — switches between Chinese/English based on app locale |
| 10 | MCP port not configurable / MCP 端口不能自定义 | Added port configuration dialog + SharedPreferences persistence |
| 11 | Linux date picker mouse wheel doesn't work / Linux 滚轮不兼容 | Use Material `showTimePicker` on Linux instead of CupertinoDatePicker |
| 12 | AI model detection has no URL format hint / 无格式提示 | Added hint text "Format: http://host:port/v1"; added 5s connect timeout on Dio |
| 13 | Sync refresh button gives no feedback / 同步刷新无反馈 | Show "Sync complete" SnackBar on success |

### Infrastructure / 基础设施
- **Linux builds now use Impeller** (`--enable-impeller`) — Vulkan/GLES-backed rendering for smoother UI, fixes laggy switches and scrolling. / Linux 构建启用 Impeller 渲染引擎，大幅提升界面流畅度。
- **Windows installer** — InnoSetup-based `.exe` installer replaces raw zip in release assets. / Windows 发版从 raw zip 改为正式安装包。

### Architecture / 架构
- **Subtask DB** — `todos.parentId` (nullable int, self-reference). No FK constraint for simplicity. / 子任务通过 `parentId` 自引用实现。
- **CLI architecture** — Initial version used raw `package:sqlite3` with hand-written SQL. Refactored in v0.20.1+ to reuse Drift DAOs via `AppDatabase.forFile()` + `NativeDatabase` (`package:drift/native.dart`), eliminating schema drift and adding full migration support. See `docs/CONSTRAINTS.md` for details. / CLI 初始版本手写 SQL，后重构为复用 Drift DAOs，消除 Schema 漂移并支持完整迁移。

---

## v0.19.2 Linux CI Baseline & macOS Fix / v0.19.2 Linux 构建基线 + macOS 修复

### Infrastructure / 基础设施
- **Linux CI baseline locked to Ubuntu 22.04** — CI runs-on changed from `ubuntu-latest` to `ubuntu-22.04`, ensuring GLIBC ≤ 2.35 for all Linux builds. / Linux CI 基线锁定到 Ubuntu 22.04，确保 GLIBC 不超过 2.35。
- **GLIBC version check** — `tool/check_glibc_version.sh` added, runs in CI to verify no `.so` file requires GLIBC > 2.35. / 新增 GLIBC 版本校验脚本，CI 中自动检查。
- **macOS Flutter version pinned to 3.41.7** — Prevents transient SDK download failures on ARM64 runners. / macOS Flutter 版本锁定，防止 ARM64 运行器偶发下载失败。

### Docs / 文档
- **CONSTRAINTS.md** — Added Linux Distribution section with build baseline / no dual-track / plugin check rules. / 新增 Linux 分发约束章节。
- **CLAUDE.md** — Collaboration rules expanded to cover CI/platform changes, Linux build rule added. / 协作规则扩展覆盖 CI/平台构建，新增 Linux 构建硬约束。

---



## v0.18.0 Calendar Navigation Fix + Open Source Prep / v0.18.0 日历导航修复 + 开源准备

### Fixes / 修复
- **Calendar page range** — Restored Day 20000/Week 4000/Month 800 constants, fixing 2004 date issue. / 日历滑动范围常量恢复，修复显示 2004 年日期问题。
- **Calendar static range** — `_calendarRange` fixed to prevent CalendarSection rebuild on swipe. / 日历 range 改为静态，防止滑动时 CalendarSection 重建。
- **Multi-day event rendering** — Cross-day events no longer hidden after first day. / 多日事件不再只在第一天显示。
- **Dark mode contrast** — Accent #3B82F6 → #60A5FA (WCAG AA). / 暗色 accent 对比度修复。
- **Page swipe deadlock** — `_isAnimating` guard prevents infinite loop. / 防止 `onPageChanged` → `animateToPage` 循环。
- **Event equality** — `==` now covers all 12 fields. / 事件 equality 覆盖全部字段。
- **ICS import duplicates** — Fixed `insertOnConflictConflictUpdate` → `insert`. / ICS 导入修复。
- **Alarm ID conflict** — Event +500000, Todo +600000 offset. / 闹钟 ID 偏移防冲突。
- **Time picker locale** — No longer forces 24h, follows system. / 时间选择器跟随系统 locale 不再强制 24h。
- **Month touch feedback** — InkWell ripple added. / 月视图触摸反馈。
- **Version dynamic read** — `package_info_plus` replaces hardcoded. / 版本号动态读取。

### New Features / 新功能
- **Settings page locale switch** — Chinese/English/Follow System. / 设置页语言切换。
- **Open source community files** — CODE_OF_CONDUCT, CONTRIBUTING, SECURITY. / 开源社区文件。

---

## v0.19.1 CI Cleanup & Docs Sync / v0.19.1 CI 清理与文档同步

### Infrastructure / 基础设施
- **release.yml test job removed** — Duplicate test job removed from release workflow, build jobs run in parallel. / 发版 workflow 移除重复 test job，构建 job 改为并行。
- **release-prep skill rewritten** — Simplified to 4-step flow matching actual process. / 发版 skill 简化为 4 步流程。

### Docs / 文档
- **ROADMAP.md updated** — Added v0.18.0/v0.19.0 entries, updated Pending Items, synced to v0.19.1. / ROADMAP 补充 v0.18.0/v0.19.0 条目，更新待完成项。
- **changelog.md updated** — Added v0.18.0 section. / 补充 v0.18.0 记录。
- **CLAUDE.md version** — Synced to current version. / 版本号同步。

---

## v0.19.1+ Code Cleanup / v0.19.1+ 代码精简

### Refactoring / 重构
- **Shared scrollable page** — `_DayScrollablePage` / `_ScrollablePage` merged into shared `CalendarScrollablePage`, removing ~92 lines of duplication. / 日/周视图的滚动页合并为共享组件，去重 ~92 行。
- **Duplicate `prefs.setString` removed** — Version changelog check fixed. / 修复版本号检查中重复的 `prefs.setString` 调用。
- **`_NavObserver` gated by `kReleaseMode`** — Debug observer no longer registered in production builds. / 导航观察器仅在 debug 模式注册。
- **Android notification plugin** — `resolvePlatformSpecificImplementation` result cached locally. / Android 通知插件调用结果缓存为局部变量。

---

## v0.19.0 Security & Stability Fixes / v0.19.0 安全与稳定性修复

### Security / 安全
- **Signing key removed from Git** — `key.properties` and `release-keystore.jks` untracked, added to `.gitignore`. Keystore rotation required on next release build. / 签名密钥从 Git 追踪中移除，加入 .gitignore。下次发版需轮换密钥。
- **Release build hardened** — Enabled R8 minification (`isMinifyEnabled`) and resource shrinking (`isShrinkResources`) with ProGuard rules. / Release 构建启用 R8 混淆和资源压缩。
- **Password fallback removed** — CalDAV sync no longer falls back to plaintext DB password when SecureStorage read fails; skips account instead. / CalDAV 同步不再回退到数据库明文密码，SecureStorage 读取失败时跳过该账户。
- **Android permission typo fixed** — `FOREREGROUND_SERVICE` → `FOREGROUND_SERVICE` (Android 14+ foreground service requirement). / 修复 Android 权限拼写错误。

### Bug Fixes / 修复
- **Todo soft-delete sync** — Added missing `isDirty: true` to `deleteTodoProvider` so soft-deleted todos are pushed to CalDAV server. / Todo 软删除补充 `isDirty` 标记，确保同步到服务器。
- **Provider crash guard** — `eventsInDateRangeProvider` now uses `int.tryParse` with fallback, preventing `FormatException` cascade crash. / 事件 Provider 改用 `tryParse`，防止格式异常导致级联崩溃。
- **Color parsing safety** — `ColorUtils.parseHex` now validates input length and uses `tryParse`, returning a default blue on invalid hex. / 颜色解析增加输入校验，非法值回退到默认蓝色。
- **Account deletion cascade** — Deleting an account now properly removes all associated events, todos, reminders, attachments, and tag links in a transaction. / 删除账户时级联清理所有关联数据（事件、待办、提醒、附件、标签），使用事务保证原子性。
- **Changelog read-mark timing** — Version changelog dialog now marks "read" only after user dismisses it, not before showing. / 更新日志在用户关闭对话框后才标记"已读"。
- **Sync error visibility** — Replaced 7 empty `catch (_) {}` blocks in `sync_service.dart` with `debugPrint` logging for diagnosability. / 同步层 7 处静默异常改为 `debugPrint` 日志输出。

---

## v0.9.8 Feedback (12 issues) / v0.9.8 反馈（12 个问题）

### #1 Calendar view switch date jump / 日历视图切换日期跳转
**Issue / 问题**: Switching day/week/month views caused inconsistent dates, title showing wrong month (two Junes). / 切换日/周/月视图时日期不一致，标题显示错误月份（两个六月）。
**Fix / 修复**: Introduced `_anchorDate` as single anchor point, pass `initialDateTime` on view switch, unified title format. / 引入 `_anchorDate` 作为唯一锚点，视图切换时传递 `initialDateTime`，统一标题格式。

### #2 Extra week numbers in week/day view / 周视图/日视图多余周数显示
**Issue / 问题**: kalender showed ISO week numbers by default. / kalender 默认显示 ISO 周数，用户不需要。
**Fix / 修复**: `weekNumberBuilder` returns `SizedBox.shrink()`. / `weekNumberBuilder` 返回 `SizedBox.shrink()`。

### #3 Todo date strip logic errors / 待办日期滑块逻辑错误
**Issue / 问题**: Anchoring logic, arrow behavior, date selection all had issues. / 锚定逻辑、箭头行为、选日期交互都有问题。
**Fix / 修复**: Rewrote `date_strip.dart` to show current week 7 days only, left/right arrows switch weeks. / 重写 `date_strip.dart`，只显示当前周 7 天，左右箭头切周。

### #4 No visual feedback on calendar tap / 日历点击无视觉反馈
**Issue / 问题**: Tapping empty area to create event had no feedback. / 点击空白区域创建事件无任何反馈。
**Fix / 修复**: `_lastTappedDate` + `Timer` for tap highlight. / `_lastTappedDate` + `Timer` 实现点击高亮。

### #5 Month view title date format error / 月视图标题日期格式错误
**Issue / 问题**: Format "7 第三周" missing "月", confusing. / 格式 "7 第三周" 缺少"月"，令人困惑。
**Fix / 修复**: Custom headers — day: "4月30日 周四", week: "4/27 – 5/3", month: "2026年4月". / 改为视图专属头部。

### #6 Settings page structure messy / 设置页结构混乱
**Issue / 问题**: Advanced feature toggles at bottom, AI/CalDAV hidden behind toggles. / 高级功能开关在底部，AI/CalDAV 需要先开开关才能看到。
**Fix / 修复**: Restructured as ExpansionTile, AI/CalDAV/MCP in "Advanced Features" section. / 重构为 ExpansionTile，AI/CalDAV/MCP 放入"高级功能"折叠区。

### #7 Advanced features lack tutorials / 高级功能缺少教程
**Issue / 问题**: Users don't know how to configure AI, CalDAV, MCP. / AI、CalDAV、MCP 用户不知道怎么配。
**Fix / 修复**: Tutorial links next to each advanced feature, created setup docs. / 每个高级功能旁添加教程链接。

### #8 MCP server settings misplaced / MCP 服务器设置位置不合理
**Issue / 问题**: MCP mixed with basic settings. / MCP 和基础设置混在一起。
**Fix / 修复**: MCP moved into advanced features ExpansionTile. / MCP 移入高级功能 ExpansionTile。

### #9 Overdue todo check not timely / 过期待办提示不及时
**Issue / 问题**: App left open past midnight wouldn't trigger overdue check. / app 一直开着过了午夜不会触发过期待办检查。
**Fix / 修复**: One-shot Timer calculating precise delay to midnight, recursive scheduling. / 改为 one-shot Timer 计算到午夜的精确延迟，递归调度。

### #10 Calendar header buttons crowded / 日历头部按钮拥挤
**Issue / 问题**: Date picker tap area too small. / 日期选择器点击区域太小。
**Fix / 修复**: Enlarged tap area, unified colors with `colorScheme.primary`. / 增大点击区域，颜色统一。

### #11 Calendar date jump (same cause as #1) / 日历日期跳转（与 #1 同因）
**Issue / 问题**: `_viewConfig()` not passing `initialDateTime`. / `_viewConfig()` 不传 `initialDateTime`。
**Fix / 修复**: Same as #1. / 同 #1。

### #12 Calendar header layout poor / 日历头部布局不合理
**Issue / 问题**: All buttons crammed in one row. / 所有按钮挤在一行。
**Fix / 修复**: Two-row layout — row 1: date + picker + today button, row 2: view switch + nav arrows. / 两行布局。

---

## v0.10.0 Feedback / v0.10.0 反馈

### #13 Per-minute date change check is wrong / 每分钟检测日期变化没逻辑
**Issue / 问题**: `Timer.periodic(1 min)` to detect midnight, too frequent and illogical. / 用 `Timer.periodic(1分钟)` 检测午夜，频率过高且不合理。
**Fix / 修复**: One-shot Timer with precise delay to midnight, recursive on trigger. / 改为 one-shot Timer 计算精确到午夜的时间差，触发后递归调度下一次。

### #14 CI repeatedly fails on formatting / CI 反复因格式化失败
**Issue / 问题**: Local Flutter version and CI version produce different `dart format` results. / 本地 Flutter 版本和 CI 版本 `dart format` 结果不同。
**Fix / 修复**: Removed `dart format --set-exit-if-changed` from CI. / 从 CI 移除 `dart format --set-exit-if-changed`。

### #15 CI analysis failures suppressed instead of fixed / CI 分析失败用压制而非修代码
**Issue / 问题**: `--no-fatal-infos` suppressed 26 info-level lints. / 用 `--no-fatal-infos` 压制 26 个 info 级别 lint。
**Fix / 修复**: Fixed all 26 infos, achieving zero issues. / 逐一修复所有 26 个 info，达到零 issue。

### #16 Version jumped to 1.0.0 / 版本号跳到 1.0.0
**Issue / 问题**: Version went from 0.9 directly to 1.0.0. / 从 0.9 直接跳到 1.0.0。
**Fix / 修复**: Changed to 0.10.0, all versions before 1.0 are 0.x. / 改为 0.10.0，1.0 之前都是 0.x 递增。

---

## v0.11.0 Feedback / v0.11.0 反馈

### #17 All releases should be marked pre-release / 所有 release 应标记为 pre-release
**Issue / 问题**: v0.9.4~v0.10.0 not marked as pre-release. / v0.9.4~v0.10.0 未标记为 pre-release。
**Fix / 修复**: `release.yml` uses `!startsWith(github.ref_name, 'v1.')`, batch-updated historical releases. / `release.yml` 改为 `!startsWith(github.ref_name, 'v1.')`，手动批量修改历史 release。

### #18 User feedback needs archiving / 用户反馈需归档
**Issue / 问题**: Feedback scattered in conversations. / 反馈散落在对话中，无法翻阅。
**Fix / 修复**: Created `docs/changelog.md` to record all feedback. / 创建 `docs/changelog.md` 记录所有反馈。

---

## v0.12.0 Feedback (19 issues) / v0.12.0 反馈（19 个问题）

### #19 Calendar month→week/day view date inaccurate / 日历月→周/日视图日期不准
**Issue / 问题**: Month view used middle date as anchor (e.g. 4.16), switching to week/day gave wrong date. / 月视图以中间日期为锚点，切换到周/日视图时日期不对。
**Fix / 修复**: Month view doesn't update `_anchorDate`, anchor only changes on user action. / 月视图不更新 `_anchorDate`，锚点只在用户主动操作时变化。

### #20 About page version display wrong, update check broken / 关于页版本号显示不对，检查更新功能失效
**Issue / 问题**: Version hardcoded, update check says "up to date" when it's not. / 版本号硬编码，检查更新显示"已是最新"但实际不是。
**Fix / 修复**: `package_info_plus` for dynamic version; API changed to `/releases?per_page=1` including pre-releases. / 用 `package_info_plus` 动态读取版本号；API 改为包含 pre-release。

### #21 Feedback should stay in-app / 反馈入口应停留在 app 内
**Issue / 问题**: Feedback jumped directly to GitHub. / 反馈直接跳转 GitHub，用户希望 app 内反馈。
**Fix / 修复**: Created `feedback_page.dart` with text input + copy to clipboard + link to GitHub Issue. / 新建 `feedback_page.dart`，支持文本输入 + 复制到剪贴板 + 跳转 GitHub Issue。

### #22 Tutorials need bilingual / 教程需双语
**Issue / 问题**: Tutorials mixed Chinese and English. / 教程中英混杂。
**Status / 状态**: Deferred to next version / 延期至下一版本。Done in v0.17.0. / v0.17.0 已完成。

### #23 New todo default date should be today / 新建待办默认日期应为今天
**Issue / 问题**: `_dueDate` defaulted to null when creating new todo. / 新建待办时 dueDate 默认为空。
**Fix / 修复**: `_dueDate` initialized to `DateTime(now.year, now.month, now.day)`. / 初始化为当天。

### #24 Custom repeat options / 自定义重复选项
**Issue / 问题**: rrule custom repeat rule UI. / rrule 自定义重复规则 UI。
**Status / 状态**: Already provided by rrule_generator library. / 已由 rrule_generator 库提供。

### #25 Touch feedback needs better solution / 触摸反馈需要更好的方案
**Issue / 问题**: Current highlight approach not intuitive enough. / 当前高亮方案不够直观。
**Fix / 修复**: `_lastTappedDate` mechanism implemented in month and day views with semi-transparent primary color, auto-clears after 400ms. / `_lastTappedDate` 机制已在月视图和日视图中实现。

### #26 Time picker should be scroll wheel / 时间选择器应为滚动式
**Issue / 问题**: Used Material TimePicker, should be wheel picker. / 使用 Material TimePicker，应改为滚轮选择器。
**Fix / 修复**: Created `wheel_time_picker.dart` based on `CupertinoDatePicker` + optional keyboard input. / 基于 `CupertinoDatePicker` + 可选键盘输入。

### #27 All todos view / 全部待办视图
**Issue / 问题**: Missing entry to view all todos. / 缺少查看所有待办的入口。
**Fix / 修复**: `todos_dao` added `watchAllNotDeleted()`, new `allTodosProvider`. `date_strip` added "All" chip. / 新增全部待办视图。

### #28 Multi-day todo display / 多天待办显示
**Issue / 问题**: How to display todos with start and due dates. / 有开始和截止日期的待办如何显示。
**Fix / 修复**: Show on due date only; when `startDate ≠ dueDate` and gap > 1 day, show range label (e.g. "3/1 – 3/5"). / 只在截止日期显示，间隔 > 1 天时显示日期范围标签。

### #29 Show changelog after each update / 每次更新后显示更改说明
**Issue / 问题**: Should show changelog popup after update. / 更新后应弹出 changelog。
**Fix / 修复**: `home_page` startup uses `SharedPreferences` to compare versions, popup on change. / 启动时用 SharedPreferences 对比版本号，版本变化时弹出对话框。

### #30 MCP server LAN access / MCP 服务器局域网访问
**Issue / 问题**: Whether MCP supports LAN access. / MCP 是否支持局域网访问。
**Fix / 修复**: Bind address changed from `loopbackIPv4` to `anyIPv4`. / 绑定地址从 `loopbackIPv4` 改为 `anyIPv4`。

### #31 Theme color feature / 主题色功能
**Issue / 问题**: Users want custom theme colors. / 用户希望自定义主题色。
**Fix / 修复**: `theme_provider` added `themeColorProvider`, `app_theme` supports optional `seedColor`. Settings page color picker grid (10 presets + reset). / 新增颜色选择网格。

### #32 UI design should match iOS/macOS quality / UI 设计需向 iOS/macOS 看齐
**Issue / 问题**: Frontend design needs improvement. / 前端设计需要提升。
**Status / 状态**: Ongoing — CupertinoIcons, Material 3 rounded corners. / 持续改进，已使用 CupertinoIcons、Material 3 圆角。

### #33-36 AI Agent design / AI Agent 设计
**Issue / 问题**: AI agent interaction protocol, persistence, task separation, CLI mode. / AI agent 交互协议、持久化、任务区分、CLI 模式。
**Status / 状态**: MCP serves as interaction protocol. Agent-created todos use `mcp-` prefix. CLI mode deferred. / MCP 已是交互协议。CLI 模式延期。

### #37 Clean up entire workspace / 整理整个 workspace
**Issue / 问题**: Project file structure needs cleanup. / 项目文件结构需要整理。
**Fix / 修复**: `flutter analyze` zero issues, no dead code, no duplicate imports. / `flutter analyze` 零 issue，无死代码、无重复导入。
