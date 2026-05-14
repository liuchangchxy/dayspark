# DaySpark Feature Evolution / 功能演进全景图

> Last updated / 最后更新: v0.19.2 | 2026-05-14
> This is the single living document for the project, replacing the archived REQUIREMENTS.md and PLAN.md.
> 本文档是项目唯一的活文档，替代已归档的 REQUIREMENTS.md 和 PLAN.md。

---

## 一、Feature Timeline / 功能时间线

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

---

## 二、Requirement Changes / 需求变更记录

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

## 三、Current Features / 当前功能清单

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

### CalDAV Sync / CalDAV 同步
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

### AI
- AI config (API Key / Base URL / Model) / AI 配置
- Preset providers (OpenAI / Claude / DeepSeek / Gemini) + auto-detect models / 预设服务商 + 自动探测模型
- Natural language parsing for event/todo creation / 自然语言解析创建事件/待办
- AI chat interface (streaming) / AI 聊天界面（流式对话）
- Create events/todos from chat (action buttons) / 聊天中创建事件/待办
- AI auto-scheduling (analyze free time → recommend) / AI 自动排程
- AI task decomposition / AI 任务分解

### MCP Server
- mcp_dart v2.1.1 + StreamableMcpServer
- 6 tools (list_events, list_todos, create_event, create_todo, complete_todo, search) / 6 个工具
- 2 resources (today events, pending todos) / 2 个资源
- LAN access (0.0.0.0) / 局域网访问

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
- Credential SecureStorage / 凭证 SecureStorage
- Biometric lock (Face ID / Touch ID) / 生物识别锁
- Enforce HTTPS / 强制 HTTPS
- Password migration from DB plaintext to SecureStorage / 密码从 DB 明文迁移到 SecureStorage

### Data / 数据
- 9 Drift tables + reactive queries / 9 张 Drift 表 + 响应式查询
- ICS export + import / ICS 导出 + 导入
- DB export + import / DB 导出 + 导入
- Tag system (name + color, CRUD + many-to-many) / 标签系统
- Attachment support / 附件支持

### i18n
- Chinese + English (107+ keys) / 中文 + 英文（107+ key）
- ARB file management / ARB 文件管理
- Date/time format follows system locale (partial) / 日期/时间格式跟随系统 Locale（部分）

---

## 四、Pending Items / 待完成项

### P0 — Must Do Before Release / 发布前必须做

| # | Feature / 功能 | Note / 说明 | Status / 状态 |
|---|------|------|------|
| 1 | CI/CD fix / CI/CD 修复 | `ci.yml` add `flutter gen-l10n` ✅; `release.yml` remove duplicate test | ✅ ci.yml done / ⏳ release.yml |
| 2 | DB migration support / 数据库迁移支持 | Drift schemaVersion upgrade strategy / Drift schemaVersion 升级策略 | ⏳ |
| 3 | v0.15.0 + v0.16.0 commit + tag | Both versions not committed yet / 两个版本都没提交 | ✅ Done (merged into v0.17.0–v0.19.0) |

### P1 — Should Do / 应该做

| # | Feature / 功能 | Note / 说明 |
|---|------|------|
| 4 | Date/time format follows system locale / 日期/时间格式跟随系统 Locale | DateFormat with locale parameter / DateFormat 用 locale 参数 |
| 5 | macOS/Windows desktop widgets / macOS/Windows 桌面小组件 | Requires native platform development / 需原生平台开发 |
| 6 | Cloud backup (optional) / 云备份（可选） | Users may need cross-device restore / 用户可能需要跨设备恢复 |
| 7 | Integration tests (CalDAV end-to-end) / 集成测试 | Verify full sync flow / 验证完整同步流程 |
| 8 | Real device build verification / 各平台真机构建验证 | At least Android + iOS / 至少 Android + iOS 真机跑一遍 |
| 9 | Animation standardization / 动画规范化 | State switches use AnimatedSwitcher 0.2s ease / 状态切换统一 AnimatedSwitcher |

### P2 — Nice to Have / 锦上添花

| # | Feature / 功能 | Note / 说明 |
|---|------|------|
| 10 | Community translation framework / 社区翻译框架 | Open-source community i18n contributions / 开源后社区可贡献 i18n |
| 11 | User docs + self-host guide (Radicale) / 用户文档 + 自部署指南 | docs/ |
| 12 | GitHub open-source release / GitHub 开源发布 | Public repo + README / 公开仓库 + README |
| 13 | Platform release packages / 各平台发布包 | APK / .app / Web |
| 14 | HarmonyOS adaptation / 鸿蒙适配 | Flutter-OH or ArkTS |

---

## 五、Engineering Recommendations / 工程师建议

### 1. DB migration before real users / 数据库迁移要在有用户之前做好
DB schema v6, every table change modifies schemaVersion + rebuilds. Once real users exist, migrations are required. / DB schema 现在是 v6，每次改表都是直接改 schemaVersion + 重建。一旦有真实用户，改表就必须走 migration。

### 2. Do a full end-to-end test on real devices / 做一次真机端到端测试
Emulator/desktop differs significantly from real devices. / 在模拟器/桌面上测和真机差异很大。

### 3. CI/CD is now functional / CI/CD 已经可用
Release workflow builds all 5 platforms with artifacts. Keep maintaining. / 发版工作流已验证，5 平台构建产物均可用。持续维护即可。

### 4. Next version scope / 下一版本范围建议
Suggest focusing on P0 #2 (DB migration) + P1 items. / 建议做 P0 #2（DB 迁移）+ P1 项。

---

## Project Stats / 项目统计

| Metric / 指标 | Value / 数值 |
|------|------|
| Source files (lib/) / 源代码文件 | ~70 |
| Test files (test/) / 测试文件 | ~25 |
| Test cases / 测试用例 | 83 (all passing / 全通过) |
| Analysis issues / 分析问题 | 0 |
| i18n keys / i18n key | 107+ |
| Dependencies / 依赖包 | 25+ |
| Built platforms / 已构建平台 | 4 (Web, macOS, Android, iOS) |
| Version / 版本 | v0.19.2+17 |
