# 自动化真实操作测试与结果 / Automated real-operation test results

全部测试都是**用浏览器真的点击/输入/拖拽**，然后断言数据与界面的实际结果；不是 DOM 快照，也不是只检查元素存在。

- 运行环境：macOS（darwin 27.2.0），Chromium 1243（`playwright-core` 1.56.1，本机缓存二进制）
- 视口：桌面 1440×900，手机 390×844
- 入口：`file://…/docs/design/interaction-model/index.html`
- 最近一次完整运行：2026-11-16

---

## 汇总

| 套件 | 内容 | 结果 |
|---|---|---|
| `tests/smoke.js` | 启动、无横向溢出、按钮都有可读名字、**手机触摸目标 ≥44px**、9 条路由可达、零控制台错误（桌面 + 手机） | **11 / 11 通过** |
| `tests/interactions.js` | 36 个端到端交互场景 | **36 / 36 通过** |
| `tests/surfaces.js` | 14 个功能面场景 | **14 / 14 通过** |
| `tests/reviewer-findings.js` | 第一轮 19 条 Reviewer 发现 + 1 条「以后」范围，逐条按原始复现步骤回归 | **20 / 20 通过** |
| `tests/reviewer-findings-r2.js` | 第二轮 20 条 Reviewer 发现（含 9 条 P1），逐条按原始复现步骤回归 | **20 / 20 通过** |
| `tests/reviewer-findings-r3.js` | 第三轮 12 条 P0/P1 + 12 条 P2/P3，逐条按原始复现步骤回归 | **24 / 24 通过** |
| `tests/reviewer-findings-r4.js` | 第四轮 7 条 P1 + 9 条 P2/P3（含 6 条新接缝），逐条按原始复现步骤回归 | **16 / 16 通过** |
| `tests/reviewer-findings-r5.js` | 第五轮 8 条 P1 + 11 条 P2 + 6 条 P3，逐条按原始复现步骤回归（含真实拖动与断点缩放） | **25 / 25 通过** |
| 合计 | | **166 / 166 通过，0 失败，0 跳过** |

`skipped = 0`：没有任何场景被跳过或注释掉。唯一一条 `note` 是测试侧的说明（鼠标拖动不会触发触摸滑动手势，该路径由同套件里的 touch 场景覆盖），不是跳过。

---

## 场景清单（名称即断言目标）

### A. 捕获与创建

| # | 场景 | 证明的行为 |
|---|---|---|
| 1 | action capture creates an unplanned todo and inbox entry counts it | 今天页捕获框 → 无截止待办 →「未安排」计数 +1 |
| 2 | todos quick add inherits the browsed day as deadline | 待办页快速添加继承所浏览日期的截止 |
| 3 | browsing another day in Todos does not move the Action day | 浏览日与「今天」互相独立 |
| 4 | composer creates a todo with a deadline that shows in Todos and Action | composer 建带截止待办 → 待办与 Action 同时出现 |
| 5 | composer type switch works on create and is locked on edit | 新建可切类型、编辑锁定类型 |
| 6 | composer blocks saving an empty title and explains why | 空标题：保存禁用 + 内联错误 + 不写库 |
| 7 | leaving a dirty composer asks before discarding and can be undone by cancelling | 脏表单关闭先确认，取消可留在原处 |

### B. 编辑、完成、删除、恢复

| # | 场景 | 证明的行为 |
|---|---|---|
| 8 | todo detail is read-only until Edit, and an edit propagates to every surface | 详情只读；显式编辑；改动同步到列表/Action |
| 9 | completing a todo moves it to the completed section and to Action earlier-today, and undo restores it | 完成 → 已完成区 + Action 早些时候；撤销复原 |
| 10 | deleting a todo moves it to Trash and restore brings it back with its data | 软删 → 回收站 → 恢复保留截止等数据 |

### C. 日历、安排、事件

| # | 场景 | 证明的行为 |
|---|---|---|
| 11 | creating an event from a calendar slot fills the grid and Action | 时间格 → 新建日程 → 格子与 Action 同时出现 |
| 12 | scheduling a todo from a slot creates an allocation that can be rescheduled | 时间格 → 安排待办 → 改期 |
| 13 | a scheduled todo shows its allocated time on the row and in its detail | 安排时段同时出现在行 meta 与详情 |
| 14 | completing one occurrence of a recurring todo leaves the series and other days intact | 重复任务按实例完成，系列与其它日期不受影响 |
| 24 | month view drills into a day and week view shows the same events | 月视图点格下钻；周视图同一批事件 |
| 25 | deadlines are listed in their own lane and never drawn as time blocks | 截止只进泳道，绝不进时间格 |
| 26 | cancelling a scheduled block removes the block but keeps the to-do | 取消安排不删待办，可撤销 |
| 32 | dragging an event block moves it and the toast undo puts it back | 拖动日程改期，时长不变，撤销真正复原 |
| 33 | dragging one occurrence of a repeating event asks the scope, and undo reverses it | 拖重复实例先问「这一次/以后/整个系列」，选「这一次」= exdate + 单次副本，撤销合并回去 |

### D. 搜索、筛选、边界

| # | 场景 | 证明的行为 |
|---|---|---|
| 15 | search finds a newly created item and opens its detail | 新建对象可被搜索到并打开 |
| 16 | search and lists explain empty results instead of showing blank space | 空结果有解释与可行动作 |
| 17 | the day list shows every row and offers no six-things cap | 今天列表不截断；六件事已按规范退役 |
| 18 | missed recurring instances beyond five are reachable from the overdue section | 逾期区不静默截断：超出 5 条的遗漏实例可展开/收起 |
| 19 | a very long title wraps without breaking the row or the page | 超长标题不撑破布局、无横向溢出 |
| 20 | opening a record that does not exist shows an error state with a way back | 缺失记录 → 错误页 + 返回 |
| 23 | tag filter narrows the list and clearing it restores every row | 标签筛选与清除 |

### E. 键盘、浮层、语言与主题

| # | 场景 | 证明的行为 |
|---|---|---|
| 21 | Escape closes the top overlay first and only then leaves the page | Esc 分层：浮层 → 菜单 → 页面 → 返回 |
| 22 | keyboard N opens a new to-do and / opens search | 全局快捷键 |
| 27 | adding a subtask from a parent detail keeps it out of the top-level lists | 子任务保存后回父详情，且不出现在顶层列表 |
| 28 | switching language and theme updates the shell immediately and persists across pages | 中英/明暗即时生效并跨页保持 |
| 29 | an AI proposal does not change data until the user applies it | AI 提案未确认前不写库 |

### F. 手机

| # | 场景 | 证明的行为 |
|---|---|---|
| 30 | mobile: bottom nav reaches every primary tab and a created item opens and returns | 底部 3 tab、新建、详情、返回全通 |
| 31 | mobile: tapping a calendar slot can create an event without leaving the calendar | 手机时间格建日程 |
| 34 | every route renders, and clicking its visible controls raises no errors | 12 条路由逐一点击全部可见控件，零控制台错误 |

### G. 独立 Reviewer 发现回归（`reviewer-findings.js`）

独立 Reviewer 以真实用户身份操作后给出 **FAIL** 与 19 条发现（1×P0、9×P1、7×P2、2×P3）。每条都按其原始复现步骤写成回归场景，修复后逐条通过：

| # | 严重度 | 发现 | 修复 |
|---|---|---|---|
| F1 | P0 | 删除重复日程的某一次 → 整个系列被软删 | 删除/编辑收敛到单一实现 `js/event-ops.js`，一律先问「这一次 / 以后 / 整个系列」；「这一次」= 加 exdate，系列存活 |
| F2 | P1 | 实例详情显示 00:00，编辑改到系列基准日 | 详情携带实例真实开始时间并标 `isOccurrence`；编辑实例走 `splitEventOccurrence`（exdate + 一次性副本） |
| F3 | P1 | 列表/详情勾选重复待办：不写库却报「已完成」 | 完成统一走 `js/todo-ops.js`：有实例就写实例，没有则警告不写 |
| F4 | P1 | composer 给重复待办排程产生看不见的幽灵安排 | 排程必须选实例（`schedule-occurrence`），否则不写并说明原因 |
| F5 | P1 | 子任务带截止后出现在 Action 顶层 | Action 投影排除 `parentId` 行（待办页早已排除） |
| F6 | P1 | 触摸端无法取消安排（只有桌面右键菜单） | 详情页每条生效安排带「取消安排」，两端同一路径 |
| F7 | P1 | 拖动后的「撤销」无效（先改值再存旧值） | 先捕获旧时间再改，撤销写回旧值 |
| F8 | P1 | 脏 composer 被侧栏/底部导航静默丢弃 | 新增 `App.leaveGuard`，任何离开 composer 的导航与 Esc 同一问句 |
| F9 | P1 | 捕获框/快速添加提交后失焦，连续输入丢失 | 渲染时保留 `data-testid` 焦点与光标位置；捕获后显式回焦 |
| F10 | P1 | 桌面删除日程后仍停在已删除记录 | 删除后若当前是详情则返回上一页（两端一致） |
| F11 | P2 | 完成的待办仍留在「现在」 | 「现在/稍后」排除已完成的待办；安排记录保留为历史 |
| F12 | P2 | 逾期区把超过 5 条的遗漏实例静默截断 | 区头计数为总数，5 条 + 「展开其余 n 项」/「收起」 |
| F13 | P2 | 详情值不可点改，只有铅笔 | 截止/优先级/标签/安排值整块可点开对应浮层 |
| F14 | P2 | 排程重叠保存后无警告 | 保存后 toast 追加「与 X 重叠」 |
| F15 | P2 | 改尺寸静默、无撤销，且实际没改 | 改尺寸只改结束时间、非静默、带撤销 |
| F16 | P2 | 排程快捷 chip 写入过去时间且预览不更新 | chip 写入未来时间并刷新预览，标签改为「今天/明天」 |
| F17 | P2 | 缺失的 event 记录导致白屏崩溃 | 与缺失待办一致的可恢复错误页 + 返回 |
| F18 | P2 | 浮层打开时按 T 把日历移到今天且浮层不关 | 有浮层时全局快捷键失效 |
| F19 | P3 | 「高亮新行」永不可见且指向错误行 | 高亮按 `id` 定位新行，跨 emit 重绘保留到动画结束 |

### H. 功能面（`surfaces.js`）
| # | 场景 | 证明的行为 |
|---|---|---|
| 1 | tags can be created, renamed and deleted with the delete warning | 标签增改删 + 删除警示 |
| 2 | calendars can be created and deleted, and a calendar with items asks what to do with them | 日历增删；有内容时询问处置；仅剩一个不可删 |
| 3 | a repeat rule set in the composer produces occurrences on later days | 重复规则产生后续实例 |
| 4 | a reminder added in the composer is saved and shown on the detail | 提醒保存并在详情显示 |
| 5 | selection mode can complete several rows at once and exit cleanly | 多选批量完成并干净退出 |
| 6 | trash purge is permanent and emptying trash clears every deleted row | 永久删除 / 清空回收站 |
| 7 | account sign-in validates input, signs in, syncs, and signs out | 账户校验/登录/同步/退出 |
| 8 | offline mode blocks sync and is visible in the shell | 离线阻断同步并在外壳可见 |
| 9 | hide-completed is driven from the Todo filter menu and persists | 隐藏已完成在待办页筛选菜单，跨页保持；设置里不再有第二处 |
| 10 | feedback rejects an empty message, accepts text, and about reports the version | 反馈校验；关于页版本 |
| 11 | the states bench shows loading, empty, error, permission and disabled states | 五类状态可查看 |
| 12 | turning notifications off changes the permission row instead of leaving a stale claim | 关闭通知后权限行不再撒谎 |
| 13 | mobile: swiping a row left deletes it with an undo path | 手机左滑删除 + 撤销 |
| 14 | desktop: dragging by the grip handle changes the stored order | 桌面抓手拖动改 `sortOrder` |

### I. 第二轮独立 Reviewer 发现回归（`reviewer-findings-r2.js`）

第二个独立 Reviewer 按同一标准重新操作后给出 **FAIL** 与 20 条发现（9×P1、8×P2、3×P3）。这批发现集中在**同一条写操作存在第二个实现**这一类缺陷上——批量路径绕过单条路径、块菜单绕过作用域入口、软删与恢复不对称。逐条按原始复现步骤回归，全部修复后通过。

| # | 严重度 | 发现 | 根因与修复 |
|---|---|---|---|
| R1 | P1 | 永久删除父任务后，子任务残留在回收站且永远无法恢复 | `purgeTodo` 用 `subtasksOf()`（只看**未删除**子任务），而软删父任务时子任务**已经**被删，于是整棵子树被漏掉。改为扫描全表 `parentId` 匹配并递归 |
| R2 | P1 | 批量完成重复待办不写库，却报「已完成」 | 批量路径直接调 `S.completeTodo(id)`，绕过了 `TodoOps` 的实例解析。改为在批量路径内解析 `occurrenceId`；无实例则计入 `skipped` 并如实提示 |
| R3 | P1 | 同一实例连续编辑两次 → 出现两份副本、两条 exdate | `splitEventOccurrence` 没有幂等性，`createEvent` 又丢弃未知字段导致 `splitFrom/splitAnchor` 从未持久化。两处都补上 |
| R4 | P1 | 排程实例下拉里能选到**已完成**的实例，选中后产生看不见的安排 | 下拉未过滤已完成实例；且原型 stub 未传 `occurrenceStates`，`isOccurrenceDone` 恒为 false。改为禁用+保存时拦截+传真实状态 |
| R5 | P1 | 从日历块菜单点「编辑」重复日程，不问作用域，直接改整个系列 | `blockMenu` 直接调 `App.openComposer`，绕过 `EventOps.editEvent`。改为委托 |
| R6 | P1 | 打开已删除的待办，显示成正常详情可编辑 | `todoById` 会返回软删行，`renderDetail` 未校验 `deletedAt`。改为与已删除日程走同一错误页 |
| R7 | P1 | 点「取消安排」同时弹出确认框和排程面板 | 按钮位于「点整块即编辑」的 `.v` 内，事件冒泡。补 `stopPropagation` |
| R8 | P1 | 手机上滑动手势完全无效 | `pointercancel` 被当成提交、缺 `touch-action`/指针捕获。三处都修 |
| R9 | P1 | 勾选重复待办的某次实例后，行仍留在未完成区 | 列表把重复系列当成"永远未完成"。`todosForDay` 增加 `doneInstances`，列表据此分区 |
| R10 | P2 | 「只看这一次」编辑保存后停在旧系列上 | 保存后跳系列 id。改为跳副本 id |
| R11 | P2 | 新建日程保存后网格里不高亮新块 | 高亮只匹配单一 testid，未覆盖跨界面形态。改为 `testids` 列表 |
| R12 | P2 | 从今天页新建的待办在今天就看不到自己 | 未安排预览只有计数行。按 `CORE_UX_SPEC` §16.2 补最多 3 行预览，并保证新条目总是可见 |
| R13 | P2 | 23:40 时快捷 chip 仍建议当天更早的时段 | 跨天判断缺失。改为 23 点后顺延到次日 |
| R14 | P2 | AI 提案安排的不是用户点名的那条待办 | 匹配失败时静默回落到「第一条未完成」并照常给出提案。改为按名字匹配，匹配不到时**在回复文案里明说** |
| R15 | P2 | 改了「启动时打开」却无效 | 启动页偏好从未被读取，也无任何持久化。补 `savePrefs/loadPrefs` 与 boot 读取 |
| R16 | P2 | 种子里的全天事件 start/end 是 Invalid Date | `at(2)` 传入 `h=undefined` 进 `setHours`。补 `h \|\| 0` |
| R17 | P2 | 设置里仍留着已退役的「六件事」「每周起始日」 | 未随规范清理。删除，并确认待办筛选菜单里没有第二处「隐藏已完成」 |
| R18 | P3 | English 模式下 AI 供应商列表仍显示中文 | `providerCustom` 缺英文键。补齐 |
| R19 | P3 | 拖动改时长后 toast 不说明改到了几点 | 只说「已调整」。改为报告新的结束时间 |
| R20 | P3 | 浏览器后退会静默丢弃脏草稿 | 没有 `popstate` 处理。补：后退也走 `leaveGuard` 同一问句 |

### J. 第三轮独立 Reviewer 发现回归（`reviewer-findings-r3.js`）

第三个独立 Reviewer 以真实用户身份重新操作，给出 **FAIL** 与 12 条 P0/P1、6 条 P2、7 条 P3。这批发现的共同点是**原型与冻结规范的实际偏离**，以及**跨层不同步**（数据层写完、界面层没跟上）。逐条按原始复现步骤写成回归场景。

| # | 严重度 | 发现 | 根因与修复 |
|---|---|---|---|
| P1-1 | P1 | 完成待办后点撤销，待办回来了，但它占用的时段永久消失 | `completeTodo` 的取消完成分支只回退状态，从未把 `invalidatedByCompletion` 的安排改回 `active`。两处（单条 / 重复实例）都补上反操作 |
| P1-2 | P1 | 多选「完成」会把已完成的重复实例**取消完成**，还报成功 | 批量路径没查 `isOccurrenceDone`，而 `completeTodo` 对已完成实例是切换语义。批量前先判断，已完成计入跳过 |
| P1-3 | P1 | 待办详情的「更多」是死按钮 | 点击冒泡到 document 的「点外部关菜单」处理器，菜单建完即被销毁。补 `stopPropagation`（与列表行菜单一致） |
| P1-4 | P1 | 手机上根本到不了设置 / 搜索 / AI / 日历管理 / 关于 | 底部导航只有 3 个目的地，工具全在桌面 rail 上。底部导航增加「更多」，内置全部工具入口 |
| P1-5 | P1 | 手机 128 个触摸目标小于 48dp | 之前只放大了 `.icon-btn`/`.btn`。改为一个权威规则覆盖所有控件；周条横向滚动保住 48px 格宽。**第四轮复测仍不达标**：日历块用伪元素扩展命中区会被 `overflow:hidden` 裁掉、并让相邻块互相抢点击；改为手机小时高 96px（30 分钟块本身就是 48px），不再用伪元素 |
| P1-6 | P1 | 桌面 1440 是单列，详情顶掉列表且没有可见出口 | 决策错误。按 `CORE_UX_SPEC` §4 与真实 v0.34.0 实现 master-detail：≥1180 时列表常驻、右侧详情窗格、可关闭、Esc 先关窗格、切目的地清选中 |
| P1-7 | P1 | 今天页把同一个待办画两遍（安排行 + 截止行） | 投影层没去重。截止区排除已有安排的待办，截止信息作为安排行的元数据 |
| P1-8 | P1 | 待办浏览日与日历锚点互不同步 | 三套独立日期。统一为单一 `browseDate`，待办按日期与日历共写共读；今天永远读时钟 |
| P1-9 | P1 | 远日期只能一周一周点，约 3 个月要点 12 次 | 日期副标题不可点。改为按钮 + 月/年选择器，两次操作可达任意日期 |
| P1-10 | P1 | 所属日历是原生 `<select>`，无颜色、无选中态、无新建；详情里是死行 | 实现统一日历选择器：颜色 + 名称 + 选中态 + 「+ 新建日历」，新建后回到选择器并选中 |
| P1-11 | P1 | 设置页直接显示裸 i18n 键 `manageCalendars` | 三个键（另两个是 toast）在两本字典里都不存在。补齐并加了全量键扫描 |
| P1-12 | P1 | 待办表单/详情不符合 §4.2 的分区与顺序 | 重构为 任务 / 时间（截止·重复·计划执行）/ 提醒 / 整理（日历·优先级·标签）/ 内容（备注·子任务·附件），详情同序 |
| P2-1 | P2 | 手机用悬浮按钮，规范明确禁止 FAB | 改为页头动作，手机只收标签不收位置 |
| P2-2 | P2 | `TaskAllocation` 被叫作「安排执行」 | 冻结词是「计划执行」，正文与提示一并改正 |
| P2-3 | P2 | 同步分组不解释自己是什么 | 补一段说明：通过自己的 DaySpark 同步服务器在多台设备间同步 |
| P2-4 | P2 | 备份合并写作「合并恢复」 | 规范要求「合并备份」（合并而非替换） |
| P2-5 | P2 | 两条 toast 显示裸键 | 补 `exportedTo` / `notificationPermissionAsked` |
| P2-6 | P2 | 新建表单一打开就报「请填写标题」 | 未触碰的表单不该被指责。保存仍禁用，错误提示等用户真正输入后再出现 |
| P3-1 | P3 | 捕获第 4 条时预览里看不到它 | 高亮指向字符串而不是记录 id。改为 `{id}`，新条目在超出 3 行时提到首位 |
| P3-2 | P3 | 搜索框里按 Esc 什么也不发生 | 全局 Esc 在输入框内被跳过。改为：没有浮层/菜单/草稿处理者时，Esc 一律返回 |
| P3-3 | P3 | 分区名与规范不一致（外观 / 稍后今天 / 今天要完成 / 逾期） | 改为 通用 / 接下来 / 今天截止 / 已逾期 |
| P3-4 | P3 | 时间格 sheet 多出第三个出口 | 当时按「规范只定义两个工作」移除了第三个。**v0.34.0 审计纠正了这一判断**：真实产品有第三个「新建并安排」（建待办并同时占用时段）。现已恢复为三个有名字的工作 |
| P3-5 | P3 | AI 提案「应用」可被同步双击写入两次 | 加幂等守卫：状态已应用/已忽略则直接返回，不依赖重绘 |

---

### K. 第四轮独立 Reviewer 发现回归（`reviewer-findings-r4.js`）

第四个独立 Reviewer 对 `79bd867` 给出 **FAIL**：7 条 P1、11 条 P2。共同根因是**视图闭包持有状态**、**删除/筛选后选择悬空**、以及**按「真实代码长什么样」而不是「用户能否命中」来验触摸目标**。逐条按 Reviewer 自己的步骤写成回归场景。

| # | 严重度 | 发现 | 根因与修复 |
|---|---|---|---|
| D1 | P1 | 任何重绘都会清空 composer 草稿，脏表单守卫也一起失效 | 草稿只活在视图闭包里，`App.render` 重建视图时从路由参数重新造。改为草稿存 `state.composerDraft` 并带路由键复用；脏标记写入草稿；离开/保存清空 |
| D2 | P1 | 在 composer 里新建日历会丢草稿，且新日历没被选中 | 建日历触发的 emit 重绘撞上 D1；新 id 只写进旧草稿。D1 修复后草稿跨重绘保留，回调把新 id 写入同一份草稿，选择器重开时选中 |
| D3 | P1 | 在窗格里删除后选中悬空；回收站永久删除会让待办页整页空白并抛错 | 删除只清数据不清选中；`buildPane` 不处理记录不存在。store 在软删/永久删除时清选中；详情对已删记录禁用完成与编辑；窗格对缺失记录显示可关闭的错误态；删除时留在列表而不是误用 `back()` |
| D4 | P1 | 浏览明天时勾重复任务，完成的是**今天**的实例 | `TodoOps.complete` 总按今天解析实例。行勾选把所在日传进去，按该日解析；该日不匹配规则则拒绝并说明 |
| D5 | P1 | 今天页把「已排期且今天截止」的重复待办画两遍 | 去重只覆盖非重复待办。实例行排除已有当天安排的同一待办，保留安排行为主行 |
| D6 | P1 | 手机 24 个控件仍小于 48dp（菜单、日历块、开关、色板、搜索、聊天、分段、toast、plan-bar） | 逐类修：菜单项 48、开关改成 48×48 带内绘轨道、色板 48、输入框 48、toast 按钮 48、分段最小宽 48；日历块不再用会被裁切/互抢的伪元素，手机小时高改为 96px |
| D7 | P1 | 表单里的「完成状态」会把整个重复系列标完成 | 系列本就不该有整体完成态。重复待办的编辑表单不渲染状态控件，保存也不写 `status` |
| D8 | P2 | 900–1179 宽的路由详情没有可见返回 | 返回按钮只在 `<900` 渲染。路由详情在任何宽度都显示返回；窗格不显示（它的路由仍是待办） |
| D9 | P2 | 今天跨午夜不翻页 | `actionDate` 只在启动时写一次。今天页每次按钟读取；另加跨午夜定时重绘 |
| D10 | P2 | 浏览器 Back 清了窗格选中但不重绘 | `popstate` 直接改 state。清选中后调用 `App.render()` |
| D11 | P2 | 筛选把选中的记录筛掉后，窗格仍显示它 | 渲染待办页前检查选中记录是否仍在当前可见集合，不在就清选中 |
| D12 | P2 | 今天页空态永远到不了 | 「未安排」入口无条件渲染。计数为 0 时不渲染，空态可达 |
| D13 | P2 | 子任务表单里的完成状态不保存 | 保存只在非子任务时写 `status`。改为所有非重复待办都写 |
| D14 | P2 | 给无截止待办设重复会凭空造出今天的截止 | repeat picker 直接写 `dueDate`。改为写 `startDate` 作为系列锚点，截止保持为空 |
| D15 | P2 | 浏览到别的年份时日期头不显示年份 | 日期头只用月日。年份与当前年不同时补年份 |
| D16 | P2 | 点搜索/聊天输入框的留白不聚焦输入 | 容器没有转发点击。两个容器都把点击转给字段 |
| D17 | P2 | 从工具页返回待办时窗格又回来了 | 只有一级目的地清选中。任何非待办路由都清窗格 |
| D18 | P2 | 快速添加预览显示 `[object Object]` | `U.fmtDuration` 返回对象，被直接塞进文本。改为格式化后的时长文本 |
| 附 | P2 | 菜单打开时按 Esc 不是关菜单，而是直接返回上一页 | `state.menu` 从未被赋值，Esc 分支永远不成立。Esc 直接检测 DOM 里的 `.menu` 并先关闭 |


### L. 第五轮独立 Reviewer 发现回归（`reviewer-findings-r5.js`）

第五个独立 Reviewer 对 `ce4972c` 给出 **FAIL**：8 条 P1、11 条 P2、7 条 P3。共同根因仍是**按今天解析实例**、**视图闭包持有 DOM**、**用视觉位置反推时间**，以及**新增交互与冻结 SPEC 的 IA 不一致**。P1 全部修复；P2/P3 中可落地的 17 条一并修复，逐条写成真实操作回归。

| # | 严重度 | 发现 | 根因与修复 |
|---|---|---|---|
| P1-1 | P1 | 浏览明天时批量完成，写的是今天的实例 | 批量路径按 `TodoOps.todayOccurrenceId` 解析。改为按视图的 `contextDay` 解析，并逐行校验规则 |
| P1-2 | P1 | 从浏览日打开详情点完成，写的还是今天 | 详情只拿到 todo，没有日期。`openRecord/selectPane/detail` 全链路携带 `day`，完成时按该日解析实例 |
| P1-3 | P1 | 手机 6 类控件有效命中仍 <48：编辑/删除重叠、Today 区块头溢出、toast 撤销 45、安排时间 42、15 分钟块 30、slot-hit 被压住 | 删掉 `.icon-btn.sm` 的负外边距；区块头允许换行并保证 48；toast 撤销补 `min-width`；提示文字 `pointer-events:none`；15 分钟块最小 48；P1-4 修好后 slot-hit 不再被压 |
| P1-4 | P1 | 手机日历把计划块画在错误时间（08:30 画到 10:00，越排越晚） | 手机规则把 `.block` 覆盖成 `position:relative`，与写入的绝对 `top` 叠加。删除该覆盖，块恢复绝对定位 |
| P1-5 | P1 | 折叠凌晨后，03:00 事件画在 06:00；拖 10px 被改写成 06:15 | 折叠只裁可见起点、整块隐藏完全落在折叠内的事件；拖动/缩放改为「原始时间 + 位移量」计算，不再用视觉 top 反推 |
| P1-6 | P1 | picker 打开时跨断点重绘，可见表单不更新但保存写隐藏值 | 重绘后 sheet 仍调用旧闭包的 `renderBody`。composer 发布 `live` 当前实例 API，所有 sheet 回调改走 `live.renderBody/validate/titleInput` |
| P1-7 | P1 | AI 给重复待办排时间写入 `occurrenceId=null`，提示成功但日历不显示 | 新增 occurrence 解析：找到请求日或之后首个匹配发生日；没有则明确拒绝，不写不可见行 |
| P1-8 | P1 | 桌面月视图双击永远打不开新建 | 单击同步重绘，第二击落在新节点上。桌面单击延迟 220ms，双击清除定时器并打开日程 composer |
| P2-1 | P2 | 表单承诺写入计划时间，实际因缺实例被静默丢弃 | 保存前从计划时间推导 occurrence；推导不出则校验阻止保存并保留草稿；保存标签只承诺真正会写入的字段 |
| P2-2 | P2 | 计划这一天在 09:00 后仍预填过去的 09:00 | 当天计划改为「当前小时 +1」，与快捷 chips 一致 |
| P2-3 | P2 | 只有今天页的完成行有内联撤销 | 撤销状态移入 `TodoOps.complete`；待办列表完成行也渲染 `todo-undo`，今天页继续显示 `action-undo` |
| P2-4 | P2 | 本周一/下周一算错，晚上 12 点算成中午 | 周计算改为周一起点；晚上 12 点归零为午夜 |
| P2-5 | P2 | 同步、新建日历、AI 配置里按 Enter 不提交 | 三个表单补 Enter 提交（输入框内） |
| P2-6 | P2 | 日历字段仍叫「日历」 | 新增 `ownCalendar: 所属日历`，表单、详情 fact、选择器标题统一 |
| P2-7 | P2 | 跟随系统语言跨会话不重新解析 | `loadPrefs` 在 `langPref=system` 时按浏览器语言重算 `lang` |
| P2-8 | P2 | Windows/Linux 被告知「网页版不支持通知」 | 权限行对所有平台显示；「网页版不支持」只在平台无法识别为原生/网页目标时出现 |
| P2-9 | P2 | 本周六 chip 文字写周六、值写周五 | 标签与值共用同一个日期计算（周一起点，周六为 0 偏移） |
| P2-10 | P2 | 英文日历管理页在 390 横向溢出 5px | 新建按钮的文字 span 补 `.label`，沿用窄屏图标化规则，并加 `aria-label` |
| P2-11 | P2 | + 待办打开的是完整五段表单，不是 Quick Create | 新建待办默认 Quick Create：标题、截止、所属日历（多日历才显示）、更多；「更多」展开完整五段。编辑与日程仍为完整表单 |
| P3-1 | P3 | 点搜索放大镜不聚焦 | 搜索框内除按钮外的点击都转发给输入框 |
| P3-2 | P3 | 移除配置的确认文案说「还没有配置 AI」 | 改用 `aiRemoveConfirm`，描述移除后果 |
| P3-3 | P3 | 日视图行内快速添加不说明写的是截止 | 上下文 chip 改为「截止 M月D日」 |
| P3-4 | P3 | 重复设置没有「重复开始」 | 重复面板新增开始日期，写 `startDate`，不伪造 `dueDate` |
| P3-5 | P3 | 远日期要点十余次 | 日期选择器新增直接日期字段，一次输入即跳转 |
| P3-6 | P3 | 「检测模型」只塞一个模型并提示连接正常 | 改为弹出检测到的模型列表供选择 |
| P3-7 | P3 | 手机上日历缩放把手只有 7px | 手机端提高到 24px |

---

## 复现方式

```bash
cd docs/design/interaction-model/tests
npm test    # 七套一起跑
# 或单独：
node smoke.js
node interactions.js
node surfaces.js
node reviewer-findings.js
node reviewer-findings-r2.js
node reviewer-findings-r3.js
node reviewer-findings-r4.js
node reviewer-findings-r5.js
```

任一断言失败会以非零码退出并打印失败场景与具体期望/实际值，可直接用于 CI。

---

## 本轮发现并修复的缺陷（定位 → 修改 → 重跑）

| 缺陷 | 根因 | 修复 |
|---|---|---|
| 每行待办都有一条 2px 暖色横线 | 外壳 `<main class="main">` 的 `.main::before` 规则同时命中了行内同名 span | 外壳类改名 `.app-main`，删掉装饰条规则 |
| 打开 composer 必崩（`getFullYear` of null） | 视图函数把路由参数当成了 `kindOverride` | 去掉参数，改从 `state.composer` 取 |
| Esc 静默丢弃草稿 | composer 未注册 escape 处理 | 加 `Registry.escapeHandler`，Esc 先问是否放弃 |
| AI 提案「已应用」状态在重绘后丢失 | 状态只存在闭包里 | 状态写回 `m.proposal.state`，按状态渲染 |
| 程序化导航后 sheet/遮罩残留并挡住点击 | `navigate/back` 未关浮层 | 导航统一 `closeAll/closeMenu/hideToast` |
| 多选批量完成后仍停在选择态 | 完成处理器没清 `multi.active` | 清理并重绘 |
| 抓手是死控件 | 只画了图标没有拖动逻辑 | 实现 `attachReorder` |
| Action 行是 `<button>` 里套 checkbox 的非法嵌套 | 结构错误 | 改为 `div role=button tabindex=0` + 键盘处理 |
| 设置页 `section` 深链无效 | 没有锚点 | 加 `data-section` 锚点并滚动定位 |
| 周视图从不滚到 07:00 | 时间格容器高度不受限，`scrollHeight === clientHeight` | 给 `.time-wrap` 限高 + 外层滚动兜底 |
| 详情 fact 的键值挤成一行（「提醒开始时」） | `.fact .body` 不是纵向排布 | 改 flex-column |
| 截止泳道 chip 被从词中间截断 | 横向滚动容器 | 改 `flex-wrap: wrap`；手机上改为单行横向滚动 |
| 手机行折成两行、FAB 盖住最后一行 | 行内信息过多 + 底部留白不足 | 手机上隐藏 chip/提示、`row-meta` 不换行、列表底部留 96px |
| 月视图手机上 chip 被截成「11:3…」 | 月格宽度不足以放时间+标题 | 手机上改为圆点 + 「+n」，点格下钻看当天 |
| 手机日历标题显示「2026年11月 · 11月16日」 | 桌面标题格式用在窄屏 | 窄屏改为「2026年11月16日」 |
| 设置行标题与说明挤在同一行 | `.setting-row .body` 缺纵向排布 | 改 flex-column |
| 15 分钟块里的时间文字被裁掉一半 | 块高 < 文字两行 | 矮块隐藏第二行 |
| 删除详情中的记录后仍停留在已删除详情 | 依赖 `isSplit()`（已废弃的双栏判定） | 删除后一律返回列表 |
| 表单校验错误在长表单底部，用户看不到 | 错误框放在字段末尾 | 移到标题下方（`role=alert`） |
| 页面切换后键盘焦点丢失 | 重绘替换了 DOM | 路由变化时把焦点移到页面标题 |
| 重复日程「周会」从不在自己的起始日出现 | 种子数据把 `byday` 写死为周一，起始日却是「明天」 | 由起始日推导星期 |
| 拖动日程后的「撤销」是假的 | `undo` 只重绘、没有反向操作 | 每个范围分支都捕获真实逆操作（恢复时间 / 删副本 + 还原 exdate / 还原 until） |
