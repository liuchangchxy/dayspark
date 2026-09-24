# DaySpark 重生（重构）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 DaySpark 重构为"自托管的开源 Todo清单"——日历+任务双一等公民、五平台统一客户端、NAS Docker 同步后端、MCP/CLI 让 AI 操控、双端桌面小组件。

**Architecture:** 客户端继续 Flutter（保留数据模型/UI/l10n/测试资产），**删除自研 CalDAV 层**，日历视图换 kalender 库；新增 **Dart 同步后端**（同语言共享契约 package，SQLite 单文件 + Docker），协议为"服务器游标 + 幂等 push + 字段级 LWW + SSE 只发信号"；MCP server 与 CLI 长在后端同进程同数据源上；小组件走 versioned JSON 快照（home_widget + App Group）。

**Tech Stack:** Flutter 3.x / Riverpod / Drift(SQLite) / go_router / **kalender（锁 0.17.x minor）** / Dart 后端(shelf + drift + SQLite) / dart_mcp 或手写 Streamable HTTP / home_widget + WidgetKit + AppWidgetProvider / Docker

**Spec:** 需求冻结于本计划 Context；设计依据为本会话 5 份调研报告（DaySpark 资产盘点、SP/ByWave/AllisWell 源码尽调、同步+MCP 先例、UX+小组件先例）与 54 bug 审计。详细 spec 在各 Phase 启动时按 writing-plans 拆为独立子计划（本计划为跨子系统主计划，P1 已展开到可执行粒度）。

## Global Constraints（继承 calendar_todo_app/CLAUDE.md，全程有效）

- `flutter analyze`（本地用 `dart analyze .` 绕过中文路径 LSP 崩溃）零 issue；`flutter test` 全绿；禁止 `--no-fatal-infos` / `dart format --set-exit-if-changed`
- 版本号 `0.x+N`，1.0 前不跳版；commit 后必须用户确认才可 tag/push
- UI 文本必须 l10n 中英双语（app_en.arb + app_zh.arb 同步 + `flutter gen-l10n`），禁止硬编码；`CupertinoIcons`；圆角 6/8/12；信息密度优先、不大圆角不渐变
- 改 Drift 表必须：schemaVersion 递增 + onUpgrade 迁移 + `build_runner build` + `drift_dev make-migrations` + migration_test 更新且绿
- 代码风格：single quotes、trailing commas、显式返回类型、`debugPrint`、非显然处才写 WHY 注释、无 docstring/emoji
- 日历相关改动必读 `docs/CONSTRAINTS.md`（PageView 范围、_isAnimating、静态 _calendarRange 等——换 kalender 后需同步修订该文档）
- 每个 Phase 结束：analyze 零 + test 全绿 + 用户确认后才进入下一 Phase

## 已锁定的决策（用户已拍板）

1. 路线 **甲**：DaySpark 重生，不 fork 任何项目
2. 日历视图 **A：换 kalender**（`^0.17.x` 钉死 minor，不跨 minor 升级）
3. 推进顺序 **地基优先**：P1 客户端重构 → P2 同步后端 → P3 MCP/CLI → P4 平台补齐
4. 后端语言 **Dart**（与客户端共享契约 package）
5. 吸收清单：ByWave **代码**（RRULE 三范围语义、webhook、设备配对——MIT）；SP **设计**（小组件 JSON 快照契约、时间轴映射）；AllisWell **仅设计**（字段级 LWW 同步、MCP 工具面/无删除姿态/OAuth2.1、小组件单写入路径——PolyForm NC 禁止代码合并）；Todoist MCP 哲学（工作流工具 > API 映射，22 工具甜点区）
6. 排除：番茄钟/复盘、CalDAV 导出层、E2EE = P5 以后；客户端内 MCP server、CalDAV 同步、workmanager 后台同步 = 删除

---

## 架构与文件结构

```
calendar_todo_app/
├── packages/
│   └── dayspark_contracts/        # [P2新增] 共享 Dart package：记录模型、同步 DTO、MCP 工具 schema、错误码
├── server/                        # [P2新增] Dart 同步后端（shelf 路由 + drift/SQLite + SSE）
│   ├── bin/server.dart
│   ├── lib/src/{sync,auth,mcp,oauth}/
│   ├── Dockerfile + docker-compose.yml   # NAS 部署：单容器 + volume 挂 SQLite
│   └── test/
├── tool/mcp_stdio_wrapper/        # [P3新增] stdio→HTTP 桥（喂 Codex/本地 Agent）
├── tool/dayspark_cli/             # [P3新增] CLI，薄封装同一 API
└── lib/
    ├── data/local/…               # 保留；schema v8（删 CalDAV 列）
    ├── data/remote/caldav/        # [P1删除] 1201 行；ical_converter 抽出到 domain/services/ical/
    ├── domain/providers/          # 保留；删 sync/accounts/mcp provider；P2 增 sync_client provider
    ├── domain/sync/               # [P2新增] outbox、pull applier、SSE 监听（仿 AllisWell 设计、自写代码）
    ├── infrastructure/mcp/        # [P1删除] 客户端 MCP server（工具清单已成为 P3 规格）
    ├── infrastructure/platform/   # 保留；通知/小组件修复
    └── ui/pages/ + ui/widgets/    # 保留；calendar views 换 kalender；settings 拆分
```

---

## Phase 1 — 客户端地基重构（本计划详案）

**交付物：** 单机可用、无 CalDAV、kalender 视图、S1/S3 级 bug 清零、双端小组件数据通路修复的 DaySpark。版本 → `0.21.0+N`（经用户确认后）。

### Task 0: 工具链与工作区基线

**Files:** `~/.zshrc`（或 brew）、`analysis_options.yaml`、`pubspec.lock`、13 个未提交文件

- [ ] 修复 Flutter 安装：brew cask 卡在 `3.41.7.upgrading`，执行 `brew upgrade flutter --cleanup`（或 `brew reinstall flutter`），确认 `flutter --version` 可用且 PATH 有 `flutter`；把实际版本号记入 `docs/CONSTRAINTS.md`，并核对 CI（ci.yml/release.yml）Flutter 版本与本地一致性
- [ ] 审查未提交改动（13 文件）：保留 sync debugPrint、l10n 新 key（syncTooltip/justNow/minutesAgo/hoursAgo）、CupertinoIcons.checkmark、日/周视图 Semantics、新测试；`app_localizations_*.dart` 手改部分将被 `flutter gen-l10n` 重新生成覆盖（以 arb 为准）
- [ ] `analysis_options.yaml`：保留 flutter analyze 自动追加的 `build/**`，**revert** 平台目录 excludes（android/ios/... 不应从分析中隐藏，CI 上可能与 3.41.7 行为不一致）；`pubspec.lock`：确认 CI 能复现，不能则 revert
- [ ] 跑 `dart analyze .` + `flutter test`，全绿后 commit：`chore: 工具链修复 + 工作区基线`
- [ ] **引入 Vibe Coding Starter 四资产**（来源 `liuchangchxy/vibe-coding-starter`，MIT，用户指定）：
  - 建 `SPEC.md`：业务单一真理源，用模板结构初始化，填入冻结需求 8 条（日历+任务平权 / 统一五平台客户端 / 跨设备同步 / AI 可读写 MCP / 双端小组件 / 自托管 NAS 优先 / 开源 GPLv3 / 对标 Todo清单简洁体验）+ P1–P4 功能矩阵
  - 建 `DECISIONS.md`：轻量 ADR 时间线，初始化记录本会话已拍决策（路线甲、换 kalender、地基优先、Dart 后端、吸收清单、删 CalDAV/客户端 MCP、番茄/CalDAV导出/E2EE 出范围），格式照模板 `[YYYY-MM-DD] 标题 / 触发背景 / 核心决策 / 对应 SPEC 章节 / 影响范围`
  - 建 `AGENTS.md`：跨工具 AI 入口（Codex 原生读取）——声明三大底线（SPEC 先行、非破坏、交付全绿）+ 指向 `CLAUDE.md`（工程规则）与 `SPEC.md`（业务规则）+ "用户纠错→追加 `docs/CONSTRAINTS.md` 避坑清单"规则
  - 装 pre-commit 本地门禁：`.git/hooks/pre-commit`（可执行，参照 starter 的 setup-hooks.py 思路自写）跑 `dart analyze .`，非零退出码拒绝提交（`flutter test` 全量太慢不做钩子，测试仍靠流程卡口）；把 starter 的 `scripts/setup-hooks.sh` 思路做成本项目 `scripts/setup-hooks.sh` 可重装
  - `CLAUDE.md` 增补一小节「文档地图」：SPEC=业务 / DECISIONS=为什么 / CONSTRAINTS=坑 / changelog=反馈 / ROADMAP=功能，互相引用不重复
  - 以上与基线同 commit 或追加 commit `chore: 引入 SPEC/DECISIONS/AGENTS 文档与 pre-commit 门禁`

### Task 1: l10n 清理与再生成

**Files:** `lib/l10n/app_en.arb`, `app_zh.arb`, 生成文件, `date_formatters.dart`

- [ ] 删除重复 key：`noSubtasks`（保留短文案 "No subtasks" 给 todo_edit；ai_chat 改用新 key `noSubtaskSuggestions`="No subtask suggestions available"/"暂无子任务建议"）、`save`（保留第一个定义）
- [ ] 删除死 key：`reminderLabel`、`noReminder`、`defaultReminderTimes`、`eventStartingSoon`、`taskDueSoon`、`biometricLock*`、`databaseExport*`、`mcpAutoStart*` 等（grep `lib/` 确认零引用后删；MCP/生物识别等已确认功能移除）
- [ ] EN arb 补 `@moveToTodayPrompt`/`@movedToToday` placeholders（type: int）
- [ ] 硬编码 Semantics 补 l10n key（`todo_list_tile.dart:93,104,123,158,231`、`event_tile.dart:62`、`calendar_section.dart:227,238`），新增 key 中英各一份
- [ ] `date_formatters.dart` `formatRelativeTime` 硬编码英文 → 删除（settings 已用本地化版本）或改注入 AppLocalizations；grep 确认无调用后删
- [ ] `flutter gen-l10n` → `dart analyze .` → `flutter test` → commit `refactor(l10n): 去重死key补齐placeholders与Semantics`

### Task 2: 删除 CalDAV 层（含 ICS 抽出）

**Files:** `lib/data/remote/caldav/*`, `sync_provider.dart`, `accounts_provider.dart`, `settings_page.dart`, `main.dart`, `home_page.dart`, `database_provider.dart`, tables, `ics_service.dart`

- [ ] **先抽出 ICS**：`ical_converter.dart` 移至 `lib/domain/services/ical/ical_converter.dart`（保留 enough_icalendar 依赖），`ics_service.dart` import 改路径；12 个 ionic_converter 测试随迁
- [ ] 删除 `lib/data/remote/caldav/`（caldav_client、sync_service、background_sync_worker）、`sync_provider.dart`、`accounts_provider.dart`、settings 的 CalDAV/账号/后台同步 UI（`settings_page.dart:303-418` 附近）
- [ ] 删除客户端 MCP：`lib/infrastructure/mcp/`、`mcp_provider.dart`、settings MCP 段（`settings_page.dart:219-256`）——工具清单已在调研中存档为 P3 规格
- [ ] `main.dart` 移除 workmanager init；依赖删除 `workmanager`、`xml`（grep 确认无他用）；`connectivity_plus` 移除自动同步挂钩（P2 重建）
- [ ] **Schema v8 迁移**：Events/Todos 删 `uid/etag/isDirty`；Calendars 删 `caldavHref/syncToken/etag/accountId`；删 `Accounts` 表；保留默认本地日历（去 caldavHref 种子，`database_provider.dart:26-38` 改为纯本地）；`schemaVersion 7→8` + `onUpgrade` 删列删表 + `build_runner build --delete-conflicting-outputs` + `drift_dev make-migrations` + 更新 `migration_test.dart`（v1→v8）与 `tables_test.dart` 断言
- [ ] 清 import 边缘：`home_page.dart:105-113` 同步触发、`feature_flags` 的 `caldavSync`、`events_provider.dart:94`/`todos_provider.dart:130` 的 `isDirty=true` 写入
- [ ] 测试处置：删 `caldav_client_test.dart`(5)、`sync_provider_test.dart`(1)；迁 `ical_converter_test.dart`(12)；修 `tables_test.dart`(7)+`migration_test.dart`(3)
- [ ] `dart analyze .` + `flutter test` → commit `refactor: 删除 CalDAV 同步层与客户端 MCP，schema v8`

### Task 3: 换 kalender 日历视图

**Files:** `pubspec.yaml`, `lib/ui/widgets/calendar/*`（views 3 个 + calendar_section + view_switcher + event_tile + scrollable_page）

- [ ] `pubspec.yaml` 加 `kalender: ^0.17.4`（钉 minor；加 NOTE 注释 WHY：pre-1.0 breaking 风险，禁止跨 minor 升级）
- [ ] 用 kalender `MultiDayCalendarView`（周/日，visibleRange 切换）+ `MonthView` 替换 `day_calendar_view.dart`(561)、`week_calendar_view.dart`(506)、`month_calendar_view.dart`(298)、`scrollable_page.dart`；保留 `event_tile.dart` 作为 tileContent 渲染
- [ ] 移植交互：`onEventTapped`→事件详情；`onTimeSlotTapped`（点空白建事件，传当前浏览日期——顺带修 FAB/槽位用今天而非浏览日期的 bug）；拖拽 `onEventChanged`→`home_page.dart:400-405` 落库（保留 `canDrag = rrule==null && !isAllDay` 守卫，**修掉重复事件拖拽改坏系列的 S1 bug**）；all-day 条渲染全天事件（修 `take(1)` 只显示一个的 bug 与 exclusive DTEND 多显示一天的过滤 bug——统一全天判定：`isAllDay` 字段为准，渲染区间 [start, end) ）
- [ ] 重叠布局：day 视图集群列宽（修全天统一缩宽 bug）；week 视图补重叠分列（kalender 自带或 tileBuilder 里分列）
- [ ] "现在"红线放进 kalender 内置 indicator（修不随滚动 bug）
- [ ] 重复事件展开改为**可见窗口绑定**：`recurring_event_helper.dart` 加 `before/after` 窗口参数（修 2000–2030 全量展开性能 bug；kalender 提供可见范围回调喂入）
- [ ] 删除 CONSTRAINTS 中被 kalender 取代的条目（PageView 范围、_isAnimating、独立 ScrollController），新增 kalender 版本锁定约束
- [ ] 更新 `test/`：calendar 相关 widget 测试重写为 kalender 结构；`dart analyze .` + `flutter test` → commit `feat(calendar): 以 kalender 替换手写视图，修复 DST/GlobalKey/重叠/全天系列 bug`

### Task 4: 状态与交互 bug 批（S1/S4）

**Files:** `home_page.dart`, `calendar_section.dart`, `todos_provider.dart`, `events_provider.dart`, `ics_service.dart`, `about_page.dart`, providers

- [ ] `home_page.dart:391` 删 `ValueKey(adapters.length)`（修事件数变化整页重挂载传回今天的 bug）
- [ ] `home_page.dart:333-338` FAB 预填当前浏览日期（从 calendar_section anchor 取）
- [ ] 拖拽落库后调 `rescheduleRemindersProvider`（修拖拽不重排提醒；`event_edit_page.dart:92-105` 已有可复用）
- [ ] `todos_provider.dart:115-135` 删除父任务级联软删子任务（修孤儿行+幽灵提醒）；`emptyTrash` 保持现有子表顺序
- [ ] `ics_service.dart:18-24` export 加 `deletedAt.isNull()` 过滤（修回收站导出）
- [ ] `about_page.dart:78-84` `_compareVersions` 用 `int.tryParse`，解析失败视为无更新（修 build 期抛异常）
- [ ] `events_provider/search_provider/todos_provider` 非 autoDispose family → `.autoDispose` 或显式 invalidation（修 provider 泄漏：`search_provider.dart:12-26`、`ai_scheduler_provider.dart:27-31`、`todos_provider.dart:12`）
- [ ] `home_page.dart:540,580,671` `onReorder` → `onReorderItem`（消 3 条 deprecation）
- [ ] 事件回收站 UI：`trash_page.dart` 加事件分区（Events 软删已有列，复用 restore/empty 模式，空回收站级联删 reminders——参照 `todos_dao.dart:192-210` 模式写 `events_dao`）
- [ ] 每步跑对应测试 → 全绿后 commit（可拆 2–3 个 commit）

### Task 5: 通知链修复（S3，Android 整链是坏的）

**Files:** `AndroidManifest.xml`, `notification_service.dart`, `home_page.dart`, `todos_provider.dart`, `reminders_provider.dart`, `sync 删除后的 hard-delete 路径`

- [ ] `android/app/src/main/AndroidManifest.xml` 补 3 receiver：`ScheduledNotificationReceiver`、`ScheduledNotificationBootReceiver`、`ActionBroadcastReceiver`（flutter_local_notifications 21 要求，修"提醒根本不响"）
- [ ] 启动时 `tz.initializeTimeZones()` + 设置本地 location（`main.dart`；漏了会静默不触发）
- [ ] Snooze 改用 **reminder.id**（payload 带 reminderId；`home_page.dart:248-257`、`notification_service.dart:131,183-191`——修 id 空间碰撞+无法取消）
- [ ] 完成待办 → `NotificationService.cancel` 其提醒；改 due date → 调 `rescheduleRemindersProvider`（`todos_provider.dart:101-113`、`todo_edit_page.dart:75-99`）
- [ ] 从回收站恢复 → 按 reminder 行重新调度（`todos_provider.dart:137-147`）
- [ ] 账号/数据删除路径补 cancel（原 sync hard-delete 已删；`accounts_provider` 已除，核对 emptyTrash 已有 cancel）
- [ ] Android 14+：`canScheduleExactAlarms()` 检查 + 引导 intent（设置页提醒段）
- [ ] 通知文案接 l10n：`reminders_provider.dart:69-72` 的英文硬编码改读 locale（用 `SharedPreferences` 存 locale 或调度时传入已译字符串）
- [ ] 手工验证清单（真机/模拟器）：创建提醒 → 到点响 → snooze → 完成取消 → 重启后仍调度（写入 `docs/CONSTRAINTS.md` 通知章节）→ commit

### Task 6: 小组件数据通路修复（quick-add/新组件样式留 P4）

**Files:** `home_widget_service.dart`, `ios/Runner/*`, `macos/Runner/*`, providers, `AndroidManifest`

- [ ] iOS/macOS 补 `HomeWidget.setAppGroupId('group.com.dayspark.app')`（当前 App Group 缺失，Apple 组件拿不到数据；同步把 `dev.opencal.*` bundle id 与 `group.com.calendarTodoApp` 迁移到 `com.dayspark.app` 命名族——**若迁移触发签名/Provision 问题则降级为先匹配现有 group 名让组件先工作**，完整改名留 P4）
- [ ] 数据刷新：任何事件/待办增删改后调 `updateHomeWidgetProvider`（现在仅 `home_page.dart:121` 冷启动一次）——在 todos/events provider 的 mutation 出口统一挂钩
- [ ] 待办排序修 NULL：dueDate NULL 排后（`home_widget_service.dart:36-40`），并过滤 `parentId.isNull()`（子任务不占槽位）
- [ ] 快照契约升级为 SP 式 versioned JSON（`{version, generatedAt, todayEvents[], pendingTodos[]}` 单 key），双端解析留 golden 测试
- [ ] 测试：service 单测 + 手工双端组件验证 → commit

### Task 7: 设置页/首页瘦身 + 收尾

**Files:** `settings_page.dart`(960), `home_page.dart`(869)

- [ ] `settings_page.dart` 拆文件：`settings_sections/{ai,account(sync P2),appearance,notifications,about}_section.dart`（删 CalDAV/MCP 段后本就大瘦身；顺带修 `_formatRelativeTime` 保留）
- [ ] `home_page.dart` 抽 `_HomeInit` 副作用（widget 初始化、午夜检查）到独立方法/类，主体只留导航+双 tab（不动行为）
- [ ] AI 配置保留现状（BYO key 客户端 AI）——**P3 后端 MCP 就绪后再评估移除**，本 Phase 不动 `ai_chat/ai_config_dialog`（避免砍掉仍唯一可用的 AI 入口）
- [ ] 全量验证：`dart analyze .` 零 + `flutter test` 全绿 + 5 平台 `flutter build`（apk/web/macos/windows/linux 至少 web+apk 本地快验）+ 手工回归清单（建事件/建待办/完成/回收站/提醒/组件/搜索/标签）
- [ ] 文档：ROADMAP/changelog/CONSTRAINTS 更新；版本 `0.21.0+N`；**commit 后停下等用户确认再 tag/push**

---

## Phase 2 — 同步后端 + 客户端同步（启动时按 writing-plans 展开详案）

**交付物：** NAS `docker compose up` 一台服务，两台设备（含模拟器）双向同步。契约先行：`packages/dayspark_contracts`。

协议规格（五调研提炼，写死为契约）：
- 记录：`{id: UUIDv7(客户端生成), type: task|event|…, payload, rev, deleted(tombstone), serverTs(服务器权威)}`
- `POST /sync/push` `{ops:[{opId, type:upsert|delete, recordId, fields, baseRev}]}` → 逐条 `{status: applied|conflict|rejected}`（幂等 opId 唯一约束；**绝不整批回滚**；响应捎带远端变更 piggyback）
- `GET /sync/pull?cursor=&limit=` → `{changes[], nextCursor, hasMore}`；cursor = 服务器单调不透明序号（**禁用时间戳当游标**）；tombstone 走 pull
- `GET /sync/stream`（SSE）：只发 `{cursor}` 信号，不发载荷
- 冲突：服务器时间戳 LWW，**事件字段级**（title/start/end 各自决胜，AllisWell 设计自实现）；同秒用 opId 字典序破平；tombstone 保留 ≥45 天 GC
- Auth：注册/登录（argon2id hash）→ JWT access(15min) + refresh 轮换(哈希存储)；`devices` 表
- 存储：Dart drift/SQLite 单文件，volume 挂载；表 `records/sync_ops(idempotency)/users/refresh_tokens/devices/rev(seq)`

任务轮廓：① contracts package（记录/DTO/错误码，客户端与服务端共 import）→ ② server 骨架（shelf 路由、health、auth）→ ③ push/pull/seq 核心 + 单测（LWW/幂等/tombstone/部分失败 全覆盖）→ ④ SSE → ⑤ 客户端 outbox（与业务写同 Drift 事务入队）+ pull applier + 前台 SSE 监听 + 断网重连（connectivity_plus 复用）→ ⑥ 设置页"账号/服务器"UI + 登录流 → ⑦ 双设备 e2e 测试（两个 isolate 对假/真服务器）→ ⑧ Dockerfile + compose + `docs/DEPLOY.md`（NAS 部署、Tailscale 出门访问建议）→ ⑨ 验证：设备 A 建/改/删 → 设备 B 秒级一致；杀进程重启不丢；离线编辑上线后合并正确

## Phase 3 — MCP + CLI（启动时展开详案）

- 工具面 = 已定规格 **22 个**（读 9 + 写 11 + 批量；snake_case 动词_名词；ISO 8601 + IANA timezone；RRULE 结构化对象；`list_events` 范围默认 now→+7d 上限 366 天）
- Resources：`dayspark://today|overdue|inbox`；错误 = 工具结果 `{isError, {code, message, hint}}`（不是 JSON-RPC error）；写工具 `readOnlyHint:false`；**不提供 delete_task**（archive 姿态，AllisWell 先例）→ 与 P1 回收站语义对齐
- 传输双形态：`POST /mcp` Streamable HTTP + **OAuth 2.1**（DCR + PKCE-S256 + token 轮换——ChatGPT connector 硬要求，Vikunja 裸 bearer 踩坑已知）；`tool/mcp_stdio_wrapper` 喂 Codex（`~/.codex/config.toml`）与 Claude Code/Hermes
- `tool/dayspark_cli`：`dayspark task list|add|done` 等，薄封装 REST
- 验证：MCP Inspector 过协议；Claude Code + Codex 各挂一次真实 CRUD；ChatGPT connector 走 OAuth 流程截图存档

## Phase 4 — 平台补齐 + Todo清单体验

- iOS：bundle id/App Group 统一 `com.dayspark.app` 族、entitlements（含 macOS keychain-access-groups 空数组修复）、CI 加 iOS job（证书 = 手工门）+ TestFlight 手工验收
- 小组件 v2：快速添加 deep link（`app://quick-add`，主路径）、月视图点阵组件（差异化）、Upcoming 变体、组件文案 l10n、暗色样式、勾选 last-wins 队列（SP 契约补全）
- 通知验收：过 UX 报告 (d) 全清单（Android 14 权限流、Doze、iOS CalendarTrigger/time-sensitive/授权时机）
- Todo清单 UX 批：六件事收敛视图（date_strip 升级）、月视图节气/调休数据、隐藏已完成开关、设置页信息架构终态
- Windows 通知 stub 复查上游是否已修，能换则换回官方实现

## P5+（明确出范围，不进本次计划执行）

番茄钟+数据复盘、CalDAV 导出层（抄 ByWave caldav.ts）、E2EE、MCP/后台同步/小组件以外的待恢复旧功能核销。

---

## Verification（每 Phase 通用）

1. `dart analyze .` 零 issue；`flutter test` 全绿（含迁移测试 v1→v8）
2. 手工回归：建事件/建待办/子任务/完成/回收站恢复/提醒到点/搜索/标签/主题/中英切换
3. P2+ 追加：双设备同步矩阵（在线/离线/冲突/删除）；P3 追加 MCP Inspector + 三客户端 CRUD；P4 追加真机组件与 TestFlight
4. CI：push 后 ci.yml 五平台 release 构建全绿（正交验证：先普通 push 验证再谈 tag）
5. 溯源：每个修复在 changelog.md 有"原文→修复"条目（Meta-Rule 1）

## 风险与回退

- kalender pre-1.0 breaking → 锁 `^0.17.4`，升级只在 Phase 间评估；若 kalender 无法承载拖拽/全天需求，回退方案 = 保留手写视图修 DST（决策已拍 A，回退需用户重开）
- iOS bundle id 迁移可能撞签名 → Task 6 已设降级路径（先匹配现有 group 名）
- Dart 后端性能对个人应用无风险；SQLite 单写者足够
- 未提交 13 文件与 CI 版本漂移 → Task 0 先行消化，任何 revert 保留 git 历史
