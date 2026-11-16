# Independent Review — Round 9

Reviewer: independent (no part in building the prototype). Date: 2026-11-16.
Authority: `docs/CORE_UX_SPEC.md` (frozen). The prototype's docs and tests were treated as claims, never as evidence.

## Snapshot

- Commit `f0c0f2a` on `design/interaction-model-g0`.
- Viewports 1440×900, 1180×860, 1179/1000/899/390; zh + en; real pointer and CDP touch.

## P1 — blocking

| # | Finding | Root cause |
|---|---|---|
| 1 | With Todos as the active tab, record links inside a routed detail are dead clicks | `openRecord` keys off `tab === 'todos'`, not the current route, and stores a pane selection that is never rendered |
| 2 | "This and following" across a day boundary leaves the dragged occurrence behind and keeps later ones on the old weekday | the future branch truncates the old series without excluding the dragged anchor and copies the old `byday` |

## P2 — recorded

Settings split snaps back to the entry section; quick-add type override drops the parsed moment; custom repeat on an undated Todo has no anchor; a 15-minute phone block is entirely resize handle; calendar lane and month cell omit recurring deadlines; a day-view reorder reports success without changing the visible order and reshuffles hidden rows.

## P3 — recorded

Filter chip clear does not reset hide-completed and hide-completed alone shows no clear affordance; occurrence copies made by moving drop reminders.

REVIEWER_VERDICT: FAIL
