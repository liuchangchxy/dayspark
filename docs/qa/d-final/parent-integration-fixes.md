# D Final integration fixes — parent pass

Baseline: branch `codex/d-final-flutter-ui` at `03ae0cf`; design truth PR #71
`docs/design/ui-ux-prototypes/d-final/` (four frozen shots).

Parent integration corrected divergences the role reports and the independent
detector review had left open. Every item below was verified against the frozen
prototype source (`app.js` / `style.css`) rather than against the prose summary.

## Fixed

1. **Stale shell tests asserted the removed FAB** — `test/widget/app_flow_test.dart`
   still expected `FloatingActionButton` on four cases. D Final renders the create
   affordance as a topbar `新建` button (desktop) and a header `+` (mobile); a cobalt
   blob scan of all four frozen shots found no FAB-shaped region. Tests now assert the
   real `workspace-create` entry and keep their original coverage.
2. **Stale "Todos" count** — the same test asserted exactly one `Todos`, which broke
   once the Action filter pills became mobile-only (`app.js:398` `m-filters`).
3. **Desktop Action header carried the wrong control** — the pills were rendered on
   desktop and the summary line was missing. D Final's desktop `page-head` is
   `date-block + summary + 六件事` (`app.js:166-203`) and the pills are mobile-only
   (`app.js:398`). Desktop now renders `N 事件 · N 安排 · N 已逾期`; pills are gated to
   mobile.
4. **Recurrence glyph detached from the title** — it floated after the flexible title
   column. `.todo-title .repeat` (`style.css:308`) puts it inside the title block.
   Moved into the title row; new widget test locks the position, red-before-green.
5. **Two desktop content origins disagreed.** Measured from real 1440×900 captures:
   Action 229 / Todo 221 / Calendar 248. The Todo wrapper (12dp), `DateStrip` (8dp)
   and `_sectionHeader` (16dp) each added their own inset against Home's shared 28dp
   origin, and the Calendar toolbar added a second 16dp on top of it. All now defer to
   the shared origin on desktop; new guard test asserts Action and Todo text share it.
6. **Raw colour in the calendar legend** — `Color(0xFFC75A26)` violated the token rule
   and did not match D Final's amber. Replaced with the theme's semantic token.
7. **Mobile filter label** — the pills used `l.events` (日程); D Final renders 事件
   (`app.js:398`). Now uses the event-legend key.

## Deliberately not changed

- **六件事 on mobile.** D Final does place it on the mobile filter row, but that row
  already carries three pills plus the calendar action at 390dp; adding it produced a
  measured 76px `RenderFlex` overflow. Mobile reaches the toggle from the Todo tab
  strip instead, keeping the "mobile first screen is not crowded" requirement.
- **Todo ordinal column, `?tab=` deep-link, sidebar inventory, `rhythm` strip,
  status bar, alarm/notification sheet.** Pre-existing behaviour outside this
  redesign's boundary, or unreachable in the acceptance harness.
- **Detector/review claims about mobile ordering.** `detector-review.md` states D Final
  prioritises the current task over overdue on mobile; `app.js:400-403` renders
  逾期 → 接下来 → 今日截止. The implementation already matches the prototype; the
  review note is wrong and was not acted on.

## Test-assertion changes (anti-tampering disclosure)

The pre-commit guard reported modified assertions. Each was checked; none weakens
coverage. Assertion counts per file are equal or higher than `03ae0cf`
(`home_widget_service_test` 69→69, `app_flow_test` 29→29, `app_colors_test` 31→31,
`app_theme_test` 13→13, `home_action_rollover_test` 12→12,
`todo_list_tile_test` 14→25, `home_tab_navigation_test` 10→15).

- Most flags are `dart format` line reflows; every flagged string still exists.
- Three expectations changed value, all to the frozen D Final token and each
  independently confirmed against `d-final/style.css`:
  `lightAccent` `#007AFF`→`#2457D6` (`--blue`), `lightBackground`
  `#F2F2F7`→`#F5F6F8` (`--bg`), widget `accent` `#007AFF`→`#2457D6`,
  and card radius 16→10 for the compact D Final surface.
- `home_action_rollover_test` `textContaining('Overdue')` →
  `textContaining('Overdue (1)')`: narrowed to the section header, because the new
  desktop summary line also contains "Overdue". The intent is unchanged and the
  assertion is now more specific, not weaker.
- `app_flow_test` `FloatingActionButton` → the real `workspace-create` entry:
  D Final has no FAB (verified by pixel scan), so the old assertion tested a
  control the frozen design removed.

## Evidence

- `dart analyze .` — no issues.
- `flutter test` — all green, `skipped=0`.
- Real captures from the production `DaySparkApp` (web build of
  `tool/ui_acceptance/main.dart`, isolated seeded Drift database, real sidebar
  navigation): desktop Action / Calendar / Todo at 1440×900 and mobile Action at
  390×844 — see `shots/`. A dark-theme Action capture was also reviewed.
- Measured desktop content origin after the fix: Action 229, Todo 229
  (was 229 / 221). The Calendar toolbar is unindented; its remaining first-glyph
  offset is the segmented control's own internal label padding, and its container
  now starts on the shared origin.

## Honest limits

- The acceptance harness binds a single viewport per build, so the captures are the
  web build of the real app rather than a macOS window. The production widget tree,
  router, providers and Home are the shipped ones.
- Dark theme and English/long-content checks were reviewed by reading the rendered
  build and the code paths, not captured as frozen shots for every page. The dark
  Action capture was inspected; long bilingual strings are covered by widget tests
  (overdue run-over check) rather than by screenshots.
- Calendar's absolute origin still differs from Action/Todo by the segmented
  control's internal padding; this is a control-internal inset, not a container
  misalignment, and is recorded here rather than silently claimed as fixed.

