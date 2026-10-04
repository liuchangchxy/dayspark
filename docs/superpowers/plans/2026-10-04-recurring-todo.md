# Recurring Todo — Implementation Plan

Status: **R1 shared recurrence core complete; R2 remains separately scoped**
Contract: `SPEC.md` §3.1.1
Source audit: `docs/superpowers/plans/2026-10-04-recurring-todo-design-spike.md`

## Objective and scope

Implement local-calendar recurring Todo series with stable occurrence identities and safe occurrence-bound TaskAllocation, using one client/server recurrence engine. Preserve existing TaskAllocation behavior and Todo/Event separation.

Out of scope: per-occurrence completion, skip-one, edit-this, edit-this-and-future, detached overrides, EXDATE/RDATE/THISANDFUTURE, automatic orphan migration, automatic legacy-zone inference, and bulk Allocation generation.

## Gate 0 — Resolve design and toolchain blockers (must pass first)

1. Use `C:\src\flutter\bin\flutter.bat` and `dart.bat` directly; the SDK is installed but absent from PATH. Do not reinstall or upgrade.
2. Spike PASS: exact locked `rrule` vectors covered all first-subset frequencies/parts, parser rejection, unknown-token behavior, month-end and COUNT/UNTIL cases. Keep the strict allowlist wrapper in the future engine because library parsing alone silently ignores unknown parts.
3. Spike PASS: New York gap/fold, explicit candidate resolution, Shanghai viewer-zone invariance, and nominal-key/resolved-instant separation.
4. Spike PASS: four ICS forms, DUE, RRULE, nested VTIMEZONE; parser keeps raw evidence but current converter loses it. Add import wrapper before conversion.
5. Gap policy is resolved: RFC gap-before-offset; fold-first; nominal key remains distinct from resolved instant.
6. Temporary pure Dart package path dependency resolved and emitted identical vectors under client/server configs. Before product rollout align timezone to 0.11.1 on both; check default local-name change `UTC` to `Etc/UTC`.

See captured outputs and boundaries in the source-audit report. Product implementation must still add production tests and keep recurrence unsupported behavior explicit.

## Phase 1 — Shared recurrence core

R1 implementation and verification are recorded in `DECISIONS.md` and `docs/ROADMAP.md`.

- Add pure Dart `packages/dayspark_recurrence`; consume from client and server.
- Align client/server `timezone` package version and record tzdata version; keep engine zone resolution independent of `tz.local`.
- Define `LocalDate`, `LocalDateTime`, `RecurrenceAnchor`, `RecurrenceSpec`, `OccurrenceKey`, and explicit validation/resolution results. Keep DTO serialization in `dayspark_contracts`.
- Add canonical RRULE parser/allowlist; validate combinations and DATE restrictions; bound expansion.
- Implement local-calendar candidate generation, DATE-only identity, explicit IANA zone lookup, explicit gap/fold resolution, and stable versioned keys.
- Fail closed for DATE-TIME windows beyond the pinned tzdata's common future-transition horizon; refresh the shared dependency locks together to extend it.
- Add golden vectors for anchors, recurrence dates, local keys, UTC instants, COUNT, UNTIL, month-end, DST, invalid/unsupported rules, and query-window edges.
- Keep TZData initialization inside/injected through engine API; do not read `tz.local`.

## Phase 2 — Atomic sync contract and persistence

- Add `RecurrenceSpec` wire DTO and a whole-object recurrence revision to Todo payload. Non-repeating Todo carries no recurrence zone.
- Update client Drift migration additively; do not infer a zone for existing RRULE rows.
- Update server validation/storage/applier so a partial anchor/rule/zone tuple is rejected and concurrent recurrence changes are resolved as one unit. Keep unrelated Todo field LWW unchanged.
- Add capability/version rollout rules so older clients safely preserve unknown recurrence objects and never rewrite them from old fields.
- Add client/server/contracts serialization, migration, conflict, partial-update, and round-trip tests.

## Phase 3 — Lazy legacy migration and ICS boundary

- Classify existing recurring Todo as `unknownLegacy`; prompt only when a formal recurrence operation is requested.
- Persist user's explicit interpretation atomically and test cancel/retry/offline flows.
- Wrap `enough_icalendar` import/export to inspect raw property parameters before typed getters. Preserve DATE, floating, UTC, known IANA TZID, and custom VTIMEZONE distinctions.
- Unsupported custom VTIMEZONE or lossy RRULE remains visible/read-only where safe and cannot create occurrence-bound Allocation.
- Add ICS fixtures for all four basic inputs, VTIMEZONE, DUE vs DTSTART anchor selection, malformed RRULE, and export/import semantic comparison.

## Phase 4 — Occurrence-bound Allocation integration

- Update Allocation creation to require a resolved, supported occurrence key and actual chosen execution interval.
- Keep occurrence identity fixed while rescheduling Allocation.
- Ensure old occurrence keys remain historical/orphaned after series RRULE/anchor/timezone edits or recurrence removal; do not rebind.
- Extend client/server allocation validation and Calendar projection; maintain existing busy-time completion/trash/tombstone behavior.
- Add tests for dueDate independence, start-vs-due anchoring, date-only prompt, unknown legacy, edited series orphaning, and old-device payload handling.

## Phase 5 — Acceptance and rollout

- `dart analyze .` with zero issues; full `flutter test`; package/server/contracts test suites; `git diff --check`.
- Client/server golden vectors must match for keys, status, instants, and window results using pinned engine and timezone data.
- Run migration tests against existing databases and sync tests against old/new client capability combinations.
- Perform manual UI/platform acceptance for timezone selection and lazy legacy prompt on mobile and desktop.
- Release order: protocol-capable server and clients behind explicit capability; only then expose occurrence Allocation creation.

## Stop conditions

- Stop before product implementation if any captured Design Spike vector regresses or if a change to the gap policy is proposed without revising SPEC.
- Stop if client/server engine vectors differ, if unsupported input is silently normalized, or if legacy series get an inferred zone.
- No automatic orphan migration, bulk series Allocation, or additional RFC override features in this phase.

## Completion evidence

Attach exact test outputs, the selected gap ruling, source/lock versions, schema and protocol compatibility matrix, and measured client/server golden-vector equality. Documentation-only completion or a green package unit test alone is not product acceptance.
