# G1 evidence — Android widget touch and action loop (2026-11-16)

Follows `docs/qa/task2-widget-touch-2026-11-14.md`. That pass raised every row
to 48dp; this pass closes what the raised rows exposed: the row's *hit area*,
the checkbox's second meaning (undo), and the budget that still clipped rows on
short cards.

Baseline: `main` @ `7390987` (v0.34.0+34), worktree `dayspark-g1`, branch
`g1/android-widget-touch`.

## Environment

- Android 15 / API 35 `google_apis` arm64 emulator `dayspark35`, 1080x2400,
  density 2.625, Pixel Launcher, seeded Drift DB (todos 1–6).
- Widgets added through the launcher's own picker and resized with its handles
  (`widget_resize_*`); coordinates and bounds below come from `uiautomator dump`
  of the launcher's view tree, not from the XML source.
- Tap evidence is what the tap *did*: `ActivityTaskManager` got a `VIEW
  dayspark://open/...` intent (detail title read back from the app), or the
  native command queue gained/lost one `widget_command_*` entry.

## What was wrong

1. **Rows had 48dp boxes but only the root bound the open action.** A
   `TextView` with no handler bubbles a tap to the row; any child that consumes
   it would silently kill that region, and the binding was invisible to review.
   Every informational child of a todo row, a timeline row (allocation **and**
   event) and a calendar summary row now carries the row's PendingIntent; only
   `todo_check` / `timeline_check` carry the complete action. A row with no id
   binds its list instead of staying dead.
2. **Two taps on one checkbox queued two `complete` commands.** The widget drew
   a filled check, but the app applied completion twice. A second tap now
   removes the pending command for that exact identity (target + todoId +
   occurrenceId) instead of adding another. This is a **queue-level** undo:
   once the app has consumed a command, a later tap enqueues a new `complete`
   and the consumer answers `alreadyApplied`; there is no DB un-complete path.
3. **The row budget min-clamped and clipped.** `rowBudget(...).coerceIn(min, …)`
   forced 3 rows into a 104dp rows area on a 4x2 card, so the launcher drew the
   third row as a ~20px sliver (`[99,1074][981,1094]` in the 2026-11-14
   session). Two other sources of the same failure: LARGE+Today subtracted a
   guessed header, and Action reserved a 48dp footer with `min 2` rows.
   `RowBudget` now spends dp as each header/row is actually emitted and never
   grants more than the container has; Action's footer is only reserved when
   every row still fits beside it.
4. **The row height was an arithmetic model of text growth.** It returned 48dp
   at fontScale 1.5 and 60dp at 2.0 where the real row measures 51dp and 64dp,
   so at large accessibility text the last row was charged less than it needed
   and lost its bottom (measured 47px against a 48px floor). The height is now
   measured from the inflated layout using **the row's own text**, cached per
   text/configuration. A fixed sample is not enough: at 1.5 Latin measures 51dp,
   zh 54, Arabic 58 and Tibetan 67, so any one sample under-budgets the others
   (a Latin sample squeezed a zh row to 124px against a 126px floor at 420dpi).
   The 112dp SMALL boundary also moved from the normal 8dp padding to the tight
   4dp band: it was the one height in the band that budgeted 49dp but left only
   48.

## Code

| File | Change |
|---|---|
| `TodoWidgetProvider.kt` | `internal build(size, heightDp)` for exact-size tests; spend-as-you-go budget; 4dp padding in the 110–111dp SMALL band; group header only with a row under it; Today header only when overdue+today are both present; bind all `TODO_OPEN_IDS`; "No tasks" driven by data, not by rows-that-fit |
| `TodayWidgetProvider.kt` | same budget; per-row heights (`PlannedRow`); footer never costs a row; bind all todo/timeline open regions |
| `CalendarWidgetProvider.kt` | summary rows bind their marker/time/title too (same PendingIntent) |
| `WidgetSupport.kt` | `WidgetRows` id sets + `bindOpen`; `RowBudget`; row heights measured from the inflated layout and cached per configuration/font scale; `dpToPx` |
| `WidgetSnapshot.kt` | `cancelPendingCommands` + `commandMatches` |
| `WidgetActionReceiver.kt` | checkbox tap = cancel-if-pending else enqueue `complete`, then refresh |
| `widget_timeline_row.xml` | `wrap_content` + `minHeight=48dp` so accessibility text grows the row instead of clipping it |

## Real-device taps (Pixel Launcher, API 35)

Bounds are px; `todo_check` is 126px = 48dp.

### Todos, 4x4 (logged height 344dp)

Clickable regions reported by the launcher for row 2:
`todo_item [99,948][981,1074]`, `todo_priority [99,979][104,1042]`,
`todo_check [115,948][241,1074]`, `todo_title [241,968][981,1014]`,
`todo_meta [241,1014][981,1053]` — all `clickable="true"`, with the checkbox
the only different action.

| Tap | Expected | Observed |
|---|---|---|
| recurring row `↻` (950,885) | open todo 3 | `Morning run` page |
| recurring row blank below meta (700,940) | open todo 3 | `Morning run` |
| row 2 title (500,990) | open todo 4 | `Finish report` |
| row 2 blank above title (300,950) | open todo 4 | `Finish report` |
| row 2 blank at trailing edge (955,1050) | open todo 4 | `Finish report` |
| row 3 title (500,1100) | open todo 6 | `Read book` |
| row 3 trailing blank (955,1160) | open todo 6 | `Read book` |
| row 2 checkbox centre (178,1011) | command +1, no page | 1 command, filled check, stayed on Home |
| same checkbox again | command −1 | 0 commands, unfilled check |
| row 2 checkbox left edge (117,1011) | command +1 | 1 command |
| same checkbox right edge (239,1011) | command −1 | 0 commands |
| row 3 checkbox corner (120,1080) / (235,1195) | +1 / −1 | 1 then 0 |
| every row tap above | no command | queue stayed empty |

Row taps produce a `dayspark://open/todo?id=N` `VIEW` intent
(`ActivityTaskManager: START … dat=dayspark://open/...`) and **no** command;
checkbox taps produce **no** started activity. One tap never ran two actions.

The same grid/hit-area contract is asserted for the Today widget's todo rows,
timeline allocation rows **and timeline event rows** (`every visible
informational child carries the row action`, `timeline event row opens the
event from every visible region` — the latter asserts the binding on each id,
not just that a bubble happened to work).

### Todos, 4x2 after a launcher resize

The same card resized with the launcher's bottom handle:

- Before this change the third row was a 20px sliver; now the rows area holds
  exactly two full rows (`1. Morning run`, `2. Finish report`), the third is
  absent, and `Read book` is still reachable via the list. `Tasks 3` keeps the
  total honest.
- Taps on the resized card still work: row 1 title → `Morning run`; row 2 title
  → `Finish report`; checkbox centre → 1 command; same point again → 0.

### Todos, declared minimum 110dp (unit-level)

Not reachable through the Pixel Launcher picker; covered by
`WidgetRowIntentTest.small card at its declared minimum keeps one full row`:
tight padding becomes 4dp, the rows container measures 54dp, one 48dp row is
laid out, `last.bottom <= rows.height`. `medium 140dp` asserts zero rows and
that `No tasks` stays hidden because the data is not empty. The 4dp tight
padding exists only in `TodoWidgetProvider`; Today declares 120dp and has no
tight path, so this sub-behaviour does not read across widgets.

### Large text (unit-level geometry)

`rows keep their full height at accessibility font scales` builds the real Todos
widget at 224/264/344/348dp and fontScale 1.3/1.5/2.0 and asserts every laid-out
row is still ≥48dp; `every script keeps its full row height at accessibility
font scales` repeats it at 420dpi for Latin/zh/Arabic/Devanagari/Tibetan/Thai/
Korean titles at 220/234/261/322/344dp; `the budgeted row height is never less
than the laid out row` compares the budget against the measured row. Both
geometry tests assert at least one row was laid out, so a budget that emits
nothing cannot pass them. Before the fix these failed at 1.5 (47px row against
a 48px floor; 58dp budget against a 59dp row), and with a fixed sample at
420dpi (124px against 126px). Robolectric scales fonts linearly, while API 34+
devices apply non-linear scaling, so the on-device delta at 1.5 may be smaller;
the tests assert a lower bound that holds either way, and per-text measurement
removes the script assumption entirely.

### Action/Today, SMALL 2x3 (logged height ~240dp)

Clickable regions: `action_root`, `action_date`, `action_add_todo`,
`todo_item`, `todo_check`, `todo_title`, `todo_meta`, `action_completed`.
Rows and footer rendered fully inside the card.

| Tap | Observed |
|---|---|
| row 1 title (350,1355) | `Finish report` |
| row 1 meta (350,1400) | `Finish report` |
| row 1 blank bottom (350,1435) | `Finish report` |
| row 2 title (350,1480) | `Read book` |
| row 2 trailing blank (480,1560) | `Read book` |
| row 1 checkbox (151,1378) | 1 command |
| row 1 checkbox left edge (90,1378) | 0 (undo) |
| footer `2 completed` (300,1670) | Today page |
| date `Nov 16` (150,1250) | Today page |
| `+` (290,1250) | Quick add sheet |

### Action/Today, LARGE 4x2 (logged height ~224dp)

After the footer rule: both due rows are drawn, footer is hidden because adding
it would cost a row ("the footer never costs a row"). Before this change the
second row was clipped under a preserved footer. Row taps and checkbox undo were
re-verified on this layout (`Read book`, `Finish report`, 1 → 0 commands).

### Completion and refresh

1. Tap row 3 checkbox → pending command (1), widget draws a filled circle.
2. Cold-start the app → DB row becomes `6|COMPLETED`, command queue 0, widget
   re-renders from the new snapshot (count/rows change).
3. Restore the seeded row via SQL and cold-start again → widget shows the task
   again; no stale command.

## Automated evidence

- `./gradlew :app:testDebugUnitTest` — **47 tests, 0 failed, skipped=0**
  (`WidgetRowIntentTest` 29, `WidgetSnapshotCodecTest` 18). New tests dispatch
  real `MotionEvent`s into RemoteViews inflated under Robolectric (native
  graphics) and assert the started activity URI / broadcast extras, not the XML;
  geometry tests build the real widget at fontScale 1.3/1.5/2.0 and assert each
  laid-out row is still ≥48dp.
- `flutter analyze` — **No issues found**.
- `flutter test` — **824 passed**.
- Mutation proofs (each reverted afterwards):
  - disable the undo branch → `the second tap is an undo expected:<0> but was:<1>`
  - bind only the row root → `todo_title must carry the open action`
  - remove the budget limit → `child 3 must be measured`
  - restore the arithmetic row height → `scale=1.5 height=344dp: row 3 is 47px but a touch target needs 48px` and `scale=1.5: budgeted 58dp must cover the real 59dp row`
  - replace per-row text with a fixed `M` sample, at 420dpi → `zh scale=1.5 height=220dp: row 1 is 124px but a touch target needs 126px`
  - end the tight-padding band at 112 → `the 112dp boundary still shows one full row`
  - remove each id-less fallback (calendar / today task / todo item) → its test goes red
- CI: the `unit-test` job pins JDK 17 (Gradle 8.14 refuses the runner image's
  JDK 25) and runs `flutter build apk --debug --config-only` before the Gradle
  step, because `gradlew` / `gradle-wrapper.jar` / `local.properties` are
  gitignored by Flutter's own convention. Reproduced on a fresh `git worktree`:
  without provisioning `./gradlew` does not exist (exit 127); with it the suite
  runs green. Gate #22 in `docs/GATES.md`.

## Harness limits (not claims)

- The Pixel Launcher available here gives SMALL at 2x2, LARGE at 4x2/4x4, but no
  reachable MEDIUM card; MEDIUM geometry is covered by the 140dp unit test.
- The seeded DB has no recurring **allocation** rows, so a real recurring
  occurrence was not completed on device. The recurring identity path is
  covered by `recurring allocation checkboxes carry their own occurrence
  identity` (distinct PendingIntents and `occurrenceId`/`sourceAllocationId`
  extras) and by the receiver-level occurrence-cancel test. The Todos widget's
  recurring row has no checkbox by design and was verified to open its detail
  from every region.
- Command consumption still happens when the Home page initialises (existing
  pipeline, unchanged). A cold start was used to prove it; a warm resume is not
  claimed as a consumption point.
