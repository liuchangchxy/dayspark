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
| `tests/smoke.js` | 启动、无横向溢出、按钮都有可读名字、9 条路由可达、零控制台错误（桌面 + 手机） | **11 / 11 通过** |
| `tests/interactions.js` | 34 个端到端交互场景 | **34 / 34 通过** |
| `tests/surfaces.js` | 14 个功能面场景 | **14 / 14 通过** |
| 合计 | | **59 / 59 通过，0 失败，0 跳过** |

`skipped = 0`：没有任何场景被跳过或注释掉。唯一一条 `note` 是测试侧的说明（鼠标拖动不会触发触摸滑动手势，该路径由同套件里的 touch 场景覆盖），不是跳过。

---

## 场景清单（名称即断言目标）

### A. 捕获与创建

| # | 场景 | 证明的行为 |
|---|---|---|
| 1 | action capture creates an unplanned todo and inbox entry counts it | Action 捕获框 → 无截止待办 → 收件箱计数 +1 |
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
| 17 | the six-things cap hides extra rows and expands and collapses reversibly | 六件事上限可展开/收起且可逆 |
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

### G. 功能面（`surfaces.js`）

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
| 9 | hide-completed and six-things settings change the list and persist across navigation | 设置改变列表并跨页保持 |
| 10 | feedback rejects an empty message, accepts text, and about reports the version | 反馈校验；关于页版本 |
| 11 | the states bench shows loading, empty, error, permission and disabled states | 五类状态可查看 |
| 12 | turning notifications off changes the permission row instead of leaving a stale claim | 关闭通知后权限行不再撒谎 |
| 13 | mobile: swiping a row left deletes it with an undo path | 手机左滑删除 + 撤销 |
| 14 | desktop: dragging by the grip handle changes the stored order | 桌面抓手拖动改 `sortOrder` |

---

## 复现方式

```bash
cd docs/design/interaction-model/tests
node smoke.js
node interactions.js
node surfaces.js
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
