# Independent Review — Round 6

Reviewer: independent (no part in building the prototype). Date: 2026-11-16.
Authority: `docs/CORE_UX_SPEC.md` (frozen). The prototype's docs and tests were treated as claims, never as evidence. The prototype's test suite was not run or reused.

## Snapshot

- Commit `ec4c816` on `design/interaction-model-g0`.
- Viewports: 1440×900, 1180×860, 1000×860, 899×800, 390×844; Chinese and English.
- Own Playwright scripts in `/tmp/review6`; real mouse, touch, keyboard and drag.

## Verified working

Desktop master-detail at ≥1180; routed detail with a visible back below 1180; sheets across a resize writing the visible form only; month double-click creating an event; chat/AI recurring allocation writing a real occurrence; batch/detail completion on the browsed day; Quick Create; calendar create-and-select; folded-dawn drag/resize time math; no raw i18n keys; no console/page errors; no horizontal overflow at 390; no unintended dead buttons.

## P1 — blocking

| # | Finding | Root cause |
|---|---|---|
| 1 | Settings split jumps back to 通用 after any in-section action | `settings.js` local `active`, reset every render |
| 2 | Global render resets scroll and loses the selected item | `app.js` replaces `#view`, restores focus but not scroll |
| 3 | Calendar header 新建日程 uses a stale focus date after browsing | `calendarFocusDay || a`; `shift()` does not update it |
| 4 | Allocation block on another day completes the week-anchor occurrence | `allocBlock` calls `openTodo(todo)` without the column day |
| 5 | Touch drag commits on `pointercancel` (scroll gesture) | `pointercancel` shares the commit path with `pointerup` |
| 6 | Three consecutive 15-minute events overlap; tapping B opens C | phone hour 96px + `min-height:48`; blocks overlap |
| 7 | Phone back-to-now pill covers the More tab | `bottom:12px` inside content that reaches under the nav |
| 8 | Three phone create actions are the same naked `+`; Calendar has no accessible name | labels dropped in JS/CSS on narrow screens |
| 9 | Cancelling the recurrence-scope sheet leaves the dragged block moved | drag mutates the node; cancel never restores it |

## P2 — recorded

1. Completing a recurring Todo in the pane clears it (non-recurring keeps it).
2. Todo rows are not focusable.
3. A subtask with a deadline is invisible on Today/Todos (documented product decision; not changed).
4. All-day Event on Today renders a clock range.
5. Overdue date-only Todo shows 今天 in the time column.
6. Deleting a filtered calendar leaves a stale filter and a false empty state.
7. English Quick Add ignores English dates.
8. Event composer has no Repeat control.
9. Phone resize/reorder handles below 48px, reorder invisible.
10. Resizing a selected pane below 1180 leaves the row highlighted with no detail.

## P3 — recorded

English States page has hardcoded Chinese; bottom nav marks no tab on tools; week arrows named 返回/更多; allocation resize toast says moved; empty new-calendar name does nothing; repeat validator says 开始日期; pane edit+cancel loses selection; occurrence checkboxes have no toast/undo.

REVIEWER_VERDICT: FAIL
