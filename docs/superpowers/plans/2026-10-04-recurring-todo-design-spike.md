# Recurring Todo / occurrence identity / timezone / DST — Design Spike

Date: 2026-10-04
Status: **COMPLETE — runtime spikes, repository analysis, full Flutter tests, and diff hygiene passed; no recurring Todo product code implemented**

## Scope and evidence boundary

This stage is a design spike, not a recurring Todo implementation. Evidence is separated as:

- **Repository facts**: current tracked source, manifests, and sync shape were inspected.
- **Dependency source audit**: code in the locally cached, lockfile-selected package versions was inspected.
- **Runtime spike**: PASS on the installed absolute-path SDK `C:\src\flutter` (Flutter 3.47.3, Dart 3.13.3). App dependencies were run under `rrule 0.2.18` / `timezone 0.11.0` / `enough_icalendar 0.17.0`; server dependencies under `rrule 0.2.18` / `timezone 0.11.1`. Executable evidence is recorded below; full `dart analyze .` and `flutter test` passed at final closeout.
- **Standards check**: RFC 5545 and verified Erratum 4271 were checked at RFC Editor pages; this is separate from package runtime evidence.

The runnable RRULE/DST/DATE/ICS prototypes are retained as minimal reproducible spike harnesses. The ICS converter test was temporary and removed after it passed.

## 1. Current recurrence technical facts

- Client Todo table has `startDate`, `dueDate`, and nullable `rrule`, but no `recurrenceTimeZone` or recurrence schema/version marker: `lib/data/local/database/tables/todos_table.dart`.
- Todo sync payload serializes `startDate`, `dueDate`, and `rrule` independently via UTC ISO strings: `lib/domain/sync/sync_payload.dart`. `dayspark_contracts` currently models the record envelope and TaskAllocation, not a recurrence object: `packages/dayspark_contracts/lib/src/record_dto.dart`.
- Client Event expansion is `lib/domain/utils/recurring_event_helper.dart`; server Event expansion is `server/lib/src/data/rrule_window.dart`. Both use `rrule` independently. The server converts input windows and recurrence instances to UTC; existing event payloads do not preserve a local IANA DTSTART zone.
- Server currently records invalid RRULE IDs but falls back to the raw event interval as a one-off event. That compatibility behavior is unsafe for a Todo operation that requires occurrence identity.
- `TaskAllocationWriter.create` rejects recurring Todo today, so no current production path binds an Allocation to a recurring occurrence.
- Locked package versions: client `rrule 0.2.18`, `timezone 0.11.0`, `enough_icalendar 0.17.0`; server `rrule 0.2.18`, `timezone 0.11.1`; `dayspark_contracts` has no runtime dependencies and supports pure Dart. Both timezone versions use IANA tzdata `2025c`. Library comparison found the sole `lib/` source difference in `timezone 0.11.1` is the initial local Location name changing `UTC` to `Etc/UTC`; both APIs resolve explicit `UTC`, `Etc/UTC`, and named IANA zones. The vector prototype returned byte-for-byte identical nominal keys and instants with both package configs. Align to `0.11.1` for a shared engine, but audit any code/tests comparing `tz.local.name`; explicit series-zone resolution itself showed no difference.

## 2. RRULE library source audit

`rrule 0.2.18` is a pure Dart package and its `RecurrenceRule.getInstances(start, after, before)` operates on Dart `DateTime` calendar fields. It does not attach an IANA zone or turn values into zoned instants. This is usable as a local-calendar candidate generator if the shared engine keeps the wall fields intact and performs zone resolution as a separate stage.

The decoder recognizes DAILY/WEEKLY/MONTHLY/YEARLY and the requested INTERVAL, BYDAY, BYMONTHDAY, COUNT, and UNTIL rule parts; the parser also supports many additional RFC parts. It rejects unknown frequency values and malformed recognized values. **The decoder switch has no default rejection branch for unknown rule parts**, so a string containing an unrecognized part can be accepted with that part discarded. Therefore direct parser success is not a sufficient capability check. The engine must first tokenize and enforce its own exact allowlist; unknown parts must return explicit unsupported.

**Runtime results:** DAILY, WEEKLY+INTERVAL+BYDAY, MONTHLY+BYMONTHDAY, YEARLY anchored month/day, MONTHLY ordinal BYDAY, inclusive UTC UNTIL, and INTERVAL vectors all expanded with expected ordered instances. A MONTHLY BYMONTHDAY=31 COUNT=4 rule emitted Jan/Mar/May/Jul 31; nonexistent dates were skipped and did not consume COUNT. COUNT/UNTIL together and duplicate parts are rejected by the prototype validator. `FREQ=NOPE` and missing FREQ throw `FormatException`.

The actual package decoder accepted `RRULE:FREQ=DAILY;X-UNKNOWN=1` and ignored the unknown part. Therefore production must tokenize first, reject unknown and duplicate components, whitelist the four frequencies, validate allowed combinations/ranges, and only then call `RecurrenceRule`. A prototype validator rejects unknown parts, SECONDLY, WEEKLY+BYMONTHDAY, ordinal BYDAY outside MONTHLY/YEARLY, nonpositive interval/count, duplicate fields, and COUNT+UNTIL. The candidate creation subset remains DAILY/WEEKLY/MONTHLY/YEARLY, INTERVAL, BYDAY, BYMONTHDAY, COUNT, UNTIL; BYMONTH and other parts are not required by the brief and remain outside the first whitelist.

For a weekly `COUNT=3` nominal 02:30 series spanning New York's 2026 spring transition, RRULE produced March 1, 8, 15; the gap date remains the second counted occurrence after resolution. This matches the selected RFC policy. The tested vectors cover the specified subset examples; cross-product/property-based RFC validation remains required during product implementation.

## 3. Timezone and DST source audit

`timezone 0.11.0` is pure Dart and can be imported by client/server/shared package. The app already initializes `latest_all` tzdata for notifications and pins `tz.local` to the device. Server query code initializes `latest_all` lazily. This existing device-local initialization must not be used as recurrence series state; the shared engine should take an explicit IANA location and initialize its data once without relying on `tz.local`.

The actual `TZDateTime` construction for `America/New_York` 2026-03-08 02:30 returned 03:30 EDT, offset -04:00, instant 07:30Z. For 2026-11-01 01:30 it selected 01:30 EDT / 05:30Z; explicit offset enumeration found both 05:30Z and 06:30Z. The prototype independently enumerates offsets and checks wall-field round trips; when no candidate exists, it locates the forward transition and applies the pre-gap offset. It returned 07:30Z while retaining the nominal key `2026-03-08T02:30:00`. Thus the package constructor happens to match this case, but the production policy remains explicit code, never implicit normalization.

RFC 5545 §3.3.5 / verified Erratum 4271 behavior is implemented by the tested prototype and matches the user's updated freeze: pre-gap offset on gap, first instant on fold. No outstanding ruling remains.

## 4. DATE-only source audit

`rrule` API requires a DateTime, so the tested adapter copies only calendar fields into an internal UTC DateTime candidate generator, then extracts `LocalDate` fields. A DAILY COUNT=3 DATE anchor produced 2026-10-05, 2026-10-06, and 2026-10-07. The internal midnight candidate is never exposed as a domain/wire instant or passed through zone resolution. Invalid month-end handling and COUNT behavior also passed the vector above.

## 5. Occurrence identity

The frozen structure is viable as a deterministic key when local values are canonical and type-tagged:

- DATE-TIME: `v1:DT:2026-11-02T09:00:00@America/New_York`
- DATE: `v1:DATE:2026-11-02@Asia/Shanghai`

The parent `todoSyncId` already supplies series identity in TaskAllocation payload; do not duplicate it in `occurrenceId`. The prototype models `Occurrence { nominalLocalKey, timeZone, resolvedInstant }`; resolution never participates in the key. New York gap key remains 02:30 while resolved instant is 07:30Z/local display 03:30. Fold key remains nominal 01:30 while resolved instant is first 05:30Z. A Shanghai 09:00 series produced 01:00Z and the same key while rendering at different viewer zones. Allocation rescheduling changes no value in this identity function. A temporary path package was added to client and server, each resolved offline from its own package config, then the exact same source package generated the same three vectors in both environments.

## 6. ICS parser runtime spike

The client uses `enough_icalendar 0.17.0`. Its `Property` model exposes `definition`, `textValue`, and `parameters`; `DateTimeProperty` exposes `timezoneId`. Parameter parsing recognizes both `TZID` and `VALUE`. `VComponent` retains properties and child components, including VTIMEZONE. This provides a wrapper path for preserving raw metadata without replacing the parser.

However, `DateHelper.parseDateTime` returns UTC only for `Z`; otherwise it creates a host-local Dart `DateTime`. DATE parsing also returns a host-local `DateTime`. The typed VTODO/VEvent start/due getters expose only DateTime values, and the current `IcalConverter` reads those getters then writes plain database DateTimes, losing TZID, VALUE=DATE, floating-vs-zoned provenance, and VTIMEZONE association. Its exporter likewise assigns DateTime directly and does not supply TZID. Thus current import/export cannot serve as RecurrenceSpec conversion without a wrapper that inspects raw properties before conversion.

The executable parser fixtures produced:

| Fixture | Observed property/runtime value | `IcalConverter` result | Required treatment |
|---|---|---|---|
| Zoned `TZID=America/New_York` | raw `DTSTART;TZID=America/New_York:20261102T090000`; typed TZID retained; parsed DateTime is non-UTC 09:00 | companion contains plain local DateTime, no TZID field | wrapper reads TZID before converter loses it; known-zoned only for valid IANA |
| Floating DATE-TIME | raw `DTSTART:20261102T090000`; TZID/VALUE absent; host-local DateTime | indistinguishable from same wall fields after import | retain floating/unknown; never fill device zone |
| UTC DATE-TIME `Z` | raw `DTSTART:20261102T140000Z`; parsed DateTime `isUtc=true` | UTC instant survives | classify as instant evidence, not series wall zone |
| `VALUE=DATE` | raw `DTSTART;VALUE=DATE:20261102`; VALUE=`DATE`; getter is non-UTC midnight | companion contains local-midnight DateTime | wrapper stores DATE separately; midnight must not become a domain instant |

All fixtures also parsed a TZID-bearing `DUE` and `RRULE:FREQ=DAILY;COUNT=2`; both values were visible on parser properties. A VTIMEZONE fixture retained the VTIMEZONE child and nested STANDARD component. A separate `flutter test` against `IcalConverter` confirmed that all four inputs become ordinary DateTime companion values; DATE becomes midnight and TZID/VALUE cannot be recovered from that companion. Keep this library and add a wrapper that captures metadata before conversion; replacement is unnecessary based on these fixtures. Custom VTIMEZONE-to-IANA mapping is still not guaranteed and remains unknown/read-only if mapping is not exact.

## 7. Legacy model recommendation

Persist only two recurrence semantic states initially: `knownZoned` (complete valid RecurrenceSpec) and `unknownLegacy` (existing/ambiguous series lacking authoritative interpretation). During import/diagnosis, label evidence as zoned-IANA, floating, UTC-instant, DATE, or custom-VTIMEZONE; do not inflate these into persistent domain states unless a concrete use requires it. Existing series are unknown because current UTC payload is not proof of original series zone. Lazy migration asks at first formal recurrence operation and atomically stores the user's confirmed interpretation.

## 8. Final RecurrenceSpec structure

```text
RecurrenceSpec {
  anchor: {
    source: start | due,
    valueType: date | localDateTime,
    value: canonical offset-free value
  },
  timeZone: IANA identifier,
  rrule: canonical validated value
}
```

`startDate` wins over `dueDate`; `dueDate` remains deadline. No anchor means no expansion. Local date-time fields are never converted to UTC before recurrence generation. DATE-only remains a separate value type.

## 9. Sync atomicity design

Keep field-level LWW for unrelated Todo data. Add one nested `recurrenceSpec` object and one `recurrenceRevision`/logical write version as a single merge unit. An update replaces the full tuple after validation; clients must not independently merge legacy anchor, RRULE, and zone. Server stores/echoes the same object and rejects partial recurrence tuple updates. During rollout, adapt legacy fields only at one boundary; never merge some new object fields with some legacy values. Exact conflict policy, backward-compatible capability/version introduction, and payload migration tests belong in implementation plan Phase 2.

## 10. Shared recurrence architecture

Recommended target: a new pure Dart `packages/dayspark_recurrence` package, consumed at a pinned compatible version by Flutter client and server. A temporary pure package depending on `rrule` and `timezone` was path-added to both apps; offline dependency resolution passed on each, and the exact same package source emitted identical RRULE nominal candidates, gap/fold/Shanghai keys, and UTC instants. This confirms shared-package feasibility without production manifest changes. Keep `dayspark_contracts` for wire DTOs/envelopes; the engine emits nominal keys and explicit resolution results. Align timezone to 0.11.1 in both before product implementation; the only source difference is the default local name `Etc/UTC` vs `UTC`, while both tzdata are 2025c and the explicit-IANA vectors matched. CI should continue checking vectors and tzdata version drift.

## 11. Initial RRULE support set

Validated candidate for creation and occurrence Allocation:

- FREQ: DAILY, WEEKLY, MONTHLY, YEARLY.
- INTERVAL >= 1.
- BYDAY (weekday names; ordinal forms only for tested MONTHLY/YEARLY cases).
- BYMONTHDAY within RFC range and tested valid/invalid date behavior.
- exactly one of COUNT or UNTIL; COUNT includes DTSTART; UNTIL matches DATE/DATE-TIME and RFC zone rules.
- reject all unknown/unsupported parts before invoking `rrule`.
- finite expansion window and explicit result cap.

More complex imported rules may be read-only only if reliably expanded. If their canonical occurrence identity is unsupported, disable occurrence Allocation and return a clear unsupported result. Never silently convert parse failure to a normal Todo.

## 12. Freeze validation summary

| Frozen statement | Current status |
|---|---|
| local anchor + RRULE + IANA zone as one series fact | Prototype keeps candidate fields local and requires an explicit zone |
| stable local occurrence key separate from Allocation schedule | Gap, fold, viewer-zone and shared-package vectors pass |
| fold resolves to first occurrence | Two candidates observed; constructor and prototype select 05:30Z EDT |
| gap-before-offset and nominal identity | Constructor/prototype yield 07:30Z / displayed 03:30 EDT; identity remains nominal 02:30 |
| DATE-only is not midnight instant | RRULE candidate adapter and `v1:DATE` identity pass; not sent through zone resolver |
| requested RRULE subset | Representative frequency/part vectors pass; strict wrapper required because unknown parts are silently ignored |
| ICS retains enough evidence | Four raw properties, DUE, RRULE and nested VTIMEZONE inspected at runtime; converter loss confirmed |
| client/server shared engine feasible | Temporary package path dependency and same vectors pass under both package configs |

## 13. Required document changes

- `SPEC.md` §3.1.1: formal RecurrenceSpec, zone, identity, legacy, series edit, RRULE, ICS, and sync rules.
- `DECISIONS.md`: record package results, timezone version delta, and remaining implementation boundary.
- `docs/ROADMAP.md`: design spike runtime gates pass; implementation plan ready.
- Next-stage plan: `docs/superpowers/plans/2026-10-04-recurring-todo.md`.

## 14. Implementation readiness

**Design spike is complete.** Final gates: `dart analyze .` reported no issues; full `flutter test` passed all 414 tests; `git diff --check` passed. Temporary client/server path dependency changes were restored, and only the documented spike harness remains. No recurring Todo product code was implemented. The user has resolved gap semantics. Implementing recurrence product behavior remains a separate explicitly scoped Work conversation after final gates pass.

## 15. Open user ruling

None. Gap/fold and nominal identity behavior were explicitly updated by the user in the continuation request. No automatic migration or orphan-Allocation behavior is changed.

## 16. Rulings

- RRULE rules with unknown parts are unsupported for allocation because the inspected decoder can ignore unknown rule parts. Cost if wrong: silent identity mismatch across devices.
- Keep only `knownZoned` and `unknownLegacy` as persisted classifications. Cost if wrong: richer classification later requires additive migration, but four persistent states would create unused schema without evidence.
- Use a new shared recurrence package rather than expanding `dayspark_contracts` into a timezone engine. Cost if wrong: one extra package boundary to maintain.
- Keep SDK calls pinned to the absolute installed Flutter path in this Work because PATH omits it. Cost if overlooked: rerun work appears unavailable despite installed SDK.
