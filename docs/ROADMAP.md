# DaySpark Feature Evolution / 功能演进全景图

> Last updated / 最后更新: v0.25.0+25 | 2026-09-24 | Debt 2 unified event seam shipped: post-commit domain events (record-applied/removed) drive every derived state — remote reschedule re-arms local reminders, remote delete cancels queued notifications, three ad-hoc channels collapsed into one seam
> This is the single living document for the project, replacing the archived REQUIREMENTS.md and PLAN.md.
> 本文档是项目唯一的活文档，替代已归档的 REQUIREMENTS.md 和 PLAN.md。

**TL;DR / 快速了解**
- 当前版本 / Current: **v0.25.0+25** | 5 平台构建 (Android/Web/macOS/Linux/Windows) 全部成功
- 核心功能：日历日程管理（kalender 视图）+ 待办清单 + AI 助手（BYO key 客户端 AI）+ 自托管跨设备同步 + 服务端 MCP/AI 读写
- 最新变化：**债务2 统一事件缝落地（v0.25.0）** — 派生态失效从三条临时通道收敛为 post-commit 领域事件（`record-applied`/`record-removed`）：远端改期重挂本机提醒（关 P2.5#1）、远端删除撤销已排队通知（幽灵响铃）、事件回收站恢复重挂；新增单写入口守卫 + 棘轮基线（已收敛为空）
- 上一版：**P4 平台补齐与待办体验落地（v0.24.0）** — Apple 资产统一、小组件 v2 三变体、六件事/隐藏已完成、节气调休标记、设置 IA 终态、time-sensitive 通知（设备门 caveat）、adhoc keychain 签名修复
- 待完成：iOS TestFlight provisioning（time-sensitive capability keep/remove 决策）、2027 lunar 调休数据、Windows 通知恢复（stub 上游未修）、日期格式跟随系统 locale、集成测试；同步遗留项见 **Phase P2.5**（MCP 工具面随其实体同步扩展）

---

## 一、Current Features / 当前功能清单

### v0.1 — v0.7 | 2026-04-16 ~ 04-28 | Project Skeleton / 项目骨架

| Feature / 功能 | Source / 来源 |
|------|------|
| Clean Architecture directory structure / Clean Architecture 目录结构 | [Design / 设计] |
| Drift database with 9 tables / Drift 数据库 9 张表 | [Design / 设计] |
| Material 3 theme system (light/dark + design tokens) / Material 3 主题系统（light/dark + 设计 token） | [Design / 设计] |
| go_router routing / go_router 路由 | [Design / 设计] |
| Riverpod state management / Riverpod 状态管理 | [Design / 设计] |
| Calendar day/week/month views (kalender library) / 日历日/周/月视图（kalender 库） | [Design / 设计] |
| Event CRUD + CalendaEventAdapter / 事件 CRUD | [Design / 设计] |
| Todo CRUD + priority + completion tracking / 待办 CRUD + 优先级 + 完成追踪 | [Design / 设计] |
| Full-text search (events + todos) / 全文搜索（事件+待办） | [Design / 设计] |
| HomePage dual tabs (calendar + todos) / HomePage 双 tab（日历+待办） | [Design / 设计] |
| Tag system (many-to-many) / 标签系统（多对多） | [Design / 设计] |
| AI config (OpenAI compatible) / AI 配置（OpenAI 兼容） | [Design / 设计] |
| AI chat + streaming / AI 聊天 + 流式对话 | [Design / 设计] |
| ICS export / ICS 导出 | [Design / 设计] |
| i18n Chinese + English / i18n 中英双语 | [Design / 设计] |
| GitHub Actions CI/CD | [Design / 设计] |
| Attachment support / 附件支持 | [Design / 设计] |
| Project renamed to DaySpark / 灵光 / 项目更名为 DaySpark / 灵光 | [Design / 设计] |

### v0.9.0 | 2026-04-28

| Feature / 功能 | Source / 来源 |
|------|------|
| Default tab selection (calendar first / todos first) / 默认标签页选择 | [Feedback / 反馈] Users want custom homepage / 用户希望自定义首页 |
| Lunar calendar display option / 农历显示选项 | [Feedback / 反馈] Removed in v0.13.0 / 后续在 v0.13.0 移除 |
| Dark mode date picker fix / 暗黑模式日期选择器修复 | [Fix / 修复] |

### v0.9.4 | 2026-04-29

| Feature / 功能 | Source / 来源 |
|------|------|
| Android release rendering fix (uses-material-design) / Android release 渲染修复 | [Fix / 修复] |

### v0.9.5 | 2026-04-29

| Feature / 功能 | Source / 来源 |
|------|------|
| **Todo trash bin** (soft delete + restore + permanent delete + empty) / **待办回收站**（软删除 + 恢复 + 永久删除 + 清空） | [Feedback / 反馈] Users need undo delete / 用户需要撤销删除 |
| Todo UI refactoring / 待办 UI 重构 | [Feedback / 反馈] |

### v0.9.6 | 2026-04-29

| Feature / 功能 | Source / 来源 |
|------|------|
| **About page update check** (GitHub latest release) / **关于页更新检测** | [Feedback / 反馈] Users want to know about new versions / 用户想知道有没有新版 |
| **AI preset providers** (OpenAI/Claude/DeepSeek/Gemini) + auto-detect models / **AI 预设服务商** + 自动探测模型 | [Feedback / 反馈] Users don't want to manually enter base URL / 用户不想手动填 base URL |
| MCP create_event / create_todo tool | [Engineering / 工程] MCP feature completion / MCP 功能补全 |
| Calendar month view optimization / 日历月视图优化 | [Engineering / 工程] |

### v0.9.7 | 2026-04-29

| Feature / 功能 | Source / 来源 |
|------|------|
| Android signing fix / Android 签名修复 | [Fix / 修复] |
| Todo interaction improvements (swipe delete, long-press menu) / 待办交互改进（滑动删除、长按菜单） | [Feedback / 反馈] |

### v0.9.8 | 2026-04-30

| Feature / 功能 | Source / 来源 |
|------|------|
| Calendar anchor date consistency fix / 日历锚点日期一致性修复（视图切换不跳日期） | [Feedback / 反馈] #1 #11 |
| Todo date strip rewrite (7-day week view + swipe weeks) / 待办日期滑块重写（7 天周视图 + 左右切周） | [Feedback / 反馈] #3 |
| **Settings page restructured as ExpansionTile** / **设置页重构为 ExpansionTile**（高级功能折叠） | [Feedback / 反馈] #6 |
| Advanced feature tutorial links / 高级功能教程链接 | [Feedback / 反馈] #7 |
| Precise midnight timer (replaces per-minute polling) / 精确午夜定时器（替代每分钟轮询） | [Feedback / 反馈] #9 #13 |
| Calendar header two-row layout / 日历头部两行布局 | [Feedback / 反馈] #12 |

### v0.10.0 | 2026-04-30

| Feature / 功能 | Source / 来源 |
|------|------|
| Version reverted from 1.0.0 to 0.10.0 / 版本号从 1.0.0 回退到 0.10.0 | [Feedback / 反馈] User explicitly requested no 1.0 before ready / 用户明确要求 1.0 前不跳版 |
| CI removed dart format check / CI 移除 dart format 检查 | [Feedback / 反馈] #14 |
| Cleared all lint info to zero issues / 清除全部 lint info 达到零 issue | [Feedback / 反馈] #15 |

### v0.11.0 | 2026-04-30

| Feature / 功能 | Source / 来源 |
|------|------|
| Offline sync queue reliability / 离线同步队列可靠性增强 | [Engineering / 工程] |
| **Todo drag-and-drop reordering** / **待办拖拽排序** | [Feedback / 反馈] Users want manual ordering / 用户希望手动排列顺序 |
| **Notification action buttons** (Mark Done / Snooze 1h) / **通知操作按钮**（标记完成 / 延后 1 小时） | [Feedback / 反馈] Users want in-notification actions / 用户希望通知上直接操作 |
| All releases marked as pre-release / 全部 release 标记为 pre-release | [Feedback / 反馈] #17 |

### v0.12.0 | 2026-05-01 | 19 User Feedback Items / 19 项用户反馈

| Feature / 功能 | Source / 来源 |
|------|------|
| Month→week/day view date accuracy / 月→周/日视图切换日期准确性 | [Feedback / 反馈] #19 |
| About page dynamic version read + update check fix / 关于页版本号动态读取 + 检查更新修复 | [Feedback / 反馈] #20 |
| **In-app feedback page** (text + copy + link to GitHub) / **App 内反馈页** | [Feedback / 反馈] #21 |
| New todo default date = today / 新建待办默认日期 = 今天 | [Feedback / 反馈] #23 |
| **Wheel time picker** (CupertinoDatePicker) / **滚轮时间选择器** | [Feedback / 反馈] #26 |
| **All todos view** ("All" chip) / **全部待办视图** | [Feedback / 反馈] #27 |
| **Multi-day todo date range label** (e.g. "3/1 – 3/5") / **多天待办日期范围标签** | [Feedback / 反馈] #28 |
| **Changelog popup** (auto-show on version upgrade) / **更新日志弹窗** | [Feedback / 反馈] #29 |
| **MCP LAN access** (bind 0.0.0.0) / **MCP 局域网访问** | [Feedback / 反馈] #30 |
| **Custom theme color** (10 presets + reset) / **主题色自定义** | [Feedback / 反馈] #31 |
| Full code review (race conditions, debounce, UI fixes) / 代码全面审查 | [Engineering / 工程] |

### v0.13.0 | 2026-05-01 | Architecture Refactor / 架构重构

| Feature / 功能 | Source / 来源 |
|------|------|
| **Removed** MCP server / background sync / widgets / network listener (not working) / **砍掉** MCP / 后台同步 / 小组件 / 网络监听 | [Engineering / 工程] Tech debt cleanup / 技术债务清理 |
| **Self-built month/week/day calendar views** replacing kalender library / **自建月/周/日日历视图**替代 kalender 库 | [Engineering / 工程] kalender too restrictive / kalender 限制太多 |
| DB schema v4→v5 | [Engineering / 工程] |
| Fixed 6 high-priority bugs (sync race crash, resource leaks, etc.) / 修 6 个高优 bug | [Fix / 修复] |
| -2073 lines deleted / 删除 355 行 MCP + 62 行小组件 + 63 行后台同步 | [Engineering / 工程] |

### v0.14.0 | 2026-05-01 | Core Polish / 核心打磨

| Feature / 功能 | Source / 来源 |
|------|------|
| **CalDAV delete sync** (local soft delete + push remote + remote delete detection) / **CalDAV 删除同步** | [Engineering / 工程] Sync integrity / 同步完整性的必要补充 |
| **Multi-day event cross-day display** / **多日事件跨天显示** | [Feedback / 反馈] Multi-day events only showed on first day / 跨天事件只在第一天显示 |
| **Now indicator line** (red timeline) / **Now 指示线**（红色时间线） | [Feedback / 反馈] Users can't see current time position / 用户不知道当前时间在哪 |
| **View mode persistence** (remember last day/week/month) / **视图模式持久化** | [Feedback / 反馈] |
| **Auto-sync on app foreground** (>5 min triggers incremental) / **App 回前台自动同步** | [Engineering / 工程] |
| **Auto-sync on network recovery** (connectivity_plus) / **网络恢复自动同步** | [Engineering / 工程] Removed in v0.13.0, re-added / v0.13.0 砍掉，v0.14.0 重新加回 |
| DB schema v5→v6 (events add deletedAt) | [Engineering / 工程] |
| 9 hardcoded strings → l10n / 9 处硬编码字符串 → l10n | [Engineering / 工程] |

### v0.15.0 | Uncommitted / 未提交

| Feature / 功能 | Source / 来源 |
|------|------|
| **Home Widget** (Android home_widget + iOS WidgetKit) / **桌面小组件** | [Design / 设计] |
| **MCP Server rewrite** (mcp_dart v2.1.1 + StreamableMcpServer) / **MCP 服务器重写** | [Design / 设计] Reimplemented after v0.13.0 removal / v0.13.0 砍掉后重新实现 |
| **Tag edit/rename** / **标签编辑/重命名** | [Feedback / 反馈] Users need to change tag names and colors / 用户需要改标签名和颜色 |
| **Password security migration** (DB plaintext → FlutterSecureStorage) / **密码安全迁移** | [Engineering / 工程] Security improvement / 安全改进 |
| **Enforce HTTPS** (Dio interceptor auto-upgrades http→https) / **强制 HTTPS** | [Design / 设计] |
| **DB export/import** (Share + FilePicker) / **DB 导出/导入** | [Design / 设计] |
| **Biometric lock** (local_auth + BiometricGate) / **生物识别锁** | [Design / 设计] |
| Multi-CalDAV account support / 多 CalDAV 账户支持 | [Design / 设计] |

### v0.16.0 | Uncommitted / 未提交

| Feature / 功能 | Source / 来源 |
|------|------|
| **Calendar event drag** (LongPressDraggable + DragTarget, recurring events disabled) / **日历拖拽事件** | [Design / 设计] |
| **System alarm** (alarm plugin + NotificationService integration) / **系统闹钟** | [Design / 设计] |
| Dark accent #3B82F6 → #60A5FA (WCAG AA) / 暗色 accent 对比度修复 | [Design / 设计] |
| EventTile min height 48px + dark mode color adaptation / EventTile 最小高度 48px + 暗色模式颜色适配 | [Design / 设计] |
| Removed BoxShadow, replaced with borders / 移除 BoxShadow 用边框替代 | [Design / 设计] |
| Fixed 32x32 touch targets → 48x48 / 修复 32x32 触摸目标 → 48x48 | [Design / 设计] |

### v0.17.0 | 2026-05-02 | Engineering P0 / 工程 P0

| Feature / 功能 | Source / 来源 |
|------|------|
| GPLv3 LICENSE file / GPLv3 LICENSE 文件 | [Engineering / 工程] |
| NOTICE file (flutter_oss_licenses) / NOTICE 文件生成 | [Engineering / 工程] |
| API Key masking (show last 4 chars) / API Key 掩码显示 | [Engineering / 工程] |
| Web build fix (MCP conditional import) / Web 构建修复（MCP 条件导入） | [Fix / 修复] |
| Android build fix (workmanager ^0.9.0) / Android 构建修复 | [Fix / 修复] |
| Docs bilingual (Chinese + English) / 文档中英双语 | [Feedback / 反馈] |
| Removed personal screenshot / 移除个人截图 | [Feedback / 反馈] |

### v0.18.0 | 2026-05-03 | Calendar Polish & Open Source Prep / 日历打磨 + 开源准备

| Feature / 功能 | Source / 来源 |
|------|------|
| Calendar page range fix (20000/4000/800 → restore constants) / 日历页面范围修复 | [Fix / 修复] |
| Calendar static range (prevent CalendarSection rebuild on swipe) / 日历静态 range 防重建 | [Fix / 修复] |
| Multi-day event rendering fix / 多日事件渲染修复 | [Fix / 修复] |
| Dark mode + accent color WCAG AA fix / 暗色模式 + accent 对比度修复 | [Fix / 修复] |
| _isAnimating deadlock fix (page swipe loop) / _isAnimating 死锁修复 | [Fix / 修复] |
| Event equality (== all 12 fields) / 事件 equality 覆盖全部字段 | [Fix / 修复] |
| ICS import duplicate fix / ICS 导入重复修复 | [Fix / 修复] |
| Alarm ID offset (500000/600000) conflict fix / 闹钟 ID 偏移防冲突 | [Fix / 修复] |
| Wheel time picker follow system locale / 时间选择器跟随系统 locale | [Fix / 修复] |
| Month view touch feedback (InkWell ripple) / 月视图触摸反馈 | [Fix / 修复] |
| Dynamic version read (package_info_plus) / 版本号动态读取 | [Fix / 修复] |
| **Settings page locale switch** (中文/English/System) / **设置页语言切换** | [Feature / 功能] |
| Open source community files (CODE_OF_CONDUCT, CONTRIBUTING, SECURITY) / 开源社区文件 | [Engineering / 工程] |
| Bilingual docs (README, docs/) / 双语文档 | [Engineering / 工程] |
| RESTRUCTURED.md removed, ROADMAP as single living doc / 废弃文档清理 | [Engineering / 工程] |
| -11037 lines (oss_licenses.dart removed from git) / 移除大文件 | [Engineering / 工程] |
| docs/CONSTRAINTS.md created / 技术约束文档 | [Engineering / 工程] |

### v0.19.0 | 2026-05-14 | Security Hardening + Data Integrity / 安全加固 + 数据完整性

| Feature / 功能 | Source / 来源 |
|------|------|
| **Signing key rotation** (remove from git → restore for private repo) / **签名密钥治理** | [Security / 安全] |
| **R8 minification** + ProGuard rules / **R8 混淆 + ProGuard 规则** | [Security / 安全] |
| **Password fallback removed** (no DB plaintext fallback) / **密码不回退数据库明文** | [Security / 安全] |
| **Android permission typo** FOREREGROUND→FOREGROUND / **Android 权限拼写修复** | [Fix / 修复] |
| Architecture cleanup (infrastructure layer → lib/infrastructure/) / 架构清理（基础设施层剥离） | [Refactor / 重构] |
| file_reader moved to lib/data/ / file_reader 移到 data 层 | [Refactor / 重构] |
| Sync exception logging (7 empty catch → debugPrint) / 同步层异常日志化 | [Fix / 修复] |
| Color parsing safety (tryParse + fallback) / 颜色解析安全性 | [Fix / 修复] |
| Provider crash guard (tryParse for family keys) / Provider 级联崩溃防护 | [Fix / 修复] |
| Account cascade deletion (transactional) / 账户级联删除 | [Fix / 修复] |
| Todo soft-delete sync (isDirty flag) / 待办软删除同步标记 | [Fix / 修复] |
| Changelog read-mark timing fix / 更新日志已读标记时机修复 | [Fix / 修复] |
| release-prep skill / 发版技能 | [Engineering / 工程] |

### v0.19.1 | 2026-05-14 | CI Cleanup & Docs Sync / CI 清理与文档同步

| Feature / 功能 | Source / 来源 |
|------|------|
| release.yml duplicate test removed / release.yml 移除重复 test | [Engineering / 工程] |
| release-prep skill simplified to 4-step / 发版 skill 简化为 4 步 | [Feedback / 反馈] |
| ROADMAP updated to v0.19.1 / ROADMAP 同步到 v0.19.1 | [Engineering / 工程] |
| changelog added v0.18.0 section / changelog 补充 v0.18.0 | [Engineering / 工程] |
| CLAUDE.md version synced / CLAUDE.md 版本同步 | [Engineering / 工程] |

### v0.19.2 | 2026-05-14 | Linux CI Baseline & macOS Flutter Version Pin / Linux 构建基线 + macOS 版本锁定

| Feature / 功能 | Source / 来源 |
|------|------|
| **Linux CI baseline locked to Ubuntu 22.04** (GLIBC 2.35) / **Linux CI 基线锁定到 Ubuntu 22.04** | [Fix / 修复] |
| **`tool/check_glibc_version.sh`** — CI checks no .so exceeds GLIBC 2.35 / **GLIBC 版本校验脚本** | [Fix / 修复] |
| **macOS Flutter version pinned to 3.41.7** — solves ARM64 SDK download flakiness / **macOS Flutter 版本锁定 3.41.7** | [Fix / 修复] |
| CONSTRAINTS.md: Linux distribution constraints documented / Linux 分发约束入库 | [Docs / 文档] |
| CLAUDE.md: build rules expanded, version synced / 构建规则扩展，版本同步 | [Docs / 文档] |

### v0.20.0 | 2026-05-15 | Bug Fixes + Subtask + Terminal CLI + Headless MCP / Bug 修复 + 子任务 + 命令行 + Headless MCP

| Feature / 功能 | Source / 来源 |
|------|------|
| **Subtask support** (DB schema v6→v7, parentId column, edit page UI) / **子任务功能** | [Feedback / 反馈] |
| **Terminal CLI** (`bin/dayspark.dart` — todo/event/search CRUD via command line, Drift DAOs, full schema+ migration support) / **终端命令行**（复用 Drift DAOs，全表+全迁移支持） | [Feedback / 反馈] |
| **Headless MCP auto-start** (persistent setting, auto-start on app launch) / **Headless MCP 自动启动** | [Feedback / 反馈] |
| **Windows installer** (Inno Setup, `DaySpark-*-Setup.exe`) / **Windows 安装包** | [Feedback / 反馈] |
| **Linux Impeller rendering** (`--enable-impeller` for GPU-backed performance) / **Linux Impeller 渲染** | [Fix / 修复] |
| Todo checklist index number / 待办 checkbox 序号 | [Fix / 修复] |
| Todo All-view drag reorder / 待办全视图拖拽排序 | [Fix / 修复] |
| Todo edit page reminder UI / 待办编辑页闹钟提醒设置 | [Fix / 修复] |
| RRULE text locale-aware (not hardcoded Chinese) / RRULE 重复文本跟随语言 | [Fix / 修复] |
| MCP port configurable / MCP 端口可自定义 | [Fix / 修复] |
| Event date filter fix (same-day events not showing) / 新建日程显示修复 | [Fix / 修复] |
| Linux date picker mouse wheel fix / Linux 日期选择器鼠标滚轮兼容 | [Fix / 修复] |
| Linux alarm fallback + settings lag fix / Linux 闹钟 + 设置卡顿修复 | [Fix / 修复] |
| GitHub API 403 fix (User-Agent + timeout + friendly error) / 更新检查 403 修复 | [Fix / 修复] |
| Export Linux unimplemented fallback / Linux 导出降级 | [Fix / 修复] |
| AI model detection URL hint + timeout / AI 探测增加提示和超时 | [Fix / 修复] |
| Sync refresh shows success feedback / 同步刷新增加成功提示 | [Fix / 修复] |
| NotificationService Linux init support / 通知服务 Linux 初始化 | [Fix / 修复] |

### v0.20.2 | 2026-05-15 | CI Hardening + Code Review Skill / CI 加固 + 代码审查 Skill

| Change / 变更 | Source / 来源 |
|------|------|
| **dayspark-code-review skill** (60 domain-specific rules, embedded in release-prep) / **代码审查 skill** | [Engineering / 工程] |
| **Fix: Windows release build (Flutter 3.41.9 MSB8066 → pin to 3.41.7)** / **修复 Windows release 旧问题** | [Fix / 修复] |
| **Fix: 6 missing l10n ARB keys** (caused gen-l10n compile failure on CI) / **修复 6 个缺失的 ARB key** | [Fix / 修复] |
| **Fix: Web build dart:ffi** (split NativeDatabase into separate file) / **修复 Web 构建 dart:ffi 问题** | [Fix / 修复] |
| **26 empty catch blocks → debugPrint** across sync, UI, infra layers / **26 处空 catch 日志化** | [Review / 审查] |
| **22 non-standard border radii → unified 6/8/12** / **22 处圆角统一** | [Review / 审查] |
| **2 dart:io imports → defaultTargetPlatform** / **2 处 dart:io 平台检测替换** | [Review / 审查] |
| **3 GestureDetector → InkWell** in month view + subtask page / **3 处手势组件替换** | [Review / 审查] |

> ⚠️ v0.20.3 / v0.20.4: Windows release 构建仍然失败，新根因 `gen_snapshot` AOT serialization bug on `NativeLaunchDetails`。`final class → base class` 假设已验证无效，根因待确认。

### v0.20.5 | 2026-05-16 | Windows Release Fix + CI Fix / Windows 发版修复 + CI 修复

| Change / 变更 | Source / 来源 |
|------|------|
| **Windows release build fixed** — `flutter_local_notifications_windows` replaced with pure-Dart stub (no FFI, no native DLL). Windows notifications temporarily disabled but release builds succeed. / **Windows release 构建修复** | [Fix / 修复] |
| **CI flutter analyze fixed** — `analysis_options.yaml` excludes `patches/**` to avoid pre-existing lint warnings from third-party override. / **CI analyze 修复** | [Fix / 修复] |
| **Flutter version unified to 3.41.7** — release.yml Windows build uses same version as CI debug and macOS release. / **Flutter 版本统一** | [Engineering / 工程] |

### v0.20.5+24 | 2026-05-17 | Security: Remove Signing Keys from Repo / 安全修复：移除签名密钥

| Change / 变更 | Source / 来源 |
|------|------|
| **Android signing keys removed from git tracking** — new random-password keystore generated, `key.properties` + `release-keystore.jks` added to `.gitignore`, old files `git rm`'d. / **Android 签名密钥移出 git 追踪** | [Security / 安全] |
| **CI injects keystore via GitHub Secrets** — `release.yml` decodes base64 keystore + writes `key.properties` from `${{ secrets.ANDROID_KEYSTORE }}` etc. / **CI 改为从 Secrets 注入签名** | [Security / 安全] |
| **Cleanup ~8 GB local build cache** — `build/`, `.dart_tool/`, `.opencode/node_modules/` removed. / **清理 ~8GB 本地构建缓存** | [Maintenance / 维护] |

### v0.25.0 | 2026-09-24 | Debt 2: Unified Event Seam / 债务2 统一事件缝

| Change / 变更 | Source / 来源 |
|------|------|
| **单一失效缝** — 进程内一切 `events`/`todos`/`reminders` 行写入收敛到 `RecordScope.run` + `lib/domain/records/writers/**`（写入即登记、**提交后**发布）；三条临时通道（provider 内联手调 / UI save 补丁 / 小组件 `tableUpdates`）→ 一条缝，`rescheduleRemindersProvider` 已删除。 / **单一失效缝** — 写入口唯一 + post-commit 领域事件 | [Feature / 功能] SPEC 3.5 规则 1–5 落地 |
| **远端改期重挂本机提醒** — 同步落地（pull / push conflict / piggyback，含 MCP·AI 远端写入）走 applier 时登记 `applied(previousReference: 写前值)`，重排器按 Δ 搬迁并把新触发时刻物化回写 `reminders.triggerTime`。 / **远端改期重挂** — 关 P2.5 #1 | [Fix / 修复] ROADMAP P2.5 #1 |
| **幽灵响铃修复** — 远端 tombstone 落地时登记 `removed` + 该记录全部 reminder id，已排队通知立即撤销。 / **幽灵响铃修复** — 远端删除不再响 | [Fix / 修复] 债务2 勘察新发现缺陷 |
| **消费端重写** — `ReminderReconciler`（四档取消 + D12 锚点归属 + 幂等零调用）替换 11 处散落 cancel/schedule；小组件刷新器换驱动源为 `RecordBus`。 / **消费端重写** | [Feature / 功能] SPEC 3.5 规则 4 |
| **双层机械守卫** — `record_seam_guard_test.dart`（G1 白名单 / G3 已删符号 / G4 `RecordScope.run` 站点数 = 25）+ `tool/record_seam_baseline.txt` 棘轮（**已收敛为空 = 全仓零豁免**）。 / **双层守卫** | [Engineering / 工程] 防漏（静默过期型失效） |
| **Governance** — CONSTRAINTS 记录缝条目 + 通知链清单补 2 项、DECISIONS ADR（显式 scope vs Zone/拦截器）、SPEC 3.5 规则补全、版本 0.25.0+25。 / **治理** — 约束/决策/SPEC/版本同步 | [Docs / 文档] |

### v0.24.0 | 2026-09-24 | P4 Platform Parity + Todo UX / P4 平台补齐与待办体验

| Change / 变更 | Source / 来源 |
|------|------|
| **Apple asset unification** — bundle id → `com.dayspark.app*`、App Group → `group.com.dayspark.app`（原子迁移）、`dayspark` URL scheme 双端、CI iOS simulator 编译门。 / **Apple 资产统一** — bundle/App Group 迁入 dayspark 族 + iOS 编译门 | [Feature / 功能] SPEC 1.1 需求 2 落地 |
| **Widget v2 three variants** — Today/Upcoming/月点阵 × Android/iOS/macOS 读 `widget_snapshot` v2（10 键含 `monthDots`）；`pendingTaps` 勾选队列（单写路径）+ `dayspark://quick-add` 快速添加；`ui` 预本地化 + `theme` 暗色；macOS home_widget shim。 / **小组件 v2 三变体** — 三端 v2 快照、勾选队列、快速添加通路、预本地化与暗色 | [Feature / 功能] SPEC 1.1 需求 5 落地 |
| **Six things + hide-completed** — 今天视图六槽收敛（默认 OFF，复用拖拽前缀语义）+ 隐藏已完成开关（三视图过滤）。 / **六件事 + 隐藏已完成** | [Feature / 功能] Todo清单 UX 批 A |
| **Solar-term & holiday month markers** — `lunar ^1.7.8`（纯 Dart）：节气微标签 + 班/休角标 + 非当月淡化；法定数据止于 2026（2027+ 角标降级为已知限制）。 / **节气/调休月标记** | [Feature / 功能] Todo清单 UX 批 A |
| **Settings IA terminal + calendar debts** — 设置一级精简（外观组/功能组/折叠高级）；日/周 08:00 起滚、事件 tile click 光标、空白槽语义、月视图非当月淡化。 / **设置 IA 终态 + 日历清欠** | [Feature / 功能] Todo清单 UX 批 B |
| **Time-sensitive notifications + device gate** — `interruptionLevel: .timeSensitive` 双路径 + `Runner.entitlements` 真接线（三配置 `CODE_SIGN_ENTITLEMENTS`）；个人 team 拒绝 capability → device/TestFlight fail-closed（keep/remove 决策跟进）。 / **time-sensitive 通知 + 设备门** | [Feature / 功能] 通知验收 |
| **macOS adhoc keychain SIGKILL fix** — `keychain-access-groups` 整键删除（空数组实验证明同样崩，2026-09-24 崩溃根因）。 / **macOS adhoc keychain 崩溃修复** | [Fix / 修复] 用户实测崩溃 |
| **Hygiene bucket + Windows stub recheck** — tool 测试进 CI、`$e` 脱敏、consent 防帧头、RFC 7591 两字段、`response_mode` 校验、Linux `APPLICATION_ID` 迁移；Windows 通知上游未修 → override 保留。 / **卫生桶 + Windows stub 复查** | [Engineering / 工程] P1–P3 评审结转 |
| **Governance** — CONSTRAINTS（macOS 签名/iOS 接线/time-sensitive 门/monthDots schema）、DECISIONS +7、SPEC 3.4 P4 ✅、`docs/qa/p4-manual-qa.md`、版本 0.24.0+24。 / **治理** — 约束/决策/SPEC/P4 QA 清单/版本同步 | [Docs / 文档] |

### v0.23.0 | 2026-09-23 | P3 Server MCP + CLI / P3 服务端 MCP 与 CLI

| Change / 变更 | Source / 来源 |
|------|------|
| **Server MCP endpoint (`POST /mcp`)** — stateless Streamable HTTP in-process with the sync backend: **17 frozen tools** (7 read + 10 write, event+task face; calendar/tag/reminder tools deferred to P2.5 entity sync) + **3 resources** (`dayspark://today`/`overdue`/`inbox`); errors-as-tool-results with code/message/hint; writes land in the P2 LWW/`nextSeq` internal-op seam (AI = one virtual device). / **服务端 MCP 端点（`POST /mcp`）** — 与同步后端同进程的无状态 Streamable HTTP：**17 个冻结工具**（7 读 + 10 写，event+task 面；calendar/tag/reminder 工具随 P2.5 实体同步补）+ **3 个资源**；业务错误以工具结果返回；写走 P2 LWW/`nextSeq` 内部 op 缝（AI 即一台虚拟设备） | [Feature / 功能] SPEC 1.1 需求 4 落地 |
| **OAuth 2.1 authorization server, two-track** — RFC 8414/9728 discovery, RFC 7591 DCR, PKCE-S256-only authorize + minimal consent page, rotation reusing P2 family-revoke, RFC 7009 revoke; scopes `mcp:read`/`mcp:write` double-gated over tools AND resources; `track` claim keeps CLI login tokens off OAuth-track refresh and OAuth tokens off `/sync/*`. / **OAuth 2.1 授权服务器（双轨）** — 发现文档、动态注册、PKCE-S256、同意页、复用 P2 家族吊销的轮换、撤销；scope 对工具与资源双门；`track` 声明保证两轨 token 互不越界 | [Feature / 功能] |
| **MCP stdio wrapper + `dayspark` CLI** — `tool/mcp_stdio_wrapper` feeds local agents (Claude Code/Codex) over stdio↔HTTP; `tool/dayspark_cli` is a thin HTTP **MCP client** dogfooding the frozen tool surface (`/auth/login` token, `credentials.json` mode 600). / **stdio 桥 + `dayspark` CLI** — 本地 Agent 经 stdio 桥接 `/mcp`；CLI 是薄 HTTP **MCP 客户端**，dogfood 冻结工具面（登录 token、凭证 600 权限） | [Feature / 功能] |
| **MCP e2e matrix (5 cases) + four-client QA doc** — server-side matrix: create propagate, complete converge, disjoint-field concurrent merge, OAuth full chain, scope demotion all green; manual Inspector/Claude Code/Codex/ChatGPT checklist at `docs/qa/p3-mcp-qa.md`. / **MCP e2e 矩阵（5 例）+ 四客户端 QA 说明** — 创建传播、完成收敛、不相交字段并发合并、OAuth 全链路、scope 降权全绿；手工清单见 p3-mcp-qa.md | [Engineering / 工程] Orthogonal verification / 正交验证 |
| **X-Forwarded-Proto trust fix** — reverse-proxy HTTPS origins advertised correctly by OAuth discovery and 401 challenge (direct exposure byte-identical when header absent). / **反代 XFP 信任修复** — OAuth 发现与 401 challenge 正确广告 https 源（缺头时行为不变） | [Fix / 修复] |
| **Governance** — CONSTRAINTS MCP section (protocol hard rules), DECISIONS +5 entries, SPEC 3.4 P3 ✅, version 0.23.0+24. / **治理** — CONSTRAINTS MCP 章节、DECISIONS +5 条、SPEC 3.4 P3 ✅、版本 0.23.0+24 | [Docs / 文档] |

### v0.22.0 | 2026-09-23 | P2 Sync Backend / P2 同步后端

| Change / 变更 | Source / 来源 |
|------|------|
| **`dayspark_contracts` protocol package** — shared DTOs/error codes as SSOT between client and server, 37 contract tests. / **`dayspark_contracts` 协议包** — 客户端/服务端共享 DTO 与错误码（SSOT），37 项契约测试 | [Engineering / 工程] SPEC 1.1 需求 3 落地 |
| **Sync server (Docker)** — Dart shelf backend: JWT auth (argon2id + refresh rotation), idempotent per-op push, watermark-cursor pull, field-level LWW, tombstones, SSE cursor-only stream; drift/SQLite single file; multi-stage image on debian trixie, JWT fail-fast; deploy guide `docs/DEPLOY.md`. / **同步服务端（Docker）** — Dart shelf 后端：JWT 认证（argon2id+刷新轮换）、逐条幂等 push、水位线游标 pull、字段级 LWW、墓碑、SSE 只发 cursor；drift/SQLite 单文件；trixie 多阶段镜像、JWT 快速失败；部署指南见 DEPLOY.md | [Feature / 功能] Self-hosted NAS sync / 自托管 NAS 同步 |
| **Client sync engine** — schema v9 `sync_outbox` + explicit provider-exit enqueue + pull/piggyback applier (event/todo) + `SyncEngine` rounds + SSE listener with reconnect/foreground triggers; account settings section (server URL / register / login / status). / **客户端同步引擎** — schema v9 出站队列 + provider 出口显式入队 + pull/piggyback 应用器（event/todo）+ 引擎轮次 + SSE 监听（断网恢复/回前台）；账号设置区 | [Feature / 功能] Offline-first convergence / 离线优先收敛 |
| **Dual-device e2e matrix** — 5 cases vs a real server in `flutter test` (create/edit/delete tombstone/offline field-disjoint merge/alternating cursors); case ④ caught a real lost-update, fixed by dirty-fields push (`SyncSnapshot` + `dirtyFields`). / **双设备 e2e 矩阵** — `flutter test` 内对真 server 跑 5 例；例 ④ 抓到真丢更新，以脏字段推送修复 | [Engineering / 工程] Orthogonal verification / 正交验证 |
| **CI `server-test` job** — `dart analyze` + `dart test` for `server/` and contracts tests for `packages/dayspark_contracts`. / **CI `server-test` 任务** — server analyze+test 与 contracts 测试 | [Engineering / 工程] |
| **Governance** — CONSTRAINTS Sync section (protocol hard rules), DECISIONS entries, SPEC 3.4 P2 ✅, `docs/qa/p2-manual-qa.md`. / **治理** — CONSTRAINTS 同步章节、DECISIONS 条目、SPEC 3.4 P2 ✅、手工双设备 QA 清单 | [Docs / 文档] |

### v0.21.0 | 2026-09-22 | Phase 1 Foundation Refactor / Phase 1 基础重构

| Change / 变更 | Source / 来源 |
|------|------|
| **kalender calendar views** — day/week/month views rebuilt on `kalender ^0.17.0` (pinned minor), replacing hand-rolled views; fixes DST drift, GlobalKey collisions, overlap layout, all-day series bugs. / **kalender 日历视图** — 基于 kalender 重建日/周/月视图，修复 DST/GlobalKey/重叠/全天系列 bug | [Engineering / 工程] Decision A revisited / 决策 A 重开后拍板 |
| **Removed CalDAV sync layer + client MCP, schema v8** — accounts/sync_queue dropped, CalDAV columns removed; migration test v1→v8. / **移除 CalDAV 同步层与客户端 MCP，schema v8** | [Engineering / 工程] Replaced by P2 sync backend / P3 server MCP |
| **Notification chain repair** — 3 Android receivers, local timezone init, snooze on `reminder.id`, cancel/reschedule wiring on complete/edit/delete/trash, exact-alarm guidance tile, notification text l10n. / **通知链修复** | [Fix / 修复] |
| **Widget data path repair** — App Group wiring (`setAppGroupId` + macOS Runner entitlements), write-driven refresh, versioned snapshot dual-write, NULL-due sinking, subtask filtering. / **小组件数据通路修复** | [Fix / 修复] |
| **Bug batch** — event trash sections + cascade restore, child soft-delete cascade, `restore` no-op fix (`Value.absent()`), FAB prefills browsed date, drag reschedule reminders, ICS skips soft-deleted, family providers → autoDispose, version compare `tryParse`. / **bug 批** | [Fix / 修复] |
| **l10n cleanup** — dead keys removed, placeholders + Semantics fixed. / **l10n 清理** | [Engineering / 工程] |
| **Settings/home slimming** — settings split into `settings_sections/*`, home initState side effects extracted (zero behavior change). / **设置页与首页瘦身** | [Engineering / 工程] |
| **Governance baseline** — `SPEC.md` / `DECISIONS.md` / `AGENTS.md` + pre-commit `dart analyze` gate. / **治理基线** | [Engineering / 工程] |

### v0.20.1 | 2026-05-15 | Comprehensive UI Fixes / 大规模 UI 修复

| Fix / 修复 | Source / 来源 |
|------|------|
| **Accessibility (Semantics)** on all interactive elements / 全交互元素无障碍标签 | [Review / 审查] |
| **Desktop keyboard shortcuts** (Escape→back, framework for Ctrl+S/N) / 桌面键盘快捷键 | [Review / 审查] |
| **Platform-adaptive scroll physics** (Bouncing iOS/macOS vs Clamping others) / 平台感知滚动动效 | [Review / 审查] |
| **Desktop cursor + hover states** on 17+ interactive elements / 桌面指针光标+悬停效果 | [Review / 审查] |
| **Platform-aware drag** (Draggable on desktop, LongPressDraggable on mobile) / 拖拽平台自适应 | [Review / 审查] |
| **Fixed `dart:io` import for Web** (wheel_time_picker Web crash) / 修复 Web 构建崩溃 | [Review / 审查] |
| **Fixed `build()` side effects** in home_page + settings_page / 修复 build 方法内副作用 | [Review / 审查] |
| **Fixed GestureDetector/InkWell nesting** in month calendar / 修复月视图手势冲突 | [Review / 审查] |
| **i18n: 6 new l10n keys** (nMore, subtaskHint, reminderLabel, etc.) / 新增 6 个国际化 key | [Review / 审查] |
| **Hardcoded weekday labels** → `DateFormat.E()` for all locales / 硬编码星期→全 locale 适配 | [Review / 审查] |
| **Fixed 12+ small touch targets** (<44px) across the app / 修复 12+ 处过小触摸目标 | [Review / 审查] |
| **GestureDetector→InkWell** in date picker, color picker, tag chips / 批量替换 InkWell | [Review / 审查] |
| **Search debounce** (300ms) to reduce query spam / 搜索去抖 | [Review / 审查] |
| **Event filtering memoization** in month view (O(n×42)→O(n)) / 月视图事件过滤缓存 | [Review / 审查] |
| **Chat bubble max-width** capped at 600px on desktop / 聊天气泡最大宽度限制 | [Review / 审查] |
| **Visual consistency**: border radius unified (16→8), tag chip alpha adjusted / 视觉一致性统一 | [Review / 审查] |
| **DRY**: color list extracted to top-level constant in tags_page / 标签页颜色列表去重 | [Review / 审查] |
| **PackageInfo caching** removes FutureBuilder per-rebuild overhead / PackageInfo 缓存 | [Review / 审查] |
| **Hardcoded User-Agent version** → dynamic PackageInfo / User-Agent 版本号动态化 | [Review / 审查] |

---

## 二、Requirement Changes / 需求变更记录

### Frozen Requirements Status / 冻结需求完成状态

> Full definitions in `SPEC.md` 1.1 / 完整定义见 SPEC.md 1.1；此处只跟踪完成状态。 / Status tracking only.

| # | Frozen Requirement / 冻结需求 | Status / 状态 |
|---|------|------|
| 2 | **统一五平台客户端** (single Flutter codebase, feature parity) / **统一五平台客户端**（单一代码库、功能对齐） | ✅ 完成 (v0.24.0) — five-platform parity verified (six-suite + Kotlin); caveats: iOS device/TestFlight builds gated on time-sensitive provisioning, Windows notifications stubbed / 五平台对齐已验证；caveat：iOS 真机/TestFlight 受 time-sensitive provisioning 门限制、Windows 通知仍为 stub |
| 3 | **Cross-device sync** (offline-first, field-level LWW) / **跨设备同步**（离线优先、字段级 LWW） | ✅ 完成 (v0.22.0) — sync backend + client engine + dual-device e2e / 同步后端 + 客户端引擎 + 双设备 e2e |
| 4 | **AI 可读写 MCP** (AI reads/writes events & todos) / **AI 可读写 MCP**（AI 读写事件/待办） | ✅ 完成 (v0.23.0) — server MCP 17 tools + 3 resources, OAuth 2.1 two-track, stdio wrapper + CLI / 服务端 MCP 17 工具 + 3 资源、OAuth 2.1 双轨、stdio 桥 + CLI |
| 5 | **双端小组件** (Android + iOS/macOS widgets, quick actions) / **双端小组件**（Android + iOS/macOS，支持快速操作） | ✅ 完成 (v0.24.0) — widget v2 three variants (Today/Upcoming/月点阵) × Android/iOS/macOS, pendingTaps + quick-add; caveat: iOS widget device QA needs a provisioned signed build (sim OK) / 小组件 v2 三变体 + 勾选/快速添加；caveat：iOS 真机组件验收需 provisioning 通过的签名包（模拟器可验） |
| 1, 6–8 | Remaining frozen requirements / 其余冻结需求 | See `SPEC.md` 1.1; tracked by phase plan below / 见 SPEC 1.1，由下方阶段规划跟踪 |

### Scheme Changes / 方案级变更

| Original / 原方案 | Changed to / 变更后 | Version / 版本 | Reason / 原因 |
|--------|--------|------|------|
| kalender library for calendar / kalender 库做日历视图 | Self-built views / 自建月/周/日视图 | v0.13.0 | kalender too restrictive, drag/layout limited / kalender 定制性不足，拖拽/布局受限 |
| Single CalDAV account / 单 CalDAV 账户 | Multi-account / 多账户 | v0.15.0 | Users have multiple calendar services / 用户有多个日历服务 |
| Fixed blue #2563EB theme / 固定蓝色 #2563EB 主题 | 10 preset color custom / 10 种预设色自定义 | v0.12.0 | Users want personalization / 用户要求个性化 |
| Material TimePicker | CupertinoDatePicker wheel / CupertinoDatePicker 滚轮 | v0.12.0 | Users want iOS style / 用户要求 iOS 风格 |
| Lunar calendar display / 农历显示 | Removed / 移除 | v0.13.0 | Package size + not commonly used / 包体积 + 不常用 |

### Removed Then Re-added / 砍掉又加回

| Feature / 功能 | Removed / 砍掉版本 | Re-added / 加回版本 | Reason / 原因 |
|------|----------|----------|------|
| MCP Server | v0.13.0 | v0.15.0 | Not working, rewritten from scratch / 实现不工作，从零重写 |
| Background sync / 后台同步 | v0.13.0 | v0.15.0 | Same / 同上 |
| Home Widget / 桌面小组件 | v0.13.0 | v0.15.0 | Same / 同上 |
| Network auto-sync / 网络监听自动同步 | v0.13.0 | v0.14.0 | Same / 同上 |

### User-Requested Features Not in Original Design / 用户要求但不在原始设计里的功能

| Feature / 功能 | Version / 版本 | Note / 说明 |
|------|------|------|
| Todo trash bin / 待办回收站 | v0.9.5 | Original only had "delete", no "undo" / 原始需求只有"删除"，没有"撤销" |
| Todo drag reorder / 待办拖拽排序 | v0.11.0 | Original didn't mention ordering / 原始需求没提排序 |
| Notification action buttons / 通知操作按钮 | v0.11.0 | Original only said "notifications" / 原始需求只说"通知"，没说通知上的交互 |
| Wheel time picker / 滚轮时间选择器 | v0.12.0 | Original used Material default / 原始需求用 Material 默认 |
| Custom theme color / 主题色自定义 | v0.12.0 | Original had fixed blue / 原始需求固定蓝色 |
| All todos view / 全部待办视图 | v0.12.0 | Original didn't have "all" / 原始需求没提"全部" |
| Changelog popup / 更新日志弹窗 | v0.12.0 | Original didn't mention / 原始需求没提 |
| In-app feedback page / App 内反馈页 | v0.12.0 | Original didn't mention / 原始需求没提 |
| About page update check / 关于页更新检测 | v0.9.6 | Original didn't mention / 原始需求没提 |
| AI preset providers + model detection / AI 预设服务商 + 探测模型 | v0.9.6 | Original only said "AI API config" / 原始需求只说"AI API 配置" |
| Default tab selection / 默认标签页选择 | v0.9.0 | Original didn't mention / 原始需求没提 |
| Tag edit/rename / 标签编辑/重命名 | v0.15.0 | Original only had "create/delete" / 原始需求只有"创建/删除" |
| Now indicator line / Now 指示线 | v0.14.0 | Original didn't mention / 原始需求没提 |
| View mode persistence / 视图模式持久化 | v0.14.0 | Original didn't mention / 原始需求没提 |
| CalDAV delete sync / CalDAV 删除同步 | v0.14.0 | Original only said "two-way sync" / 原始需求只说"双向同步"没提删除传播 |
| App foreground auto-sync / App 回前台自动同步 | v0.14.0 | Original only said "background periodic sync" / 原始需求只说"背景定时同步" |
| Network recovery auto-sync / 网络恢复自动同步 | v0.14.0 | Original didn't mention / 原始需求没提 |
| Password security migration / 密码安全迁移 | v0.15.0 | Original only said "store in secure storage" / 原始需求只说"存入 secure storage"没提迁移 |

---

## 一、Current Features / 当前功能清单

### Calendar / 日历
- Day/week/month view switching (self-built, not third-party) / 日/周/月视图切换（自建）
- Event CRUD (title, date/time, all-day, description, location) / 事件 CRUD
- Recurring events (RRULE + rrule_generator UI) / 重复事件
- Event drag (LongPressDraggable, recurring disabled) / 事件拖拽
- Multi-day event cross-day display / 多日事件跨天显示
- Now red indicator line (week/day views) / Now 红色指示线（周/日视图）
- Tap empty area to create event (with highlight feedback) / 点击空白区域创建事件
- View mode persistence / 视图模式持久化
- Calendar header date picker + "Back to today" / 日历头部日期选择器 + "回到今天"
- Day/week/month anchor date consistency / 日/周/日视图锚点日期一致性

### Todos / 待办
- Todo CRUD (title, due date, priority, description) / 待办 CRUD
- Completion tracking (mark done, strikethrough) / 完成追踪
- Priority high/medium/low (iCalendar 1/5/9) / 优先级高/中/低
- Recurring todos (RRULE) / 重复待办
- Due date labels (overdue, today, tomorrow, day after, next week, custom) / 截止日期标签
- Todo trash bin (soft delete + restore + permanent delete) / 待办回收站
- Drag-and-drop reordering / 拖拽排序
- All todos view / 全部待办视图
- Multi-day todo date range label / 多天待办日期范围标签
- New todo default date = today / 新建待办默认日期 = 今天
- Tag filter chips / 标签 filter chips

### Search / 搜索
- Full-text search events and todos / 全文搜索事件和待办
- Combined search results / 搜索结果合并显示
- Tap to jump to edit page / 点击跳转编辑页

### CalDAV Sync / CalDAV 同步 — Removed in v0.21.0 / 已于 v0.21.0 移除
> Replaced by the planned self-hosted sync backend (P2: `dayspark_contracts` + push/pull/SSE). History below is archival. / 由 P2 自托管同步后端替代，以下为历史存档。
- Multi-account management (add/delete) / 多账户管理
- Calendar list discovery (PROPFIND) / 日历列表发现
- Full sync + incremental sync (sync-token / ctag) / 全量同步 + 增量同步
- VEVENT + VTODO sync / VEVENT + VTODO 同步
- Two-way sync + ETag conflict detection (server priority) / 双向同步 + ETag 冲突检测
- Offline sync queue / 离线同步队列
- Delete sync (local soft delete + push remote + remote delete detection) / 删除同步
- Background periodic sync (workmanager 15 min) / 后台定时同步
- App foreground auto-sync (>5 min triggers incremental) / App 回前台自动同步
- Network recovery auto-sync / 网络恢复自动同步
- Credential secure storage (FlutterSecureStorage) + password migration / 凭证安全存储 + 密码迁移
- Enforce HTTPS / 强制 HTTPS

### Notifications & Reminders / 通知与提醒
- Local scheduled notifications (flutter_local_notifications) / 本地定时通知
- Notification action buttons (Mark Done / Snooze 1h) / 通知操作按钮
- System alarm (alarm plugin, optional toggle) / 系统闹钟（可选开关）
- Home widget (Android home_widget + iOS WidgetKit) / 桌面小组件
- ⚠️ Windows notifications temporarily disabled (pure-Dart stub to bypass gen_snapshot AOT crash) / Windows 通知暂时禁用

### AI
- AI config (API Key / Base URL / Model) / AI 配置
- Preset providers (OpenAI / Claude / DeepSeek / Gemini) + auto-detect models / 预设服务商 + 自动探测模型
- Natural language parsing for event/todo creation / 自然语言解析创建事件/待办
- AI chat interface (streaming) / AI 聊天界面（流式对话）
- Create events/todos from chat (action buttons) / 聊天中创建事件/待办
- AI auto-scheduling (analyze free time → recommend) / AI 自动排程
- AI task decomposition / AI 任务分解

### MCP Server — Client-side removed in v0.21.0 / 客户端 MCP 已于 v0.21.0 移除
> Rebuilt in P3 as server-side MCP (17 tools + OAuth 2.1 + stdio wrapper). History below is archival. / P3 以服务端 MCP 重建（17 工具 + OAuth 2.1 + stdio 桥），以下为历史存档。
- mcp_dart v2.1.1 + StreamableMcpServer (archived / 历史)
- 6 tools (list_events, list_todos, create_event, create_todo, complete_todo, search) (archived / 历史)
- 2 resources (today events, pending todos) (archived / 历史)
- LAN access (0.0.0.0) (archived / 历史)

### UI/UX
- Material 3 + CupertinoIcons (iOS style) / Material 3 + CupertinoIcons（iOS 风格）
- Dark mode + System/Light/Dark switch / 深色模式 + 切换
- Custom theme color (10 presets) / 主题色自定义（10 预设色）
- Wheel time picker / 滚轮时间选择器
- Progressive disclosure settings (ExpansionTile + feature flags) / 渐进式披露设置
- Advanced feature tutorial links / 高级功能教程链接
- Changelog popup (auto on version upgrade) / 更新日志弹窗
- In-app feedback page / App 内反馈页
- About page + update check / 关于页 + 更新检测
- WCAG AA dark contrast / WCAG AA 暗色对比度
- 48x48 min touch targets (core areas fixed) / 48x48 最小触摸目标
- Minimal shadows (BoxShadow → border) / 最小阴影（BoxShadow → border）

### Security / 安全
- Credential SecureStorage (AI API key) / 凭证 SecureStorage（AI API key）
- ~~Biometric lock (Face ID / Touch ID) / 生物识别锁~~ — removed; `local_auth` no longer a dependency / 已移除
- ~~Enforce HTTPS / 强制 HTTPS~~ — CalDAV-era Dio interceptor removed with sync layer / 随 CalDAV 同步层移除
- ~~Password migration from DB plaintext to SecureStorage / 密码从 DB 明文迁移~~ — accounts table dropped in schema v8 / accounts 表已随 schema v8 移除

### Data / 数据
- 8 Drift tables + reactive queries (schema v8) / 8 张 Drift 表 + 响应式查询（schema v8）
- ICS export + import / ICS 导出 + 导入
- DB export + import / DB 导出 + 导入
- Tag system (name + color, CRUD + many-to-many) / 标签系统
- Attachment support / 附件支持

### i18n
- Chinese + English (107+ keys) / 中文 + 英文（107+ key）
- ARB file management / ARB 文件管理
- Date/time format follows system locale (partial) / 日期/时间格式跟随系统 Locale（部分）

---

## 二、Pending Items / 待完成项

### P0 — Must Do Before Release / 发布前必须做

| # | Feature / 功能 | Note / 说明 | Status / 状态 |
|---|------|------|------|
| 1 | ~~**Windows release build fix / Windows release 构建修复**~~ | `gen_snapshot` crashes on `NativeLaunchDetails` — fixed by replacing with pure-Dart stub | ✅ 已修复 (v0.20.5) |
| 2 | ~~**DB migration support / 数据库迁移支持**~~ | Drift schema snapshots + `build.yaml` + migration test (v1→v7 数据完整性验证全通过) | ✅ 已完成 (2026-05-16) |
| 3 | ~~**CI/CD cleanup / CI/CD 清理**~~ | `release.yml` 移除 `--verbose` 诊断标记（Windows AOT 排查用，问题已修） | ✅ 已修复 (2026-05-16) |
| 4 | ~~**Remove signing keys from repo / 签名密钥移出仓库**~~ | `key.properties` + `release-keystore.jks` removed from git, injected via GitHub Secrets | ✅ 已修复 (2026-05-17) |

### P1 — Should Do / 应该做

| # | Feature / 功能 | Note / 说明 |
|---|------|------|
| 4 | Date/time format follows system locale / 日期/时间格式跟随系统 Locale | DateFormat with locale parameter / DateFormat 用 locale 参数 |
| 5 | macOS/Windows desktop widgets / macOS/Windows 桌面小组件 | Requires native platform development / 需原生平台开发 |
| 6 | Cloud backup (optional) / 云备份（可选） | Users may need cross-device restore / 用户可能需要跨设备恢复 |
| 7 | ~~Integration tests (CalDAV end-to-end) / 集成测试~~ | CalDAV removed in v0.21.0 → superseded by P2 dual-device sync matrix / CalDAV 已移除，由 P2 双设备同步矩阵替代 |
| 8 | Real device build verification / 各平台真机构建验证 | At least Android + iOS / 至少 Android + iOS 真机跑一遍 |
| 9 | Animation standardization / 动画规范化 | State switches use AnimatedSwitcher 0.2s ease / 状态切换统一 AnimatedSwitcher |

### P1 — 待修缺陷（阻断，2026-09-26 发现）

| # | Item / 项 | Note / 说明 |
|---|------|------|
| 1 | **Web 端白屏 — v0.25.0 已发布产物在浏览器里不可用** | 根因已定位（1 级）：`main.dart:52 await AlarmService.init()` 缺 `kIsWeb` 守卫 → `alarm_service.dart:10` 的 `Platform.isAndroid/isIOS` 在 dart2js 产物里是**一调用就抛**的 stub → `main()` 在 `runApp` 之前中断 → 白屏。**最小修复≈一行**（`if (kIsWeb) return;` + `foundation.dart` import，影响面为零）；同批建议补 `notification_service.dart:116`、`notifications_section.dart:37/53` 的同类守卫；并加 CI「web 冒烟截图非纯白」断言。证据链/防复发见 `DECISIONS.md` 事故条目与 `CONSTRAINTS.md` Web 章节 | [Bug / 缺陷] 会话发现，未修 |

### P3 — 同步 / 派生态遗留（2026-09-24 债务2 收尾登记）

| # | Item / 项 | Note / 说明 |
|---|------|------|
| 1 | **`reminders.triggerTime` 是"派生态存进了表"** | 行内时刻只是重排器算出的派生结果，却是所有写入路径必须携带的"写前旧值"之源（`previousReference` 之所以必须存在，正是因为它）。改存 `offsetMinutes`（相对父行参考时刻的偏移）可让全部写入路径无需带旧值、也让跨进程写天然可重算；与 D1（载荷 schema 版本化）一并收敛。 / Derived state stored in a table; storing `offsetMinutes` removes the need for every writer to carry the pre-write value. Converge with D1. |
| 2 | **P2.5 #2：ICS 接 outbox + `syncId` 回填** | `ics_service.dart` 仍裸 `insert`（派生态义务已由债务2 覆盖：导入包一次 `RecordScope.run` + 每成功行一条 `applied`，见 `docs/CONSTRAINTS.md`）；导入行 `sync_id` 为 NULL、首次编辑前不推送。 / Imported rows stay out of the outbox until first edited. |
| 3 | **CLI 跨进程写（`bin/dayspark.dart`）接入缝** | 直开同一库文件，进程内钩子结构上盖不住 → 现靠冷启动/恢复前台全量重算兜底（`SPEC.md` §5 规则 9）。接入方式（IPC / 写后信号 / 单一写进程）未定。 / Cross-process writes converge by recompute only. |
| 4 | **逃生门 / 留档件清理** | `scheduleReminderProvider`（零调用者，T2 保留一个版本的逃生门）与 `ReminderWriter.referenceChanged` + R1a/R1b/R1c（零调用者，T4 applier 改用 `applyRemote` 自带登记）在下一次通知相关改动时一并删除或重新接线。 / Two zero-caller escape hatches from debt 2, kept one version by design — clean up or re-wire in the next notification change. |
| 5 | ~~**事件软删是否连带删提醒行（产品决策待定；本地/远端两侧现状不一致）**~~ — **✅ 已决策并实施（2026-09-25，债务2 收尾）**：**统一为"保留"**——与待办侧对称，用户从回收站恢复事件时提醒要能重新生效。 **实施点**：`EventWriter.softDelete`（`lib/domain/records/writers/event_writer.dart`）去掉 `db.delete(db.reminders)…go()`，父行只置 `deletedAt`、提醒行**保留**为惰性；登记由 `removed` + `reminderIds` 改回 **`applied`**（`previousReference` = 写前 `startDt`）——`removed` 的语义是"记录已不存在"，而行仍在回收站里，故改由重排器读父行 `deletedAt != null` 走 **`inactive` 档**撤 OS 通知；`restore` 本就走 `applied`，行保留后同一批 id 按行内 `triggerTime`（Δ=0，绝对时刻不变）被重新排上。 **硬删路径不变**：`hardDeleteEventWithChildren` / `emptyEventTrash` 仍**硬删**提醒行（并发 `removed` + `reminderIds`）——永久删除后留下惰性行就是垃圾。 **残留（本次有意不动，已披露）**：远端 tombstone（`applyRemoteTombstone`）仍登记 `removed` + `reminderIds`。两侧现在都**保留行**、用户可见行为一致（都撤通知、恢复都能重挂），差别只剩登记格——远端删除不是用户在本机做过的动作、也不知本机有哪些行；改它要动 T4 已钉死的断言面（`applier_test.dart:288` 等），超出本次范围。 **断言侧据实**：**改**（非"补"）`test/domain/providers/events_provider_test.dart:215-216` 的 `expect(reminders, isEmpty)` → `expect(reminders.map((r) => r.id), [reminderId])`——该断言钉的正是被本次决策推翻的旧行为（软删连带硬删行）；同测试另外两条断言（`cancel(reminderId)` 恰好 1 次、`event.deletedAt` 非空）不变且仍绿。 **新增测试**：`record_write_seam_test.dart` S14（行仍在 + 登记 `applied` + inactive 档撤通知）/ S15（恢复 → 同一 id 按行内绝对时刻重排，本次要修的用户可见行为）；`events_dao_test.dart` 新增一条钉住 `emptyEventTrash` 连带硬删行（此前**零覆盖**：去掉该行删除，全量 315 条仍全绿）。 / **已采纳**：两侧语义一致、回收站恢复能重挂提醒（更可恢复、更少意外）；代价 = 惰性行留在库里直到清空回收站。"远端删除 → 通知不响"不受影响（仍由 `removed` 撤）。 | ✅ 已完成 (2026-09-25) |
| 6 | **Linux bundle 主程序名仍是旧名 `calendar_todo_app`** | 桌面 id 已在 P4 改为 `com.dayspark.app.dayspark`，但 `linux/CMakeLists.txt` 的 `BINARY_NAME` 未同步 → 从终端启动要敲 `./calendar_todo_app`，与产品名不符（观感问题，不影响功能）。改名需同步改桌面文件与打包脚本 | [Cosmetic / 观感] v0.25.0 产物验收发现 |
| 7 | **macOS 发行包带 `com.apple.security.get-task-allow`** | v0.25.0 产物验收发现：adhoc 签名的 DMG 里该 entitlement 仍在（允许调试器 attach）。属**既有状态**（历次 release 同）且不阻断使用，但发行包带调试授权是硬化缺口 → 若要收紧需在 release 配置里去除（注意别踩 `keychain-access-groups` 那类 taskgate 坑） | [Security / 安全] v0.25.0 产物验收发现 |
| 8 | **`release.yml` 的 `generate_release_notes: true` 实为空转** | v0.25.0 发版时该 flag 产出的 body 是**空的**（0 行），实际靠人工 notes 填充 → 要么去掉该 flag，要么查明为何未生成（上一个是 prerelease，GitHub 的自动生成可能因此无基线） | [Engineering / 工程] v0.25.0 发版时发现 |

### P2 — Nice to Have / 锦上添花

| # | Feature / 功能 | Note / 说明 |
|---|------|------|
| 10 | Community translation framework / 社区翻译框架 | Open-source community i18n contributions / 开源后社区可贡献 i18n |
| 11 | User docs + self-host guide (Radicale) / 用户文档 + 自部署指南 | docs/ |
| 12 | GitHub open-source release / GitHub 开源发布 | Public repo + README / 公开仓库 + README |
| 13 | Platform release packages / 各平台发布包 | APK / .app / Web |
| 14 | HarmonyOS adaptation / 鸿蒙适配 | Flutter-OH or ArkTS |

### Phase Plan (v0.21.0 onward) / 阶段规划（详见 SPEC.md P1–P4 矩阵）

| Phase | Scope / 范围 | Status / 状态 |
|------|------|------|
| P1 — Foundation / 基础 | kalender views, CalDAV/MCP removal (schema v8), notification chain, widget data path, governance docs | ✅ 完成 (v0.21.0) |
| P2 — Sync backend / 同步后端 | `dayspark_contracts`, shelf server (auth/JWT, push/pull/SSE, LWW/idempotency/tombstone), client outbox + pull applier, Docker on NAS, dual-device e2e / 自托管同步后端 + 客户端 outbox | ✅ 完成 (v0.22.0)；遗留项见 Phase P2.5 / leftovers in Phase P2.5 |
| P3 — Server MCP + CLI / 服务端 MCP | 17 tools + 3 resources + OAuth 2.1 two-track (DCR + PKCE), `tool/mcp_stdio_wrapper`, `tool/dayspark_cli`, MCP e2e matrix + 4-client QA doc / 服务端 MCP + CLI | ✅ 完成 (v0.23.0)；工具面随 P2.5 实体同步扩展（calendars/tags/reminders 待补）/ tool surface grows with P2.5 entity sync |
| P4 — Platform parity / 平台补齐 | iOS bundle/App Group family + widget v2 (3 variants, quick-add, month dots, l10n/dark), notification sweep (time-sensitive), todo UX batch (six-things, solar terms, hide-completed, settings IA), Windows stub revisit / 平台补齐与待办体验批 | ✅ 完成 (v0.24.0)；跟进 / follow-ups: TestFlight provisioning（time-sensitive keep/remove）、2027 lunar 调休数据、Windows 通知 stub 上游 |

### Phase P2.5 — Sync Leftovers / 同步遗留项（P2.5）

> Deferred out of P2 (review-disclosed). / P2 范围外的评审披露遗留项。

| # | Item / 项 | Note / 说明 |
|---|------|------|
| 1 | ~~**Re-wire local reminders on remote schedule edits / 远端改期必须重挂本地提醒**~~ — ✅ **交付于 v0.25.0（债务2 T4）**：引擎的 push/pull 两处事务改经 `RecordScope.run`，`SyncApplier.apply(record, tx)` 的六个写点全部走 `writers/` 并登记 `applied(previousReference: 写前 startDt/dueDate)`（tombstone 登记 `removed` + reminderIds）；`ReminderReconciler` 订阅领域事件后按 Δ 重排并物化回写 `triggerTime`，由 OS 侧重挂。同一路径顺带覆盖 pull / push conflict / piggyback 三条落地分支与 MCP·AI 远端写入。 / ~~**pull/piggyback 应用的事件时间或待办到期变更必须重新接线本地提醒**~~ — ✅ v0.25.0 交付：同步 applier 接入记录缝，四种落地分支统一重排，远端改期/删除都会立刻反映到本机闹钟 | ✅ 已关单 (v0.25.0) |
| 2 | **ICS import bypasses outbox / ICS 导入绕过出站队列** — `ics_service.dart` still raw-`insert`s; imported rows have NULL `sync_id` and don't push until first edited. / `ics_service.dart` 仍裸 `insert`，导入行 `sync_id` 为 NULL，首次编辑前不推送 | Enqueue exit is provider-bound; import path deferred / 入队出口绑定在 provider，导入路径遗留 |
| 3 | **`calendarId` multi-calendar heuristic / `calendarId` 多日历启发式** — calendars don't sync in P2; unknown `calendar_id` falls back to the first local calendar, so calendar attribution may drift across devices. / 日历 P2 不同步；未知 `calendar_id` 回退首个本地日历，跨设备日历归属可能漂移 | Needs calendar sync or a calendar map / 需日历同步或映射表 |
| 4 | **`parentSyncId` late re-link / `parentSyncId` 迟到回链** — if the parent row isn't on the device at apply time the child stays top-level; the parent arriving later does **not** re-link. / 应用时父行不在本机则子行置顶层，父行之后到达**不会**回链 | Candidate: re-link by `parentSyncId` later / 候选：按 `parentSyncId` 回链 |
| 5 | Tag / reminder / attachment payloads not applied / tag、提醒、附件载荷不同步 | P2 applier covers event + todo only / P2 应用器只覆盖 event+todo |

---

## 五、Engineering Recommendations / 工程师建议

### 1. DB migration before real users / 数据库迁移要在有用户之前做好
DB schema v8, every table change modifies schemaVersion + rebuilds. Once real users exist, migrations are required. / DB schema 现在是 v8，每次改表都是直接改 schemaVersion + 重建。一旦有真实用户，改表就必须走 migration。

### 2. Do a full end-to-end test on real devices / 做一次真机端到端测试
Emulator/desktop differs significantly from real devices. / 在模拟器/桌面上测和真机差异很大。

### 3. CI/CD is now functional / CI/CD 已经可用
- CI（ci.yml）全平台已改为 `--release` 构建，release-only bug 在 CI 阶段即暴露 / CI now builds all platforms in release mode, catching release-only bugs early
- Release（release.yml）默认为 Draft，人工验收后再 Publish / Releases are draft by default, requiring manual review before publishing
- Keep maintaining. / 持续维护即可。

### 4. Next version scope / 下一版本范围建议
Suggest focusing on P0 #2 (DB migration) + P1 items. / 建议做 P0 #2（DB 迁移）+ P1 项。

---

## Project Stats / 项目统计

| Metric / 指标 | Value / 数值 |
|------|------|
| Source files (lib/) / 源代码文件 | ~75 |
| Test files (test/) / 测试文件 | ~30 |
| Test cases (app / server / contracts / wrapper / CLI) / 测试用例（app/server/contracts/wrapper/CLI） | 316 / 195 / 37 / 9 / 20 (all passing / 全通过) + Kotlin 7 |
| Analysis issues / 分析问题 | 0 (root + server + contracts + wrapper + CLI) |
| i18n keys / i18n key | 264 |
| Dependencies / 依赖包 | 25+ |
| Built platforms / 已构建平台 | 5 (Web, macOS, Linux, Android, Windows) — all release builds passing |
| Version / 版本 | v0.25.0+25 |
