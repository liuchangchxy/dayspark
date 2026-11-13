# DaySpark Todo 手机端 UI 审计

**范围**：只针对「待办」一级目的地下的 Todo 主页面、Todo Quick Create、Todo Full Create/Edit。
**基准**：`main @ 5f48ad563cb1d242106a15aa19b73ab52ee13390`，设备 moto z4 / Android 10 / 1080×2340。
**证据**：`_evidence/` 下的 15 张真机重拍截图（见 `_evidence/README.md`）+ 下列 Flutter 源码行号。

> `docs/ui-audit/stitch-20261109/` 里的 14 张原始截图在 git 中已损坏（文件是 UTF-16LE 文本被二进制管线破坏后的产物，约 38% 字节被替换为 U+FFFD，zlib IDAT 不可重建），已在本轮用 `tool/ui_acceptance/main.dart` 的种子数据在真机上重拍。本文所有结论都有源码行号与真机截图双重支撑。

---

## 1. Top 5 核心问题

### P1 · 顶部控件按视图增删，整页高度持续跳动

**这是最决定体验的一个问题。** 用户每次切换视图，页面都在他眼前重新长出来一次。

`lib/ui/widgets/todo/date_strip.dart` 的 `DateStrip.build` 有三个条件渲染：

| 视图 | "今天" 文字按钮 | 横滑 Chip 行 | 周条带 |
|---|---|---|---|
| 今天 | 无 | 全部 / 未安排 | 有 |
| 未安排 / 全部 | 无 | **今天** / 全部 / 未安排 | **无** |
| 其他日期 | **有** | 全部 / 未安排 | 有 |

三个条件：`showTodayButton`（第 35 行）、"今天" Chip（第 75 行）、`if (selectedDate != null) TodoWeekStrip(...)`（第 106 行）。

后果是：从「未安排」点进「今天」，周条带出现、截止 Chip 出现、"今天" Chip 消失；从「今天」划到上周三，右上角又长出「今天」按钮。** pinned header 高度变化 → 列表整体下移 → 用户正要点的那个 Todo Row 位移了。**

真机实测（`_evidence/10-todo-unplanned.png` vs `11-todo-today.png` vs `12-todo-all.png` vs `13-todo-other-date.png`，同一次会话内切换）：

| 视图 | Chip 数 | 周条带 | 截止 Chip | 「今天」文字按钮 |
|---|---|---|---|---|
| 未安排 | 3 | 无 | 无 | 无 |
| 今天 | 2 | **有** | **有** | 无 |
| 全部待办 | 3 | 无 | 无 | 无 |
| 其他日期 | 2 | 有 | 有 | **有** |

在 1080×2340 上，仅周条带一项就占约 195px（65dp），截止 Chip 再占约 180px（60dp）——切一个视图，列表内容整体位移约 125dp，约等于 2.5 个待办行。

**根因不是"间距没调好"，是"用一组控件的显隐来表达三种不同的视图状态"。** 视图状态应该有固定槽位，控件只改自己的选中态，不改变自己的存在与否。

---

### P2 · 核心视图导航由 32dp 的 Chip 承担

`_filterChip`（`date_strip.dart:371`）：

```dart
constraints: const BoxConstraints(minHeight: 32),
padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
```

「全部待办」「未安排」是待办目的地里仅有的两个横向视图切换，即这个页面的**主导航**。真机实测（`_evidence/README.md`）：Chip 高 **108px = 36dp**、宽 206px = 69dp，低于 Material 3 的 48dp 最小触控尺寸，也没有按压态的水波纹范围。文字用 `AppTypography.caption`（13sp）+ `w600`，未选中时只有 `Border.all(color: theme.dividerColor)` 一道 1px 灰边，选中态是一块填充色——**在没有颜色的深色模式/高对比场景下，选中与未选中的区别只剩"有没有边框"**。

作为对照，同一屏右上角的 `+ 待办` 按钮实测 144px = **48dp**，是合规的。也就是说：**这个页面把最重要的导航交给了全页最小、对比最弱的控件，而把 48dp 的预算花在了一个按钮上。**

周条格的日格触控尚可（实测格高约 195px = 65dp），但单格宽仅约 116px = 39dp。

**结论：这个页面把最重要的导航（在三个核心视图间移动）交给了全页最小、对比最弱的控件。**

---

### P3 · 两个创建入口，能力不对等，且都在静默制造截止时间

`home_page.dart` 的 `_buildTodoTab()` 同时挂了：

1. `TodoQuickAdd`（`todo_quick_add.dart`）——常驻在列表顶部的内联捕获行，48px 高，`CupertinoIcons.add` + `TextField`，**回车即写入**。
2. 全局 `+` 按钮 → `showTodoQuickCreateSheet`（`todo_quick_create_sheet.dart`）——底部弹层，标题 `TextField` + 截止 `InputChip` + 「更多」/「保存」。

两条路径的问题：

- **能力都不完整。** 内联行只有标题 +（可选）截止 Chip；弹层只多一个「更多」。**计划执行、多 Reminder、多日历、优先级、标签、描述、子任务、附件在两个入口里都没有直接入口**，必须经「更多」进全表单。
- **内联行在静默造截止时间。** `TodoQuickAdd` 接收 `dueDate: view is TodosDayView ? view.day : null`（`home_page.dart`），回车后直接 `createTodoProvider(calendarId: calendars.first.id, summary: text, priority: 0, status: 'NEEDS-ACTION', dueDate: widget.dueDate)`。用户在「今天」视图里敲一行字回车，就得到了一个**截止 = 今天**、**日历 = 第一个日历**、**优先级 = 0** 的待办，没有任何确认、没有可察觉的 Chip 反馈。这直接违反 `docs/CORE_UX_SPEC.md` 的 "no silent deadline fabrication"。`calendars.first.id` 也硬编码了多日历场景下的默认归属。
- **两个入口视觉与行为不一致。** 一个常驻、回车即存、无取消；一个弹层、要点保存、可取消。用户无法预测"点哪里新建"以及"回车会发生什么"。

---

### P4 · Quick Create → Full Edit 丢弃已输入的标题

`todo_quick_create_sheet.dart`：

```dart
void _openFullForm() {
  final due = _dueDate;
  final router = GoRouter.of(context);
  Navigator.of(context).pop();
  router.push(
    due == null ? '/todo/new' : '/todo/new?due=${due.millisecondsSinceEpoch}',
  );
}
```

`_controller.text` **从未被转发**。用户在 Quick Create 里输入「买牛奶」→ 点「更多」→ 全表单打开，标题框是空的。已经敲过的字消失了，弹层也已 pop，无法返回补救。

截止日期被当作 URL 参数带走了，标题没有。**这个缺陷单独就能让"快速创建 → 升级完整编辑"这条设计意图完全失效**，也是本次审计中唯一一个确定的功能性 Bug（按要求不修，只在重设计中消除）。

---

### P5 · Full Create/Edit 是常展开的扁平配置表；空状态用整屏留白填满

**Full Form.** `todo_form_page.dart` 第 735–880 行是一个扁平 `ListView`：标题 `TextField` →（编辑时）完成 Checkbox → `RowDivider` + `SectionLabel(任务)` → `ScheduleRow(截止)` + `RepeatRow` + `ExecutionScheduleSection` → `RowDivider` + `SectionLabel(提醒)` → `RemindersSection` → `RowDivider` + `SectionLabel(整理)` → 日历行 + `calendarExplanation` 说明文字 + 优先级 + `TagChips` → `RowDivider` + `SectionLabel(内容)` → 描述 + 子任务 + 附件。

五个 `SectionLabel` 全部常驻展开，**与这个待办有没有值无关**。新建一条「取快递」会看到 5 个分组标题和十几行空白字段。这是设置页的形态，不是创建表单的形态。`docs/CORE_UX_SPEC.md` 要求的 progressive disclosure 在这里是反的：**一次披露全部，而不是按需披露**。加 Section 标题不等于渐进披露——字段仍然是全平铺的。

**空状态.** `empty_state.dart` 用 88×88 圆形底 + 40px 图标 + 标题 + 可选提示 + 可选操作 + 可选附加，整体 `Center` 在一个 `SingleChildScrollView` 里。结果是：待办列表为空时，整屏就是一个居中的空状态；有 3 条时这片空间全是行；有 30 条时同一片空间全是行。**页面没有稳定的"形状"**，用户的视觉锚点每次都在变。加上 P1 的 header 抖动，整个页面在四种状态间有四种不同高度。

---

## 2. 支撑性发现（不进 Top 5，但必须在重设计中一并处理）

- **Todo Row 层级拥挤。** `todo_list_tile.dart`：2×18px 优先级色条（`priority == 1` 时才是 error 色，2–4 是 warning 色，其余透明）+ 48×48 Checkbox + 2 行标题（`maxLines: 2` + ellipsis）+ 行内 14px 重复图标 + 12sp 日期 + 最多 3 个 8px 标签圆点。手机上 `compact = constraints.maxWidth < 600` 恒为 true，所以永远是"标题在上、日期在下、标签点在右"这一种排法，**"这是什么"和"什么时候"在视觉上没有分层**。优先级用一条 2px 竖线表达，是全行最弱的信号却承担"高优先级"这一语义；标签用 8px 圆点，没有文字，在真机上几乎不可辨。
- **已完成任务藏在菜单里。** `home_page.dart` 的 `_displayMenu` 是一个 `PopupMenuButton<bool>`，里面只有一个 `CheckedPopupMenuItem`「隐藏已完成」。**用一个设置形状的控件承载一个视图开关**，且需要两次点击才能到达。
- **长标题与元数据抢同一行。** `maxLines: 2` 截断后，重复图标和标签点仍占位，标题可用宽度被压缩；`_dueDateLabel` 在跨天时返回 `10月19日 – 10月23日` 这样的区间字符串，在 12sp 下更容易溢出。
- **标签筛选行与视图切换竞争顶部空间。** `home_page.dart` 在 `DateStrip` 之下又挂了一行标签筛选（`_displayMenu` / `_manageTagsButton` / `_trashButton`），手机上是三个小图标按钮挤在一行，与 P2 的 32dp Chip 叠加，顶部区域总高度在被反复加码。

---

## 3. 应保留的结构

| 保留 | 理由 |
|---|---|
| 今天 / 日历 / 待办 一级导航 | `docs/CORE_UX_SPEC.md` 已冻结，三者回答三个不同问题，不重排 |
| `TodosView` 密封类（Day / Inbox / All）作为待办目的地**内部**视图 | 语义正确：全部待办与未安排是待办的两个视角，不是一级目的地。视图模型本身没问题，有问题的是它的渲染方式（P1/P2） |
| `dueDate`（截止）与 `TaskAllocation`（计划执行）两个独立时间字段 | 产品核心语义。"最晚什么时候完成" ≠ "计划什么时候实际执行"，合并任何一个都会毁掉日历规划能力 |
| 未安排 = 无有效 TaskAllocation，**不是** `dueDate == null` | `todos_provider.dart` 的 `unplannedTodosProvider` 实现正确（`pendingTodosProvider` 减去出现在 `allActiveTaskAllocationsProvider` 中的待办）。这个语义必须原样保留 |
| 勾选优先于点开：行首 48dp 勾选区 + 点行打开详情 | 高频操作（完成）比低频操作（查看）更快，这是对的 |
| 平面分组行 + 细分隔线，无逐行 Card | D Final 冻结视觉契约（`DESIGN.md`）。这是它看起来像成熟工具而不是 SaaS Dashboard 的原因 |
| 截止以**可编辑 Chip** 出现在创建表单中 | CORE_UX_SPEC 要求"继承的截止时间必须显示为可编辑 Chip"。概念正确，问题只在它出现的位置和时机 |
| 常驻捕获入口的**意图** | `todo_quick_add.dart` 的注释"Enter writes the row and keeps the focused, so five small tasks cost five lines of typing"是对的。错的是它顺带静默造了截止时间（P3） |

## 4. 应推翻的结构

| 推翻 | 换成什么 | 原因 |
|---|---|---|
| `DateStrip` 的三处条件渲染（`showTodayButton` / "今天" Chip / `if (selectedDate != null) 周条带`） | 固定高度的**视图切换段**（48dp，三个槽位常驻）+ 独立的**日期条**（只属于"某一天"视图，槽位常驻但可禁用/可收起） | P1：控件的显隐不能用来表达视图状态。槽位固定，选中态变化，页面高度恒定 |
| 32dp `_filterChip` 承担主导航 | 48dp 分段控件（Segmented Button / Tab Row），选中态不依赖边框 | P2：高频触控目标必须达到 48dp；选中态不能只靠 1px 边框 |
| 双创建入口（内联 `TodoQuickAdd` + 全局 `+` 弹层） | **单一创建入口**：一个 Quick Create 表面，输入标题后按需展开截止/计划执行/提醒/日历，"更多"平滑升级到 Full Edit 且**带走已输入内容** | P3 + P4：两个能力都不完整的入口不如一个完整的入口；标题丢失必须消除 |
| Full Form 五段常展开 | 默认只显示有值或正在编辑的分组；空分组折叠为一行摘要；重复规则、子任务、附件进二级设置页 | P5：渐进披露的方向反了 |
| 整屏居中 Empty State | 行内空态（in-list empty slot）+ 页面常驻结构（视图切换、日期条、创建入口始终在） | P5：页面必须有稳定形状 |
| `PopupMenuButton` 单布尔项「隐藏已完成」 | 列表内的行内开关或视图段的第四个槽位 | 两次点击才能到达一个开关 |
| 2×18px 优先级色条 + 8px 标签圆点 | 文字化/可读的元数据行：日期、重复、标签名、计划执行时段，各自有明确字重与颜色角色 | 2px 和 8px 在 1080p 真机上不可辨，无法承担语义 |

---

## 5. 诊断问题覆盖

审计按 12 个诊断维度逐条落点，不重复展开：

| 维度 | 落点 |
|---|---|
| 浏览方式 | P1 / P2（视图切换的形态与触控） |
| 日期浏览 | P1（周条带条件渲染）；`TodoWeekStrip` 本身保留 |
| 状态清晰度 | P3（静默截止）；P5（空态与满态无稳定形状） |
| 结构稳定性 | **P1** |
| 顶部区域拥挤 | P1 + P2 + 标签筛选行叠加 |
| 重复创建入口 | **P3** |
| Todo Row 层级 | 支撑性发现 |
| 未安排如何进入计划 | 未安排语义正确（保留），但"安排到日历"在三个创建入口里都没有可见路径 |
| 大片空白 | **P5** |
| 触控目标 | **P2** |
| 长标题 | 支撑性发现 |
| 已完成任务 | 支撑性发现 |

---

## 6. 给重设计的约束

1. 视觉语言绑定 D Final 冻结契约：钴蓝 `#2457D6`、画布 `#F5F6F8`、白内容面、`#171A20` / `#667080`、分隔线 `#E3E6EB`、平面分组行 + 细分隔线、无渐变无装饰阴影。**三套方案共用这一套语言，只在信息架构与交互模型上分歧。**
2. 信息架构绑定 `docs/CORE_UX_SPEC.md`：今天/日历/待办、截止 vs 计划执行、未安排语义、`AppSpacing`/`AppTypography` token、≥48dp 触控。
3. 不删除任何既有业务能力：标题、截止时间、重复、计划执行、多 Reminder、多日历、优先级、标签、描述、子任务、附件。
4. 不改 `lib/`、`android/`、`test/`；本轮产物只写 `design/opendesign/todo-mobile-v030/`。
