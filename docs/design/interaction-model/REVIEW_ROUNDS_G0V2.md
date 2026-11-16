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
(all ten) went through deep review again, with one integrator. Each reviewer read OpenDesign first, quoted it,
and reproduced findings with its own `/tmp` Playwright scripts. Rulings D-16…D-20 were in scope.

Snapshot: `6977f26` + the round-2 fix set (committed with this ledger).

### Verdicts

| Domain | Verdict | P1 | P2 | P3 |
|---|---|---|---|---|
| A 外壳 | FAIL | 2 | 1 | 1 |
| B 今天 | PASS | 0 | 4 | 2 |
| C 待办 | FAIL | 4 | 9 | 2 |
| D 日历 | FAIL | 2 | 5 | 3 |
| E Composer | FAIL | 4 | 1 | 1 |
| F 详情 | FAIL | 6 | 5 | 2 |
| G 工具面 | FAIL | 3 | 7 | 3 |
| H 设置 | FAIL | 3 | 5 | 2 |
| I 数据语义 | FAIL | 3 | 2 | 1 |
| J 视觉/i18n | FAIL | 1 | 5 | 9 |
| Integrator | FAIL | 1 | 3 | 2 |

Round-1 P1 count 37 → round-2 P1 count 29 (strictly down; several round-2 P1s are the same root cause seen
from a second entry point, clustered below).

### Round-2 P1 backlog — clustered by root cause

Status: `fixed` means code changed and the named regression passes; `verified` requires the round-3 reviewer
for that domain to reproduce the fix independently.

#### N1 — trashed records are read-only as a whole page

| ID | Finding | Root cause | Fix | Regression | Status |
|---|---|---|---|---|---|
| F2-1 / G-P1-1 | Trashed Todo head menu edited, occurrence boxes completed, 添加子任务 created a live orphan | head/menu/occurrence controls never consulted the page's `ro` flag | head menu omitted; occurrence/subtask boxes disabled; no inline editors | r12-14 | fixed |
| F2-2 | Trashed Event head still offered 编辑 / 移到回收站 and both wrote | edit/trash icons added before the read-only branch | head offers only 返回 (banner carries 恢复) | r12-15 | fixed |
| G-P1-1b | 回收站 rows were inert, so D-18 had no UI entry point | rows built as plain divs | row opens the read-only detail; Enter/Space too | r12-14 | fixed |

#### N2 — completion and read-only surfaces agree

| ID | Finding | Root cause | Fix | Regression | Status |
|---|---|---|---|---|---|
| C-P1-2 / F2-6 | Completed Todo still drawn as an open planned row and toggling reopened it | planned lane read allocations without the record's done state; D-11 wording contradicted INV-144 | planned lane excludes completed records; D-11 amended to INV-144 (row leaves current work, started block stays history) | r12-04 | fixed |
| C-P1-3 / B-03 | Completed Todo could be scheduled from the row menu and wrote a block | row menu offered 安排时间 unconditionally | scheduling item only for open records in row and detail menus | r12-05 | fixed |
| F2-4 | Recurring subtask checkbox wrote but never rendered checked | checkbox read series status, not occurrence state | shared occurrence resolved for state and write | r12-17 | fixed |

#### N3 — one browsed date and one deadline reader

| ID | Finding | Root cause | Fix | Regression | Status |
|---|---|---|---|---|---|
| D-R2-2 | Month + 日程 created on stale `calendarFocusDay` (a week away) and at 01:00 in the folded dawn | second date source; header bypassed the fold guard | create uses `browseDate`; start clamped out of folded dawn | r12-08 | fixed |
| I-R2-1 | Deadline lane dropped recurring deadlines outside the series anchor window | lane filtered raw `dueDate` | lane expands occurrences in range and uses each occurrence's deadline | r12-24 | fixed |
| I-R2-2 / R3-1 | Lane chip opened detail on the browse date; completion refused | chip called `openTodo(todo)` without its own day | chip carries its occurrence day into the detail | r12-25 | fixed |
| F2-3 | Recurring 截止 fact followed today/anchor, and its editor wrote the series anchor | detail fallback to today; inline editor wrote `todo.dueDate` | fact resolves the context day; a recurring deadline is not inline-editable (series edit) | r12-16 | fixed |

#### N4 — the calendar tells the truth about blocks

| ID | Finding | Root cause | Fix | Regression | Status |
|---|---|---|---|---|---|
| D-R2-1 | 改期… ignored its end field for Events | `moveEvent` treated every dialog save as a delta move | `{exact:true}` writes both fields | r12-07 | fixed |
| D-R2-5 / I-R2-01 | Block menu existed only on `contextmenu`; the D-16 fallback was unreachable by touch | no hold gesture | 480ms pointer hold opens the menu; movement cancels; trailing click swallowed | r12-09 | fixed |
| J-R2-1 | Two events with identical intervals shared a column; the first was unreachable | overlap map keyed by start-end | layout assigned per block; identical intervals get separate columns | r12-26 | fixed |

#### N5 — shells and forms do not write on a refused path

| ID | Finding | Root cause | Fix | Regression | Status |
|---|---|---|---|---|---|
| A-R2-1 | `T` changed the browsed date and toasted success before the discard guard resolved | mutation before guard | guard wraps the whole action | r12-01 | fixed |
| A-R2-2 | `N` inside a composer then 放弃 left a duplicate composer entry | `navigate` pushed a second composer | opening from a composer replaces the entry | r12-02 | fixed |
| C-P1-1 | Desktop pane refused planned-only / other-day rows | pane visibility built from the deadline projection only | pane accepts exactly the rows the day body renders | r12-03 | fixed |
| C-P1-4 | Phone drew a 48×15 reorder grip and reordered | CSS + handler existed on touch | grip not drawn on phone; D-07 touch has swipe only | r12-06 | fixed |
| E-P1-1 | Deadline chip label said 今天/本周 while writing tomorrow/next week | fixed labels | labels derive from the resolved instant (D-23) | r12-10 | fixed |
| E-P1-2 | 重复开始 survived removing recurrence and blocked saves invisibly | clear only when no deadline; payload/validation read the orphan | clearing recurrence clears the anchor; payload/validation only use it while recurring | r12-11 | fixed |
| E-P1-3 | Save label kept a stale tag count and omitted reminders | tag/calendar/reminder handlers re-rendered without validating | handlers re-run validation | r12-12 | fixed |
| E-P1-4 | Overlapping schedule saved without the D-09 conflict toast | save toast built without the conflict | save toast names the same conflict as the preview | r12-13 | fixed |

#### N6 — settings and tools claim only what happened

| ID | Finding | Root cause | Fix | Regression | Status |
|---|---|---|---|---|---|
| H-1 / I-R2-3 | 合并备份 toasted success with no file and no write | confirm-only stub | file chooser, parse, id/updatedAt merge, 新增/更新/跳过 report, refusal without a file (D-22) | r12-21 | fixed |
| H-2 | Device row stayed "—" after the sheet loaded a real list | count only refreshed on an unrelated render | the load updates the row it came from | r12-22 | fixed |
| H-3 / G P2 | Restore after calendar deletion left a dangling calendar | restore cleared `deletedAt` without checking the calendar | restore rebinds to a live calendar (D-21) | r12-23 | fixed |
| G-P1-2 | Calendar delete-with-content had no undo | calendar row removed permanently, contents soft-deleted | undo restores the calendar and takes back its rows/bindings (D-10 amended) | r12-19 | fixed |
| G-P1-3 | About's GitHub rows toasted a URL instead of acting | placeholder actions | real `window.open`, copied address when blocked | r12-20 | fixed |
| F2-5 | 所属日历 inline editor wrote on pick | deliberate deviation from D-13 | calendar is a fact; editing goes through composer | r12-18 | fixed |

### Round-2 rulings written back to OpenDesign

D-11 amended (INV-144 stands; row leaves current work), D-21 restore rebinding, D-22 merge file/report,
D-23 truthful quick-chip labels, D-24 touch hold opens the block menu, D-25 identical intervals get their own
column.

### Round 3 — verification round against `5ec8e36`

| Domain | Verdict | P0 | P1 | P2 | Notes |
|---|---|---|---|---|---|
| A shell | FAIL | 0 | 1 | 0 | browser Back asked the leave guard twice |
| B today | PASS | 0 | 0 | 1 | second completion steals the first row's inline undo |
| C todos | PASS | 0 | 0 | 3 | checkbox label on done rows; duplicate 今天 heads; tablet-touch grip |
| D calendar | FAIL | 0 | 1 | 1 | hold/drag click guard lost under 4–12px finger jitter |
| E composer | FAIL | 0 | 1 | 0 | a first block named itself in the conflict toast |
| F detail | FAIL | 0 | 1 | 1 | 备注 inline editor and attachment delete still live on a trashed record |
| G tools | FAIL | 0 | 2 | 2 | trashed 备注 editor (same root as F); calendar-move undo skipped trashed rows |
| H settings | FAIL | 0 | 1 | 1 | merge compared ISO `updatedAt` as a string |
| I data | FAIL | 0 | 1 | 1 | deadline lane listed a completed recurring occurrence as open |
| J visual | PASS | 0 | 0 | 5 | type scale, dark tokens/contrast, width caps, toast over 回到现在, 3-way overlap |
| Integrator | pending | | | | running |

#### Round-3 backlog

| ID | Finding | Root cause | Fix | Regression | Status |
|---|---|---|---|---|---|
| A-R3-1 | Browser Back with a dirty composer asked twice | the escape handler re-read a dirty flag the guard had already resolved | the accepted-discard branch clears the local draft state | r12-27 | fixed |
| E-R3-1 | A first schedule toasted itself as an overlapping conflict | conflict scan ran after the allocation was written | the conflict is computed before the write | r12-28 | fixed |
| H-R3-1 | Merge skipped newer rows whose `updatedAt` was an ISO string | string comparison against a `Date` | both sides normalized to a timestamp before comparing | r12-29 | fixed |
| F-R3-1 / G-P1-1 | Trashed record still opened the 备注 editor and drew attachment delete | read-only gate applied per control, missed two | notes are a fact when trashed; delete is not drawn | r12-30 | fixed |
| G-R3-2 | Calendar move-undo left trashed rows bound to the surviving calendar and kept a re-stamped `deletedAt` | inverse built from live rows while the forward op rewrites the whole table | delete snapshots every affected row; undo restores from it | r12-31 | fixed |
| D-R3-1 | 4–12px finger jitter on a block opened the menu and then navigated | drag threshold 4px vs hold cancel 8px, and a zero-delta move still re-rendered; the click guard lived on the detached node | drag threshold 8px, zero-delta writes skipped, document-level guard swallows the trailing block click | r12-32 | fixed |
| I-R3-1 | The deadline lane listed a completed recurring occurrence as an open deadline | the recurring branch never consulted the occurrence state | done occurrences are skipped, matching the dated list | r12-33 | fixed |

Round-4 scope: A, D, E, F, G, H, I (every domain the patch touched); B, C, J stay frozen at PASS.

### Round 4 — deep review of the patched domains against `17a886e`

| Domain | Verdict | P0 | P1 | P2 | Notes |
|---|---|---|---|---|---|
| A shell | FAIL | 0 | 1 | 2 | a re-render during the discard question asked twice and lost a kept draft |
| D calendar | FAIL | 0 | 3 | 4 | 8px was both hold and drag; a hold could still drag; month cell (fixed in `81380b4`) |
| E composer | FAIL | 0 | 4 | 3 | phone save label widened the page; silent cross-day refusal; rule did not cover the block day; recurring-event conflicts invisible |
| F detail | FAIL | 0 | 2 | 3 | phone note/subtask targets under 48px; trashed recurring record still drew occurrence boxes |
| G tools | FAIL | 0 | 1 | 2 | feedback submit still reported a false failure (About was fixed) |
| H settings | PASS | 0 | 0 | 5 | scroll offset, sync phase copy, notification label, platform statement, device cache |
| I data | FAIL | 0 | 2 | 1 | month grid vs lane; cascade-touched subtask not undone (both fixed in `81380b4`) |

#### Round-4 backlog

| ID | Finding | Root cause | Fix | Regression | Status |
|---|---|---|---|---|---|
| A-R4-1 | Resizing while the discard question was open asked twice and a kept draft was gone | popstate re-ran the whole ladder after the guard approved, reaching the freshly rendered page's handler | a resolved guard navigates directly | r12-36 | fixed |
| D-R4-1 | Exactly 8px was both a hold and a drag; a block at 09:07 moved +15 on release | drag threshold `>=8`, movement read from the snapped rendered top | drag starts beyond 8px; movement is the finger's delta | r12-46 | fixed |
| D-R4-2 | Sliding after the hold menu opened still dragged and wrote | the drag listeners stayed live after the menu opened | the menu owns the gesture; pointermove and release write nothing | r12-47 | fixed |
| D-R4-3 | Month cell painted a finished occurrence as an open deadline | cell used series status and the raw anchor date | occurrence-aware cell (committed in `81380b4`) | r12-34 | fixed |
| D-R4-5 | The gesture guard swallowed any block click for 400ms | guard keyed on time only | guard keyed on time and the release point | r12-49 | fixed |
| D-R4-6 | A jitter on the resize strip navigated into the record | strip tap fell through to the block click | a strip gesture never navigates | r12-48 | fixed |
| E-R4-1 | Phone save label overflowed the footer, widened the page and pushed the sheet's actions off screen | label drawn as one unbreakable line in a shrinkable flex item | the label wraps inside its own button on phone | r12-42 | fixed |
| E-R4-2 | Removing the repeat and moving the block across days was silently refused while the toast said 已更新 | the block kept an occurrence id a non-repeating record cannot own; the refusal went unchecked | the stale occurrence is cleared; a refused reschedule is surfaced | r12-43 | fixed |
| E-R4-3 | A live block survived on a day the new rule never reaches | validation compared the occurrence date, not the rule on screen | validation asks the shown rule | r12-44 | fixed |
| E-R4-4 | Conflict scan and suggested slots ignored repeating event occurrences | the scan read raw series times | the scan expands occurrences through `eventsOnDay` | r12-45 | fixed |
| F-R4-1 | Phone 备注 and subtask title were 18–21px targets | the mobile block never gave these two text controls a 48px box | both grow to 48px | r12-40 | fixed |
| F-R4-2 | A trashed repeating record still drew occurrence checkboxes and completion copy | the section was gated per checkbox, not per surface | the section is not rendered when trashed | r12-39 | fixed |
| G-R4-1 | Feedback submit claimed a blocked tab that really opened | `window.open(..., 'noopener')` always returns null | open normally, then sever the opener | r12-37 | fixed |
| I-R4-1 | Month grid kept a finished recurring deadline the lane dropped | see D-R4-3 | occurrence-aware cell | r12-34 | fixed |
| I-R4-2 | Undo after deleting a calendar did not restore a cross-calendar cascaded subtask | the snapshot held seed rows only | the snapshot covers the cascade | r12-35 | fixed |

Round-5 scope: A, D, E, F, G, I; H stays PASS and frozen; B, C, J frozen at PASS.
