# DaySpark Core UX Spec

> Status: REVIEW CANDIDATE  
> Baseline: `65ca360ab81c04189eb117df0ef3d8238068db88`  
> Scope: Mobile + Desktop core product UX / IA only. No domain, sync engine, MCP, Widget, schema, or backend rewrite.

## 0. Product judgment

DaySpark's main problem is no longer missing capability. It is that the UI exposes domain objects and implementation modules more clearly than it exposes user jobs.

The product already has strong primitives: Todo, Event, TaskAllocation, recurrence, reminders, multiple calendars, sync, backup, AI, MCP. The core UX must turn those into three questions:

1. **今天** — What do I need to face and do today?
2. **日历** — When does something happen, and when have I planned to do a task?
3. **待办** — What tasks exist, and how do I organize/refine them?

The current user-facing term **“行动 / Action” is retired**. Internal names such as `AppTab.action` and `actionProjectionProvider` may remain. The projection remains; only the product model changes.

The current Todo child destination **“今天” is also removed as a named destination**. Two different “Today” concepts must not compete.

---

## 1. Core information architecture

### 1.1 Primary destinations

| Product destination | Purpose | Not responsible for |
|---|---|---|
| **今天** | Cross-type daily agenda: current/next Event, planned Todo execution, due-today Todo, overdue obligations, recurring occurrences | Full task inventory; calendar management |
| **日历** | Time planning: Event + planned Todo execution + deadline markers | Task completion inventory |
| **待办** | Task inventory, capture, refinement, completion, filtering | Showing a time grid |

### 1.2 Mobile

Bottom Navigation is fixed:

**今天 / 日历 / 待办**

Do not support tab reordering. Stable navigation is more valuable than customization here. “启动时打开” may remain.

The global create button stays in a stable top-right position. Do not add a FAB just to follow a convention.

### 1.3 Desktop

Sidebar primary destinations are also:

**今天 / 日历 / 待办**

Under **待办**, secondary views are:

- **未安排** — pending top-level Todos with no deadline.
- **全部待办** — all pending Todo inventory.

Do not add a second sidebar destination named “今天”.

Calendar/tag management can remain secondary management destinations. Settings remains at the bottom.

---

## 2. “今天” page

“今天” is not a list and does not create a new persisted DailyPlan. It is the existing derived Action projection presented in user language.

First-glance hierarchy:

1. **现在** — currently active Event / planned execution, if any.
2. **接下来** — chronological Event and planned Todo execution.
3. **今天截止** — Todo deadlines due today.
4. **已逾期** — overdue obligations.
5. Compact shortcut: **未安排 N 项**.
6. Completed items stay folded/secondary.

Event, planned execution, and deadline must remain visually distinct:

- 日程: event marker.
- 计划: planned Todo execution.
- 截止: deadline marker.

A Todo may appear once as a planned execution and once as a deadline. That is correct because they represent different facts.

The current “六件事” mode does not define a meaningful planning model; it only truncates the list after six items. It should not remain a primary Today concept.

---

## 3. Creation model

### 3.1 One global create semantic

The visible global `+` always means **新建**. It must not secretly mean “Todo on this tab, Event on another tab”.

Opening it shows the same compact creation surface on every platform:

- Type: **待办 / 日程**
- Title, autofocus
- Context chips/fields that are visible before save
- **更多** opens the full editor with the draft preserved

Context may choose the initial type:

- 今天: default Todo
- 待办: default Todo
- 日历: default Event
- Calendar time slot: Event by default, with “安排待办” also available

The user can always switch type before save.

### 3.2 No silent deadline fabrication

A new Todo with no explicit deadline remains undated.

Being on “今天” does not silently set its deadline to today.

If a context inherits a deadline, it must be visible as an editable chip such as **截止：10 月 23 日** before saving. An explicit due-date view may inherit that date.

### 3.3 Platform presentation

Mobile: global `+` opens a bottom sheet / compact full-width surface.

Desktop: `+ 新建` opens a compact anchored popover or panel. Keep Todo inline entry for fast batch capture.

Keyboard entry is worth keeping on desktop. The product target is one quick-create semantic, not pixel-identical controls.

Widget Quick Add remains the smallest subset of this model. If Widget sets today as deadline, its landing copy must say **今天截止** rather than the ambiguous **今天**.

---

## 4. Todo UX

### 4.1 Three time concepts

#### 截止
Domain: `Todo.dueDate`.

Meaning: when the task must be finished.

It is not execution time and does not occupy calendar busy time.

User label: **截止**. Use date/time formatting as the value; do not make the field name “截止时间” when date-only is valid.

#### 重复开始
Domain: existing `startDate`.

Current DaySpark contract uses this mainly as the recurrence anchor. It is **not** a general “task becomes actionable from this date” feature.

Therefore:

- Do not show a standalone ordinary Todo field named “开始日期”.
- Put it inside Repeat setup.
- User label: **重复开始**.

A future Things-style generic start date would be a separate domain feature and is outside this UX round.

#### 计划执行
Domain: `TaskAllocation`.

Meaning: a real time block reserved to do this Todo.

User-facing noun: **计划执行**.  
User-facing action: **安排时间** / **安排到日历**.

It may occur multiple times. It appears on Calendar and Today, occupies busy time, and remains independent from deadline.

Never show “TaskAllocation” to ordinary users.

### 4.2 Todo information hierarchy

#### Quick Create
Visible by default:

- 标题
- optional visible 截止 chip
- optional 所属日历 only when context/multiple calendars makes it useful
- 更多

#### Full Create / Full Edit
Use the same section order on mobile, desktop full page, and desktop detail pane:

**任务**
- 标题
- 完成状态 when editing

**时间**
- 截止
- 重复
- 计划执行

**提醒**
- 提醒

**整理**
- 所属日历
- 优先级
- 标签

**内容**
- 备注
- 子任务
- 附件

Do not present every field as one flat uninterrupted form.

Todo Detail and New/Edit Todo must use the same terminology and section order. Auto-save vs explicit Save may differ, but information architecture must not.

Desktop master-detail keeps the list visible. Mobile uses a full detail page. Both expose the same capabilities; the desktop pane may collapse empty secondary sections to save width.

Subtasks must not exist only in the full form while disappearing from normal detail editing.

---

## 5. Calendar and multiple calendars

A DaySpark **日历** is a shared grouping/color context for Event and Todo. It is not the same as “scheduled time”.

Todo field label: **所属日历**.  
Event field label: **所属日历**.

When helpful, explain once:

> 日历用于分组和颜色；把待办真正排进时间轴，请使用“计划执行”。

Calendar picker behavior:

- Always opens, even when only one calendar exists.
- Shows color + calendar name + selected state.
- Always includes **+ 新建日历**.
- Creating a calendar returns to the picker and selects the new calendar.

Settings destination title: **日历管理**.

New Chinese installs should use **个人** as the default calendar name instead of literal **Personal**. Do not silently rename an existing user-created calendar unless it can be identified as the untouched system default.

Calendar view semantics stay:

- 日程 occupies time.
- 计划执行 occupies time.
- 截止 is a non-busy deadline lane.

Clicking an empty time slot keeps the two real jobs: **新建日程** and **安排待办**.

---

## 6. Terminology

| Current/internal | Final Chinese |
|---|---|
| Action | **今天** |
| Inbox | **未安排** |
| Six Things | **retire from primary product UI** |
| Calendar | **日历** |
| Personal | **个人** |
| Manage Calendars | **日历管理** |
| Deadline | **截止** |
| Start Date | **重复开始** (only inside recurrence) |
| TaskAllocation | **计划执行** |
| Schedule Todo | **安排待办 / 安排到日历** |
| ICS | **日历 .ics 导入/导出** |
| Backup | **DaySpark 完整备份** |
| Account | **同步** |
| Sync | **同步** |
| AI Assistant | **AI 助手** |
| All Tasks | **全部待办** |

Do not use “台历” for `.ics`.

---

## 7. Settings IA

Settings must be organized by user jobs, not source modules.

### 通用
- 主题
- 强调色
- 语言
- 启动时打开

Accent colors should be compact. Mobile may wrap/horizontally present swatches; desktop should not spend a large vertical block on them.

Do not add Bottom Navigation / Sidebar reordering.

### 日历
- 日历管理

Expose this entry on both mobile and desktop Settings. Desktop may additionally keep the sidebar shortcut.

### 同步
Replace **账号**.

Logged out copy must explain that this is DaySpark multi-device sync through a DaySpark Sync Server.

Fields:
- **同步服务器**
- 邮箱
- 密码
- 登录
- 注册

Do not make “服务器地址” appear without explanation and do not imply an official DaySpark cloud account if none exists.

Logged in:
- current account/email
- server
- last sync state
- connected devices
- 立即同步
- 退出

### 数据
Split into two clearly labelled subgroups.

**日历数据交换**
- 导入 .ics
- 导出 .ics / 导出全部日历

**DaySpark 备份**
- 导出完整备份
- 合并备份

Because the current restore behavior is merge/upsert, user-facing copy should say **合并备份**, not “恢复” if that would imply replacement.

### AI 助手
Remove the current:
高级功能 → ExpansionTile → AI 助手 → AI 配置 → Dialog nesting.

Top level:
- **启用 AI 助手** switch
- status/configuration row when enabled
- provider/model summary
- API key / endpoint under configuration

Ordinary users should not see every provider field before choosing to enable AI.

### 通知与提醒
Keep only platform-relevant controls:
- 通知权限
- 精确定时 permission where required
- 闹钟/提醒 sound behavior

Do not redesign the notification engine in this round.

### 关于
Version, update, feedback, licenses.

### Todo-only display preferences
“隐藏已完成” belongs to the Todo page's display/filter menu, not global Settings.

“六件事” should be removed from Settings and primary Todo/Today controls. Preserve old persisted preference only if needed for compatibility; do not build new product logic around it.

---

## 8. Visual hierarchy

This is not a new design system. Use only these rules:

- **Page Header**: one clear page title; optional one-line context/subtitle. Avoid breadcrumb + duplicate large title.
- **Section**: separate major groups mainly with whitespace and section labels.
- **Card**: use only when a group truly behaves as one object/status block. Do not wrap every Settings group in a card.
- **Row**: one primary label, optional secondary explanation/value, one trailing control.
- **Divider**: only between sibling rows when needed. Do not combine Card borders plus dense dividers everywhere.
- **Spacing**: use the existing spacing scale; favor 8/16/24/32 rhythm rather than local one-off gaps.
- **Primary Action**: one dominant action per surface.
- **Form hierarchy**: essential fields first; secondary capabilities grouped and progressively disclosed.

Touch targets remain at least 48dp on mobile. Desktop may be denser without shrinking critical click targets into icon-only traps.

---

## 9. Existing backend capability → product capability

| Existing capability | Product expression |
|---|---|
| Action Projection | **今天** cross-type agenda |
| TaskAllocation | Todo **计划执行** + Calendar **安排待办** |
| recurring Todo/Event | **重复**; occurrence complexity stays behind the UI |
| reminders | Todo/Event **提醒** section |
| multiple calendars | **所属日历**, color grouping, picker with create |
| tags | Todo organization + filtering |
| sync | Settings **同步**, device/status visibility |
| ICS | **日历数据交换** |
| full backup | **DaySpark 备份** |
| AI | simple **AI 助手** enable/configuration |
| MCP / CLI | later **集成 / 开发者** route; not primary product IA |

The main product advantage to surface is the distinction between **deadline** and **planned execution**. That is already implemented in the domain and should become visible in Today, Todo, and Calendar.

---

## 10. MCP / ChatGPT route

Current DaySpark backend is already unusually close to a real integration product:

- remote HTTP MCP
- OAuth
- read/write tools
- TaskAllocation workflow tools
- public-HTTPS deployment model

The repository's current ChatGPT setup text is no longer the final target product UX.

Separate later route:

1. Add a DaySpark **集成** onboarding page that shows MCP endpoint, OAuth readiness, server reachability, and read/write scope explanation.
2. Validate DaySpark against the then-current ChatGPT custom MCP/plugin flow.
3. Package and submit DaySpark as a public ChatGPT plugin/app so ordinary users do not have to understand MCP URLs.
4. Keep self-hosted OAuth sign-in as the account connection.
5. Treat manual custom MCP connection as a developer/admin path, not the consumer path.

No MCP server rewrite is part of Core UX implementation.

---

## 11. Priority

### P0 — product comprehension / core task completion
- User-facing Action → **今天**.
- Remove competing Todo “今天” destination.
- Define **今天 / 日历 / 待办** responsibilities.
- Unified global create semantic.
- Deadline / Repeat Start / Planned Execution semantics.
- Todo form/detail hierarchy.
- Calendar concept + picker with **+ 新建日历**.
- Settings: **同步**, ICS vs backup, flattened AI settings.
- Core Chinese terminology.

### P1 — efficiency / prevent misunderstanding
- Retire Six Things from primary UI.
- Move Hide Completed to Todo display controls.
- Default new-calendar name **个人**.
- Desktop quick-create keyboard entry and compact presentation.
- Todo Detail capability parity, including subtasks.
- Widget landing copy aligned with deadline semantics.
- Compact Appearance layout.

### P2 — visual polish
- Brand expression.
- Exact density/spacings after real device review.
- Card/divider cleanup beyond core screens.
- Animation/micro-interaction polish.
- Secondary empty states and decorative refinements.

---

## 12. Mobile vs Desktop

Same product logic, different shell.

**Mobile**
- Bottom nav.
- full-screen details.
- bottom-sheet quick create.
- touch-first 48dp targets.
- lower information density.

**Desktop**
- persistent sidebar.
- master-detail where width permits.
- anchored quick-create panel/popover.
- inline Todo entry remains useful for batch capture.
- keyboard operation and denser rows.

Do not force pixel identity.

---

## 13. First implementation slice

Do **not** implement all P0 items in one PR.

First implementation PR is only **Core Shell + Create Model**:

1. Rename user-facing Action to **今天** while keeping internal domain/provider names.
2. Mobile bottom nav and desktop primary sidebar become **今天 / 日历 / 待办**.
3. Remove the duplicate Todo child destination “今天”.
4. Rename Todo views **收件箱/待办箱 → 未安排**, **全部 → 全部待办**.
5. Make the existing global `+` open one unified compact create surface with **待办 / 日程** type selection and visible inherited context.
6. Preserve existing domain writes and routes; no schema/provider/sync changes.
7. Do not touch Todo form hierarchy, Settings IA, MCP, Widget layout, or notification behavior in this first PR.

Acceptance:
- A new user can explain the three primary destinations from their names and first screen.
- The `+` has the same meaning everywhere.
- Creating a Todo never silently invents a deadline.
- Calendar context can default to Event without hiding the Todo option.
- Mobile and Desktop express the same creation semantics.

After this PR is accepted, the next bounded implementation slice is Todo time/form + Calendar picker, then Settings IA.

---

## 14. Explicit non-goals

- No backend/domain/schema rewrite.
- No new DailyPlan / My Day entity.
- No generic Things-style Start Date feature.
- No sync-engine rewrite.
- No MCP rewrite in this UX round.
- No Widget redesign.
- No notification-engine redesign.
- No navigation reordering.
- No new business capability.
- No large Design System.
- No broad legacy cleanup.
- No assumption that desktop is already correct.
- No forced pixel parity across platforms.

---

## 15. Review gate

This UX spec is ready to become canonical only after product review approves these decisions.

Before code implementation, update the canonical requirements in `SPEC.md` where this document changes user-facing product behavior, following `AGENTS.md`'s SPEC-first rule.

Review questions are now answered:

- First-open structure: **今天 / 日历 / 待办**.
- Fast Todo/Event creation: unified quick-create surface.
- Todo time semantics: **截止 / 重复开始 / 计划执行**.
- Multiple calendars: grouping/color concept + always-accessible picker/create.
- Sync/backup/AI: explicit user-job Settings groups.
- Mobile/Desktop: same product model, platform-specific shell.
- Backend value: exposed mainly through Today projection and planned execution.
- Implementation handoff: split into bounded PRs; first PR is Shell + Create only.
