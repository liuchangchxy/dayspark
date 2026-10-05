# Recurring Todo — Implementation Plan

Status: **R1–R4 committed locally; R4 independent delta review PASS. Windows GUI smoke remains pending.**
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

R2 contract in this phase is `SPEC.md` §3.1.1. Persist `anchor_source`, `anchor_value_type`, `anchor_value`, `time_zone`, normalized `rrule`, `legacy_state`, and `recurrence_revision` as structured nullable columns on Todo. A complete `knownZoned` tuple is present together; `unknownLegacy` keeps tuple columns null and preserves old fields. Non-recurring rows have no recurrence state. Upgrade current client schema v11 to v12 additively and verify real v11→v12 close/reopen migration with Todo relations and TaskAllocation unchanged.

Wire uses one nested `recurrenceSpec` object, `recurrenceRevision`, and `recurrenceLegacyState`. Ordinary Todo fields retain field-level LWW. Server validates and resolves the recurrence object atomically; equal revision ties use a deterministic whole-object winner. Legacy clients can omit new keys and read the compatibility projection, but cannot write legacy recurrence fields over an active new recurrence. Independent fields in that op remain eligible for LWW.

New and edited series must flow through TodoWriter; remote apply validates without echo; legacy confirmation updates state, tuple, revision, projection, and outbox in one RecordScope transaction. New model recurrence creation requires a full spec. Old rrule-only MCP/service writes must be explicitly rejected until supplied a zone and local anchor. ICS imports without authoritative IANA wall-time evidence remain unknownLegacy; no converter-derived UTC instant is treated as an anchor.

Acceptance includes migration cases for ordinary/start-only/due-only/start+due/completed/trashed/TaskAllocation-linked Todo and tags/attachments/reminders; DATE and DATE-TIME persistence; contract old-payload parsing; compatibility write rejection; and conflict cases A–E from the R2 brief. Recurrence tuple must never be field-merged, and remote apply must not create outbox echo.

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

R3 completion on 2026-10-05:

- Added `TodoOccurrence` as a finite-window read-only projection over the shared engine; DATE values retain null resolved instants. `expandTodoOccurrences` distinguishes ordinary, unknown legacy, unsupported, and expanded outcomes.
- Added shared `isOccurrenceValidForSpec`; client writer and server sync validation use it. Repeating allocations require a valid non-null occurrence key; unknown legacy is rejected; ordinary Todos retain null keys.
- Calendar projection includes valid recurring allocations and hides orphan keys. Todo detail keeps every allocation visible and marks orphan associations. Active orphan intervals remain busy; cancelled/completion-invalidated and unresolved items do not.
- Todo arrange UI exposes a bounded 90-day occurrence picker and then a separately selected actual execution interval. No recurrence occurrence is projected as a timed block by itself.
- Due projection is intentionally absent: R2 has no relative local due semantics, and UTC duration subtraction would be DST-unsafe.
- Verification: root analyze clean; root Flutter suite 435 passed; recurrence 19, contracts 52, server 233, wrapper 9, CLI 20 passed; two-device occurrence identity round-trip passed. Exact final stage gates are recorded in the R3 completion report and DECISIONS.

## Phase 5 — Acceptance and rollout

- `dart analyze .` with zero issues; full `flutter test`; package/server/contracts test suites; `git diff --check`.
- Client/server golden vectors must match for keys, status, instants, and window results using pinned engine and timezone data.
- Run migration tests against existing databases and sync tests against old/new client capability combinations.
- Perform manual UI/platform acceptance for timezone selection and lazy legacy prompt on mobile and desktop.
- Release order: protocol-capable server and clients behind explicit capability; only then expose occurrence Allocation creation.

R4 work started 2026-10-05:

- Added raw-property-aware VTODO recurrence import. Explicit IANA TZID + supported strict RRULE can produce knownZoned while preserving the nominal local anchor; floating, UTC, invalid/unsupported RRULE and invalid/unknown IANA zone remain unknownLegacy. DTSTART wins over DUE; DUE remains imported independently.
- Added knownZoned recurrence export using local DATE/TZID property and canonical RRULE; unknownLegacy continues through legacy fields.
- Added first-arrange legacy confirmation dialog and provider call through `TodoWriter.confirmLegacyRecurrence`; it requires explicit save, lets the user enter/choose anchor interpretation and DATE/DATE-TIME, and presents device timezone only as a suggestion.
- ICS import receives the original VCALENDAR while classifying each VTODO. A same-TZID VTIMEZONE is never promoted from matching offset values alone: declared offsets outside the IANA zone's tzdata are recorded as a conflict; otherwise the definition remains unverified and the Todo stays `unknownLegacy`. DATE ignores timezone metadata for identity and uses timezone-free v2 keys.
- Known series edit UI now displays the canonical anchor/type and allows series timezone/value-type edits while preserving the prior nominal anchor when only rule/zone changes. It warns that existing allocations do not move.
- Occurrence picker explains its 90-day window; selector limit and 2037 transition horizon have dedicated localized errors.
- DATE-only occurrence IDs now use a timezone-free v2 identity while accepting the legacy v1 DATE form; timezone remains series metadata. ICS evidence is stored separately from `RecurrenceSpec`. The confirmation flow previews up to five occurrences through the shared engine over a bounded 90-day/100-result window, and `TodoEditPage` exposes the same confirmation path for unknownLegacy records. A semantic ICS round-trip matrix and real-server A–G plus old-client capability recovery tests are present.
- Latest gates (2026-10-05 R4 closeout): root `dart analyze .` and `flutter analyze` clean; root `flutter test` 453 passed; recurrence 20, contracts 53, server 233, wrapper 9 and CLI 20 passed; wrapper used CI's `dart test`; migration tests passed in root suite; version guard and 17-case selftest passed; whitespace/path scans and `git diff --check` clean.
- Wrapper timeout was caused by invoking its pure Dart tests through `flutter test`, which makes `Platform.resolvedExecutable` point at the Flutter test runner, not the Dart CLI expected by `dart run`. No wrapper source or POSIX behavior change was needed. Windows build was rechecked: Build Tools 18 lacks the ATL component needed by third-party `flutter_secure_storage_windows`; third-party `connectivity_plus` UTF-8 source triggers C4819 under code page 936, then existing `/WX` makes it fatal. See `docs/ROADMAP.md` for the Windows release smoke checklist.
- R4 independent delta review: **PASS** (original P1 resolved; no new P0/P1 or P2/P3); R4 was committed locally after all listed automatic gates passed. Windows release build and GUI manual acceptance remain **NOT RUN**: local Build Tools 18 lacks ATL, and the third-party `connectivity_plus` source triggers C4819 under code page 936 with `/WX`. See `docs/ROADMAP.md` for the remaining Windows build/launch smoke checklist. No push or PR was created.

## Stop conditions

- Stop before product implementation if any captured Design Spike vector regresses or if a change to the gap policy is proposed without revising SPEC.
- Stop if client/server engine vectors differ, if unsupported input is silently normalized, or if legacy series get an inferred zone.
- No automatic orphan migration, bulk series Allocation, or additional RFC override features in this phase.

## Completion evidence

Attach exact test outputs, the selected gap ruling, source/lock versions, schema and protocol compatibility matrix, and measured client/server golden-vector equality. Documentation-only completion or a green package unit test alone is not product acceptance.
