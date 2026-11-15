# 关键操作行为定义 / Key-operation behaviour contract

每条操作写清三件事：**数据怎么变 → 界面怎么回 → 失败怎么办**。原型代码即实现，测试即证据（`tests/*.js` 的场景名对应下表编号）。

领域语义遵循 `SPEC.md`：`dueDate` 是截止（不是执行时间）、`TaskAllocation` 是可移动的执行时段、`Event` 占据时间。三者永不互相冒充。

---

## A. 全局

### A1 创建入口（唯一入口原则）
- **数据**：`composer` 路由，`kind` 在打开时确定；新建待办默认无截止、第一个日历、优先级 0；新建日程默认「今天下一个整点 + 1 小时」。
- **界面**：桌面从页头「新建待办/新建日程」；移动从右下 FAB；日历从时间格 sheet。保存后**回到打开它的地方**并高亮新行（`S.state.highlight`）。子任务例外：回父详情。
- **失败**：标题为空 → 保存禁用 + 内联错误，不写库。脏表单关闭 → 先确认「放弃修改？」。
- 证据：`interactions.js`「composer creates a todo…」「composer blocks saving an empty title…」「leaving a dirty composer…」

### A2 返回语义（唯一返回路径）
- **数据**：`history` 栈；`back()` 弹一层。
- **界面**：`Esc` 先关最上层浮层（sheet/modal/menu）→ 再关菜单 → 再交给页面自己的 escape 处理（composer 会先问是否放弃）→ 最后才返回上一页。`action` 是根，不返回。
- **失败**：无历史 → 回 `action`。
- 证据：`interactions.js`「Escape closes the top overlay first…」

### A3 页面切换清理
- **数据**：`navigate/back` 一律关闭全部 sheet/modal/menu 与 toast。
- **界面**：不残留遮罩、不残留可点击但看不见的层。
- **失败**：无。
- 证据：`surfaces.js` 全套（切换页面后仍可点击）。

### A4 今日 vs 浏览日
- **数据**：`actionDate` 只由 Action/「回到今天」写；`todosView.day` 只由周条/日历下钻写。两者独立。
- **界面**：Action 永远显示今天，页头无日期切换；待办页周条可看任意日，页头副标题显示所看日期。
- **失败**：无。
- 证据：`interactions.js`「browsing another day in Todos does not move the Action day」

---

## B. 待办

### B1 捕获（Action 捕获框）
- **数据**：`createTodo({summary})` → 无 `dueDate`、无 `startDate`、`status=NEEDS-ACTION`、`parentId=null`、无重复。即「未安排」。
- **界面**：输入框清空、保持焦点可连续输入；收件箱计数 +1；toast「已创建 …」带撤销。
- **失败**：空输入 Enter 无效。
- 证据：`interactions.js`「action capture creates an unplanned todo…」

### B2 快速添加（待办页）
- **数据**：day 视图 → `dueDate = 该日 00:00`（日期型，不显示 00:00）；Inbox/All → `dueDate = null`。
- **界面**：新行出现在对应分区；输入框清空并保持焦点。
- **失败**：空输入无效。
- 证据：「todos quick add inherits the browsed day as deadline」

### B3 完成 / 取消完成
- **数据**（非重复）：`status: NEEDS-ACTION → COMPLETED`，`completedAt = now`；**所有 `startAt >= completedAt` 的 active 安排 → `invalidatedByCompletion`**；早于完成时刻的安排保留为历史。取消完成：状态回退、`completedAt = null`，**不复活**已失效/已取消的安排。
- **数据**（重复）：只写 `occurrenceStates[occId].completedAt`，**系列本身永远保持 NEEDS-ACTION**；同样使该实例未来的安排失效。
- **界面**：行移到「已完成」区（Day 单区 / All·Inbox 按完成日分组）；Action 出现于「今天早些时候」；toast 带撤销（撤销 = 再调一次 `completeTodo`，即反操作）。
- **失败**：重复待办未给 `occurrenceId` → 警告 toast，不写库。
- 证据：「completing a todo moves it to the completed section…」「completing one occurrence of a recurring todo…」

### B4 删除 / 恢复 / 永久删除
- **数据**：删除 = `deletedAt = now`（软删），父待办删除时子任务一并软删。恢复 = `deletedAt = null`（保留截止、标签、安排等全部字段）。永久删除 = 行移除 + 其安排一并移除。
- **界面**：行立即从列表消失；toast 撤销；回收站出现该行（含删除时间）；恢复后回到原列表；永久删除有二次确认且不可撤销。
- **失败**：无（软删不会失败）。
- 证据：「deleting a todo moves it to Trash…」「trash purge is permanent…」

### B5 安排执行时间（不改截止）
- **数据**：新增 `TaskAllocation{todoId, startAt, endAt, state:active, occurrenceId?}`。**`dueDate` 不变，也不创建 Event**。
- **界面**：待办行 meta 出现时间区间；详情「执行时间」事实出现；日历出现虚线安排块；toast 带撤销（撤销 = 取消该安排）。
- **失败**：与已有安排/事件重叠 → 保存仍允许（手动排程不校验空闲），但 toast 警告「与 X 冲突」；重复待办必须先选实例，未选不写库。
- 证据：「scheduling a todo from a slot creates an allocation…」「a scheduled todo shows its allocated time…」

### B6 改期 / 取消安排
- **数据**：改期 = 改写 `startAt/endAt`；取消 = `state = cancelledByUser`（行保留，历史可见）。
- **界面**：块移动位置；取消后块消失、详情「历史安排」出现该条；toast 撤销。
- **失败**：结束 ≤ 开始 → 内联错误，不写库。
- 证据：「scheduling a todo… can be rescheduled」「cancelling a scheduled block removes the block but keeps the to-do」

### B7 详情只读 + 显式编辑
- **数据**：详情不写任何字段；只有点「编辑」进 composer 才写。内联可改的仅：截止、优先级、标签、备注（点值即开编辑浮层，保存即写）。
- **界面**：详情是事实清单（截止/执行/重复/优先级/标签/日历/提醒/父任务/实例/子任务/历史安排/备注/时间戳），底部「编辑」「移到回收站」。
- **失败**：改完即 toast「已更新」；无撤销（可再改回）。
- 证据：「todo detail is read-only until Edit…」

### B8 子任务
- **数据**：`parentId = 父 id`；子任务不出现在顶层列表、不计入收件箱、不计入六件事。
- **界面**：父详情列出子任务，可勾选、可点进；保存后回父详情。
- **失败**：标题为空不保存。
- 证据：「adding a subtask from a parent detail…」

### B9 排序
- **数据**：拖动后按可见顺序重写 `sortOrder = (i+1)*10`。
- **界面**：行立即换位；toast「顺序已保存」。
- **失败**：无。
- 证据：`surfaces.js`「desktop: dragging by the grip handle…」

### B10 多选批量
- **数据**：批量完成 = 逐条 `completeTodo`；批量删除 = 逐条软删（一次确认）。
- **界面**：选择条显示「已选 n 项」+ 全选/完成/删除/取消；操作后退出选择态；删除可撤销。
- **失败**：未选时完成/删除按钮禁用。
- 证据：「selection mode can complete several rows…」

### B11 左滑 / 右滑（触摸端）
- **数据**：左滑超阈值 = 软删；右滑 = 完成。
- **界面**：滑动露出背景提示（完成 / 删除），释放后执行；删除有 toast 撤销。
- **失败**：滑动不足阈值 → 回弹，不执行。
- 证据：「mobile: swiping a row left deletes it with an undo path」

---

## C. 日程（Event）

### C1 创建
- **数据**：`Event{summary, startDt, endDt, isAllDay, calendarId, location?, rrule?, tagIds, reminderOffsets}`。全天事件归零到 00:00–23:59。
- **界面**：时间格出现实心块；Action 对应时段出现；toast 撤销（撤销 = 软删）。
- **失败**：结束 ≤ 开始 → 内联错误 + 保存禁用。
- 证据：「creating an event from a calendar slot…」

### C2 拖动 / 改时长
- **数据**：拖动 = 改 `startDt/endDt`（保持时长，可跨日）；改尺寸 = 只改 `endDt`；15 分钟吸附。
- **界面**：块跟随移动，释放后落位；toast「已移到 …」带撤销。
- **撤销**：撤销是**真实逆操作**，不是重绘 —— 普通日程还原拖动前的 `startDt/endDt`；重复实例按所选范围分别还原（删副本 + 移除 exdate / 还原原系列 `until` / 平移回原位）。
- **失败**：重复事件的单次拖动 → 先问「这一次 / 以后 / 整个系列」；选「这一次」= 加 exdate + 建一次性事件。取消 sheet 不写任何数据，块弹回原位。
- 证据：`interactions.js`「dragging an event block moves it and the toast undo puts it back」「dragging one occurrence of a repeating event asks the scope, and undo reverses it」；重复作用域见 C4。

### C3 删除
- **数据**：单次日程 = 软删；系列 = 软删；单次实例 = 加 exdate（系列保留）。
- **界面**：块消失；toast 撤销（实例撤销 = 移除 exdate）。
- **失败**：无。
- 证据：`interactions.js` 删除路径 + 回收站恢复。

### C4 重复作用域
- **数据**：「这一次」→ `exdates += anchor` 且新建一次性事件；「以后」→ 原系列 `until = 前一天`，另起新系列；「整个系列」→ 平移原系列。
- **界面**：先弹作用域 sheet，选择后才写。
- **失败**：取消 sheet → 不写。

---

## D. 日历

### D1 点空白格
- **界面**：sheet 三个明确出口：新建日程（预填该时段）/ 安排待办（选待办→选实例→落位）/ 在此新建待办（预填执行时间）。
- **数据**：见 C1 / B5。
- **失败**：无可安排待办 → 空态 + 「在此新建待办」。

### D2 月视图下钻
- **数据**：点格子 → `calendarView='day'`、`calendarAnchor=该日`。
- **界面**：直接进入该日时间格。
- **失败**：无。
- 证据：「month view drills into a day and week view shows the same events」

### D3 截止泳道
- **数据**：只读投影；**截止待办永不进入时间格**。
- **界面**：日/周/月视图顶部泳道列出区间内截止事项，点进详情。
- **失败**：无。
- 证据：「deadlines are listed in their own lane and never drawn as time blocks」

---

## E. 搜索 / 标签 / 日历管理 / 回收站

| 操作 | 数据变化 | 界面返回 | 失败 |
|---|---|---|---|
| 搜索 | 只读；`searchQuery` 记住 | 结果分组（待办/事件）+ 高亮命中；点进详情 | 无结果 → 空态文案；空查询 → 引导文案 |
| 新建/改名/改色标签 | `tags[]` 增改 | 列表即时更新；计数随之变 | 空名 → 内联错误；重名 → 内联错误 |
| 删除标签 | 标签移除，并从所有待办/事件解绑 | 列表移除 | 二次确认 |
| 新建/改名/改色日历 | `calendars[]` 增改 | 列表即时更新 | 空名 → 内联错误 |
| 删除日历 | 空：直接删；有内容：**移动**到另一日历 或 **一并删除**；仅剩一个：禁止 | sheet 二选一；删除后条目重新归属 | 仅剩一个 → 无删除按钮 + 说明文案 |
| 恢复回收站 | 清 `deletedAt` | 行离开回收站 | 无 |
| 永久删除 / 清空 | 行移除（+ 子级） | 回收站清空 → 空态 | 二次确认，不可撤销 |

证据：`surfaces.js` 标签、日历、回收站三组。

---

## F. 设置

| 设置 | 数据 | 界面 | 失败 |
|---|---|---|---|
| 主题 / 主题色 | `theme`、`accent` | 立即全站生效并跨页保持 | 无 |
| 语言 | `lang` | 立即全站切换（含 rail、页头、按钮） | 无 |
| 默认页 | `defaultTab` | 下次启动生效（不打断当前） | 无 |
| 六件事 | `sixThings` | 待办页 chip 同步高亮，今日列表折叠 | 无 |
| 隐藏已完成 | `hideCompleted` | 所有待办视图的已完成区立即消失 | 无 |
| 每周起始日 | `weekStartsOn` | 周条与日历周视图重排 | 无 |
| 通知开关 | `notificationsEnabled` | 权限行同步变「已允许/未允许」 | 无 |
| 登录 | `account` 写入；校验 URL / 邮箱 / 密码长度 | 成功后出现同步行与设备行 | 任一不合法 → 字段错误，不写 |
| 立即同步 | `lastSync = now` | 状态行更新时间 | 离线 → 警告 toast，**不写 lastSync** |
| 退出登录 | `account` 清空 | 回到未登录表单 | 二次确认 |
| AI 配置 | `ai.provider/model/configured` | 设置与聊天页副标题同步 | 测试连接为模拟 |

证据：`surfaces.js`「switching language and theme…」「hide-completed…」「account sign-in…」「offline mode blocks sync…」

---

## G. AI 助手

- **数据**：**提案不写入**。用户点「应用」才执行 `run()`；拒绝则只标状态。会话仅内存。
- **界面**：助手回复 + 提案卡（应用/拒绝）；应用后卡片显示「已应用」且按钮消失，状态跨重渲染保持。
- **失败**：无 Key → 空态 + 「配置 AI」；发送中 → 输入禁用、显示输入中气泡。
- 证据：「an AI proposal does not change data until the user applies it」

---

## H. 跨页面一致性（同一事实只有一个来源）

| 事实 | 写入点 | 必须同步出现的界面 |
|---|---|---|
| 待办标题/截止 | composer、详情内联 | 待办列表、Action、日历泳道、搜索、子任务行 |
| 完成状态 | 行勾选、详情、批量、Action | 待办列表已完成区、Action 今天早些时候、rail 计数 |
| 安排时段 | composer、时间格 sheet、详情、改期 | 待办行、详情执行时间、日历安排块、Action 此刻/稍后 |
| 日程 | composer、拖动、改期 | 日历网格、Action、搜索、月视图 chip |
| 删除 | 行菜单、详情、滑动、批量 | 列表、Action、日历、搜索、回收站 |
| 标签 | 标签页、composer、行菜单 | 待办行 chip、筛选结果、标签计数 |

验证方式：每条写入场景的断言都跨 ≥2 个界面读取（见 `tests/interactions.js` 各场景末段的 `go(page, 'action')` 检查）。
