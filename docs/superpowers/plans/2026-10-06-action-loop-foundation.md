# Phase 1 — Action Loop Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement Phase 1 — Action Loop Foundation: clean up deadline semantics, add the derived Today / Action projection as default home view, support scheduling an existing ordinary Todo into a TaskAllocation from Calendar empty slots, enable direct Todo completion from Action, and restore the direct pending Checkbox affordance under ordinal/reordering.

**Architecture:**
- A derived `ActionProjectionProvider` (no new DB entity) calculates today's events, active ordinary-Todo task allocations, due today ordinary todos, overdue ordinary todos, and compact unplanned inbox count.
- `defaultTabProvider` and `HomePage` navigation extended to three projections: Action (default), Calendar, and Todos, preserving existing saved preferences.
- Calendar empty time slot tap presents a choice between creating an Event or scheduling an existing ordinary Todo into a TaskAllocation.
- `TodoCreatePage` initializes with `_dueDate = null` (no default to today). Startup bulk overdue deadline-mutation prompt is removed.
- `TodoListTile` keeps the interactive Checkbox on pending rows even when an ordinal index is present.
- Existing domain writers (`TodoWriter.toggleTodoCompletion`, `TaskAllocationWriter.create`) handle all mutations; Todo `dueDate` remains immutable across allocation lifecycles.

**Tech Stack:** Flutter, Dart, Riverpod, Drift (SQLite), kalender, go_router.

**Spec:** SPEC.md §1.1, §3.1, §3.5

## Global Constraints

- SPEC-first: Document changes in `SPEC.md`, `DECISIONS.md`, and `docs/ROADMAP.md` before implementation.
- Preserve Frozen Product Rulings: Todo = obligation, TaskAllocation = planned execution interval, Event = independently occurring event, dueDate = deadline fact, Calendar / Action = projections.
- No new persistent entity for Action / DailyPlan.
- Invariant: TaskAllocation lifecycle operations (create, reschedule, cancel, complete) must NEVER mutate Todo.dueDate.
- Zero issues on `dart analyze .` and all green on `flutter test`.
- All user-facing strings localized in both `app_en.arb` and `app_zh.arb`.

## Review Focus

1. Creating an ordinary Todo without selecting a deadline leaves `dueDate == null`; selecting a deadline preserves it.
2. Startup overdue prompt is gone; overdue Todos retain their original `dueDate` and appear in Overdue sections as factual deadlines.
3. Scheduling an ordinary Todo from Calendar empty slot creates a `TaskAllocation`, does NOT create an `Event`, and leaves `Todo.dueDate` unchanged.
4. Action projection correctly segregates and labels allocations (planned time) vs deadlines (due/overdue), and allows direct Todo completion through `toggleTodoProvider`.
5. Pending Todo row displays both the ordinal number and an active Checkbox; clicking the Checkbox toggles completion without opening details.

---

### Task 1: Document Spec, Decisions, and Roadmap Updates

**Files:**
- Modify: `SPEC.md`
- Modify: `DECISIONS.md`
- Modify: `docs/ROADMAP.md`

- [ ] **Step 1: Update SPEC.md with Phase 1 Action Loop Foundation contracts**
Document:
- Today / Action projection rules (derived projection, default home entry, membership, visual/semantic distinction between plan and deadline).
- Ordinary Todo deadline semantics (no default `dueDate`, overdue items retain factual `dueDate`, TaskAllocation operations never mutate `dueDate`).
- Calendar empty-slot scheduling flow (create Event vs schedule existing ordinary Todo).
- Pending row Checkbox affordance and six-things as presentation/focus cap.

- [ ] **Step 2: Update DECISIONS.md with ADR entry**
Add lightweight ADR `[2026-10-06] Phase 1 — Action Loop Foundation`:
Record background, core decisions, SPEC section mappings, impact scope, and rulings with cost of wrong judgment.

- [ ] **Step 3: Update docs/ROADMAP.md**
Update Roadmap status for Action Loop Foundation / Phase 1.

---

### Task 2: Deadline Semantic Cleanup & Invariant Test

**Files:**
- Modify: `lib/ui/pages/todo/todo_create_page.dart`
- Modify: `lib/ui/pages/home/home_page.dart`
- Test: `test/domain/records/task_allocation_deadline_invariant_test.dart`
- Test: `test/ui/pages/todo/todo_create_deadline_test.dart`

- [ ] **Step 1: Write deadline invariant tests and Todo create tests**
Write failing tests verifying:
- TaskAllocation create, reschedule, cancel, and Todo completion do not change `todo.dueDate`.
- `TodoCreatePage` initializes with `_dueDate == null`.
- Startup overdue check prompt is removed from `HomePage`.

- [ ] **Step 2: Run tests to verify failures**
Run `flutter test test/domain/records/task_allocation_deadline_invariant_test.dart` and `test/ui/pages/todo/todo_create_deadline_test.dart`.

- [ ] **Step 3: Implement deadline semantic cleanup**
- In `lib/ui/pages/todo/todo_create_page.dart`: Set `_dueDate = null;` by default.
- In `lib/ui/pages/home/home_page.dart`: Remove `_checkOverdueTodos` from startup and day rollover.

- [ ] **Step 4: Verify tests pass**
Run `flutter test test/domain/records/task_allocation_deadline_invariant_test.dart` and `test/ui/pages/todo/todo_create_deadline_test.dart`.

---

### Task 3: Restore Pending Checkbox on Todo Rows

**Files:**
- Modify: `lib/ui/widgets/todo/todo_list_tile.dart`
- Test: `test/ui/widgets/todo/todo_list_tile_test.dart`

- [ ] **Step 1: Write test for TodoListTile pending row with ordinal index**
Add tests in `test/ui/widgets/todo/todo_list_tile_test.dart`:
- When `index != null` and `!isCompleted`: Checkbox is rendered and tapping it toggles completion; ordinal number is displayed as a separate visual indicator.

- [ ] **Step 2: Run test to verify failure**
Run `flutter test test/ui/widgets/todo/todo_list_tile_test.dart`.

- [ ] **Step 3: Implement Checkbox + Ordinal in TodoListTile**
Update `lib/ui/widgets/todo/todo_list_tile.dart`:
Display the ordinal indicator alongside the active Checkbox on pending rows so that completion is never displaced.

- [ ] **Step 4: Verify test passes**
Run `flutter test test/ui/widgets/todo/todo_list_tile_test.dart`.

---

### Task 4: Calendar Empty-Slot Scheduling for Ordinary Todos

**Files:**
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_zh.arb`
- Create: `lib/ui/widgets/calendar/calendar_slot_sheet.dart`
- Modify: `lib/ui/pages/home/home_page.dart`
- Test: `test/ui/widgets/calendar/calendar_slot_sheet_test.dart`

- [ ] **Step 1: Add l10n strings and generate localizations**
Add strings for:
- `scheduleTodo` ("Schedule Todo" / "安排待办")
- `createEventOption` ("Create Event" / "新建日程")
- `selectTodoToSchedule` ("Select Todo to Schedule" / "选择要安排的待办")
- `noSchedulableTodos` ("No pending todos to schedule" / "没有可安排的待办")
Run `flutter gen-l10n`.

- [ ] **Step 2: Write test for slot action sheet and scheduling**
Write tests verifying:
- Tap empty slot triggers sheet offering Create Event vs Schedule Todo.
- Selecting Create Event navigates to event creation.
- Selecting Schedule Todo shows ordinary pending Todos, schedules TaskAllocation with exact interval, preserves `dueDate`, and does not create an Event.

- [ ] **Step 3: Implement calendar slot action sheet & hook into HomePage**
- Create `calendar_slot_sheet.dart` to present options and candidate ordinary Todo picker.
- Hook into `home_page.dart:onTimeSlotTapped`.

- [ ] **Step 4: Verify tests pass**
Run `flutter test test/ui/widgets/calendar/calendar_slot_sheet_test.dart`.

---

### Task 5: Derived Today / Action Projection & HomePage Integration

**Files:**
- Create: `lib/domain/providers/action_projection_provider.dart`
- Modify: `lib/domain/providers/default_tab_provider.dart`
- Modify: `lib/ui/pages/settings/settings_sections/appearance_section.dart`
- Create: `lib/ui/pages/home/action_section.dart`
- Modify: `lib/ui/pages/home/home_page.dart`
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_zh.arb`
- Test: `test/domain/providers/action_projection_provider_test.dart`
- Test: `test/ui/pages/home/action_section_test.dart`
- Test: `test/ui/pages/home/home_tab_navigation_test.dart`

- [ ] **Step 1: Add l10n strings for Action projection**
Add strings for:
- `action` ("Action" / "行动")
- `actionFirst` ("Action First" / "行动优先")
- `scheduledSection` ("Scheduled" / "计划执行")
- `dueTodaySection` ("Due Today" / "今日截止")
- `unplannedInbox` ("Unplanned Inbox" / "待安排待办")
- `unplannedInboxCount` ("{count} unplanned" / "{count} 条未安排")
Run `flutter gen-l10n`.

- [ ] **Step 2: Write unit test for ActionProjectionProvider**
Test:
- Aggregates today's events, ordinary task allocations, due today ordinary todos, overdue ordinary todos, unplanned count.
- If a Todo has both today's allocation and today's due date, it is present in both without loss of either fact.
- Completed todos are segregated into completed collection.

- [ ] **Step 3: Implement ActionProjectionProvider**
Create `lib/domain/providers/action_projection_provider.dart` watching database and providers.

- [ ] **Step 4: Update defaultTabProvider and Appearance Settings**
- Update `AppTab` enum: `{ action, calendar, todos }`. Default is `action`.
- Existing `'calendar'` and `'todos'` preferences continue to resolve to `AppTab.calendar` and `AppTab.todos`.
- Update `AppearanceSection` dialog to offer all three options.

- [ ] **Step 5: Implement ActionSection UI and hook into HomePage**
Create `ActionSection`:
- Overdue section (if any) with original deadline and direct completion checkbox.
- Scheduled timeline (Events + TaskAllocations) with planned execution interval and direct completion checkbox for allocations.
- Due today section with direct completion checkbox.
- Compact Inbox / Unplanned entry showing count and navigating to Todos tab.
- Collapsed Completed section.
Update `HomePage` to render `ActionSection` on Tab 0, `CalendarSection` on Tab 1, and `TodoSection` on Tab 2.

- [ ] **Step 6: Write widget tests for ActionSection and Tab navigation**
Verify:
- ActionSection renders all sections correctly.
- Tapping checkbox on an ordinary Todo or TaskAllocation calls `toggleTodoProvider` and completes the task.
- Home default tab respects saved preference and defaults to Action.

- [ ] **Step 7: Run all related tests and ensure they pass**

---

### Task 6: Full Verification, Gates & Code Quality

**Files:**
- All touched files

- [ ] **Step 1: Run l10n check & outlet verification**
Run `flutter gen-l10n` and verify all outlets are covered.

- [ ] **Step 2: Run dart analyze .**
Ensure 0 issues.

- [ ] **Step 3: Run full flutter test**
Ensure 100% passing tests with skipped=0.

- [ ] **Step 4: Check git diff and version consistency**
Verify no unintended file modifications or Phase 2 leakage.

---

### Task 7: Git Commit, Push & PR Creation

- [ ] **Step 1: Commit with descriptive message**
Format: `feat: establish the Action Loop foundation`

- [ ] **Step 2: Push feature branch to origin**
Push `feature/action-loop-foundation`.

- [ ] **Step 3: Create PR using gh pr create**
Include:
- Frozen Issue #3 / Phase 1 references (`Refs #3`)
- Base SHA: `ced2c0663d1f72da4a3dcf95ad8a081bdc4fb8ff`
- Changed behavior
- Preserved invariants
- Explicit non-goals
- Test verification results
- Rulings disclosure
