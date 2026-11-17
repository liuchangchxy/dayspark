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
   removes a pending command with that exact identity (target + todoId +
   occurrenceId) and action instead of adding another. That queue-level undo
   only covers a command the app has not consumed yet; undoing **after** the
   write is the separate fix in the next section.
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
| `WidgetSnapshot.kt` | `cancelPendingCommands` + `commandMatches`; `completed` on todo/task rows; `todos.today.completed`; `complete`/`uncomplete` action on the command |
| `WidgetActionReceiver.kt` | checkbox tap = cancel-if-pending else enqueue the row's action (`complete` / `uncomplete`), then refresh |
| `TodoWidgetProvider.kt` (undo) | completed-today rows drawn after the open ones, checked/muted/struck, checkbox bound to `uncomplete` |
| `TodayWidgetProvider.kt` (undo) | completed due/occurrence rows checked/muted/struck; checkbox bound to `uncomplete` for their own target |
| `home_widget_service.dart` | snapshot keeps today's completed todos (`todos.today.completed`) and completed due-today/occurrence rows in a separate `action.completed` array (never `action.dueToday`); timeline occurrences carry `completed` and are not duplicated into `completed` |
| `widget_command.dart` | executor accepts `complete`/`uncomplete` and acts per desired state (idempotent replay) |
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

## Undo after the write (2026-11-17)

The queue-level undo above ends where the reported bug begins: once the app has
consumed the command and written `COMPLETED`, the row was no longer in the
snapshot, so a later tap had nothing to act on — completion was one-way from the
widget. Fixed end to end:

- the checkbox intent carries the **desired state**, not a blind toggle:
  `action = complete | uncomplete` in both the intent extra and the data URI, so
  a replayed command stays idempotent (a replayed `complete` must never
  un-complete);
- the snapshot keeps today's completed rows in their own array —
  `action.completed` for the Action/Today widget, `todos.today.completed` for
  the Todos widget — never appended to `action.dueToday`, so both widgets can
  still draw the row checked, muted and struck through after the refresh;
- `dueToday` keeps its old cross-platform shape for a reason: the Apple widgets
  decode it without a `completed` field and send a hardcoded `complete`, so a
  completed row placed there would render as an open row whose box can never
  fill;
- `action.completed` is drawn last, after every open group (now, later, due
  today, overdue), so on a short card the undo rows are what gets dropped and an
  open overdue task can never be displaced by one;
- completed rows are filtered to tasks that were actually due today or earlier,
  top-level only: an inbox, future-due or checklist-subtask completion was never
  a widget row;
- a completed recurring occurrence already drawn on the timeline is not
  duplicated into `action.completed`; that timeline row itself now carries
  `completed` and its checkbox sends `uncomplete`;
- the queue cancel is action-narrowed: only a pending command with the same
  action is cancelled, so a stale committed-but-unacked `complete` can no longer
  swallow the user's undo tap;
- the executor acts per desired state: `(status == 'COMPLETED') ==
  wantedCompleted` → `alreadyApplied`, otherwise one
  `toggleTodo(isCompleted: wantedCompleted)`.

### The loop on device (API 35, 420dpi, Pixel Launcher)

Final code, `flutter build apk --debug` installed with `adb install -r`. Todos
widget 2×2 added through the launcher's own picker; bounds come from
`uiautomator dump` (`todo_check` 126px = 48dp, rows `[88,621][498,747]`,
`[88,747][498,873]`, `[88,873][498,999]`). DB seeded with three todos due today.
Screenshots are in `docs/qa/g1-undo/shots/`.

| Step | Observed |
|---|---|
| tap `2. Finish report` checkbox in Todos (645,874) | queue 1 command, `{"action":"complete","target":"todo","todoId":2}`, widget filled, no page |
| cold start app | queue 0, DB `2|Finish report|COMPLETED`; `Today 2`; open rows renumbered `1. Buy milk`, `2. Read book`; the completed row is **still drawn** checked, muted and struck through (`02-completed-row-stays.png`) |
| tap that completed row's checkbox (645,1000) | queue 1 command, `{"action":"uncomplete","target":"todo","todoId":2,"todoSyncId":"01a1e6dc-…"}` — not `complete` |
| cold start app | queue 0, DB `2|Finish report|NEEDS-ACTION`; widget back to `Today 3` with `2. Finish report` open in its place (`03-undone.png`) |
| tap the same checkbox again (645,874) | queue 1 `complete` → cold start → `COMPLETED`, and the checked/struck row is drawn again (`04-completed-again.png`) |
| tap the completed row's **title** (350,1000) | opened the todo detail (showing `Mark incomplete`); **0** commands |

That is the loop the acceptance asks for: open → complete writes to the DB →
refresh → tap → restores → refresh → tap → completes again, with the completed
row reachable in between and no row/checkbox cross-triggering.

### The same loop on Action/Today (2×2, side by side with Todos)

Both widgets were on the same home screen at the same time, so every completion
made in one was visible in the other after the next refresh. The Action
completed row keeps both lines (title + `17:00`) and its checkbox sends
`uncomplete` for its own target, exactly like the Todos row.

The placement that matters is which row gets dropped on a short card. With one
open due task, one open **overdue** task and two completed rows on a 224dp card:

| Widget | Rows drawn (top to bottom) |
|---|---|
| Action/Today | `Read book` (open due), `Overdue thing` (open overdue), `Buy milk` (completed), and the second completed row is the one dropped |
| Todos | `Overdue thing` (open), `1. Read book` (open), `Buy milk` (completed) |

`05-overdue-never-displaced.png` is that state. Before the restructure the
completed rows sat between the due and overdue groups and took the budget, so
the open overdue task disappeared instead.

Neither widget mutates the snapshot itself; both read the same one.

### The recurring path is symmetric

A completed occurrence from `completedTodayTaskInstances` is added to
`action.completed` with `target: "taskInstance"` and its `occurrenceId`, unless
its block is already on the timeline; in that case the timeline row carries
`completed` and sends `uncomplete` for the same occurrence. The Android tests
assert both rows' checkboxes send `uncomplete` carrying their own occurrence
identity. No allocation was completed on device (the seeded DB has none — see
harness limits), so that path is unit-level only in this pass.

### Harness note

This schema stores `DateTime` as Unix **seconds** (`created_at` defaults to
`strftime('%s', …)`). A seed written in milliseconds read back as year 58848,
every todo fell outside "today", and the widget correctly showed `No tasks` —
a seed error, not a widget bug. Seed due dates in seconds.

## Automated evidence

- `./gradlew :app:testDebugUnitTest` — **58 tests, 0 failed, skipped=0**
  (`WidgetRowIntentTest` 40, `WidgetSnapshotCodecTest` 18). New tests dispatch
  real `MotionEvent`s into RemoteViews inflated under Robolectric (native
  graphics) and assert the started activity URI / broadcast extras, not the XML;
  geometry tests build the real widget at fontScale 1.3/1.5/2.0 and assert each
  laid-out row is still ≥48dp.
- `flutter analyze` — **No issues found**.
- `flutter test` — **831 passed** (824 before this pass; +7 for the undo path:
  executor restores a completed todo and is idempotent, executor restores a
  completed occurrence, snapshot keeps the completed occurrence's row, completed
  rows skip tasks that were never due today, the Todos block applies the same
  filter, completed rows never appear in `dueToday`, and a timeline occurrence
  is not duplicated into `completed`).
- Mutation proofs (each reverted afterwards):
  - disable the undo branch → `the second tap is an undo expected:<0> but was:<1>`
  - bind only the row root → `todo_title must carry the open action`
  - remove the budget limit → `child 3 must be measured`
  - restore the arithmetic row height → `scale=1.5 height=344dp: row 3 is 47px but a touch target needs 48px` and `scale=1.5: budgeted 58dp must cover the real 59dp row`
  - replace per-row text with a fixed `M` sample, at 420dpi → `zh scale=1.5 height=220dp: row 1 is 124px but a touch target needs 126px`
  - end the tight-padding band at 112 → `the 112dp boundary still shows one full row`
  - remove each id-less fallback (calendar / today task / todo item) → its test goes red
  - completed row sends `complete` again → `the checked row must ask to restore,
    not to complete again expected:<[un]complete> but was:<[]>complete` (2 tests red)
  - executor rejects `uncomplete` → both restore tests red (`alreadyApplied`
    / `terminalInvalid` instead of one `toggleTodo(isCompleted: false)`)
  - snapshot drops `completed` → the completed-row test goes red (the widget's
    undo row has no data again)
  - completed rows placed before the overdue group → `completed rows never
    displace an open overdue task on a short card` and `today widget draws the
    completed undo row last and never instead of an open task` red
  - completed rows put back into `action.dueToday` → `completed todos never
    appear in dueToday` red (this is the guard for the Apple contract)
  - the footer drawn beside a completed row → `the footer is a fallback only and
    is never drawn beside a completed row` red
  - receiver always queues `complete` → `the receiver writes the row's own
    action into the queue` red
  - no due-date filter on completed rows → `completed rows skip tasks that were
    never due today` red (actual set included Inbox task / Next week / Subtask)
  - empty-state check ignores completed rows → `a card whose only tasks are
    completed shows the undo row, not a done label` goes red
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

## Re-verification on the committed build (10:20–10:50)

The device matrix above was captured before the last two changes (row height
measured from each row's own text; 110–112dp tight padding; timeline event and
calendar summary bindings; id-less row fallbacks). Those changes were re-tested
on the branch's own commit `7f9d075`, built with `flutter build apk --debug` and
installed with `adb install -r` on the same API 35 / 420dpi emulator.

Widgets present: Todos 2x2 (SMALL) and Action/Today 4x2 (LARGE). Bounds below
come from `uiautomator dump` of the launcher, not the XML.

### Todos 2x2 (SMALL), rows container `[88,1315][498,1735]`

Every row child is clickable: `todo_item`, `todo_check` (126px = 48dp),
`todo_title`, `todo_meta` where shown, `todo_repeat` on the recurring row.

| Tap | Observed |
|---|---|
| recurring row title `1. Morning run` | opened `Morning run`, 0 commands |
| recurring row trailing blank (460,1430) | opened `Morning run`, 0 commands |
| row 2 title (350,1504) | opened `Finish report`, 0 commands |
| row 2 blank above title (250,1450) | opened `Finish report`, 0 commands |
| row 2 trailing blank (470,1540) | opened `Finish report`, 0 commands |
| row 3 title (350,1630) | opened `Read book`, 0 commands |
| row 2 checkbox centre (151,1504) | 1 pending command; launcher kept focus (no page) |
| same checkbox again | 0 commands (undo) |
| row 3 checkbox left edge (90,1630) | 1 command |
| row 3 checkbox right edge (213,1630) | 0 commands (undo) |

No row tap added a command; no checkbox tap opened a page.

### Completion and refresh

1. Checkbox on `2. Finish report` → command queue 1.
2. `am force-stop` then cold start → queue 0; DB row `4|Finish report` →
   `COMPLETED`; widget count `3` → `2`, the row is gone and `Read book` is
   renumbered to `2`.
3. Action/Today simultaneously refreshed to only `Read book` plus `3 completed`.

### Action/Today 4x2 (LARGE), rows area `[99,696][981,968]`

One task row (`Read book`), section header and a 48dp footer all inside the
card; no clipped row (footer bottom 1094 ≤ root bottom 1126).

| Tap | Observed |
|---|---|
| row title (350,797) | opened `Read book`, 0 commands |
| row meta `04:38` (350,840) | opened `Read book`, 0 commands |
| row blank bottom (350,870) | opened `Read book`, 0 commands |
| checkbox centre (162,817) | 1 command, launcher kept focus |
| same checkbox again | 0 commands (undo) |
| footer `3 completed` (350,1031) | opened the app (MainActivity), 0 commands |

### Limits of this re-run

- Without Tags widget changes the Todos card could not be widened past 2x2:
  the launcher icons to its right block the resize handle, and the handle did
  not accept synthetic drags this session. 4x4 is covered by the Robolectric
  geometry tests at 344dp and by the 2026-11-14 session on the same layouts.
- MEDIUM remains unreachable from the picker (unit-tested at 140dp).

## CI on the pull request

`CI` run 43791376341 on PR #105: **all eight jobs pass** — `unit-test` 8m43s
(including `Provision the Android Gradle project` and `Android widget touch and
intent tests`, the latter `BUILD SUCCESSFUL in 4m 52s`, 300 tasks executed),
`server-test`, `build-android`, `build-ios-simulator`, `build-linux`,
`build-macos`, `build-web`, `build-windows`, and the `test` gate.
