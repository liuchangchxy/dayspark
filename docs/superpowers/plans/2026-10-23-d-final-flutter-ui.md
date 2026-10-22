# D Final Flutter UI Implementation Plan

> **For agentic workers:** Use repository docs/process/EXECUTION.md role-separated implementation and review.

**Goal:** Implement the frozen D Final across Action, Calendar, Todo, Shell and Theme, prove real rendered desktop/mobile acceptance and publish one unmerged PR.

**Architecture:** Retain Riverpod projections, writers, router and kalender engine. Change only presentation composition and existing theme values.

**Spec:** SPEC.md D Final contract; design PR #71 dc3715c98a0762365d5b09c79087f845b07961b9.

## Tasks and boundaries
- [ ] Action grouped rows, now/upcoming, selection-only inspector: action_section.dart; preserve recurring instance identity, errors/history/completion, use existing providers.
- [ ] Calendar Event/Allocation grammar, separate deadline lane: calendar widgets; Home feeds ordinary deadline data; existing drag guards stay.
- [ ] Todo flat title/date rows and 48dp independent checkbox: todo_list_tile.dart; occurrence selector stays.
- [ ] Shell/Theme: Home + WorkspaceSidebar, unified 200+28 desktop origin, mobile bottom nav, existing theme extension API and readable palette.
- [ ] Verify meaningful focused tests, dart analyze ., flutter test. Capture real Flutter desktop/mobile with isolated seeded data, compare frozen shots, one bounded polish pass; document light/dark and long content checks.
- [ ] Independent review, stage scoped diff, commit, push single branch, create one PR, inspect existing CI; never merge.

## Evidence
Task briefs, reports, seam rulings and completion evidence live in docs/qa/d-final/.
No database schema, recurrence engine, scheduling model, sync or unrelated feature changes. No new production dependency or CI gate.
