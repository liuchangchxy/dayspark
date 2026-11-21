# P2 Todo & Detail Spec Fidelity Alignment Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Realign DaySpark Todo (three modes: Unplanned, All, By Date) and Detail panes with the frozen spec in `docs/design/frozen/dayspark-spec.html`:
- Todo header structure: "待办" title + per-mode subtitle + right-hand 筛选 tool + inline 3-mode switch (.mode-switch); remove "By date ⌄" dropdown sheet and red clock.
- By Date mode: date strip (month button + 7-day strip with 44x48 cards, ink selected, red today) + background event band (.bg-band with chips "只做时间背景") + grouping (计划执行 / 截止 / 无日期).
- Task rows: unified with spec task rows (16px check, 13px title, 10px meta, 9.5px due pill, hair border, no card).
- Empty states: centered 27px inbox icon + 15px title + 11.5px sub, without grey background bar; remove bottom orange "Plan this day" full-width button.
- Primary colors: ink (black), no theme orange for primary button/selected states.
- Detail drawer: 380px wide, 50px head (9.5px uppercase kind + 28px circular close), resident only on >= 1180; single column on < 1180.
- Zero raw Chinese text (all l10n via arb).

## Global Constraints
- Only modify: `lib/ui/pages/todo/`, `lib/ui/pages/event/` (detail head), `lib/ui/design/` (minimal additions), `lib/l10n/*.arb`, and corresponding `test/`.
- Do NOT modify: `lib/ui/pages/calendar/`, `home/`, `shell/`, `core/theme/`, `settings/`, `search/`, `tags/`, `ai_chat/`, `server/`, `packages/`, `tool/`, schema, sync protocols, dependencies.
- Flutter binary: `C:\src\flutter\bin\flutter.bat`.
- Do not delete existing tests; update visual assertions to match the new spec contract while preserving business assertions.

---

### Task 1: Localization & App Localizations Generation

**Files:**
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_en.arb`

- [ ] **Step 1: Add new and updated strings in `app_zh.arb` and `app_en.arb`**
  Add:
  - `filter`: "筛选" / "Filter"
  - `filterEmptyHint`: "清除筛选后显示全部。" / "Clear filters to show all."
  - `dayEventsBgSub`: "{count} 项 · 只做时间背景" / "{count} items · background timeline only"
  - `todoAllActiveSummary`: "{active} 项待办 · {completed} 项已完成" / "{active} pending · {completed} completed"
  - `viewNoDateCount`: "查看无日期 {count} 项" / "View {count} unplanned"
  - Update `emptyUnplannedTitle` ("未安排是空的" / "Inbox is empty") and `emptyUnplannedHint` ("从今天或这里捕获的待办会先落到这里。" / "Tasks captured from Today or here land here first.")
  - Update `emptyDateTitle` ("这一天还没有计划" / "Nothing planned for this day") and `emptyDateHint` ("把待办拖 / 安排到这一天，或先从捕获开始。" / "Schedule or plan tasks onto this day, or start with capture.")
  - Update `todosEmptyTitle` ("这里还没有待办" / "No tasks yet") and `todosEmptyHint` ("从捕获条记一件事，它会先进未安排。" / "Capture a task to get started; it lands in Unplanned first.")

- [ ] **Step 2: Run `flutter.bat gen-l10n`**
  Verify generated files in `lib/l10n/`.

- [ ] **Step 3: Run `no_raw_text_guard_test.dart` to verify guard passes**
  Run: `C:\src\flutter\bin\flutter.bat test test/architecture/no_raw_text_guard_test.dart`

---

### Task 2: Detail Drawer & Full-Page Header Spec Alignment

**Files:**
- Modify: `lib/ui/pages/todo/todo_detail_page.dart`
- Modify: `lib/ui/pages/event/event_detail_page.dart`

- [ ] **Step 1: Replace raw English 'TODO' and 'EVENT' with localized kind labels**
  In `todo_detail_page.dart`: kind label `l.todos` ("待办").
  In `event_detail_page.dart`: kind label `l.eventLabel` ("日程").
  Ensure 50px header, 9.5px kind label with 0.09em letter-spacing, and 28px circular close button.

- [ ] **Step 2: Run detail page unit and regression tests**
  Run: `C:\src\flutter\bin\flutter.bat test test/ui/pages/todo/todo_detail_page_test.dart`
  Run: `C:\src\flutter\bin\flutter.bat test test/ui/pages/event/event_detail_regression_test.dart`

---

### Task 3: Todo Page Header, Mode Switch, and Filter Tool

**Files:**
- Modify: `lib/ui/pages/todo/a2_todo_page.dart`

- [ ] **Step 1: Replace `_head`, `_titleBlock`, and `_cardHead` with spec structure**
  - Left: Title "待办" (`l.todos`), per-mode subtitle, and `.mode-switch` (3 tabs: 未安排 / 全部 / 按日期, wash bg, radius 7, padding 3, button 27px, selected: paper bg, ink text, weight 600, shadow).
  - Right: Filter `.tool` (29px, border hair-2, radius 6, 11px ink-2, icon slider 12px, label "筛选" / `l.filter`).
  - Remove "By date ⌄" dropdown sheet (`_openModeSheet`) and red clock (`A2Clock`).

- [ ] **Step 2: Run existing tests and update mode switch interaction assertions**
  Update tests in `test/ui/pages/todo/a2_todo_date_entry_test.dart` and `test/ui/pages/todo/a2_todo_page_defects_test.dart` that tested the old dropdown sheet to use the new `.mode-switch`.

---

### Task 4: By Date Mode Alignment (Date Strip + Timed Events Band + Task Grouping)

**Files:**
- Modify: `lib/ui/pages/todo/a2_todo_page.dart`

- [ ] **Step 1: Implement spec `_dateStrip`**
  - Month button (`.ds-month`, height 28, radius 6, border hair-2, label + chevron 10px, key `todos-date-strip`).
  - 7 day cards (width 44, height 48, radius 7, ink selected with white text, red day number for today when not selected, key `todos-date-strip-today` on today card).
  - Tapping day jumps to date; tapping month button opens month/year picker.

- [ ] **Step 2: Implement `.bg-band`**
  - "当天日程" + "{count} 项 · 只做时间背景".
  - Horizontal list of `.bg-chip` (calendar dot, start time, title; tap opens event detail).

- [ ] **Step 3: Implement By Date task grouping**
  - Groups: `计划执行` (allocations), `截止` (due todos on day), `无日期` (unplanned todos, top 5 with `more-row` if > 5).
  - Remove `A2PlanBar` (orange full-width button) and grey bar.
  - Retain bottom `A2CaptureBar`.

- [ ] **Step 4: Verify tests for date strip and By date**
  Run: `C:\src\flutter\bin\flutter.bat test test/ui/pages/todo/a2_todo_date_entry_test.dart`

---

### Task 5: Task Row & Empty State Fidelity Alignment

**Files:**
- Modify: `lib/ui/pages/todo/a2_todo_page.dart`

- [ ] **Step 1: Align task rows with spec**
  - 16px check (circle, 1.4px border, ink when checked with checkmark icon).
  - 13px title (ink / faint line-through when checked).
  - 10px meta (calendar dot, name, plan meta with clock icon, repeat, missed).
  - 9.5px due pill (amberSoft / redSoft).
  - 54px min-height, 1px hair bottom border.
  - Trailing action: plan/schedule action or undo action.
  - Primary button/selected states use ink (black), not theme orange.

- [ ] **Step 2: Align empty states with spec**
  - Centered empty state: 27px tray icon (color `#B5B5AB`), 15px title (weight 600, ink), 11.5px sub (muted), padding 76px vertical.
  - No grey background bar.
  - Used for inbox empty, all empty, date empty, filter empty.

---

### Task 6: Breakpoint Enforcement (>= 1180 Resident 380 Column) & Narrow Layout

**Files:**
- Modify: `lib/ui/pages/todo/a2_todo_page.dart`

- [ ] **Step 1: Enforce >= 1180 resident detail column**
  - >= 1180: inline 380 column (`widget.detail ?? const _EmptyDetailColumn()`).
  - < 1180 (800, 1000, 1179): single column without resident 380 column; if detail is open, overlay drawer.
  - Verify 800, 1000, 1179, 1180, 1440 layout with no overflow.

- [ ] **Step 2: Run `calendar_geometry_test.dart` to verify breakpoint contract**
  Run: `C:\src\flutter\bin\flutter.bat test test/ui/pages/calendar/calendar_geometry_test.dart`

---

### Task 7: Full Test Suite, Guard, and Build Verification

- [ ] **Step 1: Run `no_raw_text_guard_test.dart`**
- [ ] **Step 2: Run all todo, event, calendar tests**
- [ ] **Step 3: Run `flutter.bat analyze` (0 issues)**
- [ ] **Step 4: Run `flutter.bat build windows --debug`**

---

### Task 8: Real Screenshots & QA Delivery

**Files:**
- Output to: `docs/qa/ui-refresh/p2-todo/`
  - 1440x900: `todo_unplanned_1440x900.png`, `todo_all_1440x900.png`, `todo_by_date_1440x900.png`, `detail_todo_drawer_1440x900.png`
  - 390x844: `todo_unplanned_390x844.png`, `todo_all_390x844.png`, `todo_by_date_390x844.png`, `detail_todo_phone_390x844.png`

- [ ] **Step 1: Generate real full-page screenshots including app top bar and shell**
- [ ] **Step 2: Save to `docs/qa/ui-refresh/p2-todo/`**
- [ ] **Step 3: Report commit SHA, gates, and changes**
