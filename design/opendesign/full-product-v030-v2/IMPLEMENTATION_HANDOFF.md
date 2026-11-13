# DaySpark 实现交接

**输入版本：** v030-v2 设计
**代码基线：** `origin/main @ 5f48ad563cb1d242106a15aa19b73ab52ee13390`
**本文件不包含实现代码。** 本次只交付设计、原型与规范，没有修改 `lib/`、数据库、Provider 或测试。

---

## 1. 已确认可复用的结构

先不要重写这些，它们的方向是对的：

| 能力 | 位置 |
| --- | --- |
| 工作区壳层 | `lib/ui/shell/workspace_scaffold.dart` |
| 侧栏 | `lib/ui/shell/workspace_sidebar.dart` |
| 宽屏页头 / 内容列 | `lib/ui/shell/workspace_page.dart` |
| 侧栏导航状态 | `lib/ui/shell/workspace_navigation.dart` |
| 宽屏断点 | `kWorkspaceBreakpoint = 1000` |
| 主从断点 | `kMasterDetailBreakpoint = 1180` |
| 选中态 | `workspaceSelectionProvider` + `TodoSelection` / `EventSelection` |
| 路由 | `lib/core/router/app_router.dart` |
| 主题 | `lib/core/theme/app_theme.dart`、`app_typography.dart`、`theme_provider.dart` |
| 日历组件 | `lib/ui/widgets/calendar/*`（已有 deadline lane、allocation tile、hour lines） |
| 小组件 | `android/app/src/main/kotlin/com/dayspark/app/*WidgetProvider.kt` + `res/layout/widget_*` |

**原则：** 在现有结构上重排与换皮，不新造第二套导航或第二套日历。桌面已有主从结构，不需要从零实现。

---

## 2. 实施顺序

### P0 — 低风险、高收益（先做）

1. **主题令牌**
   - 将 `DESIGN.md` 的颜色、间距、圆角、字号落到 `app_theme.dart` / `app_typography.dart`。
   - 深色使用独立色值，不做透明度叠加。
   - 统一 `AppSpacing` 与现有常量，避免新增第二套 4/8 体系。

2. **设置页修复**
   - `color_swatch_grid.dart`：把 `Wrap` 从 `Column` 的无限宽约束中解放，使用固定 6 列网格 / `LayoutBuilder` 计算每行 6 个；每个色点 48dp 触控。
   - `appearance_section.dart`：主题分段改为三列等宽，禁止文字换行；使用 `SegmentedButton` 或自绘三段，选中态必须有背景差。
   - 桌面设置改为左侧分区导航 + 右侧内容（`settings_page.dart` 增加 `isWorkspaceLayout` 分支）。
   - 通用分组补上四个可操作项：语言、启动时打开、周起始日、时间格式。手机用底部选择层，桌面用居中单选对话框；不要用下拉框。
   - 周起始日要进入日历计算（周条、周议程、月历首列、桌面周视图），不能只存值。
   - 时间格式只影响展示；`TimeOfDay` / 时间输入始终保存 24 小时值。12 小时显示宽度按 `2:30 PM` 预留，避免挤压标题。
   - “启动时打开”在下次启动时决定初始路由；设置页里改了只提示，不立即跳转。

3. **今天去重与空状态**
   - `home_page.dart` 手机 AppBar 不再重复“今天”；产品名可保留在极小位置或移除。
   - `action_section.dart`：无安排时渲染“今天没有固定安排”空状态 + 两个动作，不允许只剩“未安排 N 项”。
   - 已完成分组下移并默认折叠。

4. **待办分段与筛选**
   - 手机待办页的分段控件增加明确选中态；未安排/全部是视图，不是 tab。
   - 筛选按钮加文字或数量；截止 chip 改为正常可点的 chip，不使用禁用外观。
   - `todo_list_tile.dart` 行结构按 `DESIGN.md` 4.1 重排。

**验收：** 手机 412×915 下，设置主题色一行 6 个；主题文字不换行；今天空状态有下一步；待办选中态可见。

---

### P1 — 核心页面重排

1. **日历头部合并**
   - `home_page.dart` 的 `_buildPageHeader` 与 `view_switcher.dart`、`calendar_day_header.dart` 合并为一条工具条。
   - 去掉无标签 ISO 周数；范围统一为 `11月9日 – 11月15日`。
   - 移除网格内提示胶囊与重复的“＋日程”。

2. **日历内容**
   - 保留 `calendar_deadline_lane.dart`，移到时间网格上方，作为独立截止带。
   - `event_tile.dart` 与 `task_allocation_tile.dart` 使用不同视觉：日程仅 2px 日历色左边框、背景为日历色 11% 混 surface（无全边框）；计划透明/灰底 + 1px 虚线 + 空心方框。
   - 增加重叠布局：按开始时间聚类，簇内贪心分栏；宽度按簇内列数分配。
   - 当前时间线 2px 暖色，`IgnorePointer`。

3. **快速创建 / 完整表单**
   - `todo_quick_create_sheet.dart`：首屏标题 + 截止 + 计划执行 + 提醒；“更多”放优先级、日历、标签、备注、子任务，并提供“打开完整表单”入口。
   - 保存后留在来源页并显示轻提示；不要强制跳到待办列表。
   - 截止与计划执行使用不同的 picker 与文案；截止无时间时不写 `00:00`。
   - `todo_form_page.dart` / `event_form_page.dart` 按四段重排；保存固定在底部安全区。
   - 修复选择器关闭父弹层的问题（本次原型也复现过，属于通用交互缺陷）。

4. **详情**
   - `todo_detail_page.dart` / `event_detail_page.dart`：统一详情排版；子任务、备注、底部操作。
   - 桌面详情栏宽度从固定 400 改为 `clamp(400, 38vw, 720)`，内容最大 720。

**验收：** 手机日历只有一条工具条；手机周视图为 7 天议程、天视图有截止带（桌面周视图有截止带）；重叠事件并排；详情底部操作不遮挡内容；快速创建只填标题可保存。

---

### P2 — 桌面体验

1. **命令面板**
   - 新增桌面级 `CommandPalette`（`Ctrl/Cmd+K`），复用搜索 provider；空查询显示三个命令。
   - `Shortcuts` / `Actions` 包裹 `WorkspaceScaffold`；输入框内不触发 `N`。

2. **列表快速添加与右键**
   - 桌面待办列表顶部加内联输入，Enter 保存。
   - 右键菜单：完成、安排时间、编辑、移到回收站；使用 `showMenu` 或自定义浮层。

3. **窄窗**
   - 1000px 以下侧栏 64px 图标；隐藏日历/标签列表；设置仍可达。
   - 1180px 以下详情改为覆盖层；保留关闭。

4. **桌面日历**
   - 宽屏周视图 7 列 + 截止带 + 重叠；天视图最大 720；月视图 7×6，最小格高 92 并按窗口高度拉伸。

**验收：** 1440 下主从详情可用；900 下侧栏 64、详情覆盖；⌘K、N、Esc、右键均可用。

---

### P3 — 小组件

当前实现是 **RemoteViews**，继续使用 RemoteViews，不引入 Glance 重写。

| 组件 | 改动 |
| --- | --- |
| Todo | 小：一个焦点；中：今天前三条；大：正在执行/今天截止/未安排三段。移除 medium/large 顶部重复 chips。 |
| Calendar | 新增 2×2 小布局；大：迷你月历 + 当天日程；中：当天日程列表。修改 `calendar_widget_info.xml` 的 minWidth/minHeight 与 targetCell。 |
| Today / 时间轴 | 小：正在进行的一件事；中：接下来三项；大：8:00–20:00 时间轴（`widget_timeline_row` 复用）。 |
| Quick Action | **新增** provider + 3 个 layout + info XML；或先只做 medium/large，small 用单按钮。 |
| 深色 | 统一 `widget_background`、`widget_text_*`、`widget_accent` 与设计令牌；独立深色资源。 |
| 刷新 | 保持 30 分钟系统更新；时间轴不承诺分钟级，按 15 分钟近似。避免常驻前台服务。 |

**验收：** 三尺寸结构不同；小尺寸不出现列表/分组；中尺寸 3–4 条；大尺寸有分组或时间轴；深色可读；点击圆圈能完成待办（PendingIntent）。

---

## 3. 组件映射

| 原型 | Flutter 位置 | 说明 |
| --- | --- | --- |
| 手机顶栏 / 底栏 | `home_page.dart` + `NavigationBar` | 保留三 tab；顶栏去重 |
| 今天分区 | `action_section.dart` | 现在/接下来/今天截止/逾期/完成 |
| 日历工具条 | `home_page.dart` + `view_switcher.dart` | 合并为一条 |
| 截止带 | `calendar_deadline_lane.dart` | 保留，移至网格上方 |
| 日程块 | `event_tile.dart` | 2px 日历色左边框；背景为日历色 11% 混 surface；无全边框 |
| 计划块 | `task_allocation_tile.dart` | 灰底 + 空心方框 |
| 重叠分栏 | 新增布局 helper | 建议放在 `calendar_section.dart` |
| 待办行 | `todo_list_tile.dart` | 48dp 触控区 / 22dp 复选框、元信息 |
| 快速创建 | `todo_quick_create_sheet.dart` | 首屏四字段 |
| 完整表单 | `todo_form_page.dart` | 四段 |
| 日程表单 | `event_form_page.dart` | 标题/时间/日历/地点/备注 |
| 待办详情 | `todo_detail_page.dart` + 右栏 | 子任务、备注、操作 |
| 搜索 | `search_page.dart` | 手机全屏；桌面命令面板 |
| 设置 | `settings_page.dart` + `settings_sections/*` | 桌面双栏 |
| 主题色板 | `color_swatch_grid.dart` | 6 列网格修复 |
| 侧栏 | `workspace_sidebar.dart` | 密度、选中态、窄窗 |
| 主从 | `home_page.dart` + `workspace_navigation.dart` | 宽度弹性化 |
| 小组件 | `android/.../*WidgetProvider.kt` | RemoteViews |

---

## 4. 状态与数据

不要改数据库 schema。现有模型已经能表达：

- `Todo.dueDate` / `dueHasTime`
- `TaskAllocation.start/end`
- `Todo.reminders`、`subtasks`、`tags`、`calendarId`
- `Calendar` / `Tag`
- `WorkspaceSelection`

如果现有 provider 已有派生逻辑，优先复用；不要为了 UI 新造一套“今天列表”。建议派生规则：

```
unplanned = activeTodos.where(t => t.allocation == null)
overdue   = activeTodos.where(t => due != null && due < now && !sameDay(due, now))
todayDue  = dueOn(today).where(t => !plannedTodayIds.contains(t.id))
```

与原型 `assets/store.js` 的 `todayModel()` 保持一致。

### 4.1 需要修复的语义风险

- 不要把“未安排”实现成“没有截止”。
- 不要在日历里把截止渲染成占用时间块。
- 不要在待办 widget 里混入 Event。
- 不要让“计划执行”覆盖或改写 `dueDate`。
- 完成待办后，保留 600ms 视觉停留再移动/隐藏（避免列表跳动）。

---

## 5. 桌面实现细节

- `WorkspaceScaffold` 已经处理 1000px 断点；命令面板应包在这一层，确保设置/搜索页也能用。
- `workspaceSelectionProvider` 已经处理列表选中；详情宽度改为弹性后，仍保持 1180 断点。
- 侧栏底部设置按钮要使用统一的 `_SidebarRow`，不要单独造一个带浏览器默认边框的按钮（本次原型曾出现，已修）。
- 窄窗详情覆盖时，左栏保留 64px；关闭按钮必须在首屏可见。
- 键盘 `Enter` 保存时排除 textarea；`Esc` 只关闭最上层。

---

## 6. 小组件实现细节

- `WidgetSupport.sizeOf` 已有 small/medium/large 判定，沿用。
- RemoteViews 不支持组件内滚动；条目数量固定，超出以“还有 N 项”收口。
- 行高 44–48dp；整行点击，不要只让 18dp 圆圈可点。
- 深色资源不要用 `#000000`；使用设计令牌的深色 surface。
- 锁屏组件不显示具体任务标题（隐私）。
- 刷新：系统 30 分钟 + 数据变更；时间轴不承诺分钟级。
- 新增 Quick Action provider 时，点击只做入口，不在组件内弹输入法。

---

## 7. 测试与验收

### 7.1 必须新增/更新的测试

- Widget/golden：
  - 手机今天：有安排 / 无安排 / 只有逾期。
  - 日历：手机周议程 7 组；桌面周视图重叠事件、截止带、当前时间线；天视图截止带。
  - 待办：未安排 / 全部 / 空。
  - 设置：主题色 6 列、主题三段不换行、深色。
  - 桌面：1440 主从、900 图标栏 + 覆盖详情。
- 交互：
  - 快速创建只填标题保存后留在当前页并出现轻提示；在待办页保存时列表可见。
  - 快速创建 →“更多”→“打开完整表单”，已填字段带入。
  - 同步：未配置校验、登录、同步中、退出；密码不回显。
  - AI：关闭 / 未配置 / 已就绪 / 生成中 / 失败，失败保留输入。
  - 截止选日期不选时间，不显示 `00:00`。
  - 计划执行与截止互不覆盖。
  - 搜索空结果 / 有结果。
  - 回收站恢复。
  - 桌面 ⌘K / N / Esc / 右键。
- 小组件：
  - 三种尺寸布局选择正确。
  - 完成待办的 PendingIntent 更新列表与计数。
  - 深色资源可读。

### 7.2 手工验收

- 412×915：单手完成“新建待办 → 设截止 → 设计划执行 → 保存（回到来源并出现提示）→ 在待办/日历看到 → 完成”。
- 1440×900：⌘K 搜索 → 选中结果 → 详情 → 编辑 → 保存。
- 900×800：侧栏 64、详情覆盖、关闭返回。
- 小组件：三尺寸、深色、空数据、完成一条。

### 7.3 不要做

- 不要修改测试来迎合设计。
- 不要为了通过 golden 而隐藏真实状态。
- 不要用假数据填充空状态。
- 不要把未实现的能力标成完成。

---

## 8. 风险

| 风险 | 说明 | 缓解 |
| --- | --- | --- |
| 日历重叠布局 | 现有 tile 绝对定位，分栏需要改布局层 | 先做簇内分栏 helper，再加 golden |
| 桌面详情宽度 | 固定 400 → 弹性可能影响现有布局 | 1180 断点不变，详情内容加 maxWidth |
| 设置双栏 | 手机仍为单列，桌面新增导航 | 用 `isWorkspaceLayout` 分支，不改手机结构 |
| 小组件尺寸 | Calendar 当前最小 250dp | 新增 small layout + 调整 info XML，需 launcher 验证 |
| 时间轴刷新 | RemoteViews 无法分钟级 | 15 分钟近似，文档写明 |
| 主题色板 | 当前 Wrap 在 Column 中被压成单列 | 用 GridView/Wrap + 固定宽度；加 golden |
| 精确 HEAD 构建 | 本机 NDK 缺失 | 交付前在具备 SDK 的环境补 `flutter build apk` 验证 |

---

## 9. 完成定义（实现阶段）

- P0 + P1 全部落地，手机主流程可走通。
- P2 桌面键盘与窄窗可用。
- P3 至少 Todo / Calendar / Timeline 三尺寸结构正确；Quick Action 可后置。
- 新增 golden 与交互测试通过；没有通过修改测试规避。
- 深色模式全页面可读。
- Android exact-head build 在具备 SDK/NDK 的环境通过，并记录版本。
- 本文件中的 `NOT VERIFIED` 项逐条关闭或明确保留。


---

## 10. 视觉打磨交接（2026-11-10）

本轮只做 Visual Taste / De-slop / Art Direction，不改变已验收的 IA、页面关系、Todo/Event 模型或交互路径。实现时以 `DESIGN.md` 与 `prototype/` 为准，本文件只列工程落点。

### 10.1 令牌落点

- 圆角：`4 / 6 / 8 / 12 / 18`；chip 不再用 999 胶囊，日历事件块 6（手机）/ 4（桌面）。
- 字体：系统 UI 栈；只保留 400 / 500 / 600 三档字重，移除 650 / 700 / 750 / 800。
- 浅色：暖纸 `#f3f3ef`，surface `#fdfdfb`，ink `#1b1b18`，primary `#2d4f7c`，warm `#9c4a2f`。
- 深色：暖黑 `#121310`，surface `#191a17`，primary `#8fb0d9`，warm `#d08a6b`。
- 日历色迁移为低饱和自然色；旧 localStorage 数据在载入时迁移，不需要数据库迁移。
- 阴影只保留 `shadow-1` / `shadow-2` / `shadow-sheet`；主界面无阴影。

### 10.2 手机

- 顶栏 54；今天页不再重复“今天”，主标题由页面正文承担。
- 新建/日程/待办主操作改为“加号 + 文字”的蓝色文本按钮，不再是实心色块。
- 正在进行块去卡片：无圆角、无底色、无左边框；使用暖色标签、20/600 标题、2px 进度线。
- 日期选择改为 30dp 圆形选中；不再整格填蓝。
- 截止带去掉外框与底色；截止卡片用 `surface-2`、6 圆角。
- 列表行去掉行尾无标签日历色点；日历归属移至详情与日历视图。
- 详情元信息 chip 改为无底色文本；底部操作栏固定在拇指区，`sheet-body` 滚动。
- 全高详情 sheet 从屏幕顶部开始（顶部留 `safe-top`），状态栏保持可见，不再被 sheet 盖住。
- 搜索空态说明最大宽度 300，避免孤字换行。
- 深色日历事件背景用 17% 日历色 + 60% 白色混合左边，防止在近黑背景上消失。

### 10.3 桌面

- 侧栏 236；列表 380；今天内容列最大 820；右侧 rail 300；设置内容最大 680。
- 侧栏与设置导航选中改为 `surface-2` + 600，不再使用蓝色底。
- 主栏 54、标题 18/600；工具按钮 32 高。
- 主从选中行改为 `surface-2` + 600；移除 2px 蓝色 inset 边。
- 待办详情空状态：图标 + “选择一条待办” + 一句下一步说明，不再是一行居中提示。
- Today rail 的“安排”动作默认透明，hover / focus-within 显示，键盘仍可达。
- 日历周视图：日列线用 `line`，小时线用 `line-soft`；当前时间线 `z-index: 3`；今天数字 24 圆 primary；截止带改为有底、有列分隔、有暖色圆点的结构化行。
- 月视图最小格高 92，桌面按窗口高度拉伸填满；今天 24 圆；摘要 11px；每格最多 3 行，溢出显示 `+N`。
- 命令面板 12 圆角、1px 边框、`shadow-2`；结果行 6 圆角。
- 侧栏品牌 mark 改为 ink 方块；不再使用 primary 填充。

### 10.4 小组件

- 圆角 18；边框 1px line；只保留 `shadow-1`。
- 头部标签 10.5/600；正文 13/400；元信息 10.5。
- 快捷操作中/大尺寸改为 1px 发丝线分割的操作网格，去掉“卡片套卡片”。
- 日历大尺寸只展示 2 条当天日程，并在组头右侧显示“还有 N 个”；中尺寸仍为 3 条。大尺寸迷你月历用 20dp 圆与更紧行距，保证两条完整显示、不截断。
- 时间轴事件块背景提高到 11% 日历色，深色下左条提亮。
- 迷你月历数字 10.5 / 22dp 圆。

### 10.5 验证

- 渲染：手机 360 / 390 / 412；桌面 900 / 1200 / 1440；小组件 1280。
- 截图：`_evidence/polish/`（含浅色、深色、组件四类）。
- 回归通过：`proto-test`、`qa-journey`、`proto-desktop-test`、`proto-widgets-test`、`full-create-test`、`textsheet-test`、`settings-test`、`desktop-settings-test`、`hit48`。
- `overflow-audit` 的 412 day 报告为日期条与截止带的横向滚动内容，不是页面级溢出；`scrollWidth` 与 `clientWidth` 均为 412。
- Android exact-head native build: **NOT VERIFIED**（本机不安装/修复 SDK/NDK）。
- `design-handoff` 未安装；以本文件 + `VISUAL_POLISH.md` + `design-review` 流程作为交付替代。
