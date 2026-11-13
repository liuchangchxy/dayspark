# DaySpark Widgets / 桌面小组件产品规格

状态：**定稿待评审（WIDGET_SPEC_READY_FOR_REVIEW）**
取代：PR #84 `feat/widget-redesign` 的产品设计（实现细节可复用，产品分工不保留）
实现状态与发版信息看 `docs/ROADMAP.md`；快照契约是本文 §9，`SPEC.md` 只在业务规则变化时同步。

本轮只定义产品与实现契约，不包含代码实现。

---

## 0. 裁定摘要（先看这一节）

| # | 裁定 |
|---|---|
| R1 | 最终只保留 **3 个 Widget**：待办 Todos、今日行动 Action、月历 Calendar。删除 Upcoming 与 Quick Actions。 |
| R2 | Todos 只做任务，回答“我有哪些任务”；**不显示 Event，不显示时间线**。 |
| R3 | Action 直接继承 App 的 Action 投影，回答“我现在/今天该做什么”；包含 Event、TaskAllocation、今日 Todo、今日重复实例、逾期、完成计数。 |
| R4 | Calendar 回答“哪一天有什么”。点日期先在 Widget 内切换 `selectedDate`，不打开 App；Android 按实例保存，iOS/macOS 受 WidgetKit 限制（§14.2）。 |
| R5 | Todo 勾选只在“语义无歧义”时直接完成：普通 Todo、或绑定 `occurrenceId` 的今日实例。重复 Todo 的父行不显示勾选框，点击进入详情。 |
| R6 | Todos 列表只显示未完成项；完成项不进列表。Action 只用一个“已完成 N”页脚承载完成信息。 |
| R7 | `+ 待办` 不复用完整表单，走一个极简 Quick Add surface：输入 → 保存 → 自动关闭 → Widget 刷新。 |
| R8 | Calendar 第一版**不做 Widget 内切月**。只显示当前自然月。 |
| R9 | Calendar 只提供 `+ 日程`，不提供 `+ 待办`。待办创建是 Todos 的职责。 |
| R10 | 快照升级到 v5；原生端仍然只读，单写入者与 `widget_command_<id>` 命令队列不变。 |
| R11 | Action 复用现有 `TodayWidgetProvider` / `CalendarTodoWidget` 组件与 kind（保住在桌面的实例），Calendar 复用 `CalendarWidgetProvider` / `CalendarMonthWidget`；新增 Todo；删除其余两个。 |
| R12 | Android 每次动态渲染前必须先 `removeAllViews()`；星期标题重复是最小复现，所有动态容器同罪。 |
| R13 | macOS 已有可用的宿主数据通路：`macos/Runner/MainFlutterWindow.swift` 内实现了 `home_widget` MethodChannel shim，App Group entitlement 也已就位。保留并验收，不再作为开发前置任务。 |
| R14 | Android 周期刷新以 `updatePeriodMillis=1800000` 为兜底，不承诺精确 30 分钟边界；数据变化、用户操作、日期/时区广播仍即时刷新。Now/Later 允许短暂滞后，不引入高频后台任务；iOS 用时间线条目按事件边界刷新。 |
| R15 | #84 已经做对的 **真实 resize** 保留：用 `OPTION_APPWIDGET_MIN/MAX_WIDTH/HEIGHT` 选择布局与行预算，不假设固定格数。 |

---

## 1. 产品目标

用户把 DaySpark 放在桌面后，应当能在**不打开完整 App** 的情况下完成：

1. 看见今天真正要做什么；
2. 看见自己有哪些任务；
3. 看见某一天有什么；
4. 完成一个语义明确的待办；
5. 添加一条待办或一个日程。

不变量：

- **能在 Widget 内完成的动作，不打开 App。**
- 只有复杂编辑、完整详情、平台无法承载的输入（自由文本）才进入 App。
- Widget 是 DaySpark 已有业务数据的**投影**，不是第二套 Todo / Calendar 模型。
- 任何一个可点击区域都必须有明确行为；不存在“看起来能点但没反应”的区域。
- Widget root 不得吞掉内部真正交互；root 只作为空白区域的兜底。
- 尺寸变大 = 更多信息或更多操作，不能只是把空白或字号拉大。

---

## 2. DaySpark 现有真实能力（先列能力，再做映射）

以下能力以当前代码为准，不以 README 或路线图为准。

### 2.1 Action 页（`lib/ui/pages/home/action_section.dart`）

Action 只有“今天”一天，没有日期切换器。真实投影（`ActionProjectionQuery`）包含：

| 数据 | 说明 |
|---|---|
| `events` | 今天发生或跨今天的 Event，已做重复展开 |
| `allocations` | 今天有效的 TaskAllocation（给 Todo 排的执行时间） |
| `dueTodayTodos` | 今天截止的普通 Todo（非重复） |
| `todayTaskInstances` | 今天到期的重复 Todo occurrence |
| `overdueTodos` | 普通逾期 Todo |
| `missedTaskInstances` | 近 30 天内错过的重复 occurrence |
| `completedTodayTodos` | 今天完成的普通 Todo |
| `completedTodayTaskInstances` | 今天完成的重复实例 |
| `earlierMissedSeries` / `earlierHistorySeries` | 更早的遗漏/历史提示（Action 页未直接铺开） |
| `unplannedCount` | 未排期 Todo 数（Action 页不展示，仅旧 Widget 用过） |
| `unconfirmedRecurringTodos` / `recurrenceExpansionErrors` | 重复规则异常，属于 App 内处理 |

Action 页实际分区：

- **Now**：正在进行的 Event / TaskAllocation，暖色底；
- **Later today**：尚未开始的 Event / TaskAllocation，按开始时间；
- **Due today**：今日重复实例 + 今日截止 Todo；
- **Overdue**：逾期 Todo + 错过实例；
- **Earlier today**：已结束的 Event / TaskAllocation、今日完成的 Todo / 实例。

行为：Todo / 实例可勾选完成；Event 行进入 Event 详情；TaskAllocation 与 Todo 行进入 Todo 详情。

### 2.2 Todo 工作区（`lib/ui/pages/home/home_page.dart`、`todos_dao.dart`）

真实视图：

| 视图 | 语义 | 查询 |
|---|---|---|
| Today（日视图） | 今天截止的待办；今天视图额外先显示逾期 | `watchPending` + 按 `dueDate` 过滤 |
| Inbox | 无截止日期的未完成待办 | `watchInbox` |
| All | 所有未完成待办 | `watchAllNotDeleted` 过滤未完成 |
| 完成区 | 对应日期的完成项 / 全部完成项 | `watchCompleted` |

真实能力：

- Quick Add：单行输入，回车创建，默认使用第一个日历、`priority=0`、`NEEDS-ACTION`；
- 完成 / 恢复完成；重复 Todo 在勾选时弹出 occurrence 选择器；
- deadline（`dueDate`）、start date、priority、description；
- recurring Todo（`rrule` / `recurrenceRule` / 实例状态）；
- tags（行内最多 3 个颜色点）、标签筛选；
- reorder（`sortOrder`，桌面拖拽手柄 / 移动端长按）；
- Six Things（仅“今天”视图，最多 6 项 + More 折叠）；
- hide completed 偏好；
- Todo 详情即编辑页（summary、说明、日期、重复、提醒、子任务、附件、执行时间）。

### 2.3 Calendar 页（`calendar_section.dart`、`calendar_view_provider.dart`）

真实视图：**日 / 周 / 月**三种模式，锚点日期独立保存。

真实数据：

- Event（含重复展开，tile 使用所属日历颜色）；
- TaskAllocation（给 Todo 排的执行时间，由 Todo 详情/日历 slot 创建）；
- Todo deadline：日/周视图底部 deadline lane，月视图日期格上显示标记；
- 日历颜色来自 `calendars` 表；
- 月视图带节气、法定节假日/调休标记。

真实交互：

- 点日期 / 时间槽：新建 Event；slot sheet 还支持“在此新建 Todo”“把已有 Todo 排到这里”；
- Event → Event 详情（可在详情内改时间、重复、提醒、删除）；
- TaskAllocation → Todo 详情；
- Todo deadline → Todo 详情；
- 拖拽 Event / Allocation 改期；
- 日/周/月切换；今天按钮；前后翻页。

### 2.4 当前 Widget 实现（#84）

- 4 个 Widget：Today / Upcoming / Calendar / Quick Actions；
- 数据来自 v4 `widget_snapshot`，原生只读；
- 勾选写入 `widget_command_<commandId>`，由 App 消费；
- 已完成真实 resize；
- 但产品分工不成立，且存在动态容器累加 bug。

---

## 3. 最终 Widget 产品线

| Widget | 回答的问题 | 是否保留 | 尺寸 |
|---|---|---|---|
| 待办 / Todos | 我有哪些任务？ | **新增** | Small / Medium / Large |
| 今日行动 / Action | 我现在/今天该做什么？ | **保留并重做**（由 Today 演进） | Small / Medium / Large |
| 月历 / Calendar | 哪一天有什么？ | **保留并重做** | Medium / Large |
| 近期安排 / Upcoming | 未来几天有什么？ | **删除** | — |
| 快速操作 / Quick Actions | 快捷入口？ | **删除** | — |

### 3.1 为什么删除 Upcoming

- 它只是 Calendar 的“未来几天”切片，数据源与 Calendar 完全重叠；
- 它没有自己的对象：Event / Allocation / Todo deadline 都已经在 Calendar 的日视图里；
- 它把“看未来”与“看某一天”拆成两个 Widget，用户需要自己拼起来；
- 删除后，Calendar 的日期选择覆盖同一需求，Action 覆盖“今天”。

### 3.2 为什么删除 Quick Actions

- 只剩 `+ 待办`、`+ 日程`、Today、Calendar 四个导航/创建入口；
- 前两个已经自然存在于 Todos / Action / Calendar 的头部；
- 后两个就是三个核心 Widget 本身；
- 一个只有按钮、没有数据的桌面组件不构成“桌面信息”，且会诱导用户把创建入口放在桌面而不是看见内容。

三个核心 Widget 都必须自带 `+`，Quick Actions 没有独立职责。

---

## 4. 通用交互与布局原则

1. **行高与预算**：Widget 行按 44–48dp 设计；Android 用真实 `min/max height` 计算可容纳行数，不硬编码格数。iOS 按 system family 固定预算。
2. **文本截断**：标题 1 行（Medium/Small）或 2 行（Large 的 Todo），超出省略；不滚动。
3. **触控**：所有可点击区域 ≥ 44×44dp；行内的 checkbox 与标题是两个独立目标。
4. **颜色**：来自快照 `theme`（含 `error` / `warning`）；日历事件颜色来自所属日历；逾期用 `error`；Now 用 `accent` 或暖色底。
5. **日期与时间**：日期用系统语言短格式；时间 24 小时制与 App 一致；全天显示“全天”。
6. **文案**：运行期文案全部来自快照 `ui` 块（跟随 App 内语言）；原生 Gallery 名称/描述用系统语言资源。
7. **无障碍**：checkbox 读“完成/取消完成 + 标题”；行读“打开 <标题> 详情”；日期格读完整日期与当日条目数。
8. **失败兜底**：任何异常都必须返回一个可显示的布局，绝不让 launcher 出现“载入窗口小组件时出现问题”。

---

## 5. 待办 Widget / Todos

### 5.1 职责

回答“我有哪些任务”。它是**可以长期放在桌面的任务清单**，不是 Todo 页的快捷入口，也不是 Action 的副本。

硬边界：

- 不显示 Event；
- 不显示 TaskAllocation 时间线；
- 不显示“现在正在发生什么”；
- 列表只显示未完成项。

### 5.2 三种模式

| 模式 | 数据 | 排序 | 新增行为 |
|---|---|---|---|
| 今天 Today（默认） | 逾期（仅今天视图先显示）+ 今天截止的未完成 Todo | 逾期按截止日升序、优先级；今天按 `sortOrder`、`priority` | `+` 创建 `dueDate=今天` |
| 收件箱 Inbox | `dueDate == null` 的未完成 Todo | `sortOrder`、`priority` | `+` 创建无日期 Todo |
| 全部 All | 所有未完成 Todo（含逾期与今天） | `sortOrder`、`dueDate` | `+` 创建无日期 Todo |

说明：

- Todos 的模式与 App 的 Todos 视图一一对应，**不做 occurrence 展开**。重复 Todo 以父行出现（通常只在有截止日期时进入今天/全部）；重复实例的“今天该做哪一次”属于 Action。
- 今天模式在 `date == 今天` 时显示逾期分组，与 App 日视图一致。
- Six Things 打开时：今天列表最多显示 6 项；超出显示“还有 N 项”，点击进入 App 的 Todo 今天视图。Six Things 关闭时按空间预算显示。此项只影响今天模式。
- hide completed 偏好对 Widget 不产生可见变化：Widget 本来就不显示完成项。
- 完成项永远不进入 Todos 列表；今天完成了多少只在 Action 的页脚出现。

### 5.3 尺寸规格

行数按“高度预算”计算，下表是名义值；Android 可自由 resize，按 §13.3 计算。

| 尺寸 | 展示 | 最多行数 | 增加的信息/操作 |
|---|---|---|---|
| Small（2×2 / systemSmall） | 模式标签 + 未完成计数 + `+`（Android）；1–2 行 Todo（按高度，名义 2） | 2 | 只有标题、优先级条、勾选框；标题 1 行；无截止日、无 tag；iOS/macOS Small 无独立 `+` |
| Medium（4×2 名义 / systemMedium） | 模式切换（Android）+ 计数 + `+`；Todo 行 | 4 | 增加截止日 chip（All 模式）；标题 1 行；Large 才有 tag |
| Large（4×4+ / systemLarge） | 模式切换 + 计数 + `+`；分组标题；Todo 行 | 8（Android 最多 12） | 增加 tag 颜色点（≤3）、更多页脚、更大的行间距 |

尺寸变大必须增加“信息或操作”，不允许只放大字号：

- Small → Medium：出现模式切换与截止日；
- Medium → Large：出现 tag、逾期分组标题、更多计数、更宽的标题。

### 5.4 行内容与优先级

| 元素 | 规则 |
|---|---|
| 勾选框 | 普通 Todo：直接完成；重复 Todo 父行：**不显示勾选框**，改显示重复图标 |
| 标题 | 1 行（Small/Medium）或 2 行（Large）；点击进入 Todo 详情 |
| 优先级条 | 左侧 2dp；1=错误色，2–4=警告色，其余透明；与 App 一致 |
| 截止日 | Medium/Large 的 All 模式显示；今天模式只给逾期项显示红色日期；Inbox 不显示 |
| 重复图标 | `rrule` 或 `recurrenceRule` 非空时显示；点击行进入详情 |
| tag 点 | 仅 Large；最多 3 个颜色点 |
| 逾期 | 今天模式第一组；日期红色 |
| 编号 | 仅 Six Things 打开且今天模式；按可见顺序显示 1–6 |

### 5.5 可点击区域

| 区域 | 行为 |
|---|---|
| 模式 chip（Medium/Large，Android） | Widget 内切换 Today / Inbox / All，不打开 App |
| 模式标签（Small，Android） | 点击循环 Today → Inbox → All，不打开 App |
| 标题 / 计数 | 打开 App 的 Todo 对应视图（`view=today/inbox/all`） |
| `+` | 极简 Quick Add：今天模式带 `date=今天`，Inbox/All 不带日期。Android 所有尺寸；iOS/macOS 仅 Medium/Large |
| Todo 勾选框（普通） | Widget 内直接完成，乐观勾选，命令队列落库 |
| 重复 Todo 的重复图标 | 打开 Todo 详情；完成在详情内选择 occurrence |
| Todo 标题 / 行主体 | 打开 Todo 详情 |
| “还有 N 项” | 打开 App 的 Todo 当前视图 |
| 分组标题（逾期 / 今天） | 纯标签，不可点击，不做按钮外观 |
| 空白区域 | 打开 App 的 Todo 当前视图 |
| 整体 root | 仅作为空白兜底，不覆盖以上子目标 |

---

## 6. 今日行动 Widget / Action

### 6.1 职责

回答“我今天现在应该做什么”。直接继承 App Action 的产品语义：

- 有时间轴（Event + TaskAllocation）；
- 有今日任务（普通截止 + 重复实例）；
- 有逾期；
- 有完成信息；
- 有 `+ 待办` / `+ 日程`。

与 Todos 的明显区别：**Action 包含 Event 与时间顺序，Todos 不包含 Event。**

### 6.2 分区与排序

顺序与 App 一致：

1. **Now**：`start <= now < end` 的 Event / Allocation；
2. **Later today**：`start > now` 的 Event / Allocation，按开始时间；
3. **Due today**：`todayTaskInstances` + `dueTodayTodos`；实例按 anchor，Todo 按 `sortOrder`、`priority`；
4. **Overdue**：`overdueTodos` + `missedTaskInstances`；
5. **Completed**：只显示“已完成 N”页脚，不铺行。

已结束的 Event / TaskAllocation 不在 Widget 里铺行；它们仍属于 App Action 的 Earlier today，Widget 只保留“已完成 N”计数（普通 Todo + 重复实例）。

小尺寸无法铺全时，按上述顺序截断；Overdue 在 Medium/Large 至少保留一行“N 项逾期”摘要，避免被截掉。Small 在头部显示逾期计数 chip。

### 6.3 尺寸规格

| 尺寸 | 展示 | 最多行数 | 增加的信息/操作 |
|---|---|---|---|
| Small（2×2 / systemSmall） | 日期 + 星期 + 逾期计数 chip + `+`（Android）；1 行“下一件事” | 1 | 只能看一件事；无分区标题；Android 提供 `+ 待办`；iOS/macOS Small 无独立 `+`，非勾选区域打开 Action |
| Medium（4×2 名义 / systemMedium） | 日期；Now / Later / Due today 各 1–2 行；逾期摘要 1 行；`+ 待办` / `+ 日程` | 6 | 出现分区、两个创建入口 |
| Large（4×4+ / systemLarge） | Now ≤2、Later ≤3、Due today ≤3、Overdue ≤2、完成页脚 | 14 | 出现完整分区、更多逾期、完成计数、两个创建入口 |

Small 的“下一件事”选择顺序：正在进行的 Event/Allocation → 下一个 Later → 第一条 Due today。逾期只以 chip 计数呈现，点击 chip 打开 App Action。Android Small 的 `+` 只提供 Quick Add（今天）；iOS/macOS Small 没有独立 `+`。`+ 日程` 从 Medium 起提供。

### 6.4 行内容

| 类型 | 左侧 | 主体 | 右侧 |
|---|---|---|---|
| Event | 开始时间；跨时段显示 `开始–结束` | 标题；所属日历颜色条 | 详情箭头 |
| TaskAllocation | 开始时间 | Todo 标题 + “已排期” | 勾选框 |
| 今日 Todo / 实例 | 截止时间或 occurrence 时间 | 标题；逾期红色 | 勾选框 |
| 逾期 | 截止日期/时间，红色 | 标题 | 勾选框 |
| 完成页脚 | — | “已完成 N” | 箭头（打开 App） |

### 6.5 可点击区域

| 区域 | 行为 |
|---|---|
| 日期 / 标题 | 打开 App 的 Action 页 |
| 逾期计数 chip（Small） | 打开 App 的 Action 页 |
| Event 行 | 打开 Event 详情 |
| TaskAllocation 行 / 标题 | 打开 Todo 详情 |
| TaskAllocation 勾选框 | 用该 allocation 的 `occurrenceId` 直接完成（无 occurrence 时按普通 Todo） |
| 今日 Todo 勾选框 | 直接完成 |
| 今日重复实例勾选框 | 用精确 `occurrenceId` 完成 |
| 逾期 Todo / 实例 | 同上，直接完成 |
| “N 项逾期”摘要 | 打开 App 的 Action 页 |
| “已完成 N” | 打开 App 的 Action 页（Earlier today） |
| “还有 N 项” | 打开 App 的 Action 页 |
| `+ 待办` | Quick Add，`date=今天`（Android 所有尺寸；iOS/macOS Medium/Large） |
| `+ 日程` | Event 新建，默认今天：今天剩余时间从下一小时开始，否则 09:00–10:00（Medium/Large；Small 不提供） |
| 分区标题 | 纯标签，不可点击 |
| 空白区域 | 打开 App 的 Action 页 |

---

## 7. 月历 Widget / Calendar

### 7.1 职责

回答“哪一天有什么”。

核心要求：

- 点某一天 → 先在 Widget 内切换 `selectedDate` 并显示该日内容；
- 选日期不打开 App；
- “今天”可以直接切回今天；
- Event → Event 详情；TaskAllocation / Todo deadline → Todo 详情；
- `+ 日程` 默认使用当前 `selectedDate`；
- 第一版不做 Widget 内切月。

### 7.2 月格

- 只显示当前自然月（device 当前月；与快照月份一致时带内容标记）；
- 周一为每周第一天，与 App 一致；
- 日期格显示：日号；今天高亮；选中日期高亮；一个标记点；
- 标记点优先级：有 Event/Allocation → 第一个日历颜色；否则有 Todo deadline → 次要文字色；
- 不在本月内的格子留空（不显示上/下月溢出日）；
- 月标题显示“2026年11月”；旁边有“今”按钮（仅当选中的不是今天）和 `+`。

### 7.3 尺寸规格

Calendar 不支持 Small（Android 最小 4×4；iOS 不提供 systemSmall）。

| 尺寸 | 布局 | 选中日内容 | 增加的信息/操作 |
|---|---|---|---|
| Medium（Android 4×4 / iOS systemMedium） | Android：月格 + 选中日标题 + 2 行；iOS：月格 ↔ 单日模式二选一（见下） | Android 最多 2 行；iOS 单日模式最多 4 行 | 选中日期、查看当天；`+ 日程` |
| Large（4×6+ / systemLarge） | 月格 + 选中日标题 + 内容列表 | Android 最多 6 行；iOS 最多 4 行 | 更多当天条目、更多行、标题可 2 行 |

iOS systemMedium 高度不足以同时放月格与内容，因此采用**同一 Widget 内的 Month / Day 两种显示模式**：

- Month：显示月格；点日期 → 切到 Day；
- Day：显示“11月8日 周六”+ 当天内容 + `‹ 月` 返回；
- 模式与 `selectedDate` 都是 Widget 状态，不打开 App。
- Android Medium 若实际高度不足 230dp，也退化为同样的 Month/Day 模式。

### 7.4 选中日内容

顺序：

1. 全天 Event；
2. 有时间的 Event / TaskAllocation，按开始时间；
3. Todo deadline：有具体时间的按时间，仅日期的排最后。

每行：

| 类型 | 左侧 | 主体 |
|---|---|---|
| Event | `14:00` 或 `全天` | 标题 + 日历颜色条 |
| TaskAllocation | `16:30` | Todo 标题 + “已排期” |
| Todo deadline | 时间或 `□` | 标题；逾期红色 |

当天没有内容时显示“这一天没有安排”，月格保持可交互。超过行预算或超过 8 条快照上限时，最后一行显示“还有 N 项”，点击打开 App Calendar 的该日期。

### 7.5 可点击区域

| 区域 | 行为 |
|---|---|
| 月标题 | 打开 App 的 Calendar（当前选中日期） |
| “今” | Widget 内把 `selectedDate` 切回今天；Day 模式保持 Day，Month 模式保持 Month |
| 日期格 | Widget 内切换 `selectedDate`；Large 与 Android Medium（高度足够）直接更新下方内容；Month/Day 模式下进入 Day。**不打开 App** |
| `+` / `+ 日程` | 打开 Event 新建，默认日期 = 当前 `selectedDate`；今天→下一小时，其他日→09:00–10:00 |
| 选中日 Event 行 | 打开 Event 详情 |
| 选中日 TaskAllocation 行 | 打开 Todo 详情 |
| 选中日 Todo deadline 行 | 打开 Todo 详情 |
| `‹ 月`（Day 模式） | 回到 Month 模式，不打开 App |
| “还有 N 项” | 打开 App 的 Calendar（当前选中日期） |
| 空状态文字 | 纯文本，不可点击 |
| 空白区域 | 打开 App 的 Calendar（当前选中日期） |

### 7.6 不提供 `+ 待办` 的理由

App 的 Calendar 确实支持“在此时间槽新建 Todo”，但它需要**具体时间槽**作为上下文。Widget 的月格只能给出日期，给不出用户想要的执行时段；在日历上再放一个待办创建入口，会把 Calendar 变成第二个 Todos，职责重新重叠。

因此：

- 想加任务 → Todos 的 `+`；
- 想给任务排时间 → App 的 Calendar slot sheet；
- Calendar Widget 只负责“看”和“新建日程”。

### 7.7 第一版不切月

- 月格始终是当前自然月；
- 不提供左右翻月；
- 下个月由日期跨月后的快照重建接管；
- 理由：切月需要额外的 per-instance 月份状态、跨月数据（当前快照只含一个月）和 iOS 共享状态方案，收益低于成本，且会把“看本月”这个高频场景做复杂。

---

## 8. Widget 内状态

只允许以下 UI 状态，**不得新增业务实体、不得同步、不得写数据库**：

| 状态 | 取值 | Android 存储 | iOS/macOS |
|---|---|---|---|
| Todos 模式 | `today` / `inbox` / `all` | 按 `appWidgetId` 独立保存 | Widget 配置参数（每实例） |
| Calendar 选中日 | ISO 日期，默认今天 | 按 `appWidgetId` 独立保存 | App Group 共享键（见 §14.2） |
| Calendar 显示模式（Medium） | `month` / `day` | 按 `appWidgetId` 独立保存 | App Group 共享键 |

规则：

- Android：`SharedPreferences` 键 `widget_state_<appWidgetId>`，JSON 保存上述字段；`onDeleted` 删除该键；快照刷新不得重置。
- Todos 模式在列表变空、跨天、App 重启后都保持；只有在 Widget 被移除时清除。
- Calendar 选中日跨天时：若仍在本月，保留；若已不是今天所在月，重置为今天。
- iOS/macOS 的 Todos 模式用 `AppIntentConfiguration` 参数，由用户在“编辑小组件”里选择；这是 WidgetKit 唯一可靠的**每实例**配置方式。
- iOS/macOS 的 Calendar 选中日/模式存 App Group `UserDefaults`，所有 Calendar Widget 实例共享同一个选中日（§14.2）。
- 这些状态不进入 `widget_snapshot`，不触发快照重建；状态变化只重绘当前 Widget。

---

## 9. 数据来源

原生端永远不读 SQLite，只读一个 `widget_snapshot`。快照由 Flutter 侧构建，单写入者不变。

### 9.1 每个 Widget 的数据来源

| Widget | 现有数据源 | 用途 |
|---|---|---|
| Action | `ActionProjectionQuery.fetch` / `actionProjectionProvider`；`HomeWidgetService.todayTimeline` / `todayActions` / `todayStatus` | 时间线、今日任务、逾期、完成计数 |
| Todos | `todosDao.watchOrdinaryDueBetween`、`watchOrdinaryOverdue`、`watchInbox`、`watchAllNotDeleted`（过滤未完成）、`watchActiveRecurring`；`tags`/`todo_tags`；`sixThingsModeProvider` | 三种模式、排序、优先级、重复标记、tag 点、Six Things 上限 |
| Calendar | `eventsDao.getEventCandidates` + `expandRecurringEvents`；`fetchTaskAllocationsInDateRange`；`todos` 本月截止；`calendars` 颜色；`HomeWidgetService.monthCalendar` | 月格标记 + 选中日条目 |

约束：

- 不创建第二套 Todo / Calendar 模型；快照字段只是现有行/投影的字段投影。
- 不建立通用 Widget JSON renderer；三个原生视图各自读固定结构。
- 快照一次重建，三个 Widget 共用；不按 Widget 分片写多份。
- 所有列表有上限与总数（见 §9.3），防止快照无界增长。

### 9.2 快照 v5 结构

`widget_snapshot`，`version: 5`：

```json
{
  "version": 5,
  "generatedAt": "2026-11-07T08:00:00Z",
  "today": "2026-11-07",
  "action": {
    "timeline": [
      {
        "kind": "eventOccurrence",
        "eventId": 12,
        "calendarId": 1,
        "summary": "小组会",
        "start": "16:30",
        "end": "17:30",
        "startEpochMs": 1794069000000,
        "endEpochMs": 1794072600000,
        "isAllDay": false,
        "color": "#3B82F6"
      },
      {
        "kind": "taskAllocation",
        "todoId": 34,
        "todoSyncId": "todo-34",
        "occurrenceId": null,
        "allocationId": "88",
        "summary": "写论文",
        "start": "19:00",
        "end": "20:00",
        "startEpochMs": 1794078000000,
        "endEpochMs": 1794081600000,
        "isAllDay": false,
        "color": "#10B981"
      }
    ],
    "dueToday": [
      {
        "kind": "taskInstance",
        "todoId": 40,
        "todoSyncId": "todo-40",
        "occurrenceId": "occ-2026-11-07",
        "summary": "背单词",
        "displayTime": "07:30",
        "priority": 0
      }
    ],
    "overdue": [],
    "counts": {
      "dueToday": 3,
      "overdue": 2,
      "completedToday": 4
    }
  },
  "todos": {
    "today": {
      "sixThingsCap": 6,
      "items": [
        {
          "todoId": 41,
          "todoSyncId": "todo-41",
          "summary": "写论文",
          "priority": 1,
          "dueDate": "2026-11-07",
          "dueEpochMs": 1794067200000,
          "hasTime": false,
          "recurring": false,
          "tagColors": ["#F59E0B"]
        }
      ],
      "overdue": [],
      "completedCount": 2
    },
    "inbox": {
      "items": [],
      "total": 0
    },
    "all": {
      "items": [],
      "total": 0
    }
  },
  "month": {
    "year": 2026,
    "month": 11,
    "firstWeekday": 7,
    "today": 7,
    "days": [
      {
        "day": 8,
        "hasEvent": true,
        "hasTodo": true,
        "hasAllocation": false,
        "colors": ["#3B82F6"],
        "itemCount": 3,
        "items": [
          {
            "kind": "eventOccurrence",
            "eventId": 12,
            "summary": "小组会",
            "start": "09:00",
            "end": "10:00",
            "startEpochMs": 1794147600000,
            "endEpochMs": 1794151200000,
            "isAllDay": false,
            "color": "#3B82F6"
          },
          {
            "kind": "todoDeadline",
            "todoId": 43,
            "todoSyncId": "todo-43",
            "summary": "买东西",
            "start": "18:00",
            "hasTime": true,
            "startEpochMs": 1794189600000
          }
        ]
      }
    ]
  },
  "ui": {
    "locale": "zh",
    "today": "今天",
    "inbox": "收件箱",
    "all": "全部",
    "noTodos": "没有待办",
    "allTodosDone": "今天的待办都完成了",
    "noPlans": "今天没有安排",
    "allPlansDone": "今天的安排都完成了",
    "now": "现在",
    "later": "接下来",
    "dueToday": "今天要做",
    "overdue": "逾期",
    "completedCount": "已完成 {n}",
    "moreCount": "还有 {n} 项",
    "overdueCount": "{n} 项逾期",
    "selectedDayEmpty": "这一天没有安排",
    "backToMonth": "月",
    "openToUpdate": "打开 DaySpark 以更新",
    "stale": "数据待更新",
    "addTodo": "+ 待办",
    "addEvent": "+ 日程",
    "quickAddHint": "添加待办",
    "quickAddToday": "今天",
    "quickAddInbox": "收件箱",
    "save": "保存",
    "saveFailed": "保存失败，请重试",
    "allDay": "全天"
  },
  "theme": {
    "dark": false,
    "colors": {
      "background": "#FFFFFF",
      "surface": "#FFFFFF",
      "textPrimary": "#111111",
      "textSecondary": "#666666",
      "accent": "#F97316",
      "border": "#E5E5E5",
      "error": "#DC2626",
      "warning": "#D97706"
    }
  }
}
```

`ui` 中的 `{n}` 是模板占位符，由原生端按当前计数替换；其余文案直接显示。`month.firstWeekday` 使用 1=周一 … 7=周日；`todos.today.sixThingsCap` 为 6 表示最多 6 项，为 0 表示不设上限。

### 9.3 上限

| 数据 | 上限 |
|---|---|
| `action.timeline` | 30 条（今天通常远小于此） |
| `action.dueToday` / `overdue` | 各 30 条 |
| `todos.today.items` / `overdue` | 各 30 条 |
| `todos.inbox.items` | 30 条 + `total` |
| `todos.all.items` | 50 条 + `total` |
| `month.days[].items` | 每天 8 条 + `itemCount` |
| `todos.*.tagColors` | 每个 Todo 3 个 |

### 9.4 删除的旧字段

v5 不再输出：

- `upcoming`（`days` / `items` / legacy `events` / `todos`）；
- `monthDots`；
- legacy `todayEvents` / `pendingTodos` / `todoCount`；
- `pendingTaps`。

原生读取端同一版本更新，不做 v4 渲染兼容。升级迁移仍需消费一次旧快照里的 `pendingTaps`（消费后清除），v5 只是不再写入；快照损坏/版本不符按 §11 处理。

### 9.5 写路径不变

- 原生勾选 → `widget_command_<commandId>`；
- App 启动/前台/快照刷新时消费；
- 经 `toggleTodoProvider` 单一写路径落库；
- 乐观勾选由原生 pending-command 集合表达，不写快照；
- Todo 创建走 `createTodoProvider`（Quick Add），Event 创建走现有 Event 表单与写路径；
- 任何写入提交后由 `RecordBus` 驱动快照重建（§12）。

---

## 10. 添加行为

### 10.1 Todo Quick Add

平台限制：Android `RemoteViews` 不支持 `EditText`；iOS/macOS WidgetKit 不支持文本输入。因此不能用真正的“Widget 内输入框”。

产品流程：

```
点 + → 极简 Quick Add surface → 输入 → 保存 → 自动关闭 → Widget 刷新
```

Quick Add surface 要求：

- 只显示一个自动聚焦的单行输入框；
- 顶部显示落点：`今天` 或 `收件箱`（由来源模式决定，不在 surface 内改日期）；
- 回车/保存 → 调 `createTodoProvider`，`calendarId` 用第一个日历，`priority=0`，`status=NEEDS-ACTION`，`dueDate` 按落点；
- 成功后立即关闭 surface；
- 失败时保留输入并显示“保存失败，请重试”；
- 不进入完整 Todo 表单，不出现优先级、tag、重复、提醒等字段。

路由：`dayspark://quick-add?date=YYYY-MM-DD`（无 `date` 即收件箱）。App 侧新增独立的 `/quick-add` 极简页面；`dayspark://quick-add` 不再指向 `/todo/new`。保留旧 `dayspark://open/new-todo` 作为同一入口的别名。

返回行为：

- Android：surface 关闭后回到进入前的界面；冷启动场景可结束 Quick Add 任务回到桌面；
- iOS/macOS：surface 关闭后回到 Home（系统不允许程序化退出 App）。

### 10.2 Event 新建

- 入口：Action 的 `+ 日程`、Calendar 的 `+`；
- 打开现有 Event 表单，预填日期/时间：
  - 今天：从下一整点开始，1 小时；
  - 其他日期：09:00–10:00；
- 用户仍可改开始/结束、重复、提醒、日历；
- 保存后 RecordBus 触发 Widget 刷新。

Event 是复杂对象，Widget 不做内联创建。

### 10.3 深链一览

所有 Widget 导航统一走 `dayspark://`，由 `widgetDeepLinkLocation` 翻译成 go_router 路径。

| 深链 | App 落点 |
|---|---|
| `dayspark://open/action` | Action 页（`/?tab=0`）；旧 `open/today` 作为别名 |
| `dayspark://open/todos?view=today/inbox/all` | Todo 页（`/?tab=2&view=...`）；缺省 `today` |
| `dayspark://open/todo?id=<localId>` | Todo 详情 |
| `dayspark://open/event?id=<localId>` | Event 详情 |
| `dayspark://open/calendar?date=YYYY-MM-DD` | Calendar 页并定位到该日期 |
| `dayspark://open/new-event?date=YYYY-MM-DD` | Event 新建，预填日期 |
| `dayspark://quick-add?date=YYYY-MM-DD` | 极简 Quick Add；无 `date` 即收件箱 |

---

## 11. 空状态、首次状态、错误状态

任何状态都必须有可渲染布局；原生端不得把异常抛给 launcher。

| 状态 | Action | Todos | Calendar |
|---|---|---|---|
| 没有今天安排，但今天有完成项 | “今天的安排都完成了” + 已完成 N | — | — |
| 今天完全没有安排 | “今天没有安排” + `+ 待办` / `+ 日程` | — | — |
| 当前模式没有待办 | — | “没有待办” + `+`；今天模式若有过完成项则“今天的待办都完成了” | — |
| 选中日期没有内容 | — | — | 月格保留；内容区“这一天没有安排” |
| App 尚未生成快照 | “打开 DaySpark 以显示你的安排”；点击打开 App | “打开 DaySpark 以显示你的待办”；点击打开 App | 用系统当前月渲染空月格；底部“打开 DaySpark 以更新”；点击打开 App |
| 快照损坏 / 读取失败 / 版本不符 | 同“尚未生成”；记录日志，不崩溃 | 同“尚未生成” | 同“尚未生成” |
| 快照过旧：`today` 不是本地今天 | 不把昨天当今天显示；显示“打开 DaySpark 以更新”，点击打开 App | Today 模式同左；Inbox/All 可显示旧数据，但顶部加“数据待更新”行；勾选仍走命令队列（按 id/syncId 校验，失效命令安全丢弃） | 若快照月份不是本地当前月：渲染当前月空月格 + “打开 DaySpark 以更新”；同月则正常显示并加“数据待更新”提示 |
| 原生渲染异常 | 捕获后显示 fallback 布局：DaySpark 名称 + “打开 DaySpark”；root 可点 | 同左 | 同左 |
| Quick Add 保存失败 | — | 保持输入 + “保存失败，请重试” | — |
| 没有日历（极端） | — | Quick Add 显示失败提示，不写半条数据 | — |

首次添加 Widget：

- Action / Todos：如果已有快照，直接显示；没有则显示引导态。
- Calendar：即使是全新安装，也能用系统日期画出一个空月格，不出现空白或崩溃。

---

## 12. 刷新规则

### 12.1 必须触发快照重建 + 原生刷新的事件

| 触发 | 影响 Widget |
|---|---|
| Todo 创建 / 更新 / 删除 / 完成 / 恢复 | Todos、Action、Calendar（deadline） |
| Event 创建 / 更新 / 删除 / 改期 | Action、Calendar |
| TaskAllocation 创建 / 改期 / 删除 | Action、Calendar |
| TaskInstance 状态变化 | Action |
| 日历名称/颜色变化 | Action、Calendar |
| Tag 创建/更新/删除、Todo-Tag 关联变化 | Todos（tag 点） |
| Six Things 偏好变化 | Todos（今天列表上限） |
| 语言 / 主题 / 主题色变化 | 全部（`ui` / `theme`） |
| Quick Add 保存 | Todos、Action、Calendar（若今天/本月） |
| App 启动 / 前台恢复 | 全部；同时兜底外部进程（CLI/MCP）写入 |
| 同步 pull 应用完成 | 全部；`SyncApplier` 走 `RecordScope`，提交后 RecordBus 会发事件 |
| 跨天 | 全部；Android 由日期变更广播 + 下次快照重建；iOS 时间线条目跨午夜 |
| Widget 被添加 / resize | 该实例重新渲染（只用当前快照，不重建） |

### 12.2 只重绘、不重建

| 触发 | 行为 |
|---|---|
| Todos 切换 Today/Inbox/All | 读当前快照，重绘该实例 |
| Calendar 选择日期 / Month↔Day | 读当前快照，重绘该实例 |
| 勾选乐观态 | 原生 pending-command 集变化，重绘该实例 |

### 12.3 禁止

- 禁止用定时器不断 `addView` 或不断请求刷新；
- 禁止每个 Widget 各自写快照；
- 禁止原生写 SQLite 或写快照；
- 禁止无变化时重复触发全量刷新（用 `RecordBus` 合并；当前由 `WidgetRefreshScheduler` 执行：400ms 防抖合并突发、文本输入持有焦点时不重建、兜底上限 4s、同一时刻最多一个 in-flight，运行中到达的请求合并成一次补跑）；
- 禁止依赖“每 30 分钟一定准时”来做产品承诺；`updatePeriodMillis=1800000` 只是兜底，不是刷新主路径。

### 12.4 时间判定

- Snapshot 为 Event / Allocation 提供 `startEpochMs` / `endEpochMs`；
- 原生渲染时按设备当前时间计算 Now / Later，而不是依赖快照生成时的分区；
- Android 的周期刷新只是兜底：系统不保证精确边界，也不承诺每 30 分钟执行一次；
- 数据变化会触发刷新，但不保证在一次提交后立刻发生：快照重建经 400ms 防抖合并，且在文本输入持有焦点时推迟（上限 4s），避免与输入法抢 UI isolate；Widget 操作与日期/时间/时区广播仍立即重绘；
- Now/Later 在两次刷新之间允许短暂滞后，不为此引入高频后台任务；
- iOS/macOS 时间线在下一个事件边界与午夜各生成条目，边界准确；
- 跨天：iOS `Timeline(entries: [now, nextMidnight], policy: .after(nextMidnight))`；Android 监听 `ACTION_DATE_CHANGED` / `ACTION_TIME_CHANGED` / `ACTION_TIMEZONE_CHANGED` 并重绘。

---

## 13. Android 实现约束

### 13.1 动态容器必须幂等（#84 真机 bug 的根因）

`AppWidgetManager.updateAppWidget()` 把 `RemoteViews` 的操作指令应用到 launcher 中**已经存在的 View 树**；同一个 layout id 不会重新 inflate。因此：

- `RemoteViews.addView()` 是**追加**语义；
- 每个动态容器在同一轮 build 里必须先 `removeAllViews(R.id.container)`，再逐条 add；
- 只清空 grid、不清空 weekday header，就会出现星期标题不断累加。

#84 的已知问题：

| 容器 | 现状 | 要求 |
|---|---|---|
| `calendar_weekdays` | 只 `addView`，未清空 → 每次刷新多一行星期标题 | build 开头 `removeAllViews` |
| `calendar_grid` | 已清空 | 保持 |
| `calendar_summary` | 已清空 | 保持；重做后改名/复用前仍要清空 |
| `today_timeline` | 未清空 → 同类累加 | 每次 `removeAllViews` |
| `today_actions` | 未清空 → 同类累加 | 每次 `removeAllViews` |
| `upcoming_groups` | 未清空；该 Widget 删除 | — |
| 新增 Todos 行容器 | — | 必须清空 |
| 新增 Calendar 选中日行容器 | — | 必须清空 |

验收测试：对每个 Provider 连续执行两次 build/apply，断言每个动态容器的 child count 相同。任何 `addView` 目标没有对应的 `removeAllViews` 都算缺陷。

### 13.2 视图与能力

- 只用 `RemoteViews` 支持的 View：`LinearLayout`、`FrameLayout`、`RelativeLayout`、`TextView`、`ImageView`、`Button`、`ProgressBar`、`GridLayout` 等；
- 不用 `EditText`、`ScrollView`、`RecyclerView`、自定义 View；
- 勾选态用 `ImageView` + drawable，不用依赖 `CheckBox`；
- 不支持滚动：内容必须按预算裁剪，多余用“还有 N 项”；
- 所有文本单行/双行截断，不能依赖换行撑高。

### 13.3 尺寸与 resize

- `WidgetSupport.sizeOf` 继续使用 `OPTION_APPWIDGET_MIN/MAX_WIDTH/HEIGHT`；
- 行预算 = `(可用高度 - 头部 - 页脚) / 行高`，再按 Small/Medium/Large 上下限裁剪；
- `onAppWidgetOptionsChanged` 只重绘当前 `appWidgetId`；
- 保留现有 `minResizeWidth/minResizeHeight` 思路；Calendar 最小 4×4，Todos/Action 最小 2×2。

### 13.4 交互

- 勾选：`PendingIntent` → `WidgetActionReceiver` → 命令队列；**不启动 Activity**；
- 导航、Quick Add、新建 Event：`PendingIntent` → `MainActivity` + `dayspark://` URI；
- 每个可点击子 View 设置独立 PendingIntent，root 只做空白兜底；
- PendingIntent requestCode 必须按 `appWidgetId + 目标 id + 类型` 唯一，`FLAG_UPDATE_CURRENT | FLAG_IMMUTABLE`；
- 每个 provider 的 `onUpdate` / `onAppWidgetOptionsChanged` / `onDeleted` 都必须异常安全；`onDeleted` 清理实例状态。

### 13.5 fallback

- `WidgetSupport.render` 的 try/catch 保留；
- fallback 布局必须能显示“DaySpark / 打开 DaySpark”，并带 root PendingIntent；
- 不允许出现 launcher 的“载入窗口小组件时出现问题”。

---

## 14. iOS / macOS

### 14.1 共同要求

- 产品语义与 Android 一致，布局按系统原生尺寸重排，不追求像素一致；
- iOS 17+ / macOS 14+ 才支持交互式 Widget（当前扩展 target 已是 17 / 14）；
- 勾选用 `AppIntent` 写命令队列 + `WidgetCenter.reloadTimelines`，不碰 SQLite；
- `+ 待办` → Quick Add deep link；`+ 日程` → Event 表单 deep link；
- 运行期文案来自快照 `ui`；Gallery 名称/描述走系统语言；
- 时间线：现在一条 + 下一个午夜一条，`policy: .after(nextMidnight)`；
- 任何数据/解码失败都渲染空态，不崩溃。

### 14.2 真实的 WidgetKit 限制

| 限制 | 后果 | 本 Spec 的裁定 |
|---|---|---|
| `AppIntent` 无法获知触发它的具体 Widget 实例 | Calendar 的 `selectedDate` 不能像 Android 那样按实例保存 | iOS/macOS 的 Calendar 选中日/模式存 App Group，同一 kind 的所有实例共享；文档明确写“多个日历 Widget 会同步选中日”。这是可接受的降级，仍不打开 App |
| Apple 在较新系统中允许 `systemSmall` 使用 `Link`，但存在系统版本差异 | 逐行 Link 在最低支持版本上不保证一致 | v1 兼容策略：Small 主动只保留勾选 Button + 一个主 `widgetURL`，不依赖逐行 Link；Medium/Large 使用逐行 Link。这是兼容选择，不是平台永久限制 |
| 不能在 Widget 内输入文本 | Quick Add 必须进 App | 用极简 Quick Add surface，不用完整表单 |
| Widget 不能滚动 | 放不下的内容必须截断 | 用行预算 + “还有 N 项” |

Small 的勾选 Button 是 iOS 17 交互式 Widget 的标准能力。v1 不依赖 Small 的行级 Link，是为了覆盖最低 iOS 17 的系统差异，而不是断言 WidgetKit 做不到；因此 Small 中除勾选外的区域统一由一个主 `widgetURL` 承接，`+` 从 Medium 起提供。

### 14.3 Todos 模式

- 使用 `AppIntentConfiguration`，参数为 `TodoFilter`（Today / Inbox / All）；
- 每个 Widget 实例在“编辑小组件”里选择自己的模式；
- Widget 内不提供模式 chip（无法按实例改配置）；
- 这是 WidgetKit 的原生配置模式，优于把模式做成全局共享状态。

### 14.4 Calendar

- 选中日与 Month/Day 模式：App Group `UserDefaults` 共享键；
- 点日期 → `SelectDateIntent` 写共享键 + `WidgetCenter.reloadTimelines(ofKind:)`；
- 多个 Calendar 实例会显示同一个选中日（§14.2）；若未来 Apple 提供实例身份，再改为 per-instance；
- “今” → 写回今天并重绘；
- `+ 日程` → `dayspark://open/new-event?date=<selectedDate>`；
- 月份始终是当前自然月；不切月。

### 14.5 macOS 数据通路（已成立，转为验收项）

macOS 的数据通路已经存在，不是阻断项：

- `macos/Runner/MainFlutterWindow.swift` 注册了名为 `home_widget` 的 `FlutterMethodChannel`；
- 已实现 `setAppGroupId` / `saveWidgetData` / `getWidgetData` / `updateWidget`（内部调用 `WidgetCenter.shared.reloadAllTimelines()`）/ `registerBackgroundCallback` / `initiallyLaunchedFromHomeWidget`；
- `macos/Runner/Release.entitlements`、`macos/Runner/DebugProfile.entitlements` 与 `macos/CalendarTodoWidget/CalendarTodoWidget.entitlements` 都包含 `group.com.dayspark.app`。

`macos/Flutter/GeneratedPluginRegistrant.swift` 中没有 home_widget 是正常的——宿主走的是自建 shim，不是插件注册；不能据此推断“没有数据通路”。

实现阶段只做验收，不新写 shim：

- [ ] Flutter `HomeWidget.saveWidgetData('widget_snapshot', ...)` 写入 App Group，extension 能读到；
- [ ] `HomeWidget.updateWidget()` 触发 `reloadAllTimelines`，桌面立即重绘；
- [ ] Runner 与 widget extension 的 App Group 保持一致；
- [ ] shim 不得删除或重命名；若 home_widget 后续提供官方 macOS 实现，再单独评估替换，不在本版范围内。

若上述任何一条验收失败，按普通 bug 修复，不再回到“macOS Widget 是否发布”的判定。

---

## 15. 与 #84 的差异（删除 / 保留 / 重做）

### 15.1 删除

| 对象 | 处理 |
|---|---|
| Upcoming Widget（Android `UpcomingWidgetProvider`、Apple `CalendarUpcomingWidget`） | 删除 Provider / kind / 布局 / info XML / Gallery 条目 |
| Quick Actions Widget（Android `QuickActionsWidgetProvider`、Apple `CalendarQuickActionsWidget`） | 删除同上 |
| 快照 `upcoming`、`monthDots`、legacy `todayEvents` / `pendingTodos` / `todoCount`、`pendingTaps` | v5 删除 |
| `CalendarWidget` 的“点日期直接打开 App” | 否决；Android 改为实例内选中 |
| Today 的“timeline + actions 混合列表” | 拆成 Action 的显式分区 |
| 旧 `CalendarTodoWidget` 的 Today 产品语义 | 保留 kind，重做为 Action |
| Upcoming 的 `+` / Quick Actions 的四个按钮 | 不保留；能力并入三个核心 Widget |

### 15.2 保留

| 对象 | 原因 |
|---|---|
| `TodayWidgetProvider` 组件名 / `CalendarTodoWidget` kind | 保住用户已放在桌面的实例；只换产品名与内容 |
| `CalendarWidgetProvider` / `CalendarMonthWidget` kind | 同上 |
| 真实 resize 与 options 读取 | #84 做对了，保留 |
| 快照主题 / 预本地化 `ui` | 正确方向，保留并扩展 |
| 原生只读 + 命令队列 + 单写入者 | 架构正确，保留 |
| 勾选乐观态 | 保留 |
| 深链翻译 `widgetDeepLinkLocation` | 保留并扩展 |
| fallback 渲染 | 保留并覆盖所有 provider |
| macOS Runner 的 `home_widget` shim 与 App Group entitlement | 已有且必须保留，按 §14.5 验收 |

### 15.3 重做

| 对象 | 新设计 |
|---|---|
| Today → Action | 显式 Now / Later / Due today / Overdue / Completed 计数；Event + Allocation + Todo；两个创建入口 |
| Calendar | 月格 + 选中日内容；点日期不打开 App；`+ 日程` 用选中日；不切月 |
| 新增 Todos | 三模式任务清单；直接在 Widget 完成；Quick Add；Six Things 上限 |
| 快照 | v5；新增 `action` / `todos` / `month.days[].items`；删旧块 |
| Android 渲染 | 所有动态容器幂等清空 |

### 15.4 Provider / kind 对照

| 产品 | Android 组件 | Apple kind | 动作 |
|---|---|---|---|
| Action | `com.dayspark.app.TodayWidgetProvider` | `CalendarTodoWidget` | 保留标识，重做内容与显示名 |
| Calendar | `com.dayspark.app.CalendarWidgetProvider` | `CalendarMonthWidget` | 保留标识，重做内容 |
| Todos | 新增 `com.dayspark.app.TodoWidgetProvider` | 新增 `CalendarTodosWidget` | 新增 |
| Upcoming | `UpcomingWidgetProvider` | `CalendarUpcomingWidget` | 删除 |
| Quick Actions | `QuickActionsWidgetProvider` | `CalendarQuickActionsWidget` | 删除 |

Dart 侧 `HomeWidgetService` 的 provider/kind 常量、`refreshNativeWidgets` 列表同步更新。已放在桌面的 Upcoming / Quick Actions 实例会由系统移除或显示占位，这是删除的预期结果。

---

## 16. 非目标（第一版明确不做）

- Widget 内完整 Todo 编辑（summary 以外的字段、日期、重复、提醒、子任务、附件）；
- Widget 内完整 Event 编辑（标题、时间、重复、提醒、日历）；
- Widget 内拖拽排序；
- Widget 内 tag 筛选、自定义 filter builder；
- Widget 内搜索；
- Widget 内切月、周视图、日视图、多日视图；
- Calendar 的 `+ 待办` / 时间槽新建 Todo / 把 Todo 排到某时段；
- AI 推荐、自然语言输入、习惯、番茄钟；
- 任意复杂配置中心（每个 Widget 多个设置项）；
- Android 厂商专有卡片 API（Realme / ColorOS / HyperOS 等）；
- 新的数据库表、新的同步记录类型、新的业务实体；
- 锁屏 Widget、Android 锁屏小组件、Apple accessory families；
- 通知中的 Widget 操作；
- Windows / Linux / Web Widget。

非目标的作用是防止下一轮实现继续膨胀，不是防御性免责。

---

## 17. 验收清单

### 17.1 产品

- [ ] Gallery 只有 3 个 Widget：待办、今日行动、月历。
- [ ] Todos 的 Today / Inbox / All 内容与 App 对应视图一致（除完成项不显示）。
- [ ] Action 的 Now / Later / Due today / Overdue 与 App Action 一致。
- [ ] Calendar 点日期只切换选中日，不打开 App（Android；iOS/macOS 共享选中日）。
- [ ] 每个 Widget 的 `+` 行为符合 §10。
- [ ] 空态、首次态、损坏/过旧快照均有可读布局。

### 17.2 Android

- [ ] 连续刷新 10 次，月历星期标题、Action 行、Todos 行、选中日行的 child count 不变。
- [ ] 所有动态容器都有 `removeAllViews`；不存在只有 `addView` 的容器。
- [ ] resize 后行数与布局按真实高度变化，不裁切、不重叠。
- [ ] 勾选后立即乐观显示，App 下次刷新后与数据库一致。
- [ ] 勾选不启动 Activity；导航/创建才启动。
- [ ] 任意异常都显示 fallback，不出现“载入窗口小组件时出现问题”。

### 17.3 iOS / macOS

- [ ] iOS 17+ / macOS 14+ 的勾选无需打开 App。
- [ ] Todos 模式通过 Edit Widget 配置，每实例独立。
- [ ] Calendar 选中日不打开 App；多个实例共享选中日的限制在验收记录里写明。
- [ ] Small 的勾选可点，其余区域打开主目的地。
- [ ] macOS 现有 shim 通过 §14.5 验收：App Group 写入/读取、`updateWidget` → `reloadAllTimelines`、Runner 与 extension entitlement 同组；不新增 shim。

### 17.4 回归

- [ ] `dart analyze .` 零 issue。
- [ ] `flutter test` 全绿，`skipped=0`。
- [ ] 快照 v5 Kotlin/Swift 解码 fixture 测试通过。
- [ ] 命令队列对普通 Todo 与 TaskInstance 的往返测试通过。
- [ ] 深链 `quick-add` / `todos?view=` / `new-event?date=` 路由测试通过。

---

## 18. #84 真机反馈逐条结案

| # | 反馈 | 本文处理 |
|---|---|---|
| 1 | Calendar 星期标题不断重复追加 | §13.1 定位根因（RemoteViews 追加语义），要求所有动态容器先清空；列为验收硬项 |
| 2 | Calendar 动态 rows 刷新必须幂等 | §13.1；连续两次 build child count 相同 |
| 3 | Today / Upcoming 等其他动态容器同类问题 | §13.1 容器清单；Today 的 timeline/actions 同样未清空 |
| 4 | 四个 Widget 功能差异不足 | §3 只保留三个；Todos/Action/Calendar 各自回答不同问题 |
| 5 | Calendar 点日期直接打开 App 被否决 | §7.5 Android 实例内选中；iOS 共享选中日替代（§14.2） |
| 6 | 缺少真正的 Todo Widget | §5 新增 Todos，三模式、直接完成、Quick Add |
| 7 | Quick Actions 独立价值不足 | §3.2 删除 |
| 8 | Upcoming 独立价值不足 | §3.1 删除 |
| 9 | resize 做对了，应保留 | §13.3 / R15 保留 |

---

## 19. 落地事项（非产品待决）

1. **macOS 数据通路**：现有 shim 已成立，按 §14.5 验收；不是开发前置任务。
2. **iOS/macOS Calendar 共享选中日**：已拍板接受（§14.2），不作为开放问题。
3. **Calendar Medium 布局**：已拍板按 §7.3 执行：Android 高度足够时“月格 + 2 行”，不足或 iOS systemMedium 时 Month/Day 双模式。

本文其余内容均为定稿，可直接进入下一轮实现。
