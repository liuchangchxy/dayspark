# DaySpark User Feedback Log / 用户反馈记录

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
