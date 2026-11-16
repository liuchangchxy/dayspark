# Independent Review — Round 7

Reviewer: independent (no part in building the prototype). Date: 2026-11-16.
Authority: `docs/CORE_UX_SPEC.md` (frozen). The prototype's docs and tests were treated as claims, never as evidence. The prototype's test suite was not run or reused.

## Snapshot

- Commit `1a7bdd7` on `design/interaction-model-g0`.
- Viewports: 1440×900, 1180×860, 1000×860, 899×800, 390×844; Chinese and English.
- Own Playwright scripts; real pointer, keyboard, drag and keyboard input.

## P1 — blocking

| # | Finding | Root cause |
|---|---|---|
| 1 | A 40-minute allocation cannot be represented; Save writes Invalid Date | duration select lists only 15/30/45/60/90/120; `parseInt('')` becomes NaN |
| 2 | Toggling all-day and cancelling mutates the stored Event | composer draft aliases the store's Date objects |
| 3 | Cold start on To-dos leaves `state.tab='action'`: full-page detail and wrong rail highlight | boot sets route but not tab |
| 4 | Saving a split occurrence leaves the replaced detail in Back | history still holds the old detail |
| 5 | Scroll position leaks across destinations; Back resets the list | snapshots restored by container class, not destination |
| 6 | Todo reorder commits on `pointercancel` | cancel shares the commit path |

## P2 — recorded

15-minute block entirely covered by the 48px resize handle; completed recurring occurrence still says 标记完成; row focus lost after opening the pane; subtask Save leaves a blank composer in Back; logged-in sync omits the server URL; 加截止 shortcut does not open the picker; 未安排 ordered after completed; Settings groups are bordered cards (SPEC §8).

## P3 — recorded

Quick-add toast wiped by navigation; AI preview says event while filling a schedule; ISO date leaves `on` in the title; same-day all-day detail repeats the date; already-completed occurrence notification reports success; unconfigured AI navigates without opening config.

REVIEWER_VERDICT: FAIL
