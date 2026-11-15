# 与当前 Flutter 的差异清单（供 G2–G6）

基线：`main` @ `7390987`，v0.34.0+34（`feat(ux): whole-product UX convergence`）。

上一版本文档基于 `46c01fe`（v0.29.0+29），落后 55 个提交。v0.34.0 已把 Core UX 冻结成 `docs/CORE_UX_SPEC.md`，并在真实代码里落地了一部分交互契约，因此**本清单逐条对着 7390987 重新核验过**：有 5 条（D2/D4/D5/D8/D13）已在真实代码中修复，降级为「已一致」；术语也按冻结规范更新。

优先级沿用 P0–P3。本清单只描述差异，不改生产代码。

---

## 1. 交互契约级差异（必须先改，否则后续 UI 会在错误前提上叠加）

| # | 真实代码（v0.34.0 实测） | 交互模型 | 为什么必须改 | 级别 |
|---|---|---|---|---|
| D1 | 待办详情标题是 `TextField` + 600ms 防抖直写（`todo_detail_page.dart:405-413`），截止/优先级/标签/执行时间点开浮层即刻写 | 详情**只读**；「编辑」进 composer；仅截止/优先级/标签/备注可点开浮层改 | 内联即时写没有提交边界：一次误触即产生一次写入与一次同步，且无法整体撤销 | P0 |
| D2 | ~~`eventEdit` 路由无调用者~~ **已在 v0.34.0 修复**：`event_detail_page.dart:629` 已 push `/event/edit` | 唯一编辑器 = composer | — | 已一致 |
| D3 | Esc 处理散落在 6 处，各页行为不同；composer 与日历的处理规则不一致 | 统一：浮层 → 菜单 → 页面自有 escape → 返回 | 用户无法形成「Esc 会做什么」的预期 | P1 |
| D4 | ~~桌面双栏~~ **已在 v0.34.0 实现**：`isMasterDetailLayout(context)` + `_buildDetailPane(selection)`（`home_page.dart:570-577`） | **见 §1.1 规格冲突**：冻结规范 §4 要求 master-detail，原型当前是单列 | — | 见 §1.1 |
| D5 | ~~切页残留选中~~ **已修**：`WorkspaceTabNotifier.setTab` 会先清 `workspaceSelectionProvider`（`workspace_navigation.dart:23-26`） | 切页清空选中 | — | 已一致 |
| D6 | 快速添加在 day 视图继承浏览日，未安排/全部待办无截止；输入框旁无上下文提示 | 输入框右侧显示上下文 chip（「11月16日」/「未安排」） | 现状用户无法判断这条会落到哪一天 | P1 |
| D7 | **今天页无捕获框**：`A2TodayPage` 的构造参数只有 `now/onOpenTodo/onOpenEvent/onToggleTodo/onOpenUnplanned/onScheduleTodo`（`home_page.dart:556-566`），完全没有 `onCapture` | 今天页顶部捕获框 + 未安排入口 | 「先记下来」在今天的默认落点上不可达，必须切页 | P1 |
| D8 | ~~月视图无点击~~ **已修**：月格 `onTap: () => onSelectDay(date)`，`_selectDay` 会 `_setBrowse` 并在当天有事项时切到日视图（`a2_calendar_views.dart:611-613`、`a2_calendar_page.dart:149-152`） | 点格子下钻到该日 | — | 已一致 |
| D9 | **单次实例删除无撤销**：`occurrenceOnly` 分支的 snackbar 只有 `Text(l.deleted)`，没有 `SnackBarAction`（`event_detail_page.dart:931-936`）；而整系列删除分支有撤销（`:1000-1006`） | 实例删除也给撤销（移除 exdate） | 用户已学会「删除可撤销」，唯一例外会造成真实数据丢失 | P1 |
| D10 | 取消安排块无确认、有撤销；删除待办有确认、有撤销 | 取消安排加确认 | 同一类操作确认策略不一致 | P2 |
| D11 | 删除重复日程的作用域询问**只在事件详情页**（`event_detail_page.dart:869`）；块菜单与表单路径仍整系列删 | 删除与编辑统一走一个作用域入口，三个入口问同一句话 | 两条删除路径行为不同，G2 必须收敛成一处 | P0 |
| D12 | 实例详情/编辑的基准日问题随 D2 修复后仍需确认：`/event/edit` 收到的是 `CalendaEventAdapter`，composer 按系列基准日还是实例日打开 | 编辑实例 = exdate + 一次性副本 | 若按基准日打开，改一次就改错了系列 | P1 |
| D13 | ~~投影未过滤 `parentId`~~ **已修**：`action_projection_query.dart:362` 有 `t.parentId.isNull() &`，`:392` 也有 | Action 投影排除子任务 | — | 已一致 |

### 1.1 一处真实规格冲突（不是差异，是需要拍板的矛盾）

`CORE_UX_SPEC.md` §4 明文规定：

> Desktop master-detail keeps the list visible. Mobile uses a full detail page.

真实 v0.34.0 代码也是这样实现的。**但本原型在桌面上刻意用了单列**，`COVERAGE.md` §7 把它记为有意不做，理由是「双栏会让『返回』有两种含义」。

这是原型与冻结规范的直接冲突，不是偏好问题。处理方式只有两种：原型补上桌面 master-detail，或者明确记录「本轮推翻规范这一条」并说明代价。**已提交独立 Reviewer 裁定**，结论写入 `REVIEW_ROUND3.md`，不在这里自行定论。

---

## 2. 交互模型新增（真实代码完全没有的能力）

| # | 能力 | 交互模型定义 | 落地要点 | 级别 |
|---|---|---|---|---|
| N1 | 多选批量 | 选择态 + 全选/完成/删除，删除可撤销 | 需要列表级选择状态；不能污染 `workspaceSelectionProvider` | P2 |
| N2 | 左滑删除 / 右滑完成 | 触摸端；阈值 80px；删除可撤销 | 移动端可用性；桌面保持抓手排序 | P2 |
| N3 | 桌面抓手拖动排序 | 拖动写 `sortOrder` | 真实代码已有，属**已一致** | — |
| N4 | 今日节奏条 | 06:00–24:00 带，事件/安排着色 + 当前时刻线 | 纯展示 | P2 |
| N5 | 时间格 sheet 两出口 | 新建日程 / 安排待办 | 真实代码已有（slot_sheet），一致 | — |
| N6 | 安排冲突提示 | 保存时若与已有安排/事件重叠 → 警告 toast（不阻断） | 真实代码手动排程不校验 | P2 |
| N7 | 类型切换（待办 ↔ 日程） | 新建可切，编辑锁定 | 真实代码是两个独立表单 | P2 |
| N8 | 离线段 | 状态页可切；rail 显示离线；离线同步只警告 | 真实代码 local-first 无 banner | P2 |
| N9 | 详情实例列表（重复待办） | 逐个实例可勾选 + 显示已安排的时段 | 真实代码有 occurrence picker，详情无实例列表 | P2 |
| N10 | 状态与边界页 | 把 loading/empty/error/offline/permission/disabled 集中 | 纯原型用；生产应改为真实状态 | P3 |

---

## 3. 必须保留的真实约束（原型已遵守，落地不得违反）

| # | 约束 | 出处 | 原型对应 |
|---|---|---|---|
| K1 | 完成时仅 `startAt >= completedAt` 的安排失效；早于完成时刻的保留 | `DOMAIN_BEHAVIORS.md` I15.1 | `store.js` `completeTodo` |
| K2 | 安排从不改截止、从不创建 Event | I15.2 | `createAllocation` 只写 `allocations` |
| K3 | 重复待办父级永不 COMPLETED | I15.3 | `occurrenceStates` 按实例写 |
| K4 | 实例 ID 是墙上时钟身份 | I15.4 | `occurrenceIdFor` |
| K5 | 半开区间（含头不含尾） | I15.8 | `isAllocationLive` / `eventsOnDay` |
| K6 | 未安排的成员资格由「有效计划执行」决定，**不是** `dueDate == null` | `CORE_UX_SPEC.md` §1.3 / §16.2 | `plannedTodoIds()` + `inboxTodos()` |
| K7 | 截止不进时间格（截止 ≠ 执行） | SPEC §3.1 | 截止泳道 + 有测试断言 |
| K8 | 软删为默认；永久删除仅回收站 | I15.6 | 全部删除走 `deletedAt` |
| K9 | 删除日历不得产生孤儿（最后一个不可删） | I15.16 | `deleteCalendar` 返回 `{ok:false,reason:'only'}` |
| K10 | AI 提案须显式确认才写 | `DOMAIN_BEHAVIORS.md` §11 | 提案卡「应用/拒绝」+ 测试 |
| K11 | 今天页不得静默编造截止 | `CORE_UX_SPEC.md` §3.2 | 新建 chooser 二选一，不写 `dueDate` |

---

## 4. 与真实代码的**已知偏差**（原型有意简化，落地时按真实实现）

| # | 原型 | 真实 | 说明 |
|---|---|---|---|
| S1 | 附件只记录文件名 | 真实上传 + 失败回滚整笔事务 | 只定义「chip 可增删 + 保存后出现」 |
| S2 | ICS 导入导出、备份为模拟延迟 | 真实文件选择 + 解析 | 只定义入口与结果反馈 |
| S3 | 同步为 1.1s 模拟 | 真实 outbox + SSE | 只定义状态呈现 |
| S4 | AI 回复为本地规则 | 真实 BYO-key 调用 | 只定义「提案—确认—应用」结构 |
| S5 | 无 legacy 重复规则流程 | 真实有导入遗留规则确认 | 见 COVERAGE §7 |
| S6 | 无 widget / 通知栏 | 真实有 | 平台集成不在本轮 |
| S7 | 每台设备的语言/主题偏好持久化用 `localStorage` | 真实用 Drift/SharedPreferences | 原型只为刷新后保持 |

---

## 5. 建议的落地顺序（G2–G6）

1. **G2 交互契约**：D1（详情只读）、D3（统一返回）、§1.1（桌面 master-detail 与规范对齐）。这三项互相绑定。
2. **G3 收集与今日**：D7（今天页捕获框）、D6（上下文 chip）、N4（节奏条）。
3. **G4 列表操作**：N1（多选）、N2（滑动）、D9（实例删除撤销）、D10（取消安排确认）。
4. **G5 日程与安排**：D11（删除作用域收敛）、D12（实例编辑基准日）、N6、N7、N9。
5. **G6 状态与一致性**：N8（离线段）+ 全部空/错/禁用态按 `BEHAVIORS.md` 对齐。

---

## 6. 门禁建议（新增到 CI，供 G2 之后执行）

| 门禁 | 检查内容 | 防的是什么 |
|---|---|---|
| 交互契约守卫 | `lib/ui/pages/**/detail_page.dart` 不得出现 `TextField`/`onChanged` 直写 DAO | 详情重新变回内联编辑器（D1 回潮） |
| 单一编辑器守卫 | 除 composer/form 外不得直接调用 `todoWriter`/`eventWriter` 的更新入口 | 出现第二写点（D2 回潮） |
| 删除作用域守卫 | 任何 `excludeEventOccurrence` / `deleteEvent` 调用点必须走同一个作用域函数 | D11 回潮 |
| 撤销一致性守卫 | 所有删除路径的 snackbar 必须有 `SnackBarAction` | D9 回潮 |
| 截止/执行分离守卫 | `task_allocations` 写入路径不得触碰 `todos.dueDate` | K2 回归 |
| 未安排语义守卫 | 未安排查询不得以 `dueDate == null` 作为判据 | K6 回归 |
