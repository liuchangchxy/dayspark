# P2 Spec Fidelity Structural Correction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Realign DaySpark P2 (Calendar, Todo, and Details) with the frozen spec in `docs/design/frozen/dayspark-spec.html`: replace the 88px/dawn-fold scroll model with the authoritative 08:00–20:00 / 648px / 54px-hour time scale, reconstruct week/day/month blocks and lanes, enforce >=1180 breakpoint for Todo inline 380 detail drawer while keeping 800–1180 narrow-mode single-column, upgrade drawer header to 50px with 28px circular button, fix P2 defects, and verify against all gates with real screenshots.

**Architecture:**
- Geometry & Scale: The time grid in Week and Day views is mapped strictly by `pct(m) = ((m - 480) / 720).clamp(0.0, 1.0) * 100` over a 648px height (54px per hour from 08:00 to 20:00). All time-block positioning, slot-ghosts, now-lines, and tap hit-tests use this single mapping.
- Desktop vs Mobile: Desktop arranges overlapping events in side-by-side lanes (`left: lane/lanes * 100%`, `width: 100/lanes%`), while mobile maintains clear readable stacked lists.
- Detail Drawer Breakpoint: The 380px inline detail column only shows on width >= 1180. Widths below 1180 (including 800–1180) use narrow-mode single-column navigation without inline detail column or overflow.
- Detail Drawer Chrome: 50px header, 9.5px uppercase kind label, 28px circular close button with 1px border.

**Tech Stack:** Flutter 3.29.x, Riverpod 2.6, Drift, Dart.
**Spec:** `docs/design/frozen/dayspark-spec.html`

## Global Constraints
- Only modify: `lib/ui/pages/calendar/`, `lib/ui/pages/todo/`, `lib/ui/pages/event/`, `lib/ui/widgets/calendar/`, `lib/domain/providers/calendar_view_provider.dart`, `lib/l10n/*.arb`, and corresponding `test/`.
- Do NOT modify: `lib/core/theme/`, `lib/ui/design/`, `lib/ui/shell/`, `lib/ui/pages/home/`, `settings/`, `search/`, `tags/`, `ai_chat/`, `server/`, `packages/`, `tool/`, Drift schema, sync protocols, `pubspec.yaml`.
- Flutter binary: `C:\src\flutter\bin\flutter.bat`.
- Do not delete existing tests; update assertions to match the new spec contract.
- Touch targets >= 48x48 on mobile; desktop cursor and focus maintained.
- All gates must pass: `flutter.bat analyze` (0 issues), `flutter.bat test` (all green, skipped=0), `flutter.bat build windows --debug`.
- Real screenshots saved to `docs/qa/ui-refresh/p2/`.

## Review Focus
1. Time grid hit testing: tapping a position in 08:00–20:00 snaps accurately to 30-minute intervals without off-by-one errors from the old 88px/hour math.
2. Clamping edge cases: events or deadlines starting before 08:00 or ending after 20:00 clamp cleanly to 0% and 100% without overflowing the 648px box.
3. Resizing window through 1180dp: transition between single-column and master-detail in Todo does not trigger RenderFlex overflow or lose selected task state.
4. Drawer circular close button and draft saving: clicking close or navigating away commits/cancels edits according to existing draft semantics without unhandled timer leaks.
5. Calendar filtering: hiding a calendar filters events, task allocations, and deadline markers simultaneously, while the hidden banner reflects accurate hidden counts and restores properly.

---

### Task 1: Time Scale & Axis Refactoring (08:00–20:00, 648px, 54px/hour)

**Files:**
- Modify: `lib/ui/pages/calendar/a2_calendar_views.dart`
- Modify: `lib/ui/widgets/calendar/calendar_shared.dart`
- Test: `test/ui/pages/calendar/a2_calendar_page_test.dart`

**Interfaces:**
- Consumes: `CalendarNowProvider`, `AppTheme`
- Produces: `A2TimeScale` / `pct(m)` mapping utility with `kA2VisibleStartMinutes = 480` (08:00), `kA2VisibleEndMinutes = 1200` (20:00), `kA2AxisHeight = 648.0`, `kA2HourHeight = 54.0`.

- [ ] **Step 1: Write unit tests for new time scale calculations**
  Verify `offsetOf(minute)`, `rangeAt(dy)`, and hour labels [08, 10, 12, 14, 16, 18, 20].

- [ ] **Step 2: Run test to verify failure**
  Run: `C:\src\flutter\bin\flutter.bat test test/ui/pages/calendar/a2_calendar_page_test.dart`

- [ ] **Step 3: Implement new A2TimeScale and replace _A2Axis**
  Replace the 88px/dawn-fold scroll model in `a2_calendar_views.dart` with the 648px, 54px/hour model. Position hour labels at `[8, 10, 12, 14, 16, 18, 20]` using percentage positioning.

- [ ] **Step 4: Update time grid scroll wrapper**
  Ensure week/day time grid sits comfortably in a scrollable container if height is constrained, but retains fixed 648px internal scale.

- [ ] **Step 5: Run tests and verify PASS**
  Run: `C:\src\flutter\bin\flutter.bat test test/ui/pages/calendar/a2_calendar_page_test.dart`

---

### Task 2: Block Geometry, Lanes, Markers & Day/Week/Month Grids

**Files:**
- Modify: `lib/ui/pages/calendar/a2_calendar_views.dart`
- Modify: `lib/ui/widgets/calendar/calendar_deadline_lane.dart`
- Test: `test/ui/pages/calendar/a2_calendar_page_test.dart`

**Interfaces:**
- Consumes: `CalBlockItem`, `TaskAllocationCalendarItem`, `CalendaEventAdapter`, `CalendarDeadline`
- Produces: Updated `_A2TimeBlock`, `_A2NowLine`, `_dlMarker`, `_A2DesktopMonthCell`, `_dayHeadbar`

- [ ] **Step 1: Write test for block geometry and marker specifications**
  Assert radius 4, border-left 3px (event) / 2px (plan), title 9.5/600, meta 8.5, hide meta when height < 6%, now line 1.5px with 6px dot, deadline marker 1.5px with 6px dot and 8px label.

- [ ] **Step 2: Run test to verify failure**

- [ ] **Step 3: Implement CalBlock and Marker updates**
  Update `_A2TimeBlock`, now line, and deadline marker styling according to the exact spec CSS values.
  Update day headbar to 42px.
  Update all-day grid (7 columns, min-height 30) and deadline row (56px + 1fr, min-height 30).
  Update desktop month grid (7 columns, min-height 104px per row, 30px week head, 10.5 date number, red pill for today, 9px chips with 3x9 color bars, 8.5 `+N`).

- [ ] **Step 4: Run tests and verify PASS**

---

### Task 3: Todo Narrow Screen & Detail Breakpoint (1180dp)

**Files:**
- Modify: `lib/ui/pages/todo/a2_todo_page.dart`
- Test: `test/ui/pages/todo/a2_todo_page_defects_test.dart`

**Interfaces:**
- Consumes: `MediaQuery.sizeOf(context).width`
- Produces: Enforced >= 1180 inline 380 drawer rule; single-column for 800–1180 without 380 column; overflow-safe layout.

- [ ] **Step 1: Write test for width 800, 1000, 1179, and 1180 in Todo page**
  Verify that at 800–1179 no 380 column exists; at >= 1180 the 380 column is present.

- [ ] **Step 2: Run test to verify failure**

- [ ] **Step 3: Update a2_todo_page.dart layout builder**
  Ensure the 380px column is conditionally included only when width >= 1180, and when included cannot overflow the viewport.

- [ ] **Step 4: Run tests and verify PASS**

---

### Task 4: Detail Drawer Chrome & Form Fidelity

**Files:**
- Modify: `lib/ui/pages/todo/todo_detail_page.dart`
- Modify: `lib/ui/pages/event/event_detail_page.dart`
- Test: `test/ui/pages/todo/todo_detail_page_test.dart`
- Test: `test/ui/pages/event/event_detail_regression_test.dart`

**Interfaces:**
- Consumes: `AppLocalizations`, `AppTheme`
- Produces: 50px drawer header, 9.5px uppercase kind label, 28px circular close button with 1px border.

- [ ] **Step 1: Write test for drawer header geometry**
  Verify header height 50, kind label styling, 28px circle close button with border.

- [ ] **Step 2: Run test to verify failure**

- [ ] **Step 3: Implement new drawer header in TodoDetailPane and EventDetailPane**
  Replace the old inline close button with the spec-compliant drawer header bar and circular button while keeping draft saving and synchronization behaviors.

- [ ] **Step 4: Run tests and verify PASS**

---

### Task 5: Fix P2 Defects (Filter, Hidden Banner, Overdue Colors, Focus)

**Files:**
- Modify: `lib/ui/pages/calendar/a2_calendar_page.dart`
- Modify: `lib/ui/widgets/calendar/calendar_deadline_lane.dart`
- Modify: `lib/ui/pages/todo/a2_todo_page.dart`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_zh.arb`
- Test: `test/ui/pages/calendar/a2_calendar_page_test.dart`
- Test: `test/ui/pages/todo/a2_todo_page_defects_test.dart`

**Interfaces:**
- Consumes: `calendarHiddenFilterProvider`, `calendarsProvider`
- Produces: Deadline filtering by calendar, hidden banner with hidden item counts, proper overdue colors.

- [ ] **Step 1: Write tests for deadline filtering and hidden banner counts**

- [ ] **Step 2: Run tests to verify failure**

- [ ] **Step 3: Implement fixes**
  Attach `calendarId` to `CalendarDeadline` and filter deadlines alongside events/allocations.
  Update `_CalHiddenBanner` to show hidden item count and calendar names.
  Verify overdue color contrast and input focus retention.

- [ ] **Step 4: Run tests and verify PASS**

---

### Task 6: Comprehensive Test Suite & New Geometric Assertions

**Files:**
- Modify: `test/ui/pages/calendar/a2_calendar_page_test.dart`
- Modify: `test/ui/pages/todo/a2_todo_page_defects_test.dart`
- Create: `test/ui/pages/calendar/calendar_geometry_test.dart`

- [ ] **Step 1: Update old dawn fold tests to new 08:00–20:00 contract**
- [ ] **Step 2: Implement dedicated `calendar_geometry_test.dart`**
  Verify: axis height 648, hour 54, visible range 08:00–20:00, block percentage positioning, narrow screen no 380 column.
- [ ] **Step 3: Run all UI and unit tests for calendar, todo, and event**
  Verify: 0 failures, 0 skipped.

---

### Task 7: Gates & Real Screenshots

**Files:**
- Generate: `docs/qa/ui-refresh/p2/*.png`
- Document: QA Report in final output

- [ ] **Step 1: Run `C:\src\flutter\bin\flutter.bat analyze` and fix any issues (0 issues target)**
- [ ] **Step 2: Run targeted test suites and then full test suite**
- [ ] **Step 3: Run `C:\src\flutter\bin\flutter.bat build windows --debug`**
- [ ] **Step 4: Capture real screenshots on Windows**
  Capture Calendar (Week, Day, Month) at 1440x900 and 390x844.
  Capture Todo (3 modes) at 1440x900 and 390x844.
  Capture Detail drawer at 1440x900 and 390x844.
  Save to `docs/qa/ui-refresh/p2/`.
