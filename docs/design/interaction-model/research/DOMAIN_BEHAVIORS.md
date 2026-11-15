# DaySpark Domain Behaviors

Read-only inventory for a faithful interactive prototype. Source of truth is the implementation in this worktree at commit `46c01fe` (`0.29.0+29`). Where prose docs and code disagree, this document follows code and names the disagreement.

Evidence format: `path:lines`; `SPEC.md §...` for the business contract. UI labels are English/Chinese through l10n, but labels below are descriptive, not literal copy.

## 0. Shared model and time semantics

| Noun | Stored? | Role |
|---|---|---|
| Todo | Yes, `todos` | A task, optionally with deadline (`dueDate`), start (`startDate`), recurrence, subtasks. |
| Event | Yes, `events` | A calendar block; recurring events are one master row plus optional EXDATEs. |
| TaskAllocation | Yes, `task_allocations` | A concrete execution block for a Todo or one recurring Todo occurrence. Not an Event. |
| TaskInstanceState | Yes, `task_instance_states` | Sparse completion/reopen state for one recurring Todo occurrence. |
| Reminder | Yes, `reminders` | One absolute notification trigger for an Event or Todo. |
| Calendar | Yes, `calendars` | Local grouping with name/color; not a synced record type. |
| Tag | Yes, `tags` plus join tables | Many-to-many label on Todos/Events. |
| Action | No | Projection for the current civil day, computed from Events, Events' recurrences, allocations, Todos, and instance states. |
| Calendar view | No | Projection of Events and allocations over a visible range. |
| Widget snapshot/command | Native shared storage | Versioned read model and an independent completion command queue. |

Rules:

1. **Local civil day is the user-visible unit.** Day membership is `[local midnight, next local midnight)` for local-mode callers, or the equivalent UTC day for MCP/resources. Evidence: `lib/domain/services/action_projection_query.dart:307-312`, `lib/domain/records/todo_occurrence.dart:83-103`.
2. **Instant ranges are half-open.** Events and allocations occupy `[start, end)`; an item is "now" when `!start.isAfter(now) && end.isAfter(now)`. Evidence: `lib/ui/pages/home/action_section.dart:338-339`, `lib/infrastructure/platform/home_widget_service.dart:439-450`.
3. **Stored instants vs wall clocks.** Allocations are canonical UTC instants (`startAt`/`endAt` stored as UTC milliseconds). Recurrence uses nominal local wall-clock values plus an IANA zone; occurrence identity is wall-clock, not UTC. Evidence: `lib/domain/records/writers/task_allocation_writer.dart:157-176`, `packages/dayspark_recurrence/lib/src/identity.dart:36-49`.
4. **Writes go through one seam.** `RecordScope.run` writes rows, outbox entries, and post-commit domain events; rollback publishes nothing. Reminders, Action, calendar, search, widgets, and sync refresh from this seam. Evidence: `DECISIONS.md:197-207`, `lib/domain/records/record_scope.dart`.
5. **No user-facing permanent delete except explicit trash purge.** Soft delete is the normal delete; hard delete exists only in trash/permanent actions and cascades, not in client AI or MCP tools. Evidence: `DECISIONS.md:134-138`, `lib/domain/records/writers/todo_writer.dart:332-440`.

---

## 1. Todo: fields, defaults, completion, deletion, trash

### 1.1 Stored fields

| Field | Default / nullability | Meaning and behavior |
|---|---|---|
| `id` | autoincrement | Local row identity; not stable across devices. |
| `calendarId` | required | Local calendar grouping. Calendar deletion must re-home or trash contents. |
| `summary` | required text | Title. The form rejects blank; quick add trims and ignores blank. DB/writer do not enforce non-empty. `todo_form_page.dart:350-357`, `todo_quick_add.dart:38-40`. |
| `dueDate` | nullable | Deadline only. Drives Todo Today/Overdue, Action due/overdue, deadline lane, recurring anchor when `startDate` absent, todo reminder default in AI flows, and nothing about execution blocks. |
| `startDate` | nullable | Optional earliest/start field; used as recurrence anchor when present. It does **not** create an Action or calendar block. `todo_form_page.dart:301-333`. |
| `priority` | `0` | Stored integer; list ordering sorts ascending. |
| `status` | `NEEDS-ACTION` | Completion writes `COMPLETED`; reopening writes `NEEDS-ACTION`. `CANCELLED` is also treated as inactive by projections. `todos_table.dart:18-21`, `todos_dao.dart:30-50`. |
| `description` | nullable | Searchable long text. |
| `rrule` + recurrence fields | null / no recurrence | Legacy RRULE text plus structured `RecurrenceSpec` columns (`anchorSource`, `valueType`, `anchorValue`, `timeZone`, `rule`, `legacyState`, `evidence`, `revision`). See section 5. |
| `completedAt` | nullable | Set when an ordinary Todo becomes `COMPLETED`; cleared on reopen. |
| `percentComplete` | `0` | Set to 100 on complete, 0 on reopen. Not otherwise exposed as a progress editor. |
| `sortOrder` | `0` | Manual ordering for lists; global value, not per parent/view. |
| `parentId` | nullable | Subtask parent. Deleting/restoring cascades through descendants. |
| `deletedAt` | nullable | Soft-delete tombstone for the trash. |
| `syncId`, `icsUid`, `serverRev` | nullable | Stable sync identity, ICS UID, server revision. |
| tags, reminders, attachments, allocations, instance states | separate tables | Not columns on the Todo row. |

### 1.2 Behavioral rules

1. **T1.1 - Create defaults.** Quick add creates with first calendar, `priority: 0`, `status: NEEDS-ACTION`, no tags, no reminders, no recurrence, no start, and `dueDate` only when the current Todo view is a specific day; Inbox/All create an undated Todo. The full form can add all fields. `lib/ui/widgets/todo/todo_quick_add.dart:38-63`.
2. **T1.2 - Date ordering.** `startDate` must not be after `dueDate`; both form and writer reject that combination. `todo_form_page.dart:359-366`, `todo_writer.dart:32-36,91-95`.
3. **T1.3 - Ordinary completion.** Completing an ordinary Todo sets `status=COMPLETED`, `completedAt=now`, `percentComplete=100`; reopening sets `NEEDS-ACTION`, nulls `completedAt`, and zeroes percent. `todos_dao.dart:30-50`.
4. **T1.4 - Completion invalidates future plans, not history.** On completion, every `active` allocation whose `startAt >= completedAt` (millisecond UTC comparison) becomes `invalidatedByCompletion`. An allocation that started before completion remains untouched even if it ends after; equality invalidates. `todo_writer.dart:730-770`. Reopening does **not** restore invalidated blocks.
5. **T1.5 - Recurring Todo completion is occurrence-scoped.** A recurring Todo cannot be completed without an occurrence identity; parent series status stays open. See section 5. `todo_writer.dart:231-250`.
6. **T1.6 - Legacy completed series exception.** If a recurring parent is already legacy-`COMPLETED`, unchecking without an occurrence reopens the parent series; instance actions are refused until that reopen. `todo_writer.dart:231-239`, `task_instance_writer.dart:23-27`.
7. **T1.7 - Soft delete cascades.** Deleting a Todo stamps the Todo and all descendants with the same `deletedAt`; it does not delete child records, reminders, or allocations. The UI normally shows an undo affordance. `todo_writer.dart:262-277`.
8. **T1.8 - Restore.** Restoring a child also untrashes its immediately trashed parent and all descendants, mirroring the delete cascade. Restoring only a parent pulls all trashed descendants back. `todo_writer.dart:279-330`.
9. **T1.9 - Permanent delete cascades.** Permanent delete removes tag links, attachments, reminders, allocations, and task-instance states for the Todo/descendants, then the Todo rows, and queues sync tombstones for synced allocations/instances/Todos. `todo_writer.dart:332-393`. Empty Trash performs the same cleanup for all trashed Todos. `todo_writer.dart:395-440`.
10. **T1.10 - Trash surface.** Trash lists every row with `deletedAt != null`, not just top-level rows, so cascaded descendants appear individually. It offers restore and permanent-delete confirmation; Empty Trash clears Todo and Event trash after confirmation. `todos_dao.dart:269-274`, `events_dao.dart:75-80`, `lib/ui/pages/trash/trash_page.dart:23-57,115-273`.
11. **T1.11 - Soft-deleted parents hide derivations.** Action, calendar, allocations, and widgets require live parents; trashed Todos do not appear, and their reminders are cancelled from the OS queue. `action_projection_query.dart:324-388`, `reminder_reconciler.dart:305-324`.
12. **T1.12 - Calendar is mandatory.** Deleting the last calendar is refused. Deleting a non-last calendar asks whether to move its contents to another calendar or trash them. `lib/domain/providers/events_provider.dart:205-262`, `lib/ui/pages/calendar/calendars_page.dart:77-100,199-301`.
13. **T1.13 - Manual Todo creation has no default reminders.** Reminders are optional and added explicitly in the form/detail; default reminders exist only in AI-created flows. `reminders_provider.dart:132-174`, `lib/ui/widgets/reminder/reminders_section.dart:151-159`.
14. **T1.14 - Lists are projections.** The Todo navigation has All, Inbox, Six Things, and day views. The All view lists live top-level Todos (including completed, which the UI separates); Inbox is top-level, live, non-completed/non-cancelled Todos with no dueDate. `todos_dao.dart:253-267,276-287`. Day/Today views are not the Action page (section 6).
15. **T1.15 - No automatic rescheduling.** Editing `dueDate` does not move existing allocations; it shifts Todo reminders by the deadline delta (section 4). Completion only invalidates, never re-plans.

---

## 2. Event: fields, recurrence surface, editing scope, deletion

### 2.1 Stored fields

| Field | Default / nullability | Meaning |
|---|---|---|
| `id` | autoincrement | Local row identity. |
| `calendarId` | required | Local calendar grouping. |
| `summary` | required text | Event title. |
| `startDt`, `endDt` | required instants | Displayed local; interval is `[start, end)`. |
| `isAllDay` | `false` | All-day flag; all-day start/end are midnight-normalized when set through the all-day toggle. |
| `description`, `location` | nullable | Searchable. |
| `rrule` | nullable | Master recurrence rule. |
| `exdates` | nullable text | Occurrence exclusions, one ISO value per line, applied by year/month/day/hour/minute. |
| `deletedAt` | nullable | Soft delete. |
| `createdAt`, `updatedAt`, `syncId`, `icsUid`, `serverRev` | - | Audit and sync. |

Evidence: `lib/data/local/database/tables/events_table.dart:6-31`.

### 2.2 Behavioral rules

1. **E2.1 - Valid range.** The event form requires end strictly after start; equal/negative ranges are rejected. `event_form_page.dart:165-192`.
2. **E2.2 - All-day normalization.** Switching a non-all-day event to all-day normalizes start/end to local midnight before save; an event that was already all-day is not re-normalized, so an unusual imported all-day time is preserved. `event_form_page.dart:153-167`, `docs/CONSTRAINTS.md:32-35`.
3. **E2.3 - Create prefill.** Creating an event from the Calendar uses the viewed date: today starts at the next whole hour (minutes discarded), other dates at 09:00; end is +1 hour. Tapping an empty time slot prefills that local wall-clock slot and +1 hour. `home_page.dart:777-793`, `calendar_section.dart:383-403`.
4. **E2.4 - Overlaps are allowed.** Neither form nor writer rejects overlapping events; the calendar lays overlapping tiles out as separate blocks. `lib/ui/widgets/calendar/event_tile.dart:14`, `event_writer.dart:13-34`.
5. **E2.5 - Recurring expansion.** A master event expands over the requested window, clamps the visible overlap to the window, preserves duration, and keeps the master row's ID/series anchors. Invalid RRULE falls back to one master occurrence. EXDATEs remove matching occurrences at minute resolution; bad EXDATE lines are dropped. `lib/domain/utils/recurring_event_helper.dart:13-123`.
6. **E2.6 - Editing a recurring occurrence edits the series.** Tapping any occurrence opens the master event detail. The edit form anchors on series `start/end`, not the tapped occurrence, and date pickers preserve duration. There is no per-occurrence override editing. `event_form_page.dart:87-88`, `event_detail_page.dart` inline edit path.
7. **E2.7 - Deleting one occurrence = EXDATE.** For a recurring event, the delete dialog offers "this occurrence" (append EXDATE to the master) or "whole series". There is no undo snackbar for the occurrence delete. `event_detail_page.dart:510-614`.
8. **E2.8 - Deleting the series is soft and undoable.** Whole-series delete sets `deletedAt` and offers a 5-second undo snackbar; event reminders remain as rows but are cancelled from the OS and do not fire. Restore clears `deletedAt` and reschedules. `event_detail_page.dart:603-614`, `event_writer.dart:43-58`, `reminder_reconciler.dart:167-223,305-324`.
9. **E2.9 - Permanent delete cascades.** Hard delete removes event tag links, attachments, reminders, and the event. Empty Event Trash does the same for all trashed events. `events_dao.dart:92-125`.
10. **E2.10 - Event reminders are one-offs on the master.** Occurrences do not get independent reminder rows; a recurring event's reminder is anchored to the master's current start (or shifts by delta on edit), not separately per occurrence. `reminder_reconciler.dart:17-26,305-324`.
11. **E2.11 - Calendar color is calendar-owned.** Event tiles resolve color from the local Calendar row, not from the event. `home_page.dart:636-645`.
12. **E2.12 - Event drag/resize gates.** Normal non-all-day events support drag and resize. Recurring events and all-day events are interaction-disabled; the calendar rejects a stray drag and shows a reason snackbar. The adapter itself enforces `allowNone`. `lib/ui/widgets/calendar/kalender_calendar_event.dart:15-33`, `calendar_section.dart:168-184`.
13. **E2.13 - Event delete in MCP/ICS differs.** MCP `trash_event` is soft delete only; ICS import can upsert by UID; neither is a physical purge. See sections 11 and 13.
14. **E2.14 - Detail is live and mostly inline.** Event detail watches the live row; title/description/location edits are inline with debounced writes. Start/end pickers preserve the previous duration by default. `lib/ui/pages/event/event_detail_page.dart`.

---

## 3. TaskAllocation: lifecycle, constraints, busy time

### 3.1 Stored fields

| Field | Default / nullability | Meaning |
|---|---|---|
| `todoId` | nullable | Local Todo row; nullable when a synced allocation arrives before its Todo resolves. |
| `todoSyncId` | nullable | Stable parent identity, so the allocation is not tied to a local integer ID. A local create may begin null; the outbox fills it from the parent's syncId. |
| `occurrenceId` | nullable | Only recurring Todos bind an exact occurrence; ordinary Todos store null, and the writer rejects a non-null occurrenceId. |
| `startAt`, `endAt` | required | Canonical UTC instants, end strictly after start. |
| `state` | `active` | Domain state, separate from sync tombstones. |
| `createdAt`, `updatedAt`, `syncId`, `serverRev` | - | Audit and sync. |

Evidence: `lib/data/local/database/tables/task_allocations_table.dart:22-40`, `lib/domain/sync/sync_outbox.dart:99-107`.

### 3.2 Lifecycle and states

| State | Entered by | Exits | Visible |
|---|---|---|---|
| `active` | Create; reschedule keeps it | Cancel -> `cancelledByUser`; completion -> `invalidatedByCompletion`; hard delete/sync tombstone removes row | Action, Calendar, Todo detail, free/busy, widgets |
| `cancelledByUser` | `cancel`; idempotent if already cancelled | None. Cannot reschedule or cancel again | Hidden from all active projections; no history UI |
| `invalidatedByCompletion` | Todo completion/instance completion | None | Hidden; historical end-time evidence remains only in data |
| row absent | Trash purge / server tombstone | - | Hidden |

Evidence: `lib/domain/records/writers/task_allocation_writer.dart:108-127`, `todo_writer.dart:730-770`, `task_instance_writer.dart:90-126`.

### 3.3 Rules

1. **A3.1 - A plan is not the deadline.** Allocations never alter `dueDate`; scheduling a Todo does not create an Event; completing a block via its checkbox completes the Todo/occurrence. `task_allocation_writer.dart:12-74`, `action_section.dart:196-203`, `DECISIONS.md:300-310`.
2. **A3.2 - Only active parents can receive blocks.** Creation/reschedule requires a live Todo whose status is neither `COMPLETED` nor `CANCELLED`. Trashed, completed, cancelled, and unresolved parents are rejected. `task_allocation_writer.dart:178-191`, `:76-106`.
3. **A3.3 - Recurring Todo constraints.** The parent must have a confirmed `knownZoned` recurrence; creation requires a canonical `occurrenceId`; the occurrence must still belong to the current series; an occurrence with `completed` or `skipped` state cannot receive a new allocation. Ordinary Todos must not carry an occurrenceId. `task_allocation_writer.dart:20-57`.
4. **A3.4 - Range math.** Start/end are truncated to UTC milliseconds; end must be strictly after start. There is no maximum duration. `task_allocation_writer.dart:157-176`.
5. **A3.5 - No automatic overlap or deadline enforcement.** Writer allows overlapping blocks and blocks past a deadline. Manual scheduling sheet does not run the AI conflict validator; AI scheduling revalidates the chosen slot before write; MCP `schedule_task` checks conflicts by default but exposes `allow_conflicts`. `execution_schedule_section.dart:140-193`, `ai_chat_page.dart:532-547`, `server/lib/src/mcp/tools.dart:892-1067`.
6. **A3.6 - Reschedule.** Only an `active` block with a resolved parent can move; both endpoints can change. It always keeps state `active`. `task_allocation_writer.dart:76-106`.
7. **A3.7 - Cancel.** Only `active` -> `cancelledByUser`; already-cancelled is a no-op; other states throw. Cancellation never deletes the row. `task_allocation_writer.dart:108-127`.
8. **A3.8 - Cancel undo is a new block.** The snackbar undo calls `create`, producing a new allocation ID; it does not reactivate the cancelled one. If the parent/occurrence became invalid, undo fails. `execution_schedule_section.dart:229-259`.
9. **A3.9 - Completion boundary.** For an ordinary Todo, allocations with `startAt >= completedAt` are invalidated; earlier blocks remain active. For a recurring occurrence, only that occurrence's allocations are invalidated, with the same start-at boundary. `todo_writer.dart:730-770`, `task_instance_writer.dart:90-126`.
10. **A3.10 - Restoring a parent does not restore blocks.** Invalidation/cancellation is terminal; un-deleting a Todo makes its still-active historical blocks visible again, but invalidated/cancelled blocks stay terminal.
11. **A3.11 - Display filtering.** Active projections exclude deleted/cancelled parents. For ordinary completed parents, only allocations with `startAt < completedAt` can appear as history; recurring parents completed at the series level are hidden. Completed/skipped occurrences and unresolved parent IDs are hidden. `lib/domain/providers/task_allocations_provider.dart:20-131`.
12. **A3.12 - Busy time.** Busy/free computation uses the same effective active blocks (plus events) and excludes cancelled, completion-invalidated, deleted-parent, and unresolved blocks. `lib/domain/services/ai_scheduler_service.dart:11-49,143-155`, `server/lib/src/mcp/tools.dart:1299-1460`.
13. **A3.13 - Manual default time.** The schedule sheet proposes the deadline if it is in the future, otherwise now + 1 hour; length presets are 30m, 1h, 2h, 4h. `execution_schedule_section.dart:162-166,294-384`.
14. **A3.14 - Calendar drag.** Allocations are full-interaction calendar blocks; dragging/resizing persists new local wall-clock start/end through reschedule. Recurring/all-day restrictions apply only to Events, not allocations. `kalender_task_allocation.dart:20-29`, `calendar_section.dart:421-430`.
15. **A3.15 - Creation entry points.** Blocks can be created from the Todo detail execution section, the AI schedule flow, and MCP `schedule_task`. An empty calendar slot creates an Event, not an allocation; the calendar has no drag-to-create allocation gesture. `execution_schedule_section.dart:140-193`, `calendar_section.dart:383-403`, `server/lib/src/mcp/tools.dart:892`.

---

## 4. Reminders and notifications

### 4.1 Carrier and stored shape

| Field | Meaning |
|---|---|
| `parentType` | `event` or `todo`; allocations are not reminder carriers. |
| `parentId` | Local parent row. |
| `triggerTime` | Absolute instant; this is the source of truth, not a stored relative offset. |
| `isTriggered` | Delivery bookkeeping. |
| `parentSyncId`, `syncId`, `serverRev` | Sync identity. |

Evidence: `lib/data/local/database/tables/reminders_table.dart:3-13`.

### 4.2 Rules

1. **R4.1 - Absolute storage, relative presentation.** The UI describes a reminder as on time / N minutes / N hours / N days before the current anchor when possible; otherwise it shows the absolute moment. If there is no anchor, adding a reminder explains that it needs an anchor. `reminders_section.dart:161-181,237-341`.
2. **R4.2 - Presets and custom.** With an anchor: on time, 5m, 15m, 30m, 1h, 1d before, plus custom absolute picker. Without an anchor: custom absolute picker only. `reminders_section.dart:289-336`.
3. **R4.3 - Draft vs live.** In forms, reminder changes are staged; cancel leaves stored rows untouched. In live detail, add/delete writes immediately. `reminders_section.dart:31-49,133-149,183-200`.
4. **R4.4 - Defaults exist only in AI flows.** AI-created events get 5m and 15m before start; AI-created Todos with a due date get 1h and 1d before; only future triggers are inserted. Manual Event/Todo creation adds none. AI task breakdown passes `dueDate: null`, so it adds none. `reminders_provider.dart:132-174`, `ai_chat_page.dart:620-625,742-745,778-781`.
5. **R4.5 - Anchor edits shift every stored reminder.** The parent reference is Event `startDt` or Todo `dueDate`. When that reference changes, every reminder is shifted by the same delta, preserving its offset; a newly materialized trigger becomes the basis for the next comparison. Trashing/completing/cancelling suppresses delivery; restoring/activating reschedules. `reminder_reconciler.dart:17-26,167-229,305-324`.
6. **R4.6 - Scheduling gates.** Only future triggers schedule; exact alarms are used on Android when permitted, otherwise inexact. System alarm is an extra Android/iOS path. `notification_service.dart:171-178,298-357`, `alarm_service.dart`.
7. **R4.7 - Deleting a parent.** Soft-deleted Event/Todo keeps reminder rows, cancels OS notifications, and does not fire. Hard delete removes rows. `event_writer.dart:43-51`, `todo_writer.dart:332-392,395-440`.
8. **R4.8 - Locale changes reschedule.** App-language changes clear the notification handoff ledger and reschedule pending reminders with strings in the new locale. `reminder_reconciler.dart:60-78`, `reminders_provider.dart:37-99`.
9. **R4.9 - Notification payload and actions.** Payload is `parentType:parentId[:reminderId]`. Actions are `mark_complete` and `snooze`; Android and Windows expose both; iOS/macOS use time-sensitive presentation. Action button labels are currently hard-coded English (`"Mark Complete"`, `"Snooze 1h"`) even in Chinese. `notification_service.dart:151-167,259-345`.
10. **R4.10 - Tapping the notification body does nothing.** `onNotificationTapped` is never assigned; only action callbacks are wired. Do not prototype body-tap navigation as working. `notification_service.dart:135,165-166`, `home_page.dart:153`.
11. **R4.11 - Mark Complete action.** Only for `parentType == todo`. Ordinary Todo completes immediately. A recurring Todo cannot be completed generically: the app shows "select occurrence" and opens Todo detail. Event actions do nothing. `home_page.dart:267-293`.
12. **R4.12 - Snooze action.** Snooze is transient UI action, not a data edit. It reschedules the same notification ID at `now + 1h`, refuses a past time, does not update `triggerTime`, and does not survive a later reminder reconciliation. It is available only when a reminder ID is in the payload. `home_page.dart:294-311`, `notification_service.dart:250-296`.
13. **R4.13 - Platform surfaces.** Settings shows notification rows only on Android/iOS/macOS; web has none. The system-alarm switch exists only Android/iOS. Android has an exact-alarm permission fallback row. Windows/Linux have no settings section even though the service can initialize platform plugins. `lib/ui/pages/settings/settings_page.dart:84-90`, `notifications_section.dart:30-90`.
14. **R4.14 - No global enable switch.** There is no generic "notifications on/off" preference; cancellation/suppression is driven by parent state and platform permissions. `notifications_section.dart:41-90`.
15. **R4.15 - No per-occurrence reminders.** Reminders belong to the Event/Todo master; the reference is the master start or the Todo `dueDate`, not each recurring occurrence. A recurring Todo with no dueDate has no default-reminder anchor. `reminder_reconciler.dart:305-324`, `reminders_provider.dart:153-174`.

---

## 5. Recurrence: Todo and Event

### 5.1 Todo RecurrenceSpec contract

| Component | Values / rule |
|---|---|
| Anchor source | `start` if `startDate` exists, otherwise `due`. |
| Value type | `date` when hour and minute are both 0; otherwise `dateTime`. |
| Anchor value | Nominal local date/date-time; not a UTC instant. |
| Time zone | IANA zone; new rules use device zone, editing keeps the existing spec zone. |
| Rule | Canonical RRULE. UI modes: never/daily/weekly/monthly/yearly/custom, with an optional "repeat from" date. |
| Revision | Starts at 1; increments only when the recurrence spec itself changes. |
| Legacy state | `knownZoned` or `unknownLegacy`. Unknown recurrence cannot be scheduled/completed until confirmed. |

Evidence: `SPEC.md §3.1 rules 9-11`, `todo_form_page.dart:301-347`, `todo_writer.dart:37-78,154-180`, `TODO recurrence contract in DECISIONS.md:346-368`.

### 5.2 Occurrence identity and time

1. **O5.1 - Date identity.** Date-only occurrences use `v2:DATE:YYYY-MM-DD`, with no zone and no DST issue. `packages/dayspark_recurrence/lib/src/identity.dart:36-49`.
2. **O5.2 - Date-time identity.** Timed occurrences use `v1:DT:YYYY-MM-DDTHH:MM:SS@IANA_TZ`. The nominal fields are local wall time; the zone is part of identity. `identity.dart:44-49`.
3. **O5.3 - DST gap and fold.** A nonexistent wall time resolves using the pre-gap offset; an ambiguous (fold) wall time chooses the earlier instant. `packages/dayspark_recurrence/lib/src/resolver.dart:3-45`, `DECISIONS.md:352`.
4. **O5.4 - Day membership for recurring Todos.** Date-only instances belong to the nominal date. Timed instances belong to the civil day containing their resolved local instant. `todo_occurrence.dart:82-103`, `DECISIONS.md` Ruling E.
5. **O5.5 - Missing identity.** A recurring Todo without a `syncId` is skipped by Action projection; the calendar/picker paths first ensure a sync identity. `action_projection_query.dart:102-104`, `todo_occurrence_picker_sheet.dart:33-45`.

### 5.3 Completion and instance state

1. **O5.6 - Sparse state.** Completion is not a field on the Todo. A row in `task_instance_states` is unique by `(todoSyncId, occurrenceId)`; absence means pending. `task_instance_states_table.dart:3-18`, `task_instance_writer.dart:42-80`.
2. **O5.7 - Completing an occurrence never completes the series.** The parent Todo remains `NEEDS-ACTION`; only the sparse instance state becomes `completed`. The Todo list may still show the series once, not one row per occurrence.
3. **O5.8 - Picker windows.** Page 1 returns the previous 30 civil days plus today through today+90 days, capped at 100 per expansion. Earlier pages step back in 30-day chunks. The picker can page further into history, shows completion checkmarks, and keeps completed occurrences selectable. `todo_occurrence.dart:162-229`, `todo_occurrence_picker_sheet.dart:104-171`.
4. **O5.9 - Direct completion.** An allocation checkbox supplies its occurrenceId and bypasses the picker. A user toggling a recurring Todo normally opens the picker. Pending instances open the picker; already-completed instances can be reopened. `action_section.dart:196-203`, `todo_completion.dart:21-62`.
5. **O5.10 - Reopen semantics.** Reopening an occurrence nulls `completedAt`. Re-completing an already-completed state preserves the existing completion timestamp; reopening a state and completing again gets a new timestamp. `task_instance_writer.dart:55-80`.
6. **O5.11 - Occurrence completion invalidation.** Only that occurrence's active allocations with `startAt >= completedAt` are invalidated. `task_instance_writer.dart:90-126`.
7. **O5.12 - Unknown legacy recurrence.** An unconfirmed legacy rule is excluded from Action/AI scheduling and cannot accept instance completion; the picker may offer repair when the rule is supported. `todo_occurrence_picker_sheet.dart:48-65`, `action_projection_query.dart:67-100`, `task_instance_writer.dart:28-34`.
8. **O5.13 - Series edits.** Editing recurrence replaces all structured recurrence fields atomically and increments revision only for a real spec change. Existing instance states remain; after a rule change, a state whose occurrence no longer exists cannot be newly created, but an existing state can still be reopened. `todo_writer.dart:37-78,154-180`, `task_instance_writer.dart:49-53`.
9. **O5.14 - No skipped-occurrence UI.** The schema/projection recognizes `skipped`, but the picker and Action UI expose only pending/completed; skipped instances are hidden. `todo_occurrence.dart:210-221`.
10. **O5.15 - No "repeat count/end" editor beyond the generated RRULE.** The Repeat editor exposes modes and custom RRULE text; there is no separate "ends after N times/on date" control. `lib/ui/widgets/schedule/repeat_editor.dart:256-430`.

### 5.4 Event recurrence

1. **O5.16 - One master, EXDATEs, no override rows.** Occurrence deletion appends an EXDATE; occurrence edit opens the master. There is no RECURRENCE-ID-style modified instance. `event_detail_page.dart:510-614`, `event_writer.dart:64-84`.
2. **O5.17 - EXDATE matching.** Matching uses year/month/day/hour/minute; duplicates/bad lines are tolerated; the helper drops EXDATE lines that cannot parse. `recurring_event_helper.dart:13-42`.
3. **O5.18 - Expansion windows differ by surface.** Action expands around today; Calendar expands around the viewed date by +/-45 days; MCP defaults to a 7-day forward window and allows up to 366 days. `home_page.dart:641-646`, `action_projection_query.dart:36-45`, `server/lib/src/mcp/tools.dart:520`.
4. **O5.19 - ICS export loses EXDATE.** Event export writes RRULE but not EXDATE; importing the exported file can resurrect excluded occurrences. `ics_service.dart:24-110`.

---

## 6. Action and Todo "Today": membership, ordering, caps

### 6.1 Action is one civil day, not a task inbox

1. **Y6.1 - No date navigation.** Action always projects "today" from the device clock. It has no date picker and no previous/next day. `action_projection_query.dart:303-312`, `action_section.dart`.
2. **Y6.2 - Section order.** Sections render in this fixed order, each only if non-empty: Now, Later today, Due today, Overdue, Earlier today. `action_section.dart:78-165`.
3. **Y6.3 - Now.** Events and task allocations overlapping now (`start <= now < end`), sorted by start. No deadline Todos enter Now, even if their deadline time has passed. `action_section.dart:86-92,338-339`.
4. **Y6.4 - Later today.** Events and allocations whose start is strictly after now (and still today), sorted by start. `action_section.dart:93-98`.
5. **Y6.5 - Due today.** All pending recurring instances occurring today, in occurrence order, followed by every ordinary live non-completed/non-cancelled Todo with `dueDate` in today's local day, in `sortOrder, priority` order. Subtasks are not excluded by the query. `action_section.dart:119-131`, `action_projection_query.dart:324-338`.
6. **Y6.6 - Overdue.** Ordinary live non-completed/non-cancelled Todos with `dueDate < today`, all ages, ordered by dueDate then priority, followed by pending recurring instances missed within the last 30 civil days, in occurrence order. `action_section.dart:133-148`, `action_projection_query.dart:340-354`, `todo_occurrence.dart:105-132`.
7. **Y6.7 - Earlier today.** Events and allocations that already ended today, sorted by start, followed by ordinary Todos completed today sorted by completion time desc, followed by recurring instances completed today sorted by completion time desc. It is a history section, not a "completed" filter of all tasks. `action_section.dart:99-106,150-163`, `action_projection_query.dart:367-378`.
8. **Y6.8 - Hidden projection data.** Action computes but does not render: unplanned/inbox count, earlier-missed series beyond 30 days, unconfirmed recurring series, and recurrence expansion errors. A day with only inbox tasks shows the "nothing now" empty state, not the unplanned tasks. `action_projection_query.dart:59-63,190-232,281-298`, `action_section.dart:60-64,291-323`.
9. **Y6.9 - Deadline clock rule.** A due time shows only when not 00:00; date-only deadlines show the date label without a fabricated clock. `action_section.dart:214-226,283-289`.
10. **Y6.10 - Checkbox target.** Ordinary Todo checkbox toggles the Todo. Allocation checkbox completes the exact occurrence behind that allocation. Recurring instance checkbox toggles that occurrence. `action_section.dart:194-203,242-280`.
11. **Y6.11 - Completion errors are surfaced.** Errors from completion show a snackbar; they do not silently succeed. `action_section.dart:261-263,278-280`.
12. **Y6.12 - Freshness.** The projection is watched through the record bus; midnight rollover resets the day and refreshes home widgets. There is no minute-by-minute "Now" timer, but build/rebuild paths use `DateTime.now()` for section membership. `home_page.dart:166-235`, `action_section.dart:86`.

### 6.2 Todo Today / Six Things (different surface)

1. **Y6.13 - Todo views are separate.** Todo has All, Inbox, specific-day views, and a Six Things toggle. They do not share Action's immediate-overlap semantics. `date_strip.dart:10-116`.
2. **Y6.14 - Six Things cap.** Only when Six Things is on, the viewed date is today, and the six-item section is collapsed, only the first six of today's `dateTodos` render; a "More" action expands all, and "Less" collapses. The cap does not apply to other dates or All/Inbox. `home_page.dart:1093-1160`.
3. **Y6.15 - Sequence numbers.** 1-6 labels appear only for the capped Six Things rows on today. Reordering persists global `sortOrder`. `home_page.dart:1189-1210`.
4. **Y6.16 - Hide completed.** The setting hides completed ordinary Todos and completed recurring instances in Todo views; it does not affect Action or search. `home_page.dart:948-1100`.
5. **Y6.17 - Completed sections are global.** The completed Todo/instance sections use global completed queries, not a view-scoped query; Inbox/All can show completions outside that view. `todos_dao.dart:52-62`, `todos_provider.dart:11-14`, `home_page.dart:1009,1050`.

---

## 7. Calendar projection and direct manipulation

1. **K7.1 - Browsable range.** The calendar is static-bounded from 2000-01-01 through 2100-12-31. Dates outside it are not navigable. `home_page.dart:79-84`.
2. **K7.2 - View modes.** Day, week, month; default week; mode persists across restarts. The viewed date is in-memory only and resets to today on cold start. `calendar_view_provider.dart:10-42`.
3. **K7.3 - Anchor derivation.** Month anchor is visible-range start + 7 days (always inside the displayed month); day/week anchor is range start. The calendar reports anchor changes back to the page. `calendar_section.dart:214-240`.
4. **K7.4 - Navigation.** Back/forward moves one day, one week, or one month depending on mode. Month navigation jumps to the first of the target month, then the anchor derivation yields the in-month day. "Today" jumps to today and resets the anchor. `calendar_section.dart:360-381`.
5. **K7.5 - Data windows.** Events fetch/expand around the anchor by +/-45 days (enough for a 6-week month grid); allocations fetch over the full static calendar range. `home_page.dart:607-646`.
6. **K7.6 - No drag-to-create.** Tapping a time slot opens event creation with that slot; there is no drag-to-create range gesture. `calendar_section.dart:86-88,383-403`.
7. **K7.7 - Event movement.** Non-recurring, non-all-day events are draggable/resizable. Drag persists new start/end; resize changes duration. Recurring and all-day events are blocked with a snackbar and the tile resets. `kalender_calendar_event.dart:15-33`, `calendar_section.dart:155-184,421-435`.
8. **K7.8 - Allocation movement.** Allocation blocks support drag and resize as well, persisting through reschedule. They have no recurring/all-day drag gate. `kalender_task_allocation.dart:20-29`, `calendar_section.dart:421-430`.
9. **K7.9 - Overlap.** Event and allocation tiles may overlap; no collision UI or auto-shift exists. `event_tile.dart:14`.
10. **K7.10 - Deadline visibility.** Day/week views render a deadline lane for live top-level ordinary Todos with a dueDate (subtask deadlines are not included; recurrence parents and completed/cancelled Todos are excluded). Month view has no lane; instead the month day cell shows a deadline dot plus solar-term/holiday/makeup-workday marks. `home_page.dart:615-623`, `calendar_section.dart:569-612`, `calendar_deadline_lane.dart:18-110`.
11. **K7.11 - Deadline lane interactions.** Tapping a deadline opens the Todo; Todo deadlines are matched by the same civil date, not by a separate lane object. `calendar_deadline_lane.dart:18-110`.
12. **K7.12 - Recurring event visibility.** Recurring occurrences are display-only projections with the master's ID/series anchors; all-day events appear as all-day bars. Zero-duration all-day imports are given 1 hour for visibility only. `kalender_calendar_event.dart:15-45`.
13. **K7.13 - Anchor retention.** Keeping the calendar page open retains the current viewed date in memory, including after data refresh; leaving/reopening the app resets to today. View mode persists; anchor does not. `calendar_view_provider.dart:10-42`.

---

## 8. Calendars, tags, lists, filtering, reassignment

### 8.1 Calendars

1. **L8.1 - Seed.** A fresh database has at least "Personal" with color `#2563EB`; upgrades ensure at least one calendar exists. `lib/data/local/database/app_database.dart:55-61,203-212`.
2. **L8.2 - Create/edit.** Name and color are editable; color is chosen from a fixed palette. The default color is `#2563EB`. `calendars_page.dart:16-27,141-198`.
3. **L8.3 - Delete last is forbidden.** The delete control is disabled when only one calendar exists, and the provider also refuses. `calendars_page.dart:77-100`, `events_provider.dart:205-262`.
4. **L8.4 - Delete with contents.** Deleting a non-last calendar asks "move contents to another calendar" or "trash contents". Move re-homes each Event/Todo through the writers; trash soft-deletes each. The calendar row is then deleted. `calendars_page.dart:199-301`, `events_provider.dart:205-262`.
5. **L8.5 - No visibility filter.** `isActive` exists on Calendar but no Action/Calendar/Todo UI filters by calendar. All calendars render together; setting a calendar inactive is not a user-facing behavior. `lib/data/local/database/tables/calendars_table.dart:4-13`, `events_provider.dart:42`.
6. **L8.6 - Calendars are local metadata.** Calendar is not a sync record type; name/color/grouping do not sync as records. Event/Todo payloads carry local calendarId plus calendarSyncId so a receiving device can resolve/map, with fallbacks to a non-conflicting local ID or the first calendar. `packages/dayspark_contracts/lib/src/record_dto.dart:11-20`, `sync_payload.dart:191-235`.

### 8.2 Tags

1. **T8.1 - Tag fields/defaults.** Name 1-50 characters, color default `#6B7280`, stable sync identity. `tags_table.dart:3-10`.
2. **T8.2 - CRUD validation.** Name is required, max 50, and duplicates are case-insensitive. `tags_page.dart:137-233`.
3. **T8.3 - Ordering.** Tags list is ordered by name. `tags_provider.dart:10-186`.
4. **T8.4 - Assignment.** Events and Todos can carry multiple tags; assignment is through the entity's form/detail, not through the tag page. Tags page handles create/edit/delete and color.
5. **T8.5 - Delete.** Deleting a tag requires confirmation and first removes its event/todo associations, then the tag row; all changes are sync-queued. `tags_provider.dart:10-186`, `tags_page.dart:103-133`.
6. **T8.6 - Filtering.** Todo views expose tag filter chips; selecting multiple tags uses OR ("any selected tag"). There is no AND mode, no untagged filter, and no tag filter on Action, Calendar, or search. `home_page.dart:816-892,951-957`.
7. **T8.7 - Search does not match tags.** Search covers Event summary/description/location and Todo summary/description only. `events_dao.dart:56-73`, `todos_dao.dart:217-232`.
8. **T8.8 - No standalone lists.** There is no user-defined list/project entity beyond Calendars, Tags, Parent/Subtask, and the fixed Todo views. "Inbox" means undated top-level Todo, not a separate table.

---

## 9. Search

1. **S9.1 - Debounce.** Typing waits 300 ms; an empty trimmed input clears results immediately. Search submits on keyboard action too. `search_page.dart:100-127`.
2. **S9.2 - Scope.** Event match: summary OR description OR location. Todo match: summary OR description. Both exclude soft-deleted rows. Tags, calendars, reminders, allocations, and occurrence IDs are not searched. `events_dao.dart:56-73`, `todos_dao.dart:217-232`.
3. **S9.3 - Ordering.** No relevance score. Events sort by start ascending; Todos sort by dueDate ascending (null ordering follows SQLite default), then default DAO order. `events_dao.dart:56-73`, `todos_dao.dart:217-232`.
4. **S9.4 - Pagination.** 50 rows per type per page; "Load more" increases that type's limit by 50. Event and Todo paging are independent. `search_provider.dart:22-115`, `search_page.dart:223-267`.
5. **S9.5 - Empty/blank.** Blank query shows a suggestions empty state with the first 3 inbox Todos, not recent searches. No match shows "No results." `search_page.dart:138-143,275-300`, `search_provider.dart:53,85`.
6. **S9.6 - Read-only result.** Search result checkboxes are not interactive; the row opens detail. `search_page.dart:241-255`, `docs/CONSTRAINTS.md:131-135`.
7. **S9.7 - Errors.** A query failure with no cached result shows an error and Retry; stale results may remain visible while a new query fails. `search_page.dart:152-176`.
8. **S9.8 - Recurrence is not expanded.** A recurring Todo matches as its parent row; search does not list per-occurrence matches. Events match master rows.
9. **S9.9 - No scope filters.** Search has no "calendar/tag/type/date" filter UI; result sections are Events and Todos.

---

## 10. Sync, account, offline, conflicts

### 10.1 Account and local-first

1. **N10.1 - No account required.** Local CRUD, search, ICS, backup, widgets, and reminders work without login. Sync begins only when a base URL/tokens are configured. `sync_client_provider.dart:47-136`.
2. **N10.2 - Validation.** Server URL must be absolute http(s); email must contain `@`; registration password >= 8; login password non-empty. `account_provider.dart:187-200`.
3. **N10.3 - Auth outcomes.** 409 means email already registered; 401 means invalid credentials; other failures map to a generic auth failure. Login/register show inline errors. `account_provider.dart:94-148,202-206`, `account_section.dart:391-400`.
4. **N10.4 - Login state.** Successful auth saves tokens/email, enables sync, sets the sync feature flag, resets cursor/snapshot/outbox for the identity, and restarts the engine. It does not add or delete domain rows. `account_provider.dart:119-141`.
5. **N10.5 - Identity switch.** The local DB and existing `syncId`s survive; the cursor, widget snapshots, and outbox are cleared. Consequence: rows from a prior identity remain local and can be uploaded under the new identity if later edited, while pending unsynced edits are discarded. `account_provider.dart:119-141`, `DECISIONS.md:21-25`.
6. **N10.6 - Logout.** Clears tokens/email, disables sync, sets the sync flag off, invalidates the engine, and keeps local rows and the identity preference. There is no "wipe local data on logout" flow. `account_provider.dart:150-175`.
7. **N10.7 - One account.** UI has a single logged-in identity; no multi-account switcher or per-account local namespaces.
8. **N10.8 - Device registration.** Registration is attempted on login/cold start when signed in; failures are only logged. The connected-devices dialog lists server devices; logged out it shows empty, errors show a failure message. `sync_client_provider.dart:160-206`, `account_section.dart:216-228,326-369`.
9. **N10.9 - Status surface.** Logged-in status shows phase (idle/pushing/pulling/error), relative last-sync time, and rejected operation codes. Sync Now requests a round. `account_section.dart:216-258,374-389`.

### 10.2 Sync rounds and conflict rules

1. **N10.10 - Engine phases.** idle, pushing, pulling, error; rounds are serialized/coalesced. `sync_engine.dart:17,57-60,157-175`.
2. **N10.11 - Foreground only.** SSE is kept while foreground; a 15-second foreground poller provides fallback. Background pauses polling; resume triggers an immediate round. There is no background sync service. `foreground_sync_poller.dart:1-43`, `sync_client_provider.dart:47-136`.
3. **N10.12 - Initial vs ongoing cursor.** The local cursor is adopted from server head only on initial sync; otherwise the local cursor advances via pull results. Capability detection may backfill from 0. `sync_engine.dart:142-155,216-254`.
4. **N10.13 - Push then pull.** Each round pushes queued ops, then pulls; applied/duplicate ops are consumed; server-wins conflicts drop the relevant local snapshot ops; rejected ops are dropped and surfaced by code. `sync_engine.dart:256-347`.
5. **N10.14 - Field-level LWW.** The server resolves per-field last-writer-wins; the client sends only dirty fields. Ops are idempotent and carry fresh op IDs. `DECISIONS.md:85-107`, `sync_engine.dart:388-441`, `sync_outbox.dart:28-180`.
6. **N10.15 - Baselines.** A sweep assigns missing syncIds to pre-existing Events/Todos/allocations so they can participate. `sync_engine.dart:509-528`.
7. **N10.16 - Tombstones and delete convergence.** Soft-delete tombstones propagate; hard-delete tombstones remove rows; tombstones are retained at least 45 days. Delete/upsert ordering converges. `DECISIONS.md:324-335`, `sync_outbox.dart`.
8. **N10.17 - Parent resolution.** Allocations/instances arrive with sync IDs; an unresolved allocation may have `todoId = null`. Calendar resolution prefers matching calendarSyncId, then a non-conflicting local ID (link it), then the first calendar. `sync_payload.dart:191-235`, `sync_applier.dart`.
9. **N10.18 - Offline behavior.** Local writes proceed through outbox without network; the engine backs off from 1s to 60s after errors and retries on connectivity regain/foreground tick. `sync_engine.dart:374-385,530-537`, `sync_client_provider.dart:47-136`.
10. **N10.19 - Synced records.** Events, Todos, TaskAllocations, TaskInstanceStates, Reminders, Tags, tag associations, attachments. Calendars are local metadata (section 8). `record_dto.dart:11-20`.

---

## 11. AI chat and server MCP

### 11.1 Client AI chat

1. **A11.1 - Feature flag default off.** AI entry points are hidden unless `FeatureFlag.aiAssistant` is enabled; flags default false and are persisted. Settings exposes the switch under Advanced/AI. `feature_flags_provider.dart:18-24`, `ai_section.dart:26-47`, `home_page.dart:433-437`, `workspace_sidebar.dart:38-43`.
2. **A11.2 - BYO OpenAI-compatible key.** Key, base URL, and model live in secure storage; presets cover OpenAI/Anthropic/DeepSeek/Gemini/Moonshot/Qwen/GLM/Ollama/LM Studio. Default base URL is `https://api.openai.com/v1`, default model `gpt-4o-mini`; request goes to `/chat/completions` with temperature 0.3. `ai_provider.dart:10-40,74-91,133-164`.
3. **A11.3 - No key empty state.** Without config the chat page shows setup guidance; no chat call is made. `ai_chat_page.dart:323-332`.
4. **A11.4 - No conversation memory.** A request sends only the current user message, not previous turns; chat messages are in-memory and lost on restart. Errors surface as `Error: ...` text. `ai_provider.dart:213-271`.
5. **A11.5 - Actions only on the latest assistant message.** Older assistant messages do not expose action buttons. `ai_chat_page.dart:198-266`.
6. **A11.6 - Schedule flow.** Pick an existing active Todo (including subtasks), pick an occurrence if recurring, get deterministic suggestions over now through +7 civil days, choose a slot, confirm, revalidate availability, then create a TaskAllocation. It creates no Event and does not change dueDate. `ai_chat_page.dart:336-569`.
7. **A11.7 - Client suggestion grid.** Free slots are 09:00-18:00 local on every civil day, including weekends; 1-hour default; max 10. The LLM only ranks deterministic candidates and cannot invent busy/duplicate slots; deterministic fallback exists. `ai_scheduler_service.dart:53-140,159-308`.
8. **A11.8 - Breakdown flow.** Suggestions are displayed; tapping one immediately creates a Todo after calendar selection. It is **top-level** (no parent), has no due date, priority 0, and therefore no default reminders, and it is not linked to the source task. There is no confirmation sheet beyond calendar choice. `ai_chat_page.dart:571-667`.
9. **A11.9 - Create from chat.** The model parses the current prompt into Event/Todo fields; user chooses calendar; explicit confirmation shows understood fields; only then writes. Event/Todo creation adds the default reminders; failure shows a snackbar. `ai_chat_page.dart:669-793`, `ai_provider.dart:167-189`.
10. **A11.10 - One write at a time.** A `_writing` guard spans parse through write, preventing double-tap duplicate creation. `ai_chat_page.dart:675-679,791-793`.
11. **A11.11 - AI does not call MCP.** Flutter chat uses the model directly and local providers. MCP is a separate server endpoint for external agents. `ai_provider.dart`, `server/lib/src/mcp/tools.dart`.

### 11.2 Server MCP

Transport: `POST /mcp`, OAuth 2.1 with `mcp:read` / `mcp:write` scopes. External clients can use the stdio wrapper or `dayspark` CLI; the Flutter UI exposes no tool browser and no per-tool approval sheet. Authorized MCP calls execute directly against the same server record writer. `SPEC.md §3.6`, `DECISIONS.md:109-119`, `server/lib/src/mcp/tools.dart`.

Current tool inventory (22, not the 17/18 mentioned in older SPEC/ROADMAP prose). `server/lib/src/mcp/tools.dart`:

| # | Tool | Behavior summary |
|---|---|---|
| 1 | `get_events` | Events and expanded occurrences; default now through +7 days; max 366-day span. |
| 2 | `get_event` | One Event with recurrence detail. |
| 3 | `list_tasks` | Todo filters: today/overdue/upcoming/inbox, status, due range, cursor; UTC day buckets. |
| 4 | `get_task` | One Todo. |
| 5 | `list_task_occurrences` | Known-recurrence occurrences, max 90-day window, canonical occurrence IDs, sparse status. |
| 6 | `list_task_allocations` | Filter by task/occurrence/range/state. |
| 7 | `schedule_task` | Requires occurrenceId for recurring, forbids it for ordinary; conflict check by default; `allow_conflicts` override; idempotent replay; no Event/dueDate mutation. |
| 8 | `reschedule_task_allocation` | Moves an active block. |
| 9 | `cancel_task_allocation` | Sets `cancelledByUser`. |
| 10 | `search` | Case-insensitive title/description; event/task/all; no pagination. |
| 11 | `find_free_time` | Defaults 09:00-18:00 Mon-Fri, max 10; busy from events + effective allocations. |
| 12 | `list_trash` | Reads soft-deleted items; no restore tool. |
| 13 | `create_event` | Creates an event. |
| 14 | `update_event` | Updates event fields. |
| 15 | `trash_event` | Soft delete only. |
| 16 | `create_task` | Creates a Todo. |
| 17 | `update_task` | Updates Todo fields. |
| 18 | `complete_task` | Completes ordinary or exact recurring occurrence. |
| 19 | `reopen_task` | Reopens ordinary series or occurrence. |
| 20 | `snooze_task` | Moves `dueDate`, not the Reminder row; the name is misleading in this implementation. |
| 21 | `trash_task` | Soft delete only. |
| 22 | `batch_create_tasks` | Up to 100; per-item idempotency; partial failure reports error if any failed. |

Evidence for inventory: `server/lib/src/mcp/tools.dart:520,600,616,700,716,821,892,1069,1180,1252,1299,1464,1518,1588,1692,1737,1822,1933,2011,2083,2119,2160,2159-2251`.

MCP resources: exactly three - `dayspark://today`, `dayspark://overdue`, `dayspark://inbox`; UTC civil-day buckets. `server/lib/src/mcp/resources.dart:36-61`.

MCP rules:

1. **M11.1 - Same completion boundary.** Server completion invalidation skips allocations starting before completion; equality invalidates. `server/lib/src/data/record_writer.dart:454-500,790-840`.
2. **M11.2 - No permanent delete.** Only soft trash/list-trash tools exist; no hard-delete/purge tool. `DECISIONS.md:134-138`, `tools.dart`.
3. **M11.3 - No calendar/tag/reminder/attachment management tools.** The 22-tool surface centers on Events, Todos, occurrences, allocations, search, free time, trash, and batch create.
4. **M11.4 - Different free-time default from client AI.** MCP `find_free_time` excludes weekends by default; client AI's deterministic grid includes every civil day. `tools.dart:1299-1460`, `ai_scheduler_service.dart:53-140`.
5. **M11.5 - Same server LWW seam.** MCP writes go through `record_writer`, not a separate bypass. `server/lib/src/data/record_writer.dart`.

---

## 12. Home widgets and widget commands

1. **W12.1 - Platform gate.** Home widgets exist on Android and iOS only; web/desktop are no-ops. `lib/core/utils/platform_target.dart:9-33`, `home_widget_service.dart:140`.
2. **W12.2 - Versioned snapshot.** `widget_snapshot` is v3. Native widgets read it and never write it. Snapshot v3 and command queue v1 are independent. `home_widget_service.dart:112-126,203-217`, `DECISIONS.md:109-119`, `docs/CONSTRAINTS.md:245-258`.
3. **W12.3 - Snapshot source.** Snapshot is computed from `ActionProjectionQuery`, so widget "today" matches Action's events/allocations and dueToday/todayInstance sets. It is a snapshot, not a live DB view. `home_widget_service.dart:185-214`.
4. **W12.4 - Today timeline.** All today's events (including all-day) plus today's allocations, sorted by start. `home_widget_service.dart:243-279`.
5. **W12.5 - Today actions.** Ordinary Todos due today plus pending recurring instances today. Overdue and missed are not in the action list; they are counts only. `home_widget_service.dart:281-318`.
6. **W12.6 - Badge count.** `todoCount` = today's action rows + unplanned count, so the badge can exceed the number of rows shown. `home_widget_service.dart:193-195,525`.
7. **W12.7 - Upcoming.** Tomorrow through the next 7 full civil days (window `[tomorrow 00:00, tomorrow+8d 00:00)`), merging event occurrences, allocations, and ordinary Todo deadlines; no recurring Todo instances. `home_widget_service.dart:320-404`.
8. **W12.8 - Month dots.** Current civil month; a day is marked for any event occurrence or allocation overlapping it; deadlines do not create dots. `home_widget_service.dart:406-459`.
9. **W12.9 - Prelocalized chrome.** Snapshot carries localized labels and theme tokens, not raw l10n keys. Some row-level time strings in upcoming are still hard-coded English (`"All day"`, `"Deadline"`). `home_widget_service.dart:193-196,360-400`.
10. **W12.10 - Quick add is a deep link.** Widget quick add navigates to `/todo/new?source=widget`; it does not write directly from the widget. `home_widget_interactivity.dart:7-31`.
11. **W12.11 - Checkbox command.** Command v1 supports `action=complete` only. `target=todo` is forbidden for recurring Todos; `target=taskInstance` requires a non-empty occurrenceId and a recurring parent. `widget_command.dart:33-54,200-330`.
12. **W12.12 - Identity resolution.** Strict 5-case resolver uses `todoId` + `todoSyncId`: same row passes; syncId-only resolves; conflicting local/sync IDs or missing targets are terminal invalid; no guessing. `widget_command.dart:209-270`.
13. **W12.13 - Idempotency.** Already-completed ordinary/instance commands return `alreadyApplied`; invalid/malformed commands are acknowledged/discarded; transient failures remain queued for retry. `widget_command.dart:14-27,272-330,341-410`.
14. **W12.14 - Processing time.** Queued commands are drained when the app updates/home refreshes the widget, not while the app is absent. `home_widget_service.dart:132-153`.
15. **W12.15 - No live background updates promised.** Snapshot updates occur on record-bus refreshes, locale/theme changes, and app lifecycle refresh. There is no periodic background snapshot job in this implementation.

---

## 13. ICS, backup, restore, web limits

### 13.1 ICS

1. **X13.1 - Export scope.** "Export all calendars" writes one ICS containing all calendars/events/todos; no per-calendar UI selector despite the service supporting a calendar argument. `import_export_section.dart:56-60,223-255`, `ics_service.dart`.
2. **X13.2 - Synthetic UIDs.** Events export as `dayspark-event-<id>@dayspark`; Todos as `dayspark-todo-<id>@dayspark`. `ics_service.dart:24-110`.
3. **X13.3 - Omissions.** Event export writes RRULE but not EXDATE. Neither type exports reminders, tags, attachments, TaskAllocations, or instance completion states. Todo export includes due/start/priority/status/RRULE and recurrence anchor properties. `ics_service.dart:24-110`.
4. **X13.4 - Import target.** Import picks one target calendar first, then one `.ics` file. All components import in one transaction; malformed components are skipped and counted; a result snackbar reports events/todos/failed. `import_export_section.dart:155-221`, `ics_service.dart:121-191`.
5. **X13.5 - Recurrence classification.** Imported recurrence is classified into a RecurrenceSpec when evidence is sufficient; unsupported/ambiguous recurrence becomes `unknownLegacy`, which blocks occurrence actions until repaired. `ics_service.dart:202-391`, `docs/CONSTRAINTS.md`.
6. **X13.6 - Web encoding.** Web ICS import decodes bytes as strict UTF-8, not legacy charset detection; invalid bytes fail import. `import_export_section.dart:198-220,258-262`.
7. **X13.7 - Web export.** Current code supports browser download for both ICS and zip; older roadmap prose claiming web export is unavailable is stale. `import_export_section.dart:98-112,225-244`.

### 13.2 Full backup

1. **B13.1 - Container.** Zip contains `db.json` plus attachment bodies. Restore requires `db.json`. `backup_service.dart:176-212`.
2. **B13.2 - Exported tables.** Calendars, Events, Todos, Reminders, Tags, EventTags, TodoTags, Attachments. **Not** `task_allocations` or `task_instance_states`. `backup_service.dart:43-164`.
3. **B13.3 - JSON omissions.** No `serverRev`; no CreatedAt/UpdatedAt on exported rows. `backup_service.dart`.
4. **B13.4 - Restore is a merge/upsert.** One transaction; `insertOnConflictUpdate` keyed by local integer IDs. It never deletes existing rows. A restore into a DB with overlapping IDs can overwrite unrelated local rows. `backup_service.dart:229-382`.
5. **B13.5 - Consequences.** A "full backup" restores events/todos/reminders/tags/attachments but loses execution schedules and recurring instance completion history. This is not a faithful app-state snapshot.
6. **B13.6 - Attachments.** Missing attachment body keeps the recorded path only if the local file exists; otherwise the restored attachment becomes blank/fileless. `backup_service.dart:384-411`.
7. **B13.7 - UX.** Full Backup opens export or merge; merge accepts only `.zip`; web export downloads in-browser; native export writes to documents and shares; failures show snackbars. `import_export_section.dart:71-150`.

---

## 14. Settings that change behavior

| Setting | Default | Effect |
|---|---|---|
| Theme mode | System | System/light/dark; persisted; widget theme refresh on change. `theme_provider.dart`, `home_page.dart:232-233`. |
| Accent | Blue | Fixed accent palette; affects app theme and widget theme. `theme_provider.dart:8-18,48-105`. |
| Language | System | System/Chinese/English; persisted; changes l10n, re-schedules reminders with new strings, refreshes widget. `locale_provider.dart:12-49`, `reminder_reconciler.dart:60-78`. |
| Default tab | Action | Action/Calendar/Todos; persisted. If Home is open and user has not manually switched tab, changing the setting switches immediately; otherwise next open. `default_tab_provider.dart`, `home_page.dart:125-134`. |
| AI Assistant flag | Off | Hides/shows AI entry points and AI config; no model calls when off. `feature_flags_provider.dart:18-24`, `ai_section.dart`. |
| Sync flag | Set by login/logout | Login sets true, logout false; currently not used as an additional UI gate. `account_provider.dart:140,157`. |
| Six Things | Off | Enables the Six Things Todo chip and today-only six-item cap/numbering. `todos_ui_prefs_provider.dart:5-55`, `home_page.dart:1093-1210`. |
| Hide Completed | Off | Hides completed ordinary/recurring-instance rows in Todo views; not Action/search. `home_page.dart:948-1100`. |
| System alarm | Off | Android/iOS extra alarm scheduling; no UI on other platforms. `notifications_section.dart:36-59`, `alarm_service.dart`. |
| Server URL/email/password | Empty/logged out | Account and sync configuration; no effect on local-only use. `account_section.dart:123-213`. |

1. **G14.1 - Missing controls.** There is no week-start, timezone, date-format, 24-hour clock, density, first-day-of-week, sync interval, background-sync, auto-backup, or default-calendar setting. Language and theme are the only global presentation controls. `appearance_section.dart:24-203`.
2. **G14.2 - Manage Calendars placement.** The Settings row is hidden on desktop workspace layouts; calendar management remains accessible elsewhere but this Settings entry is mobile-only. `settings_page.dart:59-67`.
3. **G14.3 - Notifications section placement.** Visible only Android/iOS/macOS and not web; platform gates use `defaultTargetPlatform`, not `dart:io`. `settings_page.dart:84-90`, `notifications_section.dart:30-40`.
4. **G14.4 - AI config persistence.** Key/base/model are secure-storage values; presets only prefill, not lock. Changing model/base URL affects the next request only.
5. **G14.5 - Default tab is a start preference, not navigation state.** It does not override a tab the user explicitly selected in the current Home session. `home_page.dart:125-134`.

---

## 15. Invariants and edge cases an implementation must preserve

1. **I15.1 - One completion boundary.** All completion paths compare UTC millisecond instants; an allocation starting exactly at completion is invalidated; one starting even 1 ms earlier is historical. `todo_writer.dart:744-750`, `task_instance_writer.dart:107-109`, `server/lib/src/data/record_writer.dart:454-500`.
2. **I15.2 - Allocations never mutate deadlines or create Events.** Scheduling a task changes only `task_allocations`. `DECISIONS.md:300-310`.
3. **I15.3 - Recurring parent status is independent of instances.** A recurring Todo remains `NEEDS-ACTION` after any number of completed occurrences; do not auto-complete the series. `task_instance_writer.dart:66-80`.
4. **I15.4 - Occurrence IDs are wall-clock + zone.** Never derive a recurring occurrence identity from a UTC instant; `DATE` and `DATE-TIME` formats are distinct and canonical. `identity.dart:36-77`.
5. **I15.5 - DST behavior is fixed.** Gap uses the pre-gap offset; fold chooses the earlier instant. `resolver.dart:3-45`.
6. **I15.6 - Soft delete is the default delete.** Normal delete hides but preserves children; permanent delete is explicit trash purge and must cascade. `todo_writer.dart:262-393`, `events_dao.dart:92-125`.
7. **I15.7 - Restore mirrors cascade.** Restoring a child can untrash its parent; restoring a parent restores descendants. `todo_writer.dart:279-330`.
8. **I15.8 - Half-open time ranges everywhere.** Events/allocation visibility and occupancy use start-inclusive/end-exclusive; zero-duration/empty ranges are invalid for event forms and allocations. `action_section.dart:338-339`, `event_form_page.dart:165-192`, `task_allocation_writer.dart:168-174`.
9. **I15.9 - Action is not a task list.** Inbox/unplanned tasks, earlier-than-30-days missed series, legacy recurrence issues, and expansion errors are not rendered on Action. A day with only inbox work looks empty. `action_projection_query.dart:281-298`, `action_section.dart:60-64,291-323`.
10. **I15.10 - Full backup is not full.** Allocations and instance states are absent; a restore loses plans and occurrence completion. `backup_service.dart:43-164`.
11. **I15.11 - Local calendar metadata does not sync.** Calendars are not RecordTypes; name/color can diverge across devices. `record_dto.dart:11-20`, `sync_payload.dart:191-235`.
12. **I15.12 - Widget counts are not list lengths.** Badge includes unplanned; overdue/missed are counts; month dots exclude deadlines. `home_widget_service.dart:311-318,406-459,525`.
13. **I15.13 - Notification body taps are dead.** Only notification action callbacks work; action labels are hard-coded English. `notification_service.dart:135,151-167,318-329`.
14. **I15.14 - Snooze is temporary UI state.** It reschedules the OS notification for now+1h but does not update the reminder row. `home_page.dart:294-311`, `notification_service.dart:250-296`.
15. **I15.15 - Manual scheduling allows conflicts.** Only AI/MCP paths validate free time; the manual form writer does not. `task_allocation_writer.dart`, `execution_schedule_section.dart:140-193`, `ai_chat_page.dart:532-547`.
16. **I15.16 - Deleted calendars must never be orphaned.** Last calendar cannot be deleted; non-last delete re-homes or trashes contents. `calendars_page.dart:77-100,199-301`, `events_provider.dart:205-262`.
17. **I15.17 - Import/export fidelity is intentionally partial.** ICS omits EXDATE/reminders/tags/attachments/schedules; backup omits schedules/instance states. `ics_service.dart:24-110`, `backup_service.dart:43-164`.
18. **I15.18 - AI feature flag and breakdown semantics.** AI is hidden by default; breakdown creates an unparented, undated Todo with no reminder relation to the source. `feature_flags_provider.dart`, `ai_chat_page.dart:571-667`.
19. **I15.19 - MCP is not the in-app assistant.** Flutter AI chat does not call MCP; MCP is an external OAuth surface with its own 22 tools and no permanent delete. `server/lib/src/mcp/tools.dart`, `ai_provider.dart`.
20. **I15.20 - Widget commands fail closed.** Recurring target `todo` is terminal-invalid; taskInstance requires occurrenceId; conflicting identities are never guessed. `widget_command.dart:200-330`.

---

## 16. Minimum summary: eight subtlest semantics

1. **Action is a one-day projection, not the task list.** It always means today, has no date navigation, and renders only Now/Later/Due today/Overdue/Earlier today. Inbox/unplanned tasks, missed occurrences older than 30 days, unknown-legacy recurrence, and expansion errors are deliberately absent; a day with only inbox work shows "nothing now." Six Things belongs to the Todo view, not Action, and caps only today's dated Todos at six.
2. **`dueDate` is a deadline, never an execution block.** TaskAllocations are separate records with UTC instants; scheduling never changes `dueDate` or creates an Event. On completion, only allocations with `startAt >= completedAt` become invalid; history before completion survives. Reopening the Todo does not resurrect invalidated or cancelled blocks; cancel-undo creates a new allocation.
3. **Recurring Todo completion is instance-only.** The parent series never becomes `COMPLETED`; sparse `task_instance_states` track each occurrence. Occurrence IDs are canonical wall-clock identities (`v2:DATE:...` or `v1:DT:...@IANA`), with gap/fold rules, and the picker windows are 30 days back plus 90 days forward on page 1, then 30-day history chunks.
4. **Calendar is not uniformly manipulable.** Recurring and all-day events cannot be dragged/resized; ordinary events and allocations can. Month view has deadline dots only, while day/week has a deadline lane; recurring events have no per-occurrence edit, only whole-series edit or EXDATE deletion. The viewed date resets to today on restart; only view mode persists.
5. **Reminder rows store absolute instants, not "15 minutes before."** The relative label is computed. Editing the anchor shifts every reminder by the delta, including custom absolute ones. Default reminders exist only in AI flows, not manual creation. Snooze just reschedules the OS notification for now+1h without writing the DB, and notification-body taps currently do nothing; recurring "Mark Complete" opens the occurrence picker instead of completing.
6. **A "full backup" is not a full state backup.** It omits TaskAllocations and TaskInstanceStates, and restore is an ID-keyed upsert that can overwrite unrelated local rows. ICS additionally omits EXDATE, reminders, tags, attachments, and schedules, so re-importing an exported recurring event can resurrect excluded occurrences.
7. **Sync is local-first, but identity switching is not a data wipe.** Login sets tokens and clears cursor/snapshots/outbox; existing local rows and syncIds remain. Logging into another account can therefore mix local data with the new identity, while unsynced edits from the previous session are lost. Calendars themselves are local metadata and do not sync; events/todos only carry calendar IDs for best-effort remapping.
8. **AI and MCP are separate products with different defaults.** In-app AI is behind a default-off feature flag, sends only the current message, and its task breakdown creates an unparented, undated Todo with no confirmation beyond calendar choice. MCP is external-only, has 22 tools, no permanent-delete tool, and its free-time search defaults to weekdays while client AI's grid includes weekends.

Confirmed output path: `/Users/chang/Desktop/Code/dayspark-g0/docs/design/interaction-model/research/DOMAIN_BEHAVIORS.md`.
