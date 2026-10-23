# D Final review round 2 — the four REQUEST_CHANGES items

Baseline: PR #73, reviewed HEAD `003679888f955d4df07297c6317a4f8cbc4a7da7`.
Design truth unchanged: `docs/design/ui-ux-prototypes/d-final/` (four frozen shots,
`app.js` / `style.css`). Presentation only; no database, sync, recurrence,
TaskAllocation-domain, notification or routing change.

## 1. Desktop Todo — compact toolbar, flat list

- `_buildTodoTab` now branches on the desktop breakpoint (1000dp).
- Desktop renders `TodoDesktopToolbar` (`date_strip.dart`): one row with the month
  label, date picker, `全部任务 / 待办箱 / 六件事` and the tag/trash tools on the
  right. The seven-day week row is gone on desktop.
- Mobile keeps `DateStrip` unchanged, including the 48dp week cells.
- Filtering semantics are untouched: the same `_selectedDate` / `_showAllTodos` /
  `sixThingsModeProvider` / `_selectedTagIds` state drives the same list queries.
- Surfaced and fixed a pre-existing mobile overflow in the strip's top row
  (English labels overflowed 390dp by 135px): the chip group is now horizontally
  scrollable, so long labels cannot break the row.

## 2. Global toolbar — compact D Final topbar

- Desktop primary create is a compact `+ 新建` text button (32dp high, 6dp radius,
  primary fill), matching `.new-btn` in `style.css:94-98`; the 48dp circular
  `IconButton.filled` is gone.
- Desktop search is a bordered 236×32 field with a search glyph and the
  `搜索任务与事件` placeholder (`app.js:37-44`), placed at the head of the actions,
  establishing the same search hierarchy as the frozen topbar. Tap still routes to
  `/search`.
- Desktop `toolbarHeight` is 48 (was 52), closer to D Final's 44.
- Mobile keeps icon search and reduces the create affordance to a 32dp rounded-6
  square inside a 48dp tap target (D Final `.m-add`, `style.css:334`), removing the
  filled-circle Material look.
- Creation behaviour is unchanged: `/todo/new`, and `/event/new` with the viewed
  date range on the Calendar tab. The `workspace-create` key is preserved.

## 3. Desktop Action — restored rhythm strip

- `_buildRhythm` (`action_section.dart`) restores the frozen load-distribution bar
  from `app.js:100-110` / `style.css:124-130`: a 10dp track over 06:00–22:00,
  one block per event (solid tint) and per TaskAllocation (light fill plus 1dp
  border), a warm now-marker shown only when the viewed date is today, and
  06/09/12/15/18/21 labels on the right.
- It is rendered on non-mobile widths under the existing summary line and is
  driven only by the existing `actionProjectionProvider` data.
- Now / 接下来 / 今日任务 sections, inspector, checkboxes and recurrence
  behaviour are unchanged. No scoring, scheduling or new domain model.

## 4. Calendar acceptance data — week-spanning seed

- `tool/ui_acceptance/main.dart` now seeds the whole visible week: twelve timed
  events across Monday–Sunday and several slots per day, one multi-day all-day
  event (Wed 00:00 → Fri 00:00, half-open), five deadlines spread across the week,
  and TaskAllocations on Monday, Tuesday, Wednesday and Thursday in addition to
  today's.
- Seed-only change; no production logic touched. The Calendar capture now carries
  the deadline lane, the all-day bar and overlapping timed lanes needed to compare
  against the frozen high-density Calendar shot.

## Evidence

- Anti-tampering disclosure: the pre-commit guard flagged `expect(...)` strings in
  the two touched test files, but they moved because `dart format` reflowed the
  file. Assertion counts rose, not fell: `action_section_test` 41 → 44,
  `home_tab_navigation_test` 15 → 22; every flagged literal is still present.

- Rebuilt `tool/ui_acceptance/main.dart` for web twice (`QA_THEME=light|dark`,
  `QA_LOCALE=zh`), served the build, drove the real `DaySparkApp` with sidebar
  navigation at 1440×900 and 390×844.
- New captures in `shots/`: `desktop-action.png`, `desktop-calendar.png`,
  `desktop-todo.png`, `mobile-action.png`, and dark
  `dark-desktop-action.png`, `dark-desktop-calendar.png`, `dark-desktop-todo.png`.
- Impeccable detector re-run over the changed UI trees
  (`lib/ui/pages/home`, `lib/ui/widgets/calendar`,
  `lib/ui/widgets/todo/date_strip.dart`, `todo_list_tile.dart`,
  `workspace_sidebar.dart`, `lib/core/theme`): exit 0, stdout `[]`, zero findings
  (`/tmp/d-final-detector-2.json`, empty stderr). The detector does not parse Dart
  semantics; this is a bounded static result.
- `dart analyze .` — no issues. `flutter test` — 614 passed, `skipped=0`
  (three new widget tests: desktop Todo swaps the week strip for the toolbar,
  mobile Todo keeps the week strip, rhythm strip is desktop-only).
