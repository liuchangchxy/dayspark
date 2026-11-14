# DaySpark Core UX Spec

> Status: FROZEN UX SPEC
> Baseline: `65ca360ab81c04189eb117df0ef3d8238068db88`
> Scope: Mobile + Desktop core product UX / IA only. No domain, sync engine, MCP, Widget, schema, or backend rewrite.

## 0. Product judgment

DaySpark's main problem is no longer missing capability. It is that the UI exposes domain objects and implementation modules more clearly than it exposes user jobs.

The product already has strong primitives: Todo, Event, TaskAllocation, recurrence, reminders, multiple calendars, sync, backup, AI, MCP. The core UX must turn those into three questions:

1. **今天** — What do I need to face and do today?
2. **日历** — When does something happen, and when have I planned to do a task?
3. **待办** — What tasks exist, and how do I organize/refine them?

The current user-facing term **“行动 / Action” is retired**. Internal names such as `AppTab.action` and `actionProjectionProvider` may remain. The projection remains; only the product model changes.

Todo 仍保留按日期浏览截止任务的能力，包括查看“今天”这一天；但它只是 **待办内部的日期筛选/视图**，不再作为第二个一级或侧栏导航目的地。两个不同层级的 “Today” 不能竞争同一个用户心智。

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

- **未安排** — pending Todo items that currently have **no effective planned execution (TaskAllocation)**. `dueDate` is not the criterion.
- **全部待办** — all pending Todo inventory.

Todo keeps its date browser / date strip, including the ability to view today's due items, other dates, and create into the selected due-date context. This is a filter/view inside Todo, not a second primary destination.

Do not add a second sidebar destination named “今天”.

The current `watchInbox()` implementation (`dueDate == null`) does not match the product meaning of **未安排**. Implementing this UX is allowed to change the view/query semantics so that planned Todos are excluded, without changing the data model.

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

When the same Todo has both a planned execution and a deadline on the same day, **do not default to two full rows**.

Preferred presentation:

- planned execution is the primary row, because “今天” is an execution surface;
- deadline is attached as secondary metadata, for example **15:00–16:00 写论文 · 截止 18:00**;
- if the deadline itself needs separate risk emphasis — for example an overdue or otherwise independently actionable deadline — it may also appear in the deadline/overdue section.

The projection may contain multiple facts; the UI should merge them when they describe the same user obligation.

The current “六件事” mode does not define a meaningful planning model; it only truncates the list after six items. It should not remain a primary Today concept.

---

## 3. Creation model

### 3.1 Creation meaning must be explicit

The rule is not “every `+` must open the same type chooser”.

The rule is:

> **The user must know what will be created before tapping the action.**

Context-specific direct creation is valid when the action is labelled clearly:

- **待办** page: **+ 待办** → directly opens Todo quick create.
- **日历** page: **+ 日程** → directly opens Event create in the viewed date/time context.
- **今天** page: the page genuinely contains both types, so use a neutral **新建** action that lets the user choose **待办 / 日程**, or expose two explicit actions if the layout supports it.
- Calendar time slot: keep the explicit jobs **新建日程** and **安排待办**.

Do not use the same naked `+` icon while silently changing its meaning between pages.

Quick creation may still use a shared component internally, but product semantics are contextual and explicit rather than forcibly identical.

### 3.2 No silent deadline fabrication

A new Todo with no explicit deadline remains undated.

Being on “今天” does not silently set its deadline to today.

If a context inherits a deadline, it must be visible as an editable chip such as **截止：10 月 23 日** before saving. An explicit due-date view may inherit that date.

### 3.3 Platform presentation

Mobile:
- **+ 待办** may open a Todo bottom sheet / compact full-width surface.
- **+ 日程** may open Event creation directly.
- **今天 → 新建** uses the two-type chooser because the context is genuinely ambiguous.

Desktop:
- keep labelled contextual create actions;
- use a compact anchored popover/panel where useful;
- keep Todo inline entry for fast batch capture.

Keyboard entry is worth keeping on desktop. The product target is explicit, predictable creation semantics, not pixel-identical controls.

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
| Inbox / current `watchInbox()` | **未安排** — requires query semantics based on effective planned execution, not `dueDate == null` |
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
| MCP / CLI | 后续独立产品化；不在 Core UX Spec 中冻结接入路线 |

The main product advantage to surface is the distinction between **deadline** and **planned execution**. That is already implemented in the domain and should become visible in Today, Todo, and Calendar.

---

## 10. MCP / ChatGPT

MCP / ChatGPT integration is **out of scope for this Core UX freeze**. DaySpark already has relevant backend capability; its user-facing connection/productization route will be designed and validated as a separate product task against the platform state at that time.

---

## 11. Priority

### P0 — product comprehension / core task completion
- User-facing Action → **今天**.
- Remove the competing Todo “今天” **navigation destination**, while preserving Todo date browsing.
- Define **今天 / 日历 / 待办** responsibilities.
- Make creation actions explicit and predictable by context.
- Redefine **未安排** by effective planned-execution state rather than `dueDate == null`.
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

First implementation PR is only **Core Shell + Create Semantics**:

1. Rename user-facing Action to **今天** while keeping internal domain/provider names.
2. Mobile bottom nav and desktop primary sidebar become **今天 / 日历 / 待办**.
3. Remove the duplicate Todo “今天” **navigation entry**, but keep `TodosDayView`, date browsing, date strip, and selected-date Quick Add behavior.
4. Rename **收件箱/待办箱 → 未安排**, **全部 → 全部待办**.
5. Change **未安排** query semantics: a Todo is unplanned when it has no effective planned execution; `dueDate` alone does not determine membership. This may change query/provider behavior but does not require a data-model change.
6. Make create actions explicit:
   - Todo: **+ 待办** → direct Todo quick create.
   - Calendar: **+ 日程** → direct Event create.
   - Today: neutral **新建** → choose **待办 / 日程**.
7. Preserve visible inherited context and never silently invent a Todo deadline.
8. Preserve existing domain writers/routes and do not change schema/sync.
9. Do not touch Todo form hierarchy, Settings IA, MCP, Widget layout, or notification behavior in this first PR.

Acceptance:
- A new user can explain the three primary destinations from their names and first screen.
- Todo still supports browsing due items by date without becoming a second primary “Today”.
- **未安排** excludes Todos that already have effective planned execution, even if they have no deadline.
- Before tapping a create action, the user knows whether it creates a Todo, Event, or opens the Today chooser.
- Creating a Todo never silently invents a deadline.
- Mobile and Desktop express the same product semantics.

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
- No new persisted business entity or data model. View/query semantics may change where required to match the frozen product meaning.
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
- Fast Todo/Event creation: explicit contextual create actions; Today uses a chooser because it is genuinely two-type.
- Todo time semantics: **截止 / 重复开始 / 计划执行**.
- Multiple calendars: grouping/color concept + always-accessible picker/create.
- Sync/backup/AI: explicit user-job Settings groups.
- Mobile/Desktop: same product model, platform-specific shell.
- Backend value: exposed mainly through Today projection and planned execution.
- Implementation handoff: split into bounded PRs; first PR is Shell + Create Semantics only.

## 15. A″ core interaction model (confirmed 2026-11-14, UI rolled back 2026-11-15)

> **Status**: the product/domain model below is confirmed. The UI that first implemented it (PR #101) was rolled back on 2026-11-15 after real use rejected its presentation layer. This section is a **design target** for the next production UI, not a description of the current build.

### 15.1 Date states

- **Today** is the real today, derived from the clock; it is never stored in a writable provider and never follows a browsed date.
- **`browseDate`** is the single browsed date shared by Todo · 按日期 and the Calendar.
- Switching tabs does not change `browseDate`; tapping a Calendar date does.
- Cold start: `browseDate` = today. Midnight: only Today rolls over. Foreground return never resets `browseDate`.
- Today's header reads the clock; browsing surfaces read `browseDate`.

### 15.2 Day projection

`DayProjection(date)` = Events ∩ date + active TaskAllocations ∩ date + Todos due that date + recurring occurrences + completed state.

Today additionally shows **Now / Upcoming / Overdue**. Those three never appear on another date.

A Todo that is both due that date and planned that date appears **once** in the App: the allocation is the primary row, the deadline is secondary metadata. This is a UI/projection rule; the domain keeps both fields. Widget dedupe is out of scope.

Today's **未安排** group previews only captured items with no `dueDate` (up to three). Its count keeps the allocation-based definition from §3.2; a dated unplanned item already has a home on its own date and does not appear in Today.

### 15.3 Routes and deep links

- Today: always the real today.
- Todo · 按日期: carries `browseDate` (`view=date|bydate`, optional `date=`).
- Calendar: `calendar?date=` writes `browseDate`.
- `quick-add?date=`: the date is capture context only; it never writes `dueDate`.
- Existing widget deep links keep working; `open/todos?view=today` lands on the real today.

### 15.4 Date selection

- Near dates: one tap on the strip.
- Far dates: date header → month/year picker → day (≤2 actions, internal scrolling does not count).
- The header always shows month and day; the year is shown when it differs from the current year, and always inside the picker.

