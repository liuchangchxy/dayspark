# DaySpark 用户反馈记录

## v0.9.8 反馈（12 个问题）

### #1 日历视图切换日期跳转
**问题**: 切换日/周/月视图时日期不一致，标题显示错误月份（两个六月）。
**修复**: 引入 `_anchorDate` 作为唯一锚点，视图切换时传递 `initialDateTime`，统一标题格式。

### #2 周视图/日视图多余周数显示
**问题**: kalender 默认显示 ISO 周数，用户不需要。
**修复**: `weekNumberBuilder` 返回 `SizedBox.shrink()`。

### #3 待办日期滑块逻辑错误
**问题**: 锚定逻辑、箭头行为、选日期交互都有问题。
**修复**: 重写 `date_strip.dart`，只显示当前周 7 天，左右箭头切周。

### #4 日历点击无视觉反馈
**问题**: 点击空白区域创建事件无任何反馈。
**修复**: `_lastTappedDate` + `Timer` 实现点击高亮。

### #5 月视图标题日期格式错误
**问题**: 格式 "7 第三周" 缺少"月"，令人困惑。
**修复**: 改为视图专属头部——日视图 "4月30日 周四"、周视图 "4/27 – 5/3"、月视图 "2026年4月"。

### #6 设置页结构混乱
**问题**: 高级功能开关在底部，AI/CalDAV 需要先开开关才能看到。
**修复**: 重构为 ExpansionTile，AI/CalDAV/MCP 放入"高级功能"折叠区。

### #7 高级功能缺少教程
**问题**: AI、CalDAV、MCP 用户不知道怎么配。
**修复**: 每个高级功能旁添加教程链接，新建 `docs/ai-setup.md`、`docs/mcp-setup.md`。

### #8 MCP 服务器设置位置不合理
**问题**: MCP 和基础设置混在一起。
**修复**: MCP 移入高级功能 ExpansionTile。

### #9 过期待办提示不及时
**问题**: app 一直开着过了午夜不会触发过期待办检查。
**修复**: 改为 one-shot Timer 计算到午夜的精确延迟，递归调度。

### #10 日历头部按钮拥挤
**问题**: 日期选择器点击区域太小。
**修复**: 增大点击区域，颜色统一用 `colorScheme.primary`。

### #11 日历日期跳转（与 #1 同因）
**问题**: `_viewConfig()` 不传 `initialDateTime`。
**修复**: 同 #1。

### #12 日历头部布局不合理
**问题**: 所有按钮挤在一行。
**修复**: 两行布局——第一行日期+选择器+今天按钮，第二行视图切换+导航箭头。

---

## v0.10.0 反馈

### #13 每分钟检测日期变化没逻辑
**问题**: 用 `Timer.periodic(1分钟)` 检测午夜，频率过高且不合理。
**修复**: 改为 one-shot Timer 计算精确到午夜的时间差，触发后递归调度下一次。

### #14 CI 反复因格式化失败
**问题**: 本地 Flutter 版本和 CI 版本 `dart format` 结果不同。
**修复**: 从 CI 移除 `dart format --set-exit-if-changed`。

### #15 CI 分析失败用压制而非修代码
**问题**: 用 `--no-fatal-infos` 压制 26 个 info 级别 lint。
**修复**: 逐一修复所有 26 个 info，达到零 issue。

### #16 版本号跳到 1.0.0
**问题**: 从 0.9 直接跳到 1.0.0。
**修复**: 改为 0.10.0，1.0 之前都是 0.x 递增。

---

## v0.11.0 反馈

### #17 所有 release 应标记为 pre-release
**问题**: v0.9.4~v0.10.0 未标记为 pre-release。
**修复**: `release.yml` 改为 `!startsWith(github.ref_name, 'v1.')`，手动批量修改历史 release。

### #18 用户反馈需归档
**问题**: 反馈散落在对话中，无法翻阅。
**修复**: 创建 `docs/changelog.md` 记录所有反馈。

---

## v0.12.0 反馈（19 个问题）

### #19 日历月→周/日视图日期不准
**问题**: 月视图以中间日期为锚点（如 4.16），切换到周/日视图时日期不对。
**修复**: 月视图不更新 `_anchorDate`，锚点只在用户主动操作（点今天、选日期、周/日滑动）时变化。切换视图时锚点保持当天或用户最后选的日期。

### #20 关于页版本号显示不对，检查更新功能失效
**问题**: 版本号硬编码，检查更新显示"已是最新"但实际不是。
**修复**: 用 `package_info_plus` 动态读取版本号；API 从 `/releases/latest` 改为 `/releases?per_page=1` 包含 pre-release。

### #21 反馈入口应停留在 app 内
**问题**: 反馈直接跳转 GitHub，用户希望 app 内反馈。
**修复**: 新建 `feedback_page.dart`，支持文本输入 + 复制到剪贴板 + 跳转 GitHub Issue。关于页"反馈问题"改为跳转反馈页。

### #22 教程需双语
**问题**: 教程中英混杂。
**状态**: 延期至下一版本

### #23 新建待办默认日期应为今天
**问题**: 新建待办时 dueDate 默认为空。
**修复**: `todo_create_page.dart` 中 `_dueDate` 初始化为 `DateTime(now.year, now.month, now.day)`。

### #24 自定义重复选项
**问题**: rrule 自定义重复规则 UI。
**状态**: 已由 rrule_generator 库提供，无需额外实现

### #25 触摸反馈需要更好的方案
**问题**: 当前高亮方案不够直观。
**修复**: `_lastTappedDate` 机制已在月视图和日视图中实现点击高亮（半透明主色背景），400ms 后自动消除。

### #26 时间选择器应为滚动式
**问题**: 使用 Material TimePicker，应改为滚轮选择器。
**修复**: 新建 `wheel_time_picker.dart`，基于 `CupertinoDatePicker` + 可选键盘输入。事件创建/编辑页已替换。

### #27 全部待办视图
**问题**: 缺少查看所有待办的入口。
**修复**: `todos_dao` 新增 `watchAllNotDeleted()`，新增 `allTodosProvider`。`date_strip` 添加"全部"chip。`home_page` 新增全部待办视图。

### #28 多天待办显示
**问题**: 有开始和截止日期的待办如何显示。
**修复**: 只在截止日期显示，当 `startDate ≠ dueDate` 且间隔 > 1 天时显示日期范围标签（如 "3/1 – 3/5"）。`todo_list_tile` 新增 `startDate` 参数。

### #29 每次更新后显示更改说明
**问题**: 更新后应弹出 changelog。
**修复**: `home_page` 启动时用 `SharedPreferences` 对比版本号，版本变化时弹出"更新内容"对话框。

### #30 MCP 服务器局域网访问
**问题**: MCP 是否支持局域网访问。
**修复**: `mcp_server_service_native.dart` 绑定地址从 `loopbackIPv4` 改为 `anyIPv4`。

### #31 主题色功能
**问题**: 用户希望自定义主题色。
**修复**: `theme_provider` 新增 `themeColorProvider`，`app_theme` 支持可选 `seedColor`。设置页新增颜色选择网格（10 预设色 + 重置）。

### #32 UI 设计需向 iOS/macOS 看齐
**问题**: 前端设计需要提升。
**状态**: 持续改进，已使用 CupertinoIcons、Material 3 圆角

### #33-36 AI Agent 设计
**问题**: AI agent 交互协议、持久化、任务区分、CLI 模式。
**状态**: MCP 已是交互协议，文档化 tools schema。agent 创建 todo 用 uid 前缀 `mcp-` 区分。CLI 模式延期。

### #37 整理整个 workspace
**问题**: 项目文件结构需要整理。
**修复**: `flutter analyze` 零 issue，无死代码、无重复导入。
