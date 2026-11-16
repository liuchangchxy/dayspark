# Independent Review — Round 8

Reviewer: independent (no part in building the prototype). Date: 2026-11-16.
Authority: `docs/CORE_UX_SPEC.md` (frozen). The prototype's docs and tests were treated as claims, never as evidence.

## Snapshot

- Commit `87d8599` on `design/interaction-model-g0`.
- Viewports 1440×900, 1180×860, 1179/1000/900/899, 390×844; zh + en. Real pointer, CDP touch, keyboard.

## P1 — blocking

| # | Finding | Root cause |
|---|---|---|
| 1 | A recurring Event opened from Today shows and edits the wrong time (00:00) | `action.js` passes `occurrenceAnchor` (the midnight exdate key) instead of the occurrence start |
| 2 | A date-only deadline due today is painted 逾期 on Todos, Today and the calendar lane | instant comparison `dueDate < now` against a midnight deadline |

## P2 — recorded

Row keydown swallows inner-button activation; subtask save leaves a dead Back stop; real touch drag/resize/reorder never commits (no `touch-action: none`); clipboard reports success without checking the write.

## P3 — recorded

Search labels planned Todos 未安排; pane close drops focus to BODY; hiding completed on an all-done day leaves a blank list.

REVIEWER_VERDICT: FAIL
