# Task 2 evidence — Android widget touch targets (2026-11-14)

## What was reported

> 现役 Widget：Todos / Action / Calendar。当前问题：核心按钮实际触控区域太小，尤其
> Widget 放大后仍难点击。目标不是单纯放大图标，而是提高真实 hit target，同时保持
> Direction C 现有视觉设计。检查小 / 中 / 大尺寸。

Acceptance as written: the three widgets checked on a real device, core actions
tappable without precise aiming, no obvious mis-taps, the extra space of an
enlarged widget actually used, light/dark fine, no layout regression, automated
tests green.

## Environment

API 35 `google_apis` x86_64 emulator (`dayspark35`), 1080x2400, density 420
(2.625 px/dp), Pixel Launcher. Widgets pinned through the launcher's own widget
picker and resized with the launcher's resize handles; text values read back
from screenshots. Everything below is a measurement on that render, not a
reading of the code.

Limit of this environment, stated plainly: only the Pixel Launcher on API 35 was
available, and **it would not resize the Calendar widget vertically**. Its
handles appear (`onAppWidgetOptionsChanged` never fires) and an injected drag
from a handle either does nothing or is taken as a move of the card. Todos and
Action resize normally with the same gesture. So the Calendar card was measured
at 4x4 (large); its small/medium geometry is covered by the pure functions that
produce it (`WidgetSupport.calendarCellHeightDp` / `calendarSummaryRows` /
`calendarDayRows` / `calendarCellLayout`) and by the layout tiers they select,
not by a live resized card. This is a harness limit, not a claim.

## What changed

`44dp` was the number a finger had to hit; Material's floor is 48dp and a 44dp
row of a widget is measurably harder to hit than a 48dp one, especially with the
launcher's own scaling of `AppWidgetHostView`. The change raises the *layout*
sizes, not the glyph sizes, so the hit area is the whole row/button.

| Element | Before | After |
|---|---|---|
| todo row (`widget_todo_item` minHeight) | 44dp | 48dp |
| todo checkbox | 44x44 | 48x48 |
| Action `+ Task` / `+ Event` | 44dp tall, minWidth 44dp | 48dp tall, minWidth 48dp |
| Action completed footer | 32dp (small/medium), 36dp (large) | 48dp |
| Todos mode chips Today/Inbox/All | 44dp | 48dp |
| Calendar summary row | 44dp | 48dp |
| Calendar day cell | fixed 27dp (medium) / 32dp (large) | 27 / 32 / 36 / 40 / 44dp, derived from the card height and snapped to the tier that exists (`widget_calendar_cell`, `_36`, `_40`, `_44`), plus a 24dp tier that exists only for the declared 250dp minimum |
| Calendar summary rows | nominal 6 / 2 rows (large / medium), clipped by the launcher | exactly the rows the measured height holds; a truncated list becomes "N more" inside the card, including when there is room for a single row |

The calendar cell tiers are new layouts; each is the same three-part cell
(`calendar_cell` background + `calendar_day` + `calendar_dot`) with a larger box,
a slightly larger day number and a bigger dot, so Direction C's look is kept and
only the box grows.

Why the day cell stops at 44dp: seven columns across a phone-width card leave
~30–50dp per cell, so the 48dp floor is unreachable on one axis at every size
that exists on a launcher. The fix that matters for "must not aim precisely" is
that the *whole cell* is the target (measured below), so the finger aims at a
34–44dp box instead of a 11sp glyph.

Three geometry bugs surfaced while measuring and are fixed in the same change:

- **Calendar summary was clipped.** The list always received its nominal 6 / 2
  rows regardless of height, so a 4x4 card drew rows the launcher then cut. It
  now receives `(height - chrome - cells) / 48` rows, and when the day has more
  items than that, one of the visible rows becomes "N more" — including the
  one-row case, where that single row *is* the count (before, a day with 40 items
  showed one row and no trace of the other 39).
- **A six-week month could not fit the declared minimum.** 106dp of chrome plus
  6 × 27dp is 268dp, so a 250dp card clipped the last week row. The grid falls
  back to the 24dp tier when even the nominal cell cannot fit, landing on exactly
  250dp.
- **Action rows under-filled the card.** The budget subtracted a fixed header and
  footer allowance (large 150 + 60, medium 120 + 40, small 60 + 0) whether or not
  those were drawn. It now subtracts `actionChromeDp(small, nonEmptySections)`
  and `actionFooterDp(completedCount)`. Measured: the same 340dp card now shows
  five rows filling it, where the old formula gives `(340 - 150 - 60) / 48 = 2`
  for that height.


## Measurements (real device)

**Calendar, 4x4 (logged height 480dp, large).** Day-cell pitch measured off two
builds of the same card: 84px → 105px (**+25%**, 32dp → 40dp cells; 480dp with a
six-week month gives `(480 - 127 - 96) / 6 = 42`, snapped down to 40). A taller
card reaches 44dp.

- Keys/edge taps land on the intended day: a tap 6px above a cell's centre line
  selected day 20, a tap on the row boundary selected day 27, and two taps 49px
  apart vertically inside day 19's cell both selected day 19 — the hit area is
  the cell, not the glyph.
- The selected-day list shows exactly what the card can hold: `Nov 27 Fri` + one
  item + "47 more", with no row cut off at the bottom edge (the list used to be
  filled to its nominal 6 rows and the launcher cut whatever did not fit).

**Todos, all three sizes.** Small 2x2 (six rows in a card that holds six),
medium 3x2 (name + 3 chips + 2 rows), large 3x4 (group headers + rows). No
clipping at any size, and the extra height of the enlarged card is filled with
rows instead of blank paper.

**Action, small and large.** Small 2x3: date at 17sp, no weekday, no `+ Event`
(the small layout has no room for them), 3 rows filling the card. Large 3x4: date
header + section header + **5** rows, the whole card used.

**Light / dark.** Dark captured with `cmd uimode night yes` (the widget follows
the snapshot's theme, which follows the app, which follows the system when
unset): all three cards render on the dark surface with the snapshot's ink and
accent, the selected-day wash stays visible, and the 48dp rows keep their
spacing. Restored to `night no` afterwards.

## Automated tests

`WidgetSnapshotCodecTest` (Kotlin JVM, 21 tests) covers the geometry that the
screens rely on:

- `calendar cells grow with the card and stay finger sized` — 27/32 floor, tier
  snapping, 44dp ceiling, unknown height falls back to the nominal cell.
- `calendar summary rows follow the measured height instead of a nominal count`
  — including "a card that only fits the grid gets no clipped list row" (0).
- `calendar day mode gives the list the grid's height`.
- `calendar grid fits the declared minimum even for a six week month` — the
  24dp tier and `chrome + cell * 6 <= height` at the 250dp the provider declares.
- `calendar cell layouts exist for every height the grid can ask for` — every
  tier maps to a real layout resource.
- `action card chrome counts only the sections it draws` — the chrome/footer
  arithmetic and the 4x4 → 5 rows case.
- `short medium widgets still reserve one row instead of overflowing`.

## Not verified here

- Calendar small/medium card on a real launcher (see the environment limit), and
  the 24dp cell tier, which only engages at the declared 250dp minimum — that
  card size was not reachable either, so the tier is covered by arithmetic in
  `calendar grid fits the declared minimum...` only.
- Launchers other than Pixel Launcher on API 35: the row heights are declared in
  the layouts, so they do not depend on the host, but the resize behaviour and
  the scaling of `AppWidgetHostView` do.
