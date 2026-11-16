# G0 v2 — formal review ledger

Protocol: `docs/design/interaction-model/GOAL_G0_V2.md` §4–§6. Legacy rounds 1–10 (single reviewer,
one finding list per round) are recorded in `REVIEW_ROUND3.md` … `REVIEW_ROUND9.md` and in the
`fix(prototype): close round-N seams` commits. This file starts the分域 protocol: 10 independent
domain reviewers + 1 integrator per round, rolling backlog, maximum six rounds.

Evidence rule: a reviewer's report is a **claim** until the finding is reproduced here. Findings that
could not be reproduced are listed as `NOT_REPRODUCED` and are not fixed. The prototype's own test
suite is never used as proof that a contract holds.

---

## Round 1 — 2026-11-16

Snapshot: `655d8a6` + the settings-section-order fix. Ten domain reviewers, one integrator, all
independent, each required to read its OpenDesign domain page first and to drive the prototype with
its own Playwright scripts under `/tmp`. OpenDesign was reachable for every reviewer that returned a
report; the five reviewers that returned in the first wave cited OpenDesign-only section labels, and
the five re-run reviewers each quoted a verbatim OpenDesign line (`OPEN_DESIGN_READ`).

### Verdicts

| Domain | Verdict | P1 | P2 | P3 |
|---|---|---|---|---|
| A 外壳 | FAIL | 2 | 4 | 0 |
| B 今天 | FAIL | 2 | 6 | 1 |
| C 待办 | FAIL | 6 | 5 | 1 |
| D 日历 | FAIL | 3 | 6 | 1 |
| E Composer | FAIL | 7 | 4 | 0 |
| F 详情 | FAIL | 6 | 5 | 0 |
| G 工具面 | FAIL | 3 | 9 | 2 |
| H 设置 | FAIL | 4 | 9 | 2 |
| I 数据语义 | FAIL | 1 | 4 | 0 |
| J 视觉/i18n | FAIL | 2 | 10 | 3 |
| Integrator | FAIL | 3 | 1 | 2 |

### P0/P1 backlog — clustered by root cause

Status: `open` → `fixed` → `verified` (round 2). A closed P1 may not regress.
`fixed` means the code was changed and the regression scenario named in the row passes; it does **not** mean a
reviewer has re-derived it. `verified` is set only after the round-2 reviewer for that domain reproduced the fix
independently.

#### R1 — one navigation ladder (history, overlays, shortcuts)

| ID | Finding | Root cause | Fix | Regression evidence | Status |
|---|---|---|---|---|---|
| R1-1 | Browser Back at 今天 walks into stale history | `popstate` always calls `back()`; no root guard; primary `go()` rewrites route without resetting history | one `back()` that walks the ladder and stops at the root | r11-01 | fixed |
| R1-2 | Browser Back does not close the top overlay first (sheet survives a route change; menu closes *and* navigates; `?` modal not closed) | no `closeTop()` in the popstate path; `store.back()` returns early without closing layers | same ladder function used by Esc, browser Back and the pane | r11-02 | fixed |
| R1-3 | `N` shortcut replaces a dirty draft with no question | shortcut calls `openComposer` directly, bypassing the navigation guard | route every creation entry through the guarded navigation | r11-03 | fixed |
| R1-4 | Global shortcuts are not inert while the 更多 menu is open | `UI.menu` never registers in `openLayers` | one definition of "an overlay is open" | r11-04 | fixed |

#### R2 — one completion / scheduling write path

| ID | Finding | Root cause | Fix | Regression evidence | Status |
|---|---|---|---|---|---|
| R2-1 | Editing status in the composer is a second completion path; allocations are neither invalidated nor restored | composer writes `status`/`completedAt` directly | composer delegates to the single completion routine | r11-05 | fixed |
| R2-2 | A recurring subtask's checkbox silently does nothing | detail calls `S.completeTodo` directly with no occurrence | all completion entries call one routine | r11-06 | fixed |
| R2-3 | A completed Todo still offers 安排时间 and writes a dead allocation with a success toast | button not gated; success toast unconditional | disable with a visible reason; no write, no claim | r11-07 | fixed |
| R2-4 | Completing a missed recurring occurrence removes it with no 今天完成 row and no inline undo | only same-day occurrences enter the completed projection | completed section includes completed occurrences of the day in context | r11-08 | fixed |

#### R3 — occurrence context (series vs occurrence)

| ID | Finding | Root cause | Fix | Regression evidence | Status |
|---|---|---|---|---|---|
| R3-1 | Detail ignores the day in context: wrong 截止, wrong 计划执行, 取消安排 can cancel another occurrence | detail reads the series, not the occurrence | detail resolves the occurrence for the day it was opened for | r11-09 | fixed |
| R3-2 | A recurring allocation with no deadline is shown as `截止 今天` | allocation row substitutes start-of-day for every recurring allocation | deadline meta only when the occurrence actually has one | r11-10 | fixed |
| R3-3 | Editing a recurring occurrence offers only 仅本次 / 整个系列 | edit scope list built separately from delete | one scope implementation with three options | r11-11 | fixed |
| R3-4 | Completed subtasks leak into 全部待办 and 今天 · 今天完成 | completed projections have no `parentId` filter | children never enter top-level projections | r11-12 | fixed |
| R3-5 | A recurring row's deadline loses its time in a dated view; the calendar lane omits recurring deadlines outside the anchor window | date-only formatting of an occurrence; lane queries the raw series | one occurrence-resolving deadline reader | r11-13 | fixed |

#### R4 — the dated 待办 body is a day projection

| ID | Finding | Root cause | Fix | Regression evidence | Status |
|---|---|---|---|---|---|
| R4-1 | 按日期 omits events and has no planned / deadline split | body built from `todosForDay` only | body = planned executions, then deadline items, then events | r11-14 | fixed |
| R4-2 | 全部待办 is one flat list; 已逾期 rows appear mid-list | single section head | group 今天 / 已逾期 / 之后 / 无截止, then completed by day | r11-15 | fixed |
| R4-3 | 未安排's completed part filters by `dueDate` (INV-146) | completed query uses the old criterion | same planned-execution criterion for both halves | r11-16 | fixed |
| R4-4 | Switching to 未安排 and back to 今天 resets `browseDate` | the 今天 chip writes `browseDate` | the chip selects the day view without changing the shared date | r11-17 | fixed |

#### R5 — the composer writes only what it shows

| ID | Finding | Root cause | Fix | Regression evidence | Status |
|---|---|---|---|---|---|
| R5-1 | Deadline quick chips write past times; no 23:00 roll; 本周 can write yesterday | fixed 18:00 values and a negative week offset | chips resolve a future instant; after 23:00 roll to the next day | r11-18 | fixed |
| R5-2 | Type segment is enabled but dead in edit | early return on an enabled control | render the locked type as a fact | r11-19 | fixed |
| R5-3 | A cross-midnight Event cannot be created, and editing one rewrites its end date | end rebuilt on the start's date; only one date field | end date follows a midnight crossing; an existing cross-midnight record stays editable | r11-20 | fixed |
| R5-4 | Recurring Todo planning keeps a stale occurrence and blocks a valid day | occurrence select built once, value restored | derive the occurrence from the planned day | r11-21 | fixed |
| R5-5 | Create from the 待办 list can land with the new row neither visible nor highlighted | highlight assumes the row renders in the current view | return to the view that owns the new record and highlight it | r11-22 | fixed |
| R5-6 | 重复开始 is written to a non-recurring Todo's `startDate` | the anchor is written on change, outside the rule apply | anchor lives only inside an applied recurrence | r11-23 | fixed |
| R5-7 | 计划这一天 on a past browsed day prefills a past slot | only "today" is special-cased | never prefill a past slot; roll forward instead | r11-24 | fixed |

#### R6 — calendar truthfulness

| ID | Finding | Root cause | Fix | Regression evidence | Status |
|---|---|---|---|---|---|
| R6-1 | Month prev/next discards the day-of-month | paging builds the 1st | preserve the day, clamp at month end | r11-25 | fixed |
| R6-2 | A refused allocation drag navigates to the Todo detail and hides the reason | `restoreVisual` clears the moved flag so the trailing click passes | a refused drop consumes its click and stays put | r11-26 | fixed |

#### R7 — settings and tools tell the truth

| ID | Finding | Root cause | Fix | Regression evidence | Status |
|---|---|---|---|---|---|
| R7-1 | `section` deep links are ignored or use internal keys (`account`/`advanced`) | applied-once guard; route param not mapped | every entry applies the requested section; public keys are stable | r11-27 | fixed |
| R7-2 | 数据 omits the 标签 / 回收站 entries and counts, 导出 .ics and 合并备份 | section built with three rows | rows per the frozen IA | r11-28 | fixed |
| R7-3 | Import claims success with no file selected and writes nothing | success toast unconditional | refuse with an inline reason; claim success only on a real write | r11-29 | fixed |
| R7-4 | Connected devices is a hardcoded list with no loading / empty / error | static markup | all three states | r11-30 | fixed |
| R7-5 | Deleting a calendar with content purges it instead of soft-deleting | purge helpers | soft delete to 回收站, as the real app does | r11-31 | fixed |
| R7-6 | 反馈's GitHub submit claims an action it never performs | copies text and toasts | open the prefilled issue, or label it a placeholder | r11-32 | fixed |
| R7-7 | AI input stays editable while pending and silently drops what was typed | no disabled state on the field | disable the field and the send control while pending | r11-33 | fixed |
| R7-8 | A trashed record opens as a generic error instead of the deleted banner + 恢复 | trash guard runs before the deleted branch | trashed record opens with its banner and restore | r11-34 | fixed |

#### R8 — localization

| ID | Finding | Root cause | Fix | Regression evidence | Status |
|---|---|---|---|---|---|
| R8-1 | English mode renders Chinese seed records, tags and calendar names | seed data is literal Chinese with no locale variant | locale-aware seed; no Chinese string in English mode | r11-35 | fixed |

#### R9 — visual gate

| ID | Finding | Root cause | Fix | Regression evidence | Status |
|---|---|---|---|---|---|
| R9-1 | Phone calendar resize handle is 16px tall | CSS height, not hit area | 48px effective handle | r11-36 | fixed |

### P2/P3 — recorded, not blocking

Type scale and dark tokens against the contract; search hint duplicated; search no-results action;
skeleton shimmer gradient; radius/spacing drift; motion durations; `安排执行` in the AI quick actions;
unlabelled sync inputs; two Save buttons in the composer; event bar width; boot focus; brand glyph;
focus-on-arrival; breakpoint scroll loss; 更多 popover vs sheet; month double-click on a populated cell;
phone week lane; phone week meta hidden; grip 48×15; 隐藏已完成 chip; batch toast overwrite; batch
delete singular copy; AI prefill uses the prompt; "Everyday"; empty-state copy under a filter;
generic-error copy; settings loading states; search failure state; calendar slot loading; keyboard
arrows; phone month empty tap toast; tool-page title alignment; last-calendar explanation always
shown; extra lunar setting; AI status provider; 打开助手 when unconfigured; follow-system theme;
per-field auth validation; Windows/Linux limitation copy; permission row coupling; notification
label terminology; settings group 10.5px.

---

## Round 2 — pending

## Round 2 — 2026-11-17

Scope: protocol §5 — every domain that had a P1 (all ten) plus every domain touched by the round-1 fix diff
(all ten) goes through deep review again; one integrator. Reviewers must read OpenDesign first, quote it, and
reproduce findings with their own `/tmp` Playwright scripts. Rulings D-16…D-20 are in scope.

Snapshot: `655d8a6` + the round-1 fix set (uncommitted at review start; committed with this ledger).

| Domain | Verdict | P1 | P2 | P3 |
|---|---|---|---|---|
| A 外壳 | pending | | | |
| B 今天 | pending | | | |
| C 待办 | pending | | | |
| D 日历 | pending | | | |
| E Composer | pending | | | |
| F 详情 | pending | | | |
| G 工具面 | pending | | | |
| H 设置 | pending | | | |
| I 数据语义 | pending | | | |
| J 视觉/i18n | pending | | | |
| Integrator | pending | | | |
