---
name: dayspark-code-review
description: 对 DaySpark 代码进行领域特定审查 — 检查 CONSTRAINTS.md 硬约束、历史 bug 回归、Flutter 反模式、l10n 完整性、平台兼容性。改日历/DB/Provider/通知/同步相关代码时必须加载此 skill。
compatibility: opencode
---

# DaySpark Code Review / 代码审查

## 使用方法

修改任何文件后，在 review 阶段加载本 skill，按以下章节逐项检查。
标记为 **BLOCKER** 的项目必须修复才能合并；**WARNING** 建议修复；**SUGGESTION** 可选。

审查时源文件对照 `docs/CONSTRAINTS.md` 和 `docs/changelog.md`。

---

## A. Database / 数据库

- [ ] **A1 [BLOCKER] Schema 变更走 migration，不重建**
  改了 Drift 表定义 → 必须提升 `schemaVersion` + 写 `MigrationStrategy`。
  禁止直接改 schemaVersion 让 Drift 重建表（会丢用户数据）。
  *(CONSTRAINTS.md: DB migration 是 P0 pending item)*

- [ ] **A2 [BLOCKER] `emptyTrash` 级联删除子表**
  删 todos 前必须先删 `todo_tags`、`attachments`、`reminders`。
  *(CONSTRAINTS.md Database)*

- [ ] **A3 [BLOCKER] ICS import 用 `insert` 不用 `insertOnConflictUpdate`**
  `ics_service.dart` 里用 `insert(companion)` 直接插入。
  不能用 `insertOnConflictUpdate(Event(id: -1, ...))`。
  *(CONSTRAINTS.md Database)*

- [ ] **A4 [BLOCKER] subtask `parentId` 不加外键约束**
  `todos.parentId` 定义为 `integer().nullable()()`，不设置 `REFERENCES todos(id)`。
  *(CONSTRAINTS.md Database (continued))*

- [ ] **A5 [WARNING] `build_runner` 跑了吗？**
  改了 Drift table/DAO 或 json_serializable 注解 → 必须跑 `dart run build_runner build --delete-conflicting-outputs`。

- [ ] **A6 [WARNING] DB 字段默认值符合预期**
  新增列要考虑 nullable 和默认值，避免破坏已有查询。

---

## B. Calendar / 日历

- [ ] **B1 [BLOCKER] PageView 页面范围不能缩小**
  Day: `_totalDays = 20000`, Week: `_totalWeeks = 4000`, Month: `_totalMonths = 800`。
  当前日期 day index ≈ 19619，改小会 clamp 到 ~2004 年。
  *(CONSTRAINTS.md Calendar / PageView 范围)*

- [ ] **B2 [BLOCKER] `_calendarRange` 必须是静态的**
  返回固定的 `DateTime(2000,1,1)` 到 `DateTime(2030,12,31)`，不能跟 `_calendarAnchor` 联动。
  动态 range 会改变 provider key → 重建 CalendarSection → 丢失滑动状态。
  *(CONSTRAINTS.md Calendar / _calendarRange)*

- [ ] **B3 [BLOCKER] `_isAnimating` 防循环反馈**
  week/day/month 视图 `onPageChanged` 里检查 `if (!_isAnimating)`。
  `didUpdateWidget` 里 `animateToPage` 前后设置 true/false。
  否则形成 `onPageChanged → setState → didUpdateWidget → animateToPage → onPageChanged` 循环。
  *(CONSTRAINTS.md Calendar / _isAnimating)*

- [ ] **B4 [BLOCKER] 每个 PageView 页面需要独立 ScrollController**
  用单独的 `StatefulWidget`（`_DayScrollablePage` / `_ScrollablePage`）持有各自的 `ScrollController`。
  *(CONSTRAINTS.md Calendar / 独立 ScrollController)*

- [ ] **B5 [BLOCKER] 月导航日期必须规范化**
  `_navigateForward` month case 用 `DateTime(year, month+1, 1)`，day 固定为 1。
  如果 anchorDate.day = 31，`DateTime(year, month+1, 31)` 会跳月。
  *(CONSTRAINTS.md Calendar / 月导航)*

- [ ] **B6 [BLOCKER] `CalendaEventAdapter ==` 必须包含所有字段**
  equality 和 hashCode 必须覆盖全部字段（目前 12 个）。漏字段会导致 widget diffing 不更新。
  *(CONSTRAINTS.md Calendar / CalendaEventAdapter)*

- [ ] **B7 [WARNING] 多日事件跨天显示**
  月/周/日视图中的多日事件不能只在第一天显示。检查 date filter：用 `!end.isBefore(date)` 而非 `date.isBefore(end)`。
  *(v0.20.0 bug #5, v0.14.0 feature)*

- [ ] **B8 [WARNING] 日期格子用 InkWell 提供触摸反馈**
  月视图 `_buildDayCell` 用 `Material` + `InkWell` 替代 `GestureDetector`。
  全应用 GestureDetector → InkWell 批量替换。
  *(CONSTRAINTS.md UI, v0.20.1 #14 #18 #36)*

---

## C. Notifications & Alarms / 通知与闹钟

- [ ] **C1 [BLOCKER] Alarm ID 用偏移量避免冲突**
  Event alarm: id + 500000。Todo alarm: id + 600000。
  同一个 todo/event 的 notification 和 alarm ID 不能冲突。
  *(CONSTRAINTS.md Notifications)*

- [ ] **C2 [WARNING] 系统闹钟开关要平台门控**
  非 Android/iOS 平台隐藏 "Use system alarm" 开关。Linux 用 fallback。
  *(v0.20.0 bug #1 #2)*

- [ ] **C3 [SUGGESTION] 通知权限请求**
  检查是否有运行时通知权限请求（Android 13+ POST_NOTIFICATIONS，iOS 首次弹窗）。

---

## D. Platform Compatibility / 平台兼容

- [ ] **D1 [BLOCKER] 禁止 `dart:io Platform` 导入**
  Web 构建会 crash。用 `defaultTargetPlatform` 从 `flutter/foundation.dart` 替代。
  如果是条件导入，用 `export` + `_native.dart` / `_web.dart` 模式。
  *(v0.20.1 #11)*

- [ ] **D2 [WARNING] 平台自适应滚动动效**
  iOS/macOS 用 `BouncingScrollPhysics`，其他平台用 `ClampingScrollPhysics`。
  用已封装的 `AppScrollBehavior`。
  *(v0.20.1 #5)*

- [ ] **D3 [WARNING] 桌面端鼠标交互**
  - 可交互元素加 `MouseRegion(cursor: SystemMouseCursors.click)`
  - 桌面端用 `Draggable` 而非 `LongPressDraggable`（已封装的 `_buildDraggableEvent` 或 `_buildPlatformDraggable` 工具）
  - 聊天气泡最大宽度 `min(screen*0.75, 600)`
  *(v0.20.1 #7 #8 #10)*

- [ ] **D4 [WARNING] Web 构建验证**
  涉及 dart:io、dart:html、插件调用 → 必须确认 web 构建通过。
  至少跑 `flutter build web --debug` 验证。

- [ ] **D5 [BLOCKER] Linux 构建基线**
  Linux CI `runs-on: ubuntu-22.04`。新增原生依赖后跑 `tool/check_glibc_version.sh`。
  *(CONSTRAINTS.md Linux Distribution)*

---

## E. Security / 安全

- [ ] **E1 [BLOCKER] 密码只存 FlutterSecureStorage，不回退数据库**
  `storage.read()` 返回 null → 跳过该账户，不用 `?? account.password`。
  *(CONSTRAINTS.md Security)*

- [ ] **E2 [BLOCKER] 密钥文件禁止提交到 Git**
  `key.properties`、`*.jks` 必须在 `.gitignore` 中。
  *(CONSTRAINTS.md Security)*

- [ ] **E3 [BLOCKER] 同步层禁止空 catch 块**
  `sync_service.dart` 中所有 `catch` 必须至少 `debugPrint`。禁止 `catch (_) {}`。
  *(CONSTRAINTS.md Security)*

- [ ] **E4 [BLOCKER] Provider 解析外部输入用 `tryParse` + fallback**
  `eventsInDateRangeProvider` 等 family provider 解析 key 用 `int.tryParse`，失败返回空数据不抛异常。
  *(CONSTRAINTS.md Security)*

- [ ] **E5 [WARNING] Release 构建启用 R8**
  `build.gradle.kts` 必须有 `isMinifyEnabled = true`、`isShrinkResources = true`。
  *(CONSTRAINTS.md Security)*

- [ ] **E6 [WARNING] 颜色解析安全**
  使用 `ColorUtils.parseHex` 时必须验证输入长度 + `tryParse`，无效 hex 回退默认蓝色。
  *(v0.19.0 bug)*

---

## F. UI / UX

- [ ] **F1 [BLOCKER] 触摸目标 ≥ 48x48**
  所有可交互元素（IconButton、chip、日期格子、颜色圈等）触摸尺寸 ≥ 48px。
  移除 `visualDensity.compact` 和 `minimumSize: Size.zero`。
  *(v0.20.1 #14 #15 #16 #17)*

- [ ] **F2 [WARNING] 无障碍语义标签**
  所有交互元素加 `Semantics(button:, label:, hint:)`。
  装饰性图标（空状态图、标签色点）加 `ExcludeSemantics`。
  *(v0.20.1 #1 #2 #3 #4)*

- [ ] **F3 [BLOCKER] `build()` 方法不能有副作用**
  - 不能在 `build()` 里启动监听器、调 provider、启动 Timer
  - 用 `initState()` + `ref.listenManual()` 或 `_loaded` 守卫标志
  - `FutureBuilder` 的 future 必须缓存（静态字段或 state 变量）
  *(v0.20.1 #34 #35 #37)*

- [ ] **F4 [BLOCKER] 不存在嵌套手势冲突**
  `GestureDetector` 不能嵌套在 `InkWell` 内部。用内部 InkWell 替代外层 GestureDetector。
  *(v0.20.1 #36)*

- [ ] **F5 [WARNING] 圆角一致性**
  全 app 统一 `BorderRadius.circular(6)` 或 `circular(8)`（大圆角如 dialog 用 12 或 16）。
  禁止混合 6、8、12、16。
  *(v0.20.1 #28 #29)*

- [ ] **F6 [WARNING] 暗色模式 WCAG AA**
  暗色 accent 用 `#60A5FA`（而非 `#3B82F6`）。标签颜色浅色 0.4 / 暗色 0.3。
  *(v0.20.1 #30 #31)*

- [ ] **F7 [WARNING] 主题色不能 const 引用运行时值**
  `CircularProgressIndicator(color: Theme.of(context)...)` 不能加 `const`。
  *(CONSTRAINTS.md UI)*

- [ ] **F8 [SUGGESTION] CupertinoIcons 优先于 Icons**
  新代码用 `CupertinoIcons`，不用 `Icons`。
  *(CLAUDE.md UI 原则)*

---

## G. Internationalization (l10n) / 国际化

- [ ] **G1 [BLOCKER] 新增文本必须加 l10n key**
  禁止硬编码 `Text('xxx')`、`SnackBar(content: Text('xxx'))`、`tooltip: 'xxx'`。
  必须添加中英双语 ARB key，然后跑 `flutter gen-l10n`。
  *(CLAUDE.md UI 原则)*

- [ ] **G2 [WARNING] 日期/时间格式不硬编码**
  不用 `'周一' '周二'` 等硬编码星期。用 `DateFormat.E()` 或 `DateFormat('EEEE', locale)`。
  时间格式不强制 24h，跟随系统 locale。CupertinoDatePicker 不传 `use24hFormat`。
  *(v0.20.1 #12, CONSTRAINTS.md Time Picker)*

- [ ] **G3 [WARNING] RRULE 重复文本感知 locale**
  用 `LocaleAwareRRuleTextDelegate`。不用硬编码中文。
  *(v0.20.0 bug #9)*

- [ ] **G4 [WARNING] 数字/占位符 locale 感知**
  月视图 `"+N more"` → `l10n.nMore(count)`。提醒标签 `"min" / "h"` → `l10n.reminderLabel(minutes)`。
  *(v0.20.1 #19 #21)*

- [ ] **G5 [SUGGESTION] 修改 `.arb` 后是否跑 `gen-l10n`？**
  改 `app_en.arb` / `app_zh.arb` 后必须 `flutter gen-l10n`。

---

## H. Performance / 性能

- [ ] **H1 [WARNING] 搜索去抖**
  `search_page.dart` 中搜索输入必须加 300ms debounce（`Timer`）。
  *(v0.20.1 #25)*

- [ ] **H2 [WARNING] 月视图事件过滤缓存**
  月视图 `_buildDayCell` 或类似循环中，事件过滤结果必须缓存（events-by-date map），避免 O(n×42)。
  *(v0.20.1 #26)*

- [ ] **H3 [WARNING] PackageInfo 缓存**
  `PackageInfo.fromPlatform()` 结果缓存为静态字段，不在 build/FutureBuilder 中重复调用。
  *(v0.20.1 #27)*

- [ ] **H4 [SUGGESTION] Provider 避免不必要的重建**
  family provider 的 key 不要频繁变化。watch 粒度足够细。

---

## I. Code Standards / 代码风格

- [ ] **I1 [WARNING] 代码风格一致性**
  Single quotes、trailing commas、explicit return types。
  `debugPrint` not `print`。
  无注释（除非 WHY 非显而易见）、无 docstring、无 emoji。
  *(CLAUDE.md 代码风格)*

- [ ] **I2 [WARNING] User-Agent 版本号动态化**
  HTTP 请求的 User-Agent 从 `PackageInfo.version` 读取，不硬编码。
  *(v0.20.1 #33)*

- [ ] **I3 [WARNING] 删除 sync_tokens 等调试日志**
  检查是否残留了调试用的 debugPrint 或日志，生产代码不应输出过多调试信息。

---

## J. Architecture / 架构

- [ ] **J1 [WARNING] 基础设施服务位置**
  平台插件调用（alarm、notification、home_widget）→ `lib/infrastructure/platform/`。
  网络/socket 服务（mcp_server）→ `lib/infrastructure/mcp/`。
  `domain/services/` 只保留纯领域逻辑。
  *(CONSTRAINTS.md Architecture)*

- [ ] **J2 [WARNING] `file_reader` 在 data 层**
  `lib/data/file_reader.dart` + `_native.dart` + `_web.dart`。不在 `core/utils/`。
  *(CONSTRAINTS.md Architecture)*

- [ ] **J3 [WARNING] URL query param 用 tryParse**
  `app_router.dart` 里 `int.tryParse` 不是 `int.parse`。`state.extra` 用前做类型检查。
  *(CONSTRAINTS.md Routing)*

- [ ] **J4 [WARNING] CLI 数据库路径匹配 Flutter 应用**
  `bin/dayspark.dart` 路径必须与 `com.dayspark.app` 数据目录一致，按平台不同。
  *(CONSTRAINTS.md CLI)*

- [ ] **J5 [WARNING] CLI 复用 Drift DAOs，不手写 SQL**
  `bin/dayspark.dart` 使用 `AppDatabase.forFile()` + `NativeDatabase`，不手写 SQL。
  *(CONSTRAINTS.md CLI)*

---

## K. Regression Watch / 回归警惕

以下是从 changelog 提取的**高复发风险**模式：

- [ ] **K1 新建日程不显示** — date filter 用 `!end.isBefore(date)` 而非 `date.isBefore(end)`
- [ ] **K2 日历视图切换日期跳** — `_anchorDate` 只在用户操作时更新，月视图不更新它
- [ ] **K3 版本号硬编码** — 用 `package_info_plus` 动态读取，不写 `'v0.xx'`
- [ ] **K4 检查更新 403** — 加 User-Agent header + 10s 超时
- [ ] **K5 设置开关卡顿** — Provider 确保从 SharedPreferences 加载初始值
- [ ] **K6 Changelog 已读标记时机** — 用户 dismiss 后才标记已读，不能在 show 之前标记
- [ ] **K7 Linux 日期滚轮** — Linux 上用 Material `showTimePicker` 而非 CupertinoDatePicker
