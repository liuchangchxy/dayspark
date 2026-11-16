# Independent Review — Round 4

Reviewer: independent (no prior involvement). Date: 2026-11-16.
Authority: `docs/CORE_UX_SPEC.md` (v0.34.0, frozen). The prototype's own docs (`TEST_RESULTS.md`, `BEHAVIORS.md`, `COVERAGE.md`, `REVIEW_ROUND3.md`) were treated as claims, not evidence.

## Snapshot under review

The worktree changed while I was reviewing: another process added `js/quick-add.js`, `js/views/quickadd.js`, a three-axis Todo filter sheet, a `plan-bar`, and edits to `detail.js`/`settings.js`/`library.js`/`store.js`, all uncommitted. I therefore report against a pinned snapshot and re-ran every headline finding on it.

- Commit: `79bd867` (`docs(g0): align the six deliverables…`), parent of the concurrent edits.
- Working tree as of 2026-11-16 09:30 CST, with these hashes:

```
f39aa60e…  index.html
d93e3be9…  js/views/composer.js
a406469f…  js/views/todo.js
597f222f…  js/views/action.js
7449df9d…  js/app.js
b894a066…  js/views/detail.js
c34a16a6…  css/app.css
```

- All P1/P2 findings below were re-run against that snapshot after the concurrent edits and still reproduce. The added quick-add route was also exercised (see D18).

## Method

- Own Playwright scripts in `/tmp/review4/` (playwright-core 1.56.1, Chrome for Testing 1243). No prototype test was trusted or reused.
- Viewports: 1440×900, 1200×860, 1180×860, 1179×850, 1024×800, 1000×860, 900×850, 899×800, 390×844.
- Surfaces: 今天, 日历 (月/周/日), 待办 (日/全部/未安排, quick-add, 选择模式, filter sheet, 计划这一天), Todo detail (page and pane), Event detail, composer (create/edit, todo/event), 快速添加, 搜索, 标签, 日历管理, 回收站, 设置 (all groups), 关于, 反馈, 状态与边界, AI 助手, and every sheet/menu.
- Flows: complete/undo, delete/restore/purge, batch complete/delete, recurring occurrence tick, split occurrence, drag/resize blocks, browse-date sharing, breakpoint resizing mid-session and mid-draft, browser Back, offline, empty/disabled/error states, console errors and horizontal overflow on every route.

## Claimed fixes

| # | Claim | Verdict | Evidence (latest snapshot) |
|---|---|---|---|
| 1 | Undo after completion restores the invalidated allocation | **Reproduced** | Real UI: tick 回复客户邮件 in 全部待办 → allocation `active → invalidatedByCompletion`; click toast `撤销` → status `NEEDS-ACTION`, allocation back to `active`. Re-ticking the row (no toast) restores it too. |
| 2 | Batch 完成 no longer un-completes an already-done occurrence | **Reproduced** | Tick 读 20 页 for today → 选择 → 全选 → 完成: occurrence stays done, series stays `NEEDS-ACTION`, no completed todo is reopened. |
| 3 | Todo detail 更多 opens its menu | **Reproduced** | 1440 and 390: 编辑 / 安排时间 / 添加子任务 / 复制标题 / 移到回收站. |
| 4 | Mobile 更多 reaches Settings / Search / AI / Calendars / Trash / Tags | **Reproduced** | 390: menu has 快速添加, 搜索, AI 助手, 标签, 日历管理, 回收站, 设置; all six required destinations land on their route. |
| 5 | All phone touch targets ≥48dp (effective hit area) | **NOT reproduced** | 24 distinct offenders / 44 instances at 390. See D6. The author's P1-5 test trusts `::after` height without hit-testing, and `::after` is clipped by `overflow:hidden` on calendar blocks; it also samples only 今天/待办/日历 + one detail. |
| 6 | Desktop ≥1180 master-detail; list stays; pane with close; Esc closes; destination change clears; mobile full-page | **Reproduced with defects** | At 1180: pane opens beside the list, close works, Esc closes, 今天/日历/待办 clears it, 899 falls back to a full-page detail with back. Defects: D3 (dangling selection after pane delete), D10 (Back clears state without re-rendering), D8 (no pointer exit at 900–1179), D17 (tool destinations keep the pane). |
| 7 | Today shows a planned-and-due todo once, allocation primary, deadline metadata | **Reproduced for non-recurring; NOT for recurring** | 写 v0.29 发布说明: one `action-allocation` row, meta 安排时间 · 截止 11月16日 18:00. 读 20 页《设计中的设计》 (recurring, due 22:00, allocated 21:00): **two** rows — `action-allocation` and `action-instance` in 今天截止 (D5). |
| 8 | Todo and Calendar share one browse date; Today always reads the clock | **Partial** | Sharing verified both directions and through week/month paging; Today's `actionDate` stayed on the real today while browseDate was Dec 15. But Today never rolls at midnight (D9). |
| 9 | Todo date subtitle opens a month/year picker | **Reproduced** | Subtitle is a `<button>`; sheet 跳到日期 with «/‹/›/» and 42 day cells at 1440 and 390; year navigation 2026 → 2027. |
| 10 | 所属日历 is a picker with colour, selected state and + 新建日历, in composer and detail | **Partially reproduced** | Both surfaces open a sheet with colour dots, `aria-pressed`, and 新建日历; picker opens with one calendar. **But** creating a calendar mid-compose destroys the draft and does not select it (D2). |
| 11 | No raw i18n keys anywhere in Settings | **Reproduced** | Visible-text scan for camelCase keys, zh and en, all 12 routes (plus 快速添加): zero hits. |
| 12 | Todo form and detail use 任务 / 时间 / 提醒 / 整理 / 内容 | **Reproduced** | Composer: 任务, 时间, 提醒, 整理, 内容 (both viewports). Detail: 时间, 提醒, 整理, 内容; 任务 is the title + completion control. |

## Remaining defects

### P1 (blocking)

**D1 — Any re-render destroys the composer draft, including the dirty-guard.**
Repro (1440): 待办 → 新建待办 → type a title and notes → resize 1440 → 1000 (crosses 900). Title and notes come back empty, composer stays open, and closing it no longer asks to discard. Same wipe on theme/accent/language/hide-completed emits and on D2. Root cause: draft lives in the view closure (`js/views/composer.js:71`) while `App.render` rebuilds `#view` from route params (`js/app.js:30-40`); `draftFromRoute` never restores an in-flight draft.

**D2 — Creating a calendar mid-compose loses the draft and does not select the new calendar.**
Repro (1440): 新建待办 → title `我的草稿标题` → 截止 11月16日 18:00 → 所属日历 → 新建日历 → `新日历Q` → 创建. Result: title `""`, deadline time lost (`11月16日`), picker still 个人; saving files under 个人. Falsifies the brief and `CORE_UX_SPEC.md` §5 ("Creating a calendar returns to the picker and selects the new calendar").

**D3 — Pane selection survives deletion; a trashed record still accepts writes; purging it blanks Todo.**
Repro (1440, pure UI): 待办 → click row → pane → 移到回收站 → confirm. Route jumps to 今天 (`action`, a `back()` into history that the pane never pushed) and `paneSelection` still points at the deleted id. Rail 待办: the pane shows the trashed record (now with a deleted banner) but **完成 is still live** — clicking it writes `status=COMPLETED` to the deleted row. Then 回收站 → 永久删除 → 待办: `#view` has **0 children** plus `pageerror: Cannot read properties of null (reading 'status')` at `js/store.js:298` ← `detail.js:59` ← `todo.js:726`. Recovery needs a round-trip through another destination. Same blank state when deleting a calendar with contents that held the selected record. (The new deleted-banner is a partial mitigation; it does not gate the writes or clear the selection.)

**D4 — Ticking a recurring todo while browsing another day completes today's occurrence.**
Repro (1440): browse tomorrow → tick 每日站会记录. Toast says 已完成; the tomorrow row stays unchecked; Today's 今天截止 row becomes checked. `TodoOps.complete` resolves `todayOccurrenceId` (`js/todo-ops.js:10-26`) instead of the browsed day's occurrence.

**D5 — Today shows a recurring planned-and-due todo twice.**
Repro (seed): 读 20 页《设计中的设计》 appears as `action-allocation` (21:00, meta 安排时间 · 截止 11月16日 22:00) and as `action-instance` in 今天截止. `CORE_UX_SPEC.md` §2/§16.2: one obligation, one row, allocation primary.

**D6 — Phone touch targets are not ≥48dp.**
Measured at 390×844 by edge hit-probing (union of points that still hit the control), every route, detail top/bottom, composer, all sheets and menus:

| Control | Painted | Effective |
|---|---|---|
| Row 更多 / detail 更多 / bottom-nav 更多 menu items | 168×32 | 168×32 |
| Calendar allocation block | 87–171×30 | same |
| Calendar all-day chip | 96×22 | 96×22 |
| 计划这一天 plan-bar (new) | 200×35 | 200×35 |
| Settings accent swatches | 30×30 | 37×43 |
| Settings switches (农历, AI, alarm, exact alarm) | 38×22 | 38×22 |
| Search input | 312×20 | 312×20 |
| Chat textarea | 284×24 | 284×24 |
| Segmented buttons (theme, language, default tab, scope) | 47×48 | 47×48 |
| Toast 撤销 / 关闭 | 37×26 / 22×22 | same |
| 状态与边界 "模拟离线" | 46×17 | 46×17 |

Root causes: `.menu button` keeps `min-height:32px`; `.block`/`.month-event` are `overflow:hidden`, clipping the `::after` box; `.switch`/`.swatch` are never enlarged; inputs keep 20/24px line boxes; `.segmented button` is 47px wide; `.plan-bar` has no mobile minimum. Tapping a Settings row label also does not toggle its switch.

**D7 — Composer 完成状态 on a repeating todo completes the entire series.**
Repro: edit 每日站会记录 → 状态 → 已完成 → 保存 → `status=COMPLETED`, `completedAt=now`, `occurrenceStates={}`; every future occurrence disappears because `pendingTodos()` filters on `isOpen`. Every other surface completes per occurrence.

### P2 (record, do not block)

**D8 — Detail at 900–1179 has no visible pointer exit.** `openRecord` navigates to a full-page detail; `detail.js` renders a back chevron only when `U.isNarrow()` (<900), and the pane exists only at ≥1180. At 900/1000/1179 the head is just 更多. Escape and the rail work.

**D9 — Today does not roll over at midnight.** `state.actionDate` is set once in `seed()`. Advancing the clock 24h leaves `actionDate` on the previous day and the header unchanged. `CORE_UX_SPEC.md` §16.1: "Midnight: only Today rolls over."

**D10 — Browser Back clears the pane selection without re-rendering.** The `popstate` handler sets `state.paneSelection = null` directly (`js/app.js:281`) and emits nothing; the pane lingers until an unrelated render.

**D11 — Filtering the selected record out of the list leaves an orphan pane.** Select 预约牙医 in 全部待办, then filter by tag/calendar/priority: the row disappears, the pane keeps showing it. Same after an edit that moves the record to another day.

**D12 — Today's empty state is unreachable.** The 未安排 row is pushed unconditionally (`js/views/action.js`), so the `emptyState` branch never runs; purging every todo/event still shows capture + rhythm + `未安排 · 0 项`.

**D13 — Composer 完成状态 on a subtask is live but ignored on save.** Editing 写一页结论 shows 状态 with 已完成 and Save enabled; saving leaves `status=NEEDS-ACTION` (status only serialized when `!draft.parentId`).

**D14 — Repeat on an undated todo sets a deadline to today.** 新建待办 with 无截止 → 每天 → 截止 chip becomes 11月16日; saved todo gets `dueDate=today`. Visible before save, but contradicts `CORE_UX_SPEC.md` §3.2.

**D15 — Date header omits the year when browsing another year.** Todo subtitle at 2027-11-01 reads `11月1日 · 周一`; §16.4 requires the year when it differs.

**D16 — Search/chat containers do not forward taps to their fields.** Tapping the search-box padding leaves focus on BODY; same for the chat input container. Only the 20/24px field itself is hittable.

**D17 — Pane selection survives a tool-destination change.** Todo pane → rail 设置 → rail 待办: the pane returns with the same record. Claim 6 says changing destination clears it; primary destinations do, tools do not.

**D18 — Quick add preview prints `[object Object]`.** 快速添加 → `明天下午三点 开会` → preview shows `…15:00 – 16:00[object Object]`: `U.fmtDuration` returns `{h,m}` and is passed to `text` (`js/views/quickadd.js:111`). The preview is the feature's promise, so it must read correctly.

### P3 (cosmetic / prototype-only)

- Week view page title is month-year, so paging one week inside the same month leaves the title unchanged (browseDate does move).
- 状态与边界 controls (重试/请求权限) only toast; appropriate for a review bench, not a product defect.

## Spec conflicts

- §2 / §16.2 "appears once" — violated for recurring planned-and-due todos (D5).
- §3.2 "No silent deadline fabrication" — repeat sets today as deadline (D14).
- §5 "Creating a calendar returns to the picker and selects the new calendar" — not met mid-compose (D2).
- §8 "Touch targets remain at least 48dp on mobile" — violated broadly (D6).
- §16.1 "Today is the real today, derived from the clock" / "Midnight: only Today rolls over" — Today is frozen at boot day (D9).
- §16.4 "the year is shown when it differs from the current year" — not met (D15).

## Summary

- 7 of 12 claimed fixes reproduce cleanly (1, 2, 3, 4, 9, 11, 12).
- 4 reproduce only partially or with broken seams (6, 7, 8, 10).
- 1 does not reproduce at all (5).
- 7 P1 defects (D1–D7), 11 P2 defects (D8–D18), 2 P3 notes.
- Console errors: none on any route at 1440/390 in normal use; one uncaught TypeError reachable through pane delete → Trash purge (D3).
- Horizontal overflow: none at 1440/1180/1000/900/899/390, with or without a detail/pane open.

REVIEWER_VERDICT: FAIL
