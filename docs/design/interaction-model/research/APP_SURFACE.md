# DaySpark — App Surface & Interaction Inventory

Read-only inventory of every user-reachable surface in the Flutter app, for building an interactive prototype.
All paths are relative to `/Users/chang/Desktop/Code/dayspark`. Every claim cites `file:line`.

- Snapshot: `main` @ `46c01fe` (v0.29.0+29), 2026-11-16.
- Scope: `lib/ui/**`, `lib/core/router/app_router.dart`, platform widget/notification entry points, l10n labels.
- Not in scope: server MCP tool surface, CLI, sync protocol internals (only their UI surfaces are listed).

Conventions:
- **Label** = exact English copy from `lib/l10n/app_en.arb` with its key in parentheses.
- “→” = navigates to.
- “soft delete” = `deletedAt` set (recoverable from Trash); “hard delete” = row removed.
- Desktop = window width ≥ 1000 (`kWorkspaceBreakpoint`, `lib/ui/shell/workspace_scaffold.dart:7`); master-detail = width ≥ 1180 (`kMasterDetailBreakpoint`, `lib/ui/shell/workspace_navigation.dart:72`).

---

## 1. Route / entry table

Router: `lib/core/router/app_router.dart`. All routes use `NoTransitionPage` (26-28) — **no page animations anywhere**. Deep-link `redirect` translates `dayspark://` scheme URIs before matching (99-105).

| Path | name | Params / extra | How the user reaches it | Page built | Source |
|---|---|---|---|---|---|
| `/` | `home` | query `tab` = 0\|1\|2 (clamped) | App launch (`initialLocation`, 93); sidebar Action/Calendar/Tasks; mobile bottom nav; sidebar Today/Inbox/All; trash empty-state “Back to Tasks”; all error pages “Return to Home” | `HomePage(initialTab)` | 144-155 |
| `/settings` | `settings` | — | Desktop sidebar Settings; mobile app-bar gear | `SettingsPage` | 159-163 |
| `/event/new` | `eventCreate` | query `start`,`end` = epoch ms (defaults now / now+1h) | Header “New Event” on Calendar tab; calendar blank-slot sheet “New Event” | `EventFormPage` | 164-189 |
| `/event/detail` | `eventDetail` | `extra: CalendaEventAdapter` (required; missing → `_missingObjectPage`) | Calendar tab event tile tap; Action tab event row tap; search event row tap | `EventDetailPage` | 190-205 |
| `/event/edit` | `eventEdit` | `extra: CalendaEventAdapter` | **No in-app caller** (see §10 G1) | `EventFormPage(event:)` | 206-221 |
| `/todo/new` | `todoCreate` | query `parentId`, `source`, `start`, `end` (date or epoch ms) | Header “New Task” on Action/Tasks; Tasks quick-add? (no — inline); widget deep link; **no caller passes `parentId` or `source`** | `TodoFormPage` | 222-247 |
| `/todo/detail` | `todoDetail` | `extra: Todo` (required) | Narrow layout: todo row tap (Action, Tasks, search, calendar deadline/allocation, notification complete on recurring); desktop master-detail pane instead | `TodoDetailPage` | 248-263 |
| `/todo/edit` | `todoEdit` | `extra: Todo` | Only the legacy-recurrence notice in todo detail (“Edit”) | `TodoFormPage(todo:)` | 264-279 |
| `/search` | `search` | — | Desktop sidebar search entry; mobile app-bar search icon | `SearchPage` | 280-284 |
| `/tags` | `tags` | — | Desktop sidebar Manage Tags; Tasks-tab tag icon (mobile); `TagChips` “Create Tag” when no tags | `TagsPage` | 285-289 |
| `/calendars` | `calendars` | — | Desktop sidebar Manage Calendars; mobile Settings row | `CalendarsPage` | 290-294 |
| `/ai-chat` | `aiChat` | — | Desktop sidebar AI Assistant (flag-gated); mobile app-bar sparkles (flag-gated) | `AiChatPage` | 295-299 |
| `/about` | `about` | — | Settings → About row | `AboutPage` | 300-304 |
| `/trash` | `trash` | — | Desktop sidebar Trash; Tasks-tab trash icon (mobile) | `TrashPage` | 305-309 |
| `/feedback` | `feedback` | — | About → “Report an Issue” | `FeedbackPage` | 310-314 |
| `dayspark://quick-add` (scheme) | — | redirect → `/todo/new?source=widget` | Android home-widget quick-add; iOS widget quick-add link/`widgetURL`; OS deep link | `TodoFormPage` | interactivity 7-17, 24-31; manifest 35-48; iOS plist 33-43; macOS plist 23-32 |
| unknown path | — | — | Manual URL | Error page: “Page not found…” + “Return to Home” | 106-142 |

Shell structure:
- `/` is **outside** the `ShellRoute`; `HomePage` renders its own `WorkspaceScaffold` on desktop (`home_page.dart:483-484`).
- Every other route is inside `ShellRoute(builder: WorkspaceScaffold)` (`app_router.dart:156-158`), so the desktop rail persists while the content pane swaps.
- `WorkspacePage` supplies chrome for pushed pages: mobile AppBar with back; desktop 48px inline header with back only when `canPop` (`lib/ui/shell/workspace_page.dart:41-130`).
- `ShellRoute` + `go()` (not `push`) for sidebar destinations, so there is no back stack between top-level destinations (`workspace_sidebar.dart:185-190`).

---

## 2. Per-screen inventory

### 2.1 Desktop workspace rail — `lib/ui/shell/workspace_sidebar.dart`

Fixed width 232 (30). Rendered only when `isWorkspaceLayout` (`workspace_scaffold.dart:24`). Selected state: primary destinations highlight only on `/` (35-36); secondary destinations highlight by path prefix (165-166).

| Control | Label (key) | Action | Destination | Source |
|---|---|---|---|---|
| Brand header | app name (appName) | none (static) | — | 211-255 |
| Search entry (32px tall) | Search (search) | `go` | `/search` | 60, 259-305 |
| Action | Action (action) | set `workspaceTabProvider=action`, `go /?tab=0` | Action tab | 62-67, 192-198 |
| Calendar | Calendar (calendar) | tab=1 | Calendar tab | 68-73 |
| Tasks | Tasks (todos) | tab=2 | Tasks tab | 74-79 |
| Today (indented sub-row) | Today (today) | `TodosDayView(now)` + tab=2 | Tasks day view | 82-93 |
| Inbox (sub-row) | Inbox (inbox) | `TodosInboxView` | Tasks inbox | 94-99 |
| All Tasks (sub-row) | All Tasks (allTasks) | `TodosAllView` | Tasks all | 100-104 |
| Divider | — | — | — | 106-110 |
| Manage Calendars | Manage Calendars (manageCalendars) | `go` | `/calendars` | 112-117 |
| Manage Tags | Manage Tags (manageTags) | `go` | `/tags` | 118-123 |
| Trash | Trash (trash) | `go` | `/trash` | 124-129 |
| AI Assistant | AI Assistant (aiAssistant) | `go`; **hidden** while flag resolves false (falls back visible while loading) | `/ai-chat` | 130-136, 38-43 |
| Settings (pinned bottom) | Settings (settings) | `go` | `/settings` | 138-143 |

Row hit area: `minHeight: 32`, 7px vertical padding, `MouseRegion(click)` (384-421). Sidebar rows are **below the 48px touch target** (desktop-only surface).

### 2.2 Home chrome — `lib/ui/pages/home/home_page.dart`

| Control | Label (key) | Action | Destination / effect | Source |
|---|---|---|---|---|
| Page title | Action / Calendar / Tasks, or calendar header title | static; calendar title supplied by `CalendarSection` | — | 328-332, 531-586 |
| Page subtitle | weekday (+ lunar date in zh) on Action; calendar subtitle (year in month view) | static | — | 543, 588-595 |
| Create button (mobile app bar, desktop page header) | New Task (newTodo) / New Event (newEvent) | push form | `/todo/new`; `/event/new?start&end` | 457, 581, 770-814 |
| Mobile search icon | Search (search) | push | `/search` | 423-432 |
| Mobile AI icon | AI Assistant (aiAssistant) | push; flag-gated | `/ai-chat` | 433-446 |
| Mobile settings icon | Settings (settings) | push | `/settings` | 447-455 |
| Mobile bottom nav | Action / Calendar / Tasks | set tab (no route change) | tab 0/1/2 | 462-481, 140-144 |
| Master-detail pane (≥1180) | — | shows selected object, 400px wide, 1px divider | todo/event detail pane | 385-404, 487-504 |
| Pane close | Close (close) | clear selection | — | todo 203-209; event 187-193 |

Hidden/conditional:
- AI icon/rail hidden when `FeatureFlag.aiAssistant` is false (433-437, 38-43).
- Bottom nav and app bar only when **not** desktop (408-481).
- Detail pane only when `desktop && width≥1180 && selection != null` (386-401).

### 2.3 Action tab — `lib/ui/pages/home/action_section.dart`

One day wide (today), no date switcher, no counters (20-24). Sections are ordered: Now → Next up → To do today → Overdue → Earlier today (78-165).

| Control | Label (key) | Action | Source |
|---|---|---|---|
| Section header “Now” | Now (actionNow) | static, warm tint | 108-112 |
| Section header “Next up” | Next up (laterToday) | static | 113-117 |
| Section header “To do today” | To do today (dueTodaySection) | static | 121-131 |
| Section header “Overdue” | Overdue (overdue) | static, error accent | 133-148 |
| Section header “Earlier today” | Earlier today (actionEarlierToday) | static | 150-163 |
| Event / allocation row | time + “until HH:mm” or “Scheduled time” + title | row tap → object; checkbox (if toggleable) | 167-206, 343-446 |
| Deadline todo row | time or “Today”, meta “Deadline: date” | row tap → todo; checkbox toggles | 208-226 |
| Recurring instance row | occurrence label, meta “Recurring” / “Missed” | row tap → todo; checkbox toggles that occurrence | 228-245 |
| Row checkbox | (a11y: Mark Complete / Mark incomplete) | completes todo/allocation-bound occurrence | 424-439 |
| Row trailing chevron (no checkbox) | — | rows with no toggle show a chevron | 427-434 |

Behavior details:
- Current = started, not ended; later = starts after now; earlier = ended (89-106).
- Allocation checkbox completes the allocation’s bound `occurrenceId` (196-203); recurring instance toggles by `occurrenceId` (266-281); ordinary todo uses the shared completion helper (which opens the occurrence picker for recurring rows) (247-264).
- Date-only deadlines print no clock (285-289).

### 2.4 Calendar tab — `lib/ui/widgets/calendar/*`

`CalendarSection` (`calendar_section.dart`), hosted by `home_page.dart:605-768`. Range 2000-2100 (79-84); recurring events expanded ±45 days (641-646).

| Control | Label (key) | Action | Source |
|---|---|---|---|
| View switcher (segmented) | Day (day) / Week (week) / Month (month) | persists via `calendarViewModeProvider`; default Week | 271-275; view_switcher 28-63; provider 24 |
| Today | Today (today) | jump to today; **hidden when already viewing today** | 276-294, 110-125, 360-365 |
| Previous period | a11y “Previous” (previousPeriod) | −1 day / −7 days / −1 month | 296-306, 367-373 |
| Next period | a11y “Next” (nextPeriod) | +1 day / +7 days / +1 month | 307-317, 375-381 |
| Week number label | — | static quiet label | 496-503 |
| Day header | weekday + big date; today in accent circle | static | calendar_day_header.dart 28-56 |
| Blank time slot (day/week) | a11y “Empty time slot, activate to create an event” (emptySlotSemantics) | opens `CalendarSlotSheet` with a **1-hour** range starting at the tapped wall-clock time | 390-403, 637-643; l10n 483 |
| Event tile | title, time (all-day: none), calendar colour stripe | tap → event detail/selection | event_tile 94-114; calendar_section 405-419 |
| Allocation tile | todo title + time range, dashed primary outline, square glyph | tap → todo detail/selection | task_allocation_tile 45-92; calendar_section 405-411 |
| Drag / resize event | — | persists new range; **recurring and all-day are rejected** with snackbar and snapped back | 421-450, 155-184 |
| Drag / resize allocation | — | persists; failure reverts and shows error | 423-433, 140-153 |
| Deadline lane (day/week, only if deadlines exist) | “Deadlines” (calendarDeadlineLane) | tap item → todo; lane max height 96 | 597-612; calendar_deadline_lane 18-120 |
| Month day cell | day number; today circle; red deadline dot; holiday badge (work/rest); solar-term micro-label; adjacent-month dim 0.3 | **no tap callback** — month grid is read-only for day cells | marked_month_day_header 76-167; calendar_section 573-586 |
| Month event tiles | title (+time) | rendered by tile builder; no month-level tap callback is passed to kalender | 619; month_body.dart in kalender 0.17.0 has no tap handler |
| Empty-grid hint | “Tap an empty slot to create your first event” (emptyCalendarHint) | non-interactive overlay, taps pass through | 646-676; l10n 484 |
| Now indicator | — | warning-coloured line+circle in day/week | 526-529 |
| Hour lines / ruler | `H:mm` hourly labels | static | 516-556 |
| Page swipe | — | kalender PageView paging | kalender month_body; callbacks 451 |

Deadline data: only **non-recurring** todos with `dueDate`, not COMPLETED/CANCELLED (`home_page.dart:615-623`). Month cells get a dot via `hasDeadline` (579-584).

### 2.5 Tasks tab — list, toolbar, quick add, reorder

Hosted by `home_page.dart:838-1187`; controls in `lib/ui/widgets/todo/date_strip.dart`, `todo_quick_add.dart`, `todo_list_tile.dart`.

| Control | Label (key) | Action | Hidden/disabled | Source |
|---|---|---|---|---|
| Month label | e.g. “Sep 2026” | static | — | date_strip 38, 49-55 |
| Today (jump) | Today (today) | select today | only when selected day ≠ today | 39, 56-71 |
| All Tasks chip | All Tasks (allTasks) | `TodosAllView` | — | 79-85 |
| Inbox chip | Inbox (inbox) | `TodosInboxView` | — | 87-93 |
| Six Things chip | Six Things (sixThings) | toggles six-things cap | — | 95-101 |
| Week strip prev / next | a11y previous/next month tooltip | ±7 days, keeps weekday offset | — | 128-248 |
| Week day cells (7) | weekday abbrev + day number | select that day | only in day view | 158-231 |
| Desktop toolbar | same three chips + Today + month | same actions | desktop only | 252-354 |
| Tag filter chip (per tag) | tag name | filter pending list by tag (multi-select OR) | hidden if no tags | home 816-836, 864-904 |
| Manage tags icon (mobile) | a11y Manage Tags | → `/tags` | — | home 920-931 |
| Trash icon (mobile) | a11y Trash | → `/trash` | — | home 933-944 |
| Quick-add row | hint “Quick add” (quickAdd) | Enter creates todo; keeps focus for next | desktop + mobile; no calendar → snackbar | home 905; quick_add 38-63, 92-116 |
| Section header | Overdue / Today / date / Completed / All Tasks / Inbox + count | static | — | home 1364-1393 |
| Todo row — checkbox | a11y Mark Complete / Mark incomplete | complete; recurring → occurrence picker | checkbox omitted on read-only surfaces | list_tile 149-183, 312-335 |
| Todo row — body | title, repeat icon if recurring, up to 3 tag dots, due label | tap → detail (or pane) | — | list_tile 195-278, 234-261 |
| Todo row — priority stripe | 2px colour (red=High, amber=Medium/Low) | static | transparent for None | list_tile 139-148, 52-69 |
| Todo row — due label | Today/Tomorrow/Overdue/short date/range | static | hidden if no due date | list_tile 71-92 |
| Drag handle (desktop) | grip icon, grab cursor | reorder within pending list | desktop only (Linux/macOS/Windows) | home 1211-1241 |
| Whole-row long-press drag (mobile) | — | reorder | mobile only | home 1242-1246 |
| Six-things “More (n)” fold | More ({count}) (moreItems) | expand full day list | only today, >6 items, six-things on | home 1097-1153 |
| Six-things “Collapse” fold | Collapse (collapseList) | collapse back to 6 | only while expanded | home 1154-1163 |
| Completed group header | Today / Yesterday / date + count | expand/collapse group (today initially expanded) | hide-completed on → groups absent | home 1287-1308 |
| Empty state | “No pending tasks” (noPendingTodos) | none | — | home 1313-1335 |

Six-things cap: only day view **and** selected day == today (1097-1101); sequence numbers shown only there (1199-1211); toggling the cap collapses the fold (913-918).

### 2.6 Todo detail (inline-editable) — `lib/ui/pages/todo/todo_detail_page.dart`

Same widget is the mobile page body and desktop right pane (`TodoDetailPage` 35-49; pane 52-70).

| Control | Label (key) | Effect / save trigger | Source |
|---|---|---|---|
| Title field | hint Title (title) | 600ms debounce + submit + focus loss; empty reverts; immediate DB write | 174-201, 433-445 |
| Close (pane only) | Close (close) | clears selection | 203-209 |
| Status line | Completed (completed) / Not completed (openTask) | static | 213-234 |
| Mark Complete / Mark incomplete | Mark Complete / Mark incomplete | toggles; recurring opens occurrence picker | 235-243, 573-584 |
| Deadline row | Deadline (deadline) / No deadline (noDeadline) | date picker (time if existing has time); clear X | 253-265, 482-492 |
| Start date row | Starts at (startDate) | **read-only display**, only when repeat + start exist | 266-270 |
| Repeat row | Repeat rule (recurrenceRule) / Does not repeat (repeatNever) | opens repeat sheet; clear X stops repeat immediately | 271-283 |
| Scheduled time section | Scheduled time (executionSchedule), Add execution time (addExecution) | add / reschedule / cancel allocations (immediate) | 284-286 |
| Priority chips | None/Low/Medium/High | immediate write | 376-407 |
| Description field | hint Description (description) | 600ms debounce | 292-315, 447-455 |
| Tag chips | tag names | immediate add/remove | 317, 409-416 |
| Attachments | Add attachment / file rows | immediate add/open/delete | 321 |
| Move to Trash | Move to Trash (moveToTrash) | confirm dialog → soft delete → 5s Undo | 325-340, 586-627 |
| Legacy recurrence notice | “Edit” (edit) | → `/todo/edit` | 353-374 |

Not present in detail: reminders, subtasks, calendar picker, event-style all-day. (See §10 G4, G5.)

### 2.7 Todo form (create + edit) — `lib/ui/pages/todo/todo_form_page.dart`

One page for both; `todo` present = edit (139-145). Everything is a draft until Save (144-145). Desktop content width 720 (699).

| Control | Label (key) | Behavior | Validation / disabled | Source |
|---|---|---|---|---|
| Title | hint Title (title) | autofocus on create | required → snackbar “Please enter a title” | 737-754; 353-358 |
| Deadline row | Deadline / No deadline | date picker; clock icon popup chooses “Set deadline” vs “Deadline time” | clear X when set | 762-788 |
| Repeat row | Repeat rule | opens repeat sheet; requires anchor date; start date can be set inside | snackbar “Give it a date first…” | 789-802; repeat_editor 99-126 |
| Scheduled time section | Scheduled time / Add execution time | draft allocations; recurring asks occurrence | hidden for unknown legacy rule | 805-810 |
| Priority chips | None (0) / Low (9) / Medium (5) / High (1) | draft | — | 919-950 |
| Calendar row | Calendar (calendar) + current name | bottom-sheet picker; **tap disabled when only one calendar** | hidden if no calendars | 952-1004 |
| Description | hint Description | draft | — | 818-834 |
| Tag chips | tag names / “Create Tag” when none | draft | — | 836-839 |
| Reminders | Add Reminder | draft list; remove X | — | 841-847 |
| Attachments | Add attachment | draft list; remove X | — | 849-854 |
| Subtasks header + Add subtask | Subtasks / Add subtask | dialog with text field; list rows toggle / remove | empty → “No subtasks” | 1006-1093 |
| Save | Save (save) | atomic write, uploads, pop | spinner while saving | 719; 350-482 |
| AI parse | AI parse (aiParse) tooltip | fills only empty deadline/priority/description; snackbar names filled fields | needs title; needs AI config | 707-717; 582-647 |
| Delete (edit only) | Move to Trash (moveToTrash) tooltip | confirm → soft delete → 5s Undo | — | 701-706; 1142-1177 |
| Back / Escape | — | dirty → “Discard changes?” dialog | Escape only when form has focus | 651-691 |
| Legacy notice | “Recurring rule needs repair” / broken variants + repair button | opens legacy confirmation dialog | replaces schedule fields entirely | 757-760, 861-902 |

Create defaults (`initState` 200-227): calendar = first; from calendar slot → one draft execution `[start,end]` and deadline = start’s date; priority 0; status `NEEDS-ACTION`; `parentId` from route (441).

### 2.8 Event detail (inline-editable) — `lib/ui/pages/event/event_detail_page.dart`

| Control | Label (key) | Effect / save trigger | Source |
|---|---|---|---|
| Title | hint Title | 600ms debounce; empty reverts | 159-185, 384-396 |
| Close (pane only) | Close | clear selection | 187-193 |
| Recurring notice | “This repeats. Edits apply to every occurrence.” (recurringSeriesNoticeShort) | static | 196-216 |
| All day switch | All day (allDay) + All day/Event | immediate; normalises to midnight when turned on | 220-227, 445-454 |
| Start row | Start (startTime) | date+time picker (date only if all-day); keeps duration | 228-234, 456-474 |
| End row | End (endTime) | picker; rejects end ≤ start with snackbar | 235-241, 476-508 |
| Duration row | Duration (duration) | read-only computed; shows “end after start” error state | 242-250 |
| Repeat row | Repeat rule | immediate write; clear X stops series | 251-256 |
| Calendar row | Calendar + name | **read-only** (no tap) | 257-258 |
| Location | hint Location | 600ms debounce | 262-284, 408-416 |
| Description | hint Description | 600ms debounce | 286-309 |
| Tag chips | tag names | immediate | 311, 339-347 |
| Attachments | Add attachment / rows | immediate | 315 |
| Move to Trash | Move to Trash | scope dialog for occurrences; confirm; soft delete; 5s Undo (series only) | 319-334, 510-615 |

### 2.9 Event form — `lib/ui/pages/event/event_form_page.dart`

Create + edit in one page (29-35). Reachable for create; edit route is orphaned (§10 G1).

| Control | Label (key) | Behavior | Validation | Source |
|---|---|---|---|---|
| Title | hint Title | autofocus on create | required | 633-650; 182-187 |
| Recurring notice | recurringSeriesNoticeShort | static | — | 654-676 |
| All day switch | All day + All day/Event | toggles; date-only pickers | — | 679-686 |
| Start | Start | date+time (date-only if all-day); keeps length | — | 687-693; 426-449 |
| End | End | picker | end must be > start | 694-700 |
| Duration | Duration | computed; “The end has to come after the start.” when invalid | Save disabled while invalid | 701-714; 167, 617-623 |
| Repeat | Repeat rule | sheet | needs start (always present) | 715-720 |
| Calendar | Calendar + name | bottom sheet; dangling calendar must be re-chosen | `calendarUnavailable` snackbar | 724, 501-572; 209-215 |
| Location | hint Location | draft | — | 726-740 |
| Description | hint Description | draft, 4 lines | — | 742-758 |
| Tags | tag chips | draft | — | 760-764 |
| Reminders | Add Reminder | draft, anchored to start | — | 766-772 |
| Attachments | Add attachment | draft | — | 774-779 |
| Save | Save | atomic write + upload | disabled invalid range; spinner | 617-623; 179-303 |
| AI parse | AI parse | overwrites title/start/end/desc/location/all-day | silently no-op if title empty; needs config | 605-615; 451-499 |
| Delete (edit only) | Move to Trash | confirm; recurring gets series wording; 5s Undo | — | 599-604; 385-424 |
| Back / Escape | — | discard confirmation | — | 360-383, 580-594 |

### 2.10 Calendar blank-slot sheet — `lib/ui/widgets/calendar/calendar_slot_sheet.dart`

Modal bottom sheet, top radius 16 (39-53). Two pages: choices, then todo picker.

| Control | Label (key) | Action | Source |
|---|---|---|---|
| Range header | e.g. “Oct 24 14:00 – 15:00” | static | 91-95, 118-126 |
| New Event | New Event (createEventOption) / “Add an event at this time” | closes sheet → `/event/new?start&end` | 128-136 |
| Schedule Task | Schedule Task (scheduleTodo) / “Give an existing task a time here” | switches to picker | 137-142 |
| New Task | New Task (createTodoAndSchedule) / “Start a task and place it in this slot” | closes → `/todo/new?start&end` | 143-152 |
| Picker back arrow | — | returns to choices | 154-162 |
| Picker title | Select a Task to Schedule (selectTodoToSchedule) | static | 163-170 |
| Candidate row | todo title; subtitle Recurring / “Due: date” / No due date | non-recurring: create allocation; recurring: occurrence picker first | 201-243 |
| Loading | spinner | — | 175-179 |
| Empty | “No pending tasks available to schedule” (noSchedulableTodos) | — | 180-191 |

### 2.11 Repeat sheet — `lib/ui/widgets/schedule/repeat_editor.dart`

Row (57-126) + bottom sheet (231-404). The row prints a localized phrase, never an RRULE (51-56, 144-194).

| Control | Label (key) | Action | Source |
|---|---|---|---|
| Repeat row value | Does not repeat / Every day / Every week / Every month / Every year / “Custom repeat…” plus interval/day/count/until phrasing | opens sheet | 87-97, 144-194 |
| Clear X | tooltip Repeat never (repeatNever) | sets rule to null immediately | 94-96 |
| Sheet title + close | Repeat rule (recurrenceRule), Close | dismiss | 278-290 |
| “Repeat from” option (only when an explicit start is editable) | “Repeat from: date” | date picker → set start date → closes | 296-313 |
| Does not repeat | repeatNever | select | 314-323, 396-403 |
| Every day / week / month / year | repeatDaily/Weekly/Monthly/Yearly | select | 314-323 |
| Custom repeat… | repeatCustom | reveals `RRuleGenerator` inline | 324-335, 336-354 |
| Done | Done (done) | returns chosen rule | 359-370 |
| Anchor hint | optional label | static | 372-386 |

If no date exists the sheet refuses with “Give it a date first, then it can repeat.” (105-109).

### 2.12 Occurrence picker — `lib/ui/widgets/todo/todo_occurrence_picker_sheet.dart`

AlertDialog, width 360 (115-118).

| Control | Label (key) | Action | Source |
|---|---|---|---|
| Earlier 30 days | Earlier 30 days | page +1 | 124-127 |
| Newer | Newer (newerOccurrences) | page −1; hidden on first page | 128-133 |
| Window hint | “Showing matches only within the next 90 days…” | static | 135-141 |
| Occurrence row | formatted date/time; check icon when completed | select and close | 172-198 |
| Cancel | Cancel | close with null | 205-210 |
| Loading / error / empty | spinner / “Something went wrong…” / “No occurrences are available in the next 90 days.” | — | 146-171 |

Legacy rules intercept first: unsupported → snackbar; supported → `confirmLegacyRecurrence` (48-65).

### 2.13 Reminders section & sheet — `lib/ui/widgets/reminder/reminders_section.dart`

| Control | Label (key) | Action | Source |
|---|---|---|---|
| Add Reminder | Add Reminder (addReminder) | opens sheet | 73-87 |
| Reminder row | “On time” / “N min before” / “N h before” / “N day(s) before” / absolute moment | static | 104-117, 163-181 |
| Remove X | Remove reminder (removeReminder) | immediate (DB) or draft removal | 223-230 |
| Empty | “No reminders set” (noReminders) | — | 151-159 |
| Sheet close | Close | dismiss | 261-271 |
| No-anchor hint | “Set a deadline or start time first…” | shown only when no anchor | 274-288 |
| Presets | On time / 5 min / 15 min / 30 min / 1 h / 1 day before | returns computed time | 289-324 |
| Custom time | Custom time (remindCustom) | date+time picker | 325-336 |

### 2.14 Execution (scheduled time) — `lib/ui/widgets/schedule/execution_schedule_section.dart`

| Control | Label (key) | Action | Source |
|---|---|---|---|
| Add execution time | Add execution time (addExecution) | recurring → occurrence picker; then execution sheet | 102-109, 140-194 |
| Row | Scheduled time (executionRow) + “M/D HH:mm – HH:mm” | tap reschedules (saved rows only) | 114-127 |
| Clear X | Cancel scheduled time (cancelSchedule) | cancel + Undo snackbar (saved) or draft removal | 118-127, 231-259 |
| Sheet close | Close | dismiss | 318-332 |
| When | Scheduled time (executionWhen) | date+time picker | 334-341 |
| Length chips | 30 min / 1 h / 2 h / 4 h | choose duration | 350-367 |
| Save | Save | returns draft block | 369-377 |

Scheduling disabled when the todo is deleted/completed/cancelled (132-138).

### 2.15 Legacy recurrence dialog — `lib/ui/widgets/todo/legacy_recurrence_dialog.dart`

| Control | Label (key) | Action | Source |
|---|---|---|---|
| Title/body | “Confirm…” + explanation | static | 159-174 |
| Date only / Date and time chips | dateOnly / dateAndTime | choose anchor type | 175-200 |
| Repeat from row | legacyRepeatFrom + date | date picker (time when date+time) | 201-214 |
| Preview | Preview (preview) | computes first 5 occurrences; Save disabled until previewed | 242-270 |
| Preview error / labels | expansion errors | inline | 215-237 |
| Cancel | Cancel | abort | 243-246 |
| Save | Save | writes interpretation; disabled until previewed | 266-271 |

### 2.16 Search — `lib/ui/pages/search/search_page.dart`

| Control | Label (key) | Action | Source |
|---|---|---|---|
| Search field (autofocus) | hint Search | 300ms debounce; submit; clears page counters | 88-128 |
| Clear | a11y Close | clear query/results | 130-135 |
| Event result row | title + date | → `/event/detail` | 210-221 |
| Todo result row | title, date, tags, **no checkbox** (read-only) | → `/todo/detail` | 243-254 |
| Load More (events) | Load More | page++ | 223-234 |
| Load More (todos) | Load More | page++ | 256-267 |
| Suggestions (empty query) | “From your inbox” + top 3 inbox todos | tap → detail | 275-301 |
| Retry (error) | Retry | invalidate provider | 164-172 |

### 2.17 Tags — `lib/ui/pages/tags/tags_page.dart`

| Control | Label (key) | Action | Source |
|---|---|---|---|
| Add (header) | a11y Create Tag | open create dialog | 42-46 |
| Empty action | Create a tag (tagsEmptyAction) | open create dialog | 67-77 |
| Tag row | colour dot + name | open edit dialog | 83-89 |
| Delete icon | Delete Tag (deleteTag) | confirm (“Remove the tag … from every task?”) → delete | 90-94, 103-133 |
| Dialog name field | Tag name (tagName), max 50 | validation: required / too long / duplicate (case-insensitive) | 153-161, 179-198 |
| Colour swatches | 10 named colours | select | 163-167; color_swatch_grid 13-26 |
| Cancel / Create-or-Save | Cancel / Create / Save | writes | 171-228 |

### 2.18 Calendars — `lib/ui/pages/calendar/calendars_page.dart`

| Control | Label (key) | Action | Source |
|---|---|---|---|
| Add (header) | a11y New Calendar | create dialog | 41-45 |
| Empty action | Create (create) | create dialog | 66-75 |
| Calendar row | colour dot + name | edit dialog | 87-93 |
| Delete icon | Delete Calendar | delete decision dialog; **hidden when only one calendar** | 77, 94-100 |
| Dialog name field | Calendar Name (calendarName) | required | 129-137 |
| Colour swatches | 10 named colours | select | 139-143 |
| Cancel / Create-or-Save | Cancel / Create / Save | writes | 146-190 |
| Delete dialog | calendar name + “This calendar holds N events and M tasks.” | Move them to / Delete them with the calendar / Cancel | 217-256 |
| Move target sheet | Move them to + target rows | choose destination | 260-285 |

### 2.19 Trash — `lib/ui/pages/trash/trash_page.dart`

| Control | Label (key) | Action | Source |
|---|---|---|---|
| Empty Trash (header) | Empty Trash | confirm “Permanently delete all items in trash?” → hard delete all todos+events | 33-39, 249-278 |
| Empty state | “Trash is empty” + hint + “Back to Tasks” | go `/?tab=2` and set tab | 48-63 |
| Section headers | Tasks / Events + count | static | 200-220 |
| Todo row | struck-through title + deleted time | static | 99-128 |
| Event row | struck-through title + start · deleted time | static | 130-158 |
| Restore | Restore (restoreTodo) | restores; snackbar “Restore” | 170-181 |
| Delete Permanently | Delete Permanently (permanentDelete) | confirm “This cannot be undone.” → hard delete | 182-195, 222-247 |

### 2.20 Settings — `lib/ui/pages/settings/settings_page.dart` + sections

Page: content width 720 (54). Groups (58-77): Appearance, (mobile-only) Manage Calendars, Tasks, Data, Account, Advanced Features, Notifications (platform-gated), About.

#### Appearance — `settings_sections/appearance_section.dart`

| Control | Label (key) | Action | Source |
|---|---|---|---|
| Theme segmented | System Default / Light / Dark (themeSystem/Light/Dark) | sets `themeModeProvider` (persisted) | 52-77 |
| Accent swatches (5) | Blue/Green/Orange/Purple/Pink (localized names) | sets `themeColorProvider` (persisted) | 114-164; theme_provider 13-18 |
| Language row | Language → Follow System / Chinese / English | dialog: System / Chinese / English | 172-186, 241-262 |
| Startup view row | Startup view → Today / Calendar / Tasks | dialog: same three | 187-201, 264-278 |

#### Tasks section — `settings_sections/todos_section.dart`

| Control | Label | Action | Source |
|---|---|---|---|
| Six Things switch | Six Things + “Cap today's list at six items with a More fold” | toggle cap | 17-24 |
| Hide completed switch | Hide completed + “Hide completed items from task lists” | toggle | 25-31 |

#### Data — `settings_sections/import_export_section.dart`

| Control | Label (key) | Action | Source |
|---|---|---|---|
| Import into | Import into + “Calendar data” | pick `.ics` → choose target calendar → import; result snackbar | 50-55, 155-221 |
| Export all calendars | Export all calendars | writes `.ics` (all calendars) → share / browser download | 56-60, 225-255 |
| Full backup | Full backup + “Archive with all data and attachment files” | dialog: Merge backup / Export | 61-66, 71-96 |
| Merge backup | Merge backup | pick `.zip` → restore (upsert; nothing removed) | 79-85, 129-150 |
| Export (backup) | Export | `.zip` → share / download | 86-92, 98-125 |

#### Account — `settings_sections/account_section.dart`

| Control | Label (key) | Action | Source |
|---|---|---|---|
| Server URL | Server URL, hint `https://sync.example.com` | prefill from stored setting | 131-140 |
| Email | Email | — | 142-147 |
| Password | Password (obscured) | — | 149-155 |
| Register | Register | register; errors inline | 176-190, 295-315 |
| Login | Login | login | 191-206 |
| Logged-in identity row | email + sync phase / last sync / rejected codes | static | 220-224, 374-389 |
| Connected devices | Connected devices | dialog: device name + last active; empty / load-failed / spinner | 225-229, 320-372 |
| Sync now | Sync now (tooltip “Sync”) | request sync round | 230-251 |
| Logout | Logout | confirm “Log out? … Syncing stops…” | 253-260, 270-293 |

Error mapping: invalid URL/email, password required/too short, email exists, invalid credentials, generic auth failed (391-401).

#### Advanced Features / AI — `settings_sections/ai_section.dart`

| Control | Label (key) | Action | Source |
|---|---|---|---|
| Expansion tile | AI Assistant | expand | 20-49 |
| Enable switch | AI Assistant | sets `FeatureFlag.aiAssistant` | 26-39 |
| Tutorial icon | a11y Tutorial | opens GitHub `docs/ai-setup.md` externally | 52-65 |
| AI Configuration row | AI Configuration + “✓” when configured | opens AI config dialog | 40-47 |

#### Notifications — `settings_sections/notifications_section.dart`

| Control | Label | Platform | Source |
|---|---|---|---|
| System Alarm switch | System Alarm + “Play alarm sound for reminders” | Android/iOS only | 36-38, 46-58 |
| Notification permission row | Notification permission + desc → requests permission, snackbar | macOS only | 39, 60-74 |
| Exact alarm row | Exact alarm permission + desc | Android only, **only when not granted** | 40, 76-89 |

#### About row — `settings_sections/about_section.dart:15-20` → `/about`.

Mobile-only Manage Calendars row → `/calendars` (`settings_page.dart:59-67`).

### 2.21 AI chat — `lib/ui/pages/ai_chat/ai_chat_page.dart`

| Control | Label (key) | Action | Source |
|---|---|---|---|
| Clear chat (header) | a11y Clear chat | confirm “Clear this conversation? It can't be restored.” → clear | 134-141, 81-104 |
| Empty (configured) | “Ask me to create events or tasks” + example | static | 148-152 |
| Empty (no key) | “Connect an AI provider” + hint + “Open AI settings” | opens AI config dialog | 323-332 |
| User/assistant bubble | selectable text | — | 153-200 |
| Add Event chip (last reply only) | Add Event | parse → confirm dialog → create event + default reminders | 209-228, 669-746 |
| Add Task chip | Add Task | parse → confirm → create todo + default reminders | 229-248 |
| Schedule chip | Schedule | pick todo → occurrence → suggested slots → confirm → conflict re-check → create allocation | 249-259, 336-569 |
| Break Down chip | Break Down | suggested subtasks → tap creates a todo (calendar choice if >1) | 260-271, 571-667 |
| Message field | hint “Type a message...” | Enter sends | 288-303 |
| Send | a11y send (icon) | send; disabled while sending | 305-316 |

Chips are disabled while a write is in flight (213-216, 251-254) and only shown on the newest assistant message (202-203).

### 2.22 AI configuration dialog — `lib/ui/widgets/ai_config_dialog.dart`

| Control | Label (key) | Action | Source |
|---|---|---|---|
| Provider dropdown | Provider | presets OpenAI / Anthropic / DeepSeek / Google Gemini / Moonshot / Qwen / GLM / Ollama / LM Studio + Custom | 143-170; ai_provider 21-40 |
| Base URL | Base URL | editable **only for Custom** | 174-183 |
| API Key | API Key (masked `••••last4`) | edit; unchanged mask preserves original | 194-202, 285-288 |
| Detect Models | Detect Models / Detecting... | fetch `/models`; failure inline message | 206-234 |
| Model dropdown (after detection) | Select Model | choose | 235-255 |
| Model field (before detection) | Model, hint `gpt-4o-mini` | free text | 256-263 |
| Remove (when configured) | Remove | deletes config immediately | 268-278 |
| Cancel / Save | Cancel / Save | persist to secure storage | 279-301 |

### 2.23 About — `lib/ui/pages/about/about_page.dart`

| Control | Label (key) | Action | Source |
|---|---|---|---|
| Version | “Current version: vX (build)” | static | 144-149 |
| Check for Updates | Check for Updates | GitHub releases API; spinner; error text (rate-limited / timeout / generic) | 151-178, 44-99 |
| Update card | “New version available: tag” + release notes (8 lines) + View release | open URL externally | 181-233 |
| Up to date | Already up to date | static | 234-255 |
| Star on GitHub | Star on GitHub | open repo | 260-265 |
| Report an Issue | Report an Issue | → `/feedback` | 266-271 |
| Third-Party Licenses | Third-Party Licenses | Flutter `showLicensePage` | 272-281 |

### 2.24 Feedback — `lib/ui/pages/feedback/feedback_page.dart`

| Control | Label (key) | Action | Source |
|---|---|---|---|
| Text area | label/hint Feedback | 8 lines; copying state resets on edit | 73-83, 29-32 |
| Copy feedback | Copy feedback → Feedback copied to clipboard | clipboard + snackbar; disabled after copy until edited | 87-97 |
| Submit on GitHub | Submit on GitHub | opens prefilled new-issue URL externally | 99-104 |

### 2.25 System surfaces (not pages)

| Surface | Control | Effect | Source |
|---|---|---|---|
| Notification action | “Mark complete” (`mark_complete`) | completes todo; recurring → snackbar + push todo detail | notification_service 12-15; home 274-293 |
| Notification action | “Snooze” (`snooze`, Windows label “Snooze 1h”) | reschedules same reminder +1h | notification_service 12-15, 272, 337; home 294-311 |
| Notification body tap | — | handler `onNotificationTapped` is **never assigned** → no navigation | notification_service 135, 166 (§10 G4) |
| Android widget (Today) | Checkbox on allocation/todo rows | enqueue complete command → optimistic tick → drained on next snapshot flush | CalendarTodoWidgetProvider 132-263; widget_command 195-410 |
| Android widget (Today) | Quick add label | `dayspark://quick-add` | 266-277 |
| Android widget (Upcoming/Month) | none | read-only | UpcomingWidgetProvider 14; MonthDotsWidgetProvider |
| iOS widget | Checkbox button (Today timeline/allocation, todo actions) | `CompleteActionIntent` | CalendarTodoWidget.swift 465, 582 |
| iOS widget | Quick add link / whole-widget URL | `dayspark://quick-add` | 352, 539-542, 562, 708, 821 |
| Widget platforms | Android/iOS only (`supportsHomeWidget`) | macOS/Windows/Linux/web: no widget updates | platform_target 29-39 |

---

## 3. Creation flows

### 3.1 Global create entry points

| Entry | Visible where | Opens | Defaults | Source |
|---|---|---|---|---|
| Header create “New Task” | Action tab and Tasks tab (desktop header, mobile app bar) | `/todo/new` | first calendar; no due date | home 457, 581, 794-796 |
| Header create “New Event” | Calendar tab | `/event/new?start&end` | today: next whole hour (now.hour+1); other day: 09:00–10:00 | home 776-793 |
| Tasks quick-add | Above the todo list | inline create | dueDate = viewed day in day view, null in Inbox/All; priority 0 | home 905-907; quick_add 38-63 |
| Calendar blank slot | Day/week grid | `CalendarSlotSheet` | range = tapped time + 1h | calendar_section 390-403 |
| Slot → New Event | sheet | event form prefilled | exact slot range | slot_sheet 128-136 |
| Slot → Schedule Task | sheet | todo picker → allocation | chosen todo + occurrence | slot_sheet 137-142, 201-243 |
| Slot → New Task | sheet | todo form prefilled | execution draft = slot; deadline = slot date | slot_sheet 143-152; home 703-706; form 213-219 |
| Add subtask | Todo form | child todo | created on Save with `parentId` | form 1006-1127, 559-567 |
| AI chat “Add Task/Add Event” | AI chat | parse → confirm → create | calendar chosen if >1; default reminders | ai_chat 669-783 |
| AI chat “Break Down” | AI chat | subtask suggestions → create todo | priority 0, no due date | ai_chat 593-647 |
| Widget quick-add | Android/iOS widget | `/todo/new?source=widget` | full todo form (not inline); `source` unused | interactivity 9-17 |
| Create tag | Tags page + / empty TagChips | tag dialog | default grey `#6B7280` | tags_page 42-46; tag_chips 46-52 |
| Create calendar | Calendars page + empty state | calendar dialog | default blue `#2563EB` | calendars_page 41-45, 116 |
| AI config | Settings → AI / AI chat empty | config dialog | OpenAI + `gpt-4o-mini` | ai_config 78-83 |

There is **no FAB** and no global keyboard create shortcut.

### 3.2 Todo form field/validation matrix

| Field | Type | Required | Rule / message | Source |
|---|---|---|---|---|
| Title | text, autofocus | yes | empty → “Please enter a title” snackbar, no save | 353-358 |
| Deadline | date (+optional time) | no | clearable; time variant via clock popup | 762-788, 1129-1137 |
| Start date | via repeat sheet | no | if after deadline → “Starts at has to come before the deadline.” | 359-366 |
| Repeat | rule string | no | requires start or deadline; otherwise snackbar | 303-335; repeat_editor 105-109 |
| Executions | draft list | no | recurring requires occurrence choice | 805-810; execution 140-194 |
| Priority | 0/9/5/1 | no | default 0 | 173, 919-950 |
| Calendar | picker | effectively yes | none → “No calendar available. Add one in Settings.” | 370-378 |
| Description | multiline (4) | no | empty → null | 818-834, 380 |
| Tags | chips | no | diffed on save | 836-839, 516-522 |
| Reminders | draft list | no | diffed on save | 841-847, 524-535 |
| Attachments | draft list | no | bytes staged before transaction; missing source fails whole save | 385-395, 537-554 |
| Subtasks | draft list | no | empty summary ignored in dialog | 1095-1127 |

Save is one `RecordScope` transaction: create/update todo + allocations + tags + reminders + attachments + subtasks; failure rolls back the DB and discards staged files; attachments upload after commit (406-469).

### 3.3 Event form field/validation matrix

| Field | Type | Required | Rule / message | Source |
|---|---|---|---|---|
| Title | text | yes | “Please enter a title” | 182-187 |
| All day | switch | — | normalises to midnight only when newly turned on | 156-163, 679-686 |
| Start / End | date+time (date only if all-day) | yes | end ≤ start → “The end has to come after the start.”; Save disabled | 167, 188-193, 617-623 |
| Duration | computed | — | read-only | 701-714 |
| Repeat | rule | no | sheet | 715-720 |
| Calendar | picker | yes | no calendars → inline error + Retry; deleted calendar → “Calendar unavailable” | 199-216, 501-572 |
| Location | text | no | — | 726-740 |
| Description | text 4 lines | no | — | 742-758 |
| Tags / Reminders / Attachments | drafts | no | diffed on save | 760-779, 309-358 |

Same atomic transaction pattern as todo (241-291).

### 3.4 Occurrence selection

| Trigger | Sheet | Notes | Source |
|---|---|---|---|
| Completing a recurring todo | occurrence picker | completed parent → reopen without picker | todo_completion 43-61 |
| Scheduling a recurring todo (slot sheet, execution row, AI chat) | occurrence picker | `anchorDate` biases window | slot_sheet 224-237; execution 147-161 |
| Deleting one event occurrence | delete scope dialog (occurrence vs series) | series delete = soft delete; occurrence = exclusion | event_detail 515-554 |
| Notification “Mark complete” on recurring todo | pushes detail + snackbar “Select occurrence” | — | home 281-290 |

### 3.5 Parent / subtask creation

- Only path: Todo form “Add subtask” → staged `DraftSubtask` → on Save each new subtask becomes a child todo with `parentId` (1006-1093, 559-567). Subtask completion state toggles on save (568-579).
- `TodoFormPage.parentId` is honored at create (441) and the route parses `?parentId=` (router 226-229), but **no UI emits `parentId`** — the route parameter is unused in practice.

---

## 4. Editing flows

| Object / field | Inline detail? | Form? | Save semantics | Source |
|---|---|---|---|---|
| Todo title | yes | yes | detail: 600ms debounce; empty reverts; form: on Save | detail 174-201, 433-445; form 737-754 |
| Todo description | yes | yes | detail debounce; form on Save | detail 292-315; form 818-834 |
| Todo deadline | yes | yes | detail immediate; form draft | detail 253-265; form 762-788 |
| Todo repeat | yes | yes | detail immediate (with start/due as one spec); form draft | detail 271-283, 496-571; form 789-802 |
| Todo executions | yes | yes | detail immediate add/move/cancel; form draft diff | detail 284-286; form 805-810, 498-514 |
| Todo priority | yes | yes | detail immediate; form draft | detail 376-407; form 919-950 |
| Todo tags | yes | yes | detail immediate; form draft | detail 409-416; form 836-839 |
| Todo calendar | **no** | yes | only in form | form 952-1004 |
| Todo reminders | **no** | yes | only in form | form 841-847 |
| Todo attachments | yes | yes | detail immediate; form draft | detail 321; form 849-854 |
| Todo subtasks | **no** | yes | only in form | form 1006-1093 |
| Event title/description/location | yes | yes | detail debounce; form on Save | detail 159-309; form 633-758 |
| Event all-day | yes | yes | detail immediate | detail 220-227 |
| Event start/end | yes | yes | detail immediate with validation; form draft | detail 228-241, 456-508 |
| Event repeat | yes | yes | detail immediate | detail 251-256 |
| Event calendar | **read-only** | yes (unreachable edit route) | — | detail 257-258 |
| Event tags | yes | yes | immediate / draft | detail 311; form 760-764 |
| Event reminders | **no** | yes | only in form | form 766-772 |
| Event attachments | yes | yes | immediate / draft | detail 315; form 774-779 |
| Tag name/colour | — | dialog on Tags page | immediate | tags_page 137-232 |
| Calendar name/colour | — | dialog on Calendars page | immediate | calendars_page 109-194 |

Deadline vs execution time:
- Deadline = `dueDate` on the todo; date-only or date+time; shown in list/detail/calendar deadline lane.
- Execution = zero-or-more `task_allocations` rows (planned blocks), each optionally bound to a recurring occurrence; shown in detail/form and as dashed tiles on the calendar.
- They are independent: scheduling never changes `dueDate` (ai_chat 549 comment; execution section).

Recurrence editing model:
- Four one-tap frequencies or a custom `RRuleGenerator`; the row renders localized prose including interval, weekdays, count and until (repeat_editor 144-194).
- Clearing the repeat row is “stop repeating” with **no confirmation** (94-96).
- Imported legacy rules block date/schedule editing until the user answers “repeat from” (form 757-760, 861-917; detail 248-287).

---

## 5. List / calendar interactions

### 5.1 Gesture matrix

| Surface | Tap | Long-press | Checkbox | Swipe | Drag / reorder | Multi-select | Expand / collapse |
|---|---|---|---|---|---|---|---|
| Action rows | open object | — | complete (some rows) | — | — | — | — |
| Todo list row | open detail/pane | drag (mobile) | complete | — | yes, pending lists | no | — |
| Todo desktop row | open | — | complete | — | grip handle drag | no | — |
| Completed groups | open | — | complete (uncomplete) | — | — | no | yes (ExpansionTile) |
| Six-things fold | expand/collapse | — | — | — | — | — | yes |
| Calendar event tile | open | modify (mobile) | — | — | move + resize | no | — |
| Calendar allocation tile | open todo | modify (mobile) | — | — | move + resize | no | — |
| Calendar blank slot (day/week) | create | — | — | — | — | — | — |
| Calendar month day cell | none | none | — | — | — | — | — |
| Calendar paging | — | — | — | horizontal swipe (PageView) | — | — | — |
| Search result | open | — | none (read-only) | — | — | no | — |
| Trash row | — | — | — | **none by design** (comment 105-106) | — | no | — |
| AI message | select text | — | — | — | — | — | — |

Verified absent: `Dismissible`/`Slidable` anywhere in `lib/ui` (grep: 0 hits); no multi-select provider; no `onHorizontalDrag` custom handlers.

### 5.2 Calendar specifics

| Aspect | Behavior | Source |
|---|---|---|
| Views | Day / Week / Month; default Week; persisted | view_switcher 5; provider 24 |
| Paging | chevrons + kalender PageView; anchor derived from visible range (month: +7 days into range) | calendar_section 214-250, 367-381 |
| Blank-slot range | always 1 hour from tapped wall-clock time; kalender’s own drag-create disabled (`allowEventCreation:false`) | 88, 390-403 |
| Drag/resize | `allowResizing`/`allowRescheduling` default true (kalender); recurring and all-day rejected with snackbar; allocation failures revert | 421-450; kalender calendar_interaction 75-83 |
| Mobile modify gesture | kalender default long-press on mobile, tap-drag on desktop (app does not override) | kalender calendar_interaction 100-107 |
| Resize handles | imprecise (mobile) hides horizontal handles by default | kalender 119-127 |
| Overlap layout | side-by-side | 620-622 |
| Deadline lane | day/week only, max 96px, horizontally static per date | 597-612; lane 33-120 |
| Month cell marks | today circle, deadline red dot, holiday work/rest badge, solar term, dim adjacent months | marked_month_day_header 76-167 |
| Week start | Monday | date_strip 147; calendar_section 116-121 |
| Now line | warning colour, day/week | 526-529 |

### 5.3 Tasks list specifics

| Aspect | Behavior | Source |
|---|---|---|
| Six-things cap | only today + day view; 6 visible; “More (n)” fold; collapse row when expanded; numbers 1..n | home 1097-1163, 1199-1211 |
| Overdue grouping | day view today shows an Overdue section above today’s section | home 1060-1122 |
| Completed grouping | day: single Completed section (by completedAt == day); All/Inbox: ExpansionTile groups by completed date, today expanded | home 1165-1182, 1249-1311 |
| Hide completed | removes completed sections/groups everywhere in Tasks | home 948, 973-978, 1015-1017, 1077-1079 |
| Tag filter | OR across selected tags; filters pending and completed; applies to All/Inbox/Day | home 951-961, 1014, 1079 |
| Reorder | pending only; persists sortOrder; six-things indices map to full list | home 1189-1195, 1209-1247 |
| Date strip | day view only; month label + Today + 3 chips + week strip; All/Inbox drop the strip | date_strip 105-116 |
| Row width behavior | <600px row: date under title; ≥600px date right-aligned | list_tile 111-126, 249-270 |

---

## 6. Destructive / irreversible actions

| Action | Entry point | Confirmation | Undo | Reversibility | Source |
|---|---|---|---|---|---|
| Delete todo | Form trash icon; detail “Move to Trash” | Yes (“Are you sure you want to delete?”) | 5s snackbar Undo (restore) | soft delete → Trash | form 1142-1177; detail 586-627 |
| Delete event (non-recurring) | Form trash icon; detail button | Yes (“Delete "title"?") | 5s Undo | soft delete | form 385-424; detail 578-615 |
| Delete recurring event (series) | Detail button / form | Yes (series wording) | 5s Undo | soft delete | detail 555-601; form 392-396 |
| Delete one occurrence | Detail button on an occurrence | Scope dialog “Delete which?” → This occurrence only | **No undo** (snackbar text only) | adds exclusion | detail 515-554 |
| Cancel scheduled block | Execution row X | No | Undo snackbar | hard cancel + recreate | execution 231-259 |
| Stop repeat | Repeat row clear X | No | None (re-set repeat) | immediate write | repeat_editor 94-96 |
| Remove reminder | Reminder row X | No | None | draft or immediate delete | reminders 104-117, 223-230 |
| Remove attachment | Attachment row X | No | None | hard delete (file+row) | attachment_list 240-246, 340-342 |
| Remove tag from item | Tag chip deselect | No | Re-select | immediate | tag_chips 99-123 |
| Delete tag | Tags row delete icon | Yes (“Remove the tag … from every task?”) | None | hard delete + unlink all | tags_page 103-133 |
| Delete calendar (empty) | Calendars row delete | Yes (delete) | None | hard delete | calendars_page 246-253 |
| Delete calendar (with items) | Calendars row delete | Yes + choose Move them to / Delete them with the calendar | None | move or cascade delete | calendars_page 217-300 |
| Delete last calendar | — | Prevented: icon hidden; provider error → snackbar “Cannot delete the only calendar” | — | — | 77, 94-100, 287-300 |
| Restore trash item | Trash restore icon | No | — | undo of soft delete | trash 170-181 |
| Permanent delete | Trash delete icon | Yes (“This cannot be undone.”) | **None** | hard delete (+children for events) | trash 182-247 |
| Empty trash | Trash header | Yes (“Permanently delete all items in trash?”) | **None** | hard delete all | trash 249-278 |
| Clear AI chat | AI chat header | Yes (“It can't be restored.”) | **None** | in-memory clear | ai_chat 81-104 |
| Remove AI config | AI config dialog | No | Re-enter key | deletes key | ai_config 268-278 |
| Logout | Account section | Yes (“Your data stays… Syncing stops”) | — | re-login | account 270-293 |
| Discard form edits | Back/Escape with dirty form | Yes (“Discard changes?”) | — | drops draft | form 651-691; event 360-383 |

Notes:
- Soft-deleted todos/events are visible in Trash with restore + permanent delete (trash_page 23-27).
- Event permanent delete uses `hardDeleteEventWithChildrenProvider` (trash 155); todo uses `permanentDeleteTodoProvider` (125).
- Attachment delete from a form is staged (draft), and only applied on Save (form 537-554).

---

## 7. Global / system surfaces

### 7.1 Settings map

| Group | Controls | Persistence | Source |
|---|---|---|---|
| Appearance | Theme (3), Accent (5), Language (3), Startup view (3) | SharedPreferences | appearance 52-201; theme/locale/default_tab providers |
| Manage Calendars (mobile only) | row → `/calendars` | — | settings_page 59-67 |
| Tasks | Six Things, Hide completed | SharedPreferences | todos_section 17-31 |
| Data | ICS import, ICS export, full backup (export/merge) | files | import_export 50-66 |
| Account | login/register/logout, devices, sync now, status | server + local | account 123-401 |
| Advanced Features | AI enable, tutorial, AI config | SharedPreferences + secure storage | ai_section 20-65 |
| Notifications | alarm switch / permission / exact alarm | platform | notifications_section 36-89 |
| About | row → `/about` | — | about_section 15-20 |

### 7.2 Theme / language

- Theme mode System/Light/Dark; accent Blue/Green/Orange/Purple/Pink (light+dark pairs); no free colour picker (theme_provider 8-46).
- Language System/Chinese/English; widget snapshot rebuilds on language/theme change (home 226-236).

### 7.3 Account / sync

- Login and registration share three fields; both call the configured server URL.
- Logged-in status line shows phase (Idle/Syncing/Pulling/Sync error), last sync relative time, and rejected operation codes (account 374-389).
- Device list is read-only (name + last active) (320-372).
- No in-app “server offline” banner; failures appear in the status line and operation snackbars.

### 7.4 AI

- Two entry points: AI chat page and per-form “AI parse”.
- AI chat has no persistence layer (in-memory `StateNotifier`; `clear()` empties) — conversation lost on restart (`ai_provider.dart:213-270`).
- Form AI parse only fills empty fields (todo) or overwrites (event) and announces filled fields in a snackbar (todo form 604-637).
- All AI writes from chat go through an explicit confirmation dialog listing the parsed values (ai_chat 798-847).

### 7.5 Backup / import / export

| Action | Output / input | Notes | Source |
|---|---|---|---|
| ICS import | pick `.ics`, choose target calendar | counts events/tasks/failed | import_export 155-221 |
| ICS export | all calendars, one `.ics` | refuses when no calendar | 225-255 |
| Backup export | `.zip` (DB + attachments) | share sheet or browser download | 98-125 |
| Backup merge | `.zip` | upsert, nothing removed | 129-150 |

### 7.6 Notifications & permissions

- Android: notification permission requested at init; channel “Reminders” high importance (notification_service 115-130).
- iOS/macOS: permission requested at init; macOS has an explicit “Notification permission” row to re-ask (notifications_section 60-74).
- Android exact alarms: row shown only when `canScheduleExactAlarms()` is false (76-89).
- Notification actions: Mark complete, Snooze (+1h) (notification_service 12-15; home 267-312).
- Web/Windows/Linux: notification settings rows hidden (`hasNotificationSettings`, settings_page 86-90) though Windows/Linux init exists.

### 7.7 Widgets

- Three widgets on Android and iOS: Today, Upcoming, Month dots (service 115-126).
- Today widget: timeline rows, action rows with checkbox completion, pending count, quick-add; Upcoming/Month are read-only (iOS 444-562; Android provider).
- Quick-add only on the primary (Today) widget (UpcomingWidgetProvider 14).
- Widgets are driven by a v3 snapshot; native never writes the snapshot; completions go through an independent command queue (widget_command 29-116; service 145-217).
- Widget platforms: Android/iOS only; macOS widget folder exists but `supportsHomeWidget` is false there (platform_target 29-39).

### 7.8 Deep links

- Scheme `dayspark`; only `dayspark://quick-add` (and `dayspark:///quick-add`) is translated (interactivity 7-17).
- Android manifest filter for scheme+host (manifest 35-48); iOS/macOS `CFBundleURLSchemes` (plists). Windows/Linux/web have no registration.

---

## 8. Platform differences

| Aspect | Desktop (≥1000) | Mobile (<1000) | Source |
|---|---|---|---|
| Navigation chrome | 232px persistent rail | 3-tab `NavigationBar` + AppBar | workspace_scaffold 24; home 462-481; sidebar 30 |
| Header | in-content 48px header, no AppBar | AppBar with search/AI/settings/create | workspace_page 62-105; home 408-460 |
| Create placement | page header, right of title | AppBar action | home 581, 457 |
| Master-detail | ≥1180: list + 400px pane; 1000-1179: single column | always full-page push | home 385-404; workspace_navigation 72-75 |
| Todo reorder | dedicated grip handle, immediate drag | long-press whole row drag | home 1211-1246 |
| Calendar event modify | tap-drag/resize | long-press then drag/resize | kalender interaction defaults |
| Time picker | Material `showTimePicker` | Cupertino wheel + keyboard entry sheet | wheel_time_picker 13-21 |
| Sidebar sub-views | Today/Inbox/All as indented rail rows | chips + week strip inside Tasks | sidebar 82-104; date_strip 79-116 |
| Manage Tags / Trash | rail | icons in Tasks toolbar | sidebar 118-129; home 896-897 |
| Manage Calendars | rail | Settings row | settings_page 59-67 |
| Attachments open | share sheet (native) | share sheet (native); web downloads | attachment_list 313-332 |
| Backup / ICS export | file + share sheet | file + share sheet | import_export 105-120, 238-250 |
| Widgets | none (macOS folder inert) | Android/iOS | platform_target 29-39 |
| Notifications settings | macOS permission row | Android alarm+exact alarm; iOS alarm | notifications_section 36-89 |
| Deep links | macOS registered | Android/iOS registered | plists; manifest |
| Keyboard | Escape in the two form pages only | — | form 682-691; event 580-594 |
| Touch targets | rail rows 32px (mouse) | 48px rows/controls | sidebar 408; list_tile 156-158 |
| Web limitations | — | no notifications settings, no widgets, no deep links, browser downloads | settings_page 86-90; platform_target; attachment_list 313-320 |

Other width-driven behaviors:
- Todo row date placement switches at **600px** (row-local `LayoutBuilder`), independent of the 1000px shell breakpoint (`todo_list_tile.dart:111-126`).
- Content widths: forms/settings 720; search full; AI chat 860; about/feedback 640.

---

## 9. States

### 9.1 Empty states (exact copy)

| Surface | Title | Hint / action | Source |
|---|---|---|---|
| Action tab | “Nothing needs you right now” | “Upcoming events and deadlines will show up here on the day.” | action_section 293-323; arb 645-646 |
| Tasks list | “No pending tasks” | — | home 1313-1335; arb 103 |
| Calendar day/week | “Tap an empty slot to create your first event” | non-interactive hint | calendar_section 646-676; arb 484 |
| Search (no query) | “Search your calendar” | “Find events and tasks by title or notes.” + “From your inbox” top-3 | search 138-144, 275-301; arb 511/515/519 |
| Search (no results) | “No results” | — | search 192-200; arb 105 |
| Tags | “No tags yet” | “Tags group your tasks so you can filter by area.” + “Create a tag” | tags_page 67-77; arb 85/547/543 |
| Calendars | “No calendar available. Add one in Settings.” | “Create” | calendars_page 66-75; arb 107 |
| Trash | “Trash is empty” | “Deleted events and tasks wait here until you remove them.” + “Back to Tasks” | trash_page 48-63; arb 255/523/527 |
| AI chat (configured) | “Ask me to create events or tasks” | “e.g. "Meeting with John tomorrow 3pm"” | ai_chat 148-152; arb 92-93 |
| AI chat (no key) | “Connect an AI provider” | hint + “Open AI settings” | ai_chat 323-332; arb 531/535/539 |
| Slot sheet todo picker | “No pending tasks available to schedule” | — | slot_sheet 180-191; arb 573 |
| Occurrence picker | “No occurrences are available in the next 90 days.” | — | picker 166-171; arb 11 |
| Reminders | “No reminders set” | — | reminders 151-159; arb 368 |
| Attachments | “No attachments” | — | attachment_list 188-191; arb 220 |
| Subtasks | “No subtasks” | — | form 1026-1032; arb 373 |
| Connected devices | “No devices have reported in yet.” | — | account 332-334; arb 552 |
| Widget (today) | “No events today” / “All done!” | — | service 581-582; arb 122-123 |
| Deleted-object detail | “This item is no longer here.” | — | todo detail 138-155; event detail 115-132; arb 789 |

### 9.2 Loading states

| Surface | Indicator | Source |
|---|---|---|
| Action projection | centered spinner | action_section 43-44 |
| Tasks list | centered spinner | home 965-966, 1010-1011, 1052-1053 |
| Calendar events/allocations | centered spinner per async layer | home 625-631 |
| Search | 2px linear progress while loading; keeps previous results | search 147-150, 33-36 |
| Search first load | centered spinner | search 189-191 |
| Tags/Calendars/Trash/Settings account | centered spinner | tags 49; calendars 48; trash 41-46; account 81-90 |
| Occurrence picker | spinner in dialog | picker 146-153 |
| AI send / AI parse / detect models / save | inline spinners, control disabled | ai_chat 305-316; form 708-716; ai_config 210-221; PageSaveButton 175-181 |
| Attachment open | row spinner | attachment_list 227-233 |
| About update check | button spinner | about 155-167 |

### 9.3 Error states

| Surface | Copy | Recovery | Source |
|---|---|---|---|
| Action projection | “Couldn't load. Try again.” (actionFailedRetry) | no retry button | action_section 45-59 |
| Tasks/Calendar | “Something went wrong. Please try again.” (error) | tab switch | home 628-630, 967, 1012, 1054 |
| Search | “Search failed. Please try again.” | Retry button | search 152-175; arb 691 |
| Tags / Calendars | actionFailedRetry | Retry button | tags 50-65; calendars 49-64 |
| Trash | error text | none | trash 43-46 |
| Account load | “Couldn't load your account.” | Retry | account 91-117 |
| Device list | “Couldn't load the device list” | close/reopen | account 355 |
| AI form parse | “The assistant couldn't finish that” | dismiss | form 638-643; arb 187 |
| AI chat action | “Couldn't do that” / “Couldn't create the task” | dismiss | ai_chat 787-790; arb 219/216 |
| About update | rate-limited / timeout / generic | re-check | about 88-99 |
| Detail update failure | actionFailedRetry snackbar | retry edit | detail 470-474, 629-632 |
| Calendar drag failure | error snackbar + snap back | retry | calendar_section 140-184 |
| Scheduling failure | “Couldn't schedule that” | dismiss | home 729-740; execution 187-193 |
| Save failure | actionFailedRetry snackbar, form stays open | retry | form 472-478; event 293-299 |
| Tag/calendar save | inline error text, dialog stays | retry | tags 217-224; calendars 178-185 |

### 9.4 Offline / sync / conflict

| State | Where it appears | Copy / behavior | Source |
|---|---|---|---|
| Sync phase error | Account status line | “Sync error · Last sync …” | account 374-389 |
| Rejected ops | Account status line | “Rejected: codes” | 386-388 |
| Attachment not uploaded | Attachment row subtitle | “Not uploaded” (+ size) | attachment_list 255-262 |
| Schedule time conflict | AI chat after confirm | error snackbar “The selected time slot is now occupied…” and no write | ai_chat 532-547 |
| Offline writes | no banner; local-first | writes succeed locally; sync catches up | sync_client_provider 115-125 |
| Widget command transient failure | silently retained for retry | no UI | widget_command 400-407 |

### 9.5 Disabled / permission-denied / hidden

| Control | Condition | Source |
|---|---|---|
| Save (form) | while saving (spinner, disabled) | workspace_page 161-181; form 719 |
| Save (event form) | invalid time range | event form 617-623 |
| AI parse | while parsing | form 708-716 |
| AI chat quick-action chips | while a write is in flight | ai_chat 213-216 |
| Attachment delete | while download in flight | attachment_list 244 |
| Calendar row in todo form | only one calendar → tap null | form 967-969 |
| Calendar row in event form | one calendar and not dangling → tap null | event form 535-537 |
| AI rail/icon | feature flag false | sidebar 130; home 433-437 |
| AI config row | feature flag false | ai_section 40-47 |
| Notification settings group | web / Windows / Linux | settings_page 86-90 |
| Alarm switch | not Android/iOS | notifications_section 36-38 |
| Exact alarm row | granted or not Android | notifications_section 76-77 |
| Calendar delete | only one calendar | calendars_page 77 |
| Empty Trash | no items | trash_page 33-40 |
| Add execution | todo deleted/completed/cancelled | execution 104-109, 132-138 |
| Mark complete | read-only list surfaces (search) omit `onToggle` | list_tile 149-183 |
| Manage-tags/trash icons | mobile only | home 896-897 (inside non-desktop branch) |

---

## 10. Gaps, dead entries, and conflicting entries

**Dead / unreachable**

- **G1 — `/event/edit` is unreachable.** Registered (`app_router.dart:206-221`) but no code calls it (grep over `lib/`: only the route definition). Event editing happens exclusively through the inline detail pane; the form’s edit branch is dead UI. Consequence: event **calendar** cannot be changed after creation, and reminders cannot be edited at all (detail has no reminders section).
- **G2 — `?parentId=` on `/todo/new` has no emitter.** Route parses it (226-229) and the form uses it (441), but no UI passes it; parent/subtask creation exists only through the form’s Subtask section.
- **G3 — `?source=widget` is accepted but never read.** Router forwards `source` (241); `TodoFormPage.source` is stored (151-158) and never used. Widget quick-add therefore lands on the **full form**, not an inline quick-add, despite the `quickAddLocation` name.
- **G4 — Notification body taps do nothing.** `NotificationService.onNotificationTapped` (135) is never assigned; only `onNotificationAction` is wired (home 152-157). Tapping a notification without choosing an action has no navigation.
- **G5 — Inline detail is not fully “editable where read.”** Todo detail lacks reminders, subtasks, calendar; event detail lacks reminders and calendar editing (see §2.6/2.8). Reminders exist only inside forms, and the event edit form is unreachable (G1).
- **G6 — Unused `WorkspacePage` capabilities.** `footer`, `scrollableHeader`, `onAnchorChanged` (`calendar_section.dart:38`) are never supplied by any caller.
- **G7 — `FeatureFlag.sync` is set/cleared by login/logout (account_provider 140,157) but never read** by any UI or engine gate.

**Conflicting / duplicated entries**

- **G8 — Same action, two entries:** Six Things toggle in Settings → Tasks (`todos_section.dart:17-24`) and in the Tasks toolbar/date strip (`date_strip.dart:95-101`); both write the same provider (no conflict, but two places to discover it).
- **G9 — Create tag** from Tags page header (`tags_page.dart:42-46`) and from empty `TagChips` “Create Tag” (`tag_chips.dart:46-52`).
- **G10 — Search** from desktop rail (`sidebar:60`) and mobile app bar (`home:423-432`).
- **G11 — AI config** from Settings → Advanced (`ai_section:40-47`) and from AI chat empty state (`ai_chat:327-331`).
- **G12 — Two detail presentations on wide screens:** list tap opens the right pane (`home:513-529`) while search results always `push('/todo/detail')` / `/event/detail` (`search_page:216-220, 251-254, 297`). The same object can therefore open full-page or in-pane depending on entry.
- **G13 — Selection persists across destinations.** `workspaceSelectionProvider` is only cleared by the pane’s close or delete (`home:506-508, 490-502`); switching Action/Calendar/Tasks keeps the pane visible with the previously selected object.
- **G14 — Delete-occurrence has no Undo** while every other delete does (`event_detail:543-553` vs 608-613).
- **G15 — Trash restore snackbar reuses the action label as the message** (“Restore”) (`trash_page:174-179`), so it reads as a second button.
- **G16 — Month view is not an interaction surface.** No blank-cell creation and no month-level tap callback (`calendar_section:619`; kalender `month_body.dart` has no tap handler). Users can see deadline dots/holidays but cannot open or create from a month cell. Only event/allocation tiles render through the shared tile builder.
- **G17 — Deep-link coverage is one destination only.** No `dayspark://todo/<id>`, `event/<id>`, `search`, etc.; `widgetDeepLinkLocation` returns null for everything else (`interactivity:11-17`).
- **G18 — Widget/notification features are Android/iOS-only** although macOS ships a widget extension folder and macOS/Linux/Windows initialize notifications; the Settings gate hides notification rows on Windows/Linux (`settings_page:86-90`) and `supportsHomeWidget` excludes macOS (`platform_target:29-39`).
- **G19 — AI conversation is ephemeral** (in-memory only, `ai_provider:213-270`); closing the app silently discards it, and “Clear chat” is the only state management offered.
- **G20 — Quick-add with no calendar is a dead end:** snackbar “No calendar available. Add one in Settings.” with no action button and no navigation (`todo_quick_add:47-51`).
- **G21 — Week/day blank-slot creation is always 1 hour** even when the visual slot granularity is 30 minutes (`calendar_section:400-402`); the created event can silently overlap the next slot.
- **G22 — Reorder is limited to pending lists**; completed groups, overdue rows, and calendar items cannot be reordered, and there is no drag between dates/views.
- **G23 — No multi-select, no bulk operations** anywhere (trash included).
- **G24 — No keyboard shortcut coverage** beyond Escape in the two forms (no Cmd/Ctrl+K, no delete shortcut, no arrow navigation).
- **G25 — Sidebar row height is 32px** (`sidebar:408`) while the project rule is ≥48px touch targets; acceptable only because the rail never renders under 1000px, but it is a documented deviation.

**Model/UX ambiguities a prototype must resolve**

- Six-things cap applies only when the selected day is *today*; a user who switches to yesterday sees the full list with no visible explanation.
- `Action` “To do today” merges recurring occurrences and deadline todos without a visual distinction beyond the meta line (`action_section:121-131`).
- Calendar deadline lane silently excludes recurring todos (`home:615-623`), so a recurring task with a deadline never appears in the lane or month dot.
- Completed recurring occurrences appear under “Earlier today” mixed with ended events/allocations (`action_section:150-163`).
- Event color is always the calendar color; there is no per-event color control (event tile 25-26; home 636-645).

---

## Verification notes

- Route callers enumerated by `rg "context\.(push|go|pop)" lib` — only the call sites cited above exist; `/event/edit` has zero.
- Absence checks: `Dismissible|Slidable` → 0 hits in `lib/ui`; `LogicalKeyboardKey|CallbackShortcuts` → only the two form pages; `parentId=` → 0 hits; `onNotificationTapped` assignment → 0 hits.
- Platform gates read from `defaultTargetPlatform`/`kIsWeb` via `lib/core/utils/platform_target.dart` (the only file allowed to touch `Platform.*`).
- Kalender behavior (drag defaults, mobile long-press modify gesture, month body having no tap handler) verified in `~/.pub-cache/hosted/pub.dev/kalender-0.17.0`.
