# DaySpark — App Surface & Interaction Inventory (v0.34.0)

Read-only inventory of every user-reachable surface in the Flutter app at v0.34.0, for building an interactive prototype.
Every claim cites `file:line`. All paths are relative to `/Users/chang/Desktop/Code/dayspark-g1` (the v0.34.0 worktree).

- Snapshot: branch `g1/android-widget-touch` @ `7390987`, `pubspec.yaml` `0.34.0+34`, 2026-11-16.
- Scope: `lib/ui/**`, `lib/core/router/app_router.dart`, `lib/infrastructure/platform/**` entry points, `lib/l10n/app_en.arb`.
- Not in scope: server MCP tools, CLI, sync protocol internals (only their UI surfaces), AI provider protocol.
- Terminology is aligned with `docs/CORE_UX_SPEC.md`: 今天 (Today), 未安排 (Unplanned), 全部待办 (All Tasks), 计划执行 (planned execution / TaskAllocation), 截止 (deadline), 所属日历 (calendar), 同步 (Sync). `行动 / Action`, `收件箱 / Inbox`, `六件事 / Six Things` are **retired from the product UI** (see §11).

Conventions:
- **Label** = exact English copy from `lib/l10n/app_en.arb` with its key in parentheses.
- “→” = navigates to.
- “soft delete” = `deletedAt` set (recoverable from Trash); “hard delete” = row removed.
- Desktop = window width ≥ 1000 (`kWorkspaceBreakpoint`, `lib/ui/shell/workspace_scaffold.dart:14`); master-detail = width ≥ 1180 (`kMasterDetailBreakpoint`, `lib/ui/shell/workspace_navigation.dart:91`).
- “Todo” = task row; “Event” = calendar event; “instance” = one occurrence of a recurring item.

---

## 1. Route / entry table

Router: `lib/core/router/app_router.dart`. Every route uses `NoTransitionPage` (`_pageTransition`, 30-32) — no page animations. `/quick-add` alone uses a non-opaque, zero-duration `CustomTransitionPage` (`_overlayPage`, 39-47) so it floats above the current page. Deep links are translated to paths before matching (188-194).

| Path | name | Params / extra | How the user reaches it | Page built | Source |
|---|---|---|---|---|---|
| `/` | `home` | query `tab` 0\|1\|2, `date`, `view` | App launch (175-178); workspace tab change; widget deep links `/?tab=0/1/2`; error page “Return to Home” | `HomePage(initialTab, initialDate, initialTodoView)` | 233-248 |
| `/quick-add` | `quickAdd` | query `date` (capture context only) | `SparkTopBar` Quick add on desktop pushed pages; Android/iOS widget deep link; `dayspark://quick-add` | `QuickAddPage(contextDate)` | 249-264 |
| `/settings` | `settings` | — | `SparkTopBar` avatar; Today header gear; Todos header gear; dead sidebar | `SettingsPage` | 268-273 |
| `/event/new` | `eventCreate` | query `start`,`end` epoch ms (defaults now / now+1h), `date` | Home calendar day “+ Event”; slot sheet “New Event”; widget deep link | `EventFormPage` | 274-319 |
| `/event/detail` | `eventDetail` | `extra: CalendaEventAdapter`, or query `id` loader | Home calendar event tile; search event row; widget deep link | `EventDetailPage` | 320-339 |
| `/event/edit` | `eventEdit` | `extra` required | Event detail footer Edit | `EventFormPage(event:)` | 340-355 |
| `/todo/new` | `todoCreate` | query `parentId`, `source`, `due`, `start`, `end`, `summary` | Only the composer ellipsis “Open full form” (356-389; caller `a2_composer.dart:81-82`) | `TodoFormPage` | 356-389 |
| `/todo/detail` | `todoDetail` | `extra: Todo`, or query `id` loader | Today row tap; Todos row tap; search row tap; widget deep link | `TodoDetailPage` | 390-409 |
| `/todo/edit` | `todoEdit` | `extra: Todo` | Todo detail footer Edit; legacy-recurrence notice | `TodoFormPage(todo:)` | 410-425 |
| `/search` | `search` | — | Ctrl/Cmd K; `SparkTopBar` search; Home desktop/mobile search; dead sidebar | `SearchPage` | 426-431 |
| `/tags` | `tags` | — | Settings Data → Tags; `TagChips` “Create Tag” when empty | `TagsPage` | 432-436 |
| `/calendars` | `calendars` | — | Settings Calendar → Manage Calendars; dead sidebar | `CalendarsPage` | 437-442 |
| `/ai-chat` | `aiChat` | — | Settings AI Assistant → Open assistant | `AiChatPage` | 443-448 |
| `/about` | `about` | — | Settings About row | `AboutPage` | 449-453 |
| `/trash` | `trash` | — | Settings Data → Trash; dead sidebar | `TrashPage` | 454-458 |
| `/feedback` | `feedback` | — | About → “Report an Issue” | `FeedbackPage` | 459-464 |
| unknown path | — | — | Manual URL | “Page not found…” + “Return to Home” | 195-231 |

Shell structure:
- `/` is **outside** the `ShellRoute`; `HomePage` renders its own bars (`home_page.dart:463-523`).
- Every pushed route is inside `ShellRoute(builder: WorkspaceScaffold)` (265-267), so `SparkTopBar` persists above the swapped content (`workspace_scaffold.dart:49-61`).
- `WorkspacePage` supplies pushed-page chrome: mobile 54px `DsTopBar`; desktop 48px `DsMainBar` with back only when `canPop` (`workspace_page.dart:52-132`).
- Detail routes created from list rows pass an `extra` object; the query-`id` loader exists for notifications/widgets and shows `_DetailLoadingPage` until the live row arrives (110-173).

---

## 2. Navigation shell

### 2.1 WorkspaceScaffold — `lib/ui/shell/workspace_scaffold.dart`

| Control | Label (key) | Action | Destination | Source |
|---|---|---|---|---|
| Breakpoint | — | `isWorkspaceLayout` = width ≥ 1000 | desktop chrome vs mobile | 14-17 |
| Desktop top bar | — | renders `SparkTopBar` above the route child | all pushed routes | 49-61 |
| Keyboard shortcut | — | Ctrl/Cmd K | `/search` | 38-48 |

Comment at 19-23 states “There is no sidebar” — confirmed; `WorkspaceSidebar` is dead code (§2.6).

### 2.2 SparkTopBar (pushed routes, desktop) — `lib/ui/shell/spark_top_bar.dart`

Height 56 (31). Responsive thresholds: roomy ≥ 1180, sync badge ≥ 1120, narrow < 940, tight < 860 (87-90).

| Control | Label (key) | Action | Destination | Source |
|---|---|---|---|---|
| Brand | app name (`appName`) | — | static | 98 |
| Date nav (roomy) | weekday + date | previous / next day | sets `viewedDateProvider` | 102-112 |
| Now / Next up (roomy + today) | Now (`sectionNow`) / Upcoming (`sectionUpcoming`) | scroll/jump | in-page | 113-120 |
| Search | Search (`search`) | go | `/search` | 125-132 |
| Todos destination | Tasks (`todos`) | sets Todos view | `/?tab=2` | 134-141 |
| View segment | Day (`day`) / Week (`week`) / Month (`month`) | Day → Action tab (`/?tab=0`); Week/Month → Calendar tab (`/?tab=1`) | 143-146, 206-224 |
| Quick add | Quick add (`quickAdd`) | go overlay | `/quick-add` | 148-151 |
| Sync badge | Sync (`sync`); error tooltip | opens sync status/settings | `/settings` | 152-155, 613-620 |
| Avatar | Settings (`settings`) | go | `/settings` | 157-163 |
| Back/today chip | Today (`today`) | clears date, returns home | `_goToday` pops to `/` tab 0 | 179-187 |

Known inconsistency: there is no labelled “Calendar” destination on this bar — Week/Month of the Day/Week/Month segment are the only calendar entry, and Day maps to the retired Action tab (§12, D5/D6).

### 2.3 Home desktop bar — `lib/ui/pages/home/home_page.dart`

Home does **not** use `SparkTopBar`. It renders its own `_DesktopBar` (472-483, 1097-1256).

| Control | Label (key) | Action | Destination / effect | Source |
|---|---|---|---|---|
| Nav destinations | Today (`today`) / Tasks (`todos`) / Calendar (`calendar`) | set Home tab | 0 / 2 / 1 | 1116-1120 |
| Nav labels below 1180 | icons only | — | — | 1131 |
| Date readout + prev/next | date text | browse date ±1 day | shared `viewedDateProvider`; **no “Today” reset button** | 1174-1201 |
| Clock | — | static | — | 1203 |
| Capture | Capture (`captureQuickAddLabel`) | opens `showA2Composer` (Todo only) | composer sheet | 1222, 476-481 |
| Search | Search (`search`) | go | `/search` | 1224-1232 |

Differences vs `SparkTopBar`: Home has no sync badge, no avatar/Settings entry, no tap-to-today, no date picker, and nav order is Today/Tasks/Calendar; the mobile dock is Today/Calendar/Tasks (1404-1408) and the spec order is Today/Calendar/Todo (§12 D5).

### 2.4 Home mobile chrome — `lib/ui/pages/home/home_page.dart`

| Control | Label (key) | Action | Destination | Source |
|---|---|---|---|---|
| Bottom dock | Today / Calendar / Tasks | set tab | 0/1/2 | 1404-1408 |
| Dock height | 56px (touch safe) | — | — | 1415 |
| Keyboard behavior | — | dock hidden while keyboard open | — | 505-523 |
| Search | Search (`search`) | go | `/search` | 880-883, 1228 |

### 2.5 WorkspacePage (pushed pages) — `lib/ui/shell/workspace_page.dart`

| Control | Label (key) | Action | Source |
|---|---|---|---|
| Mobile top bar | title, back, optional actions | `Navigator.maybePop` (PopScope-aware) | 52-96, 136-145 |
| Desktop main bar | title + actions | back only when `canPop` | 99-132 |
| Save button | Save (`save`) with loading/disabled state | page-defined | 149-170 |

### 2.6 Dead sidebar — `lib/ui/shell/workspace_sidebar.dart`

Class `WorkspaceSidebar` is never imported; only self-references remain (21-22). It still contains a full v0.29-era map: width 236 / compact 64 below 980 (26-33); Today/Calendar/Tasks (78-104); Unplanned (`l.inbox`) and All Tasks (105-123); calendar/tag filter rows (128-172); Manage Calendars/Trash (173-187); Settings pinned bottom (191-203). Do not prototype it — it is not rendered.

### 2.7 Deep links — `lib/infrastructure/platform/home_widget_interactivity.dart`

| Entry | Maps to | Source |
|---|---|---|
| scheme `dayspark` | parsed and redirected | 7 |
| `dayspark://quick-add`, `/quick-add`, `?date=` | `/quick-add` | 21-31 |
| legacy `today/action/home/calendar/todos` | `/?tab=…` | 33-55 |
| legacy `new-todo` | **`/quick-add`** (no longer `/todo/new`) | 56-58 |
| legacy `new-event` | `/event/new` | 59-64 |
| legacy `todo` / `event` | detail route with id | 65-72 |
| `_todoView` | still accepts `inbox\|all\|today` as query values | 74-75 |

Constants `quickAddLocation`, today/todos/calendar locations at 9-12.

---

## 3. Today page — `lib/ui/pages/today/today_page.dart`

Purpose comment at 26-29: Today is clock-only; the only creation entry is the capture row, which writes a bare Todo. No Event creation and no date browsing here.

### 3.1 Header and capture

| Control | Label (key) | Action | Source |
|---|---|---|---|
| Header title | Today (`today`) | static | 608-625 |
| Search | Search (`search`) | `/search` | 618 |
| Settings | Settings (`settings`) | `/settings` | 623 |
| Capture field | Capture · Enter files it unplanned (`capturePlaceholder`) | Enter creates Todo | 670-684 |
| Capture result | Added to Unplanned · keep typing (`captureAddedToast`) | stays focused | 160-170 |
| Toast undo | Undo (`undo`) + occurrence title, 5s window | soft-deletes the created Todo | 184-204, 295-325, 364-393 |
| Completion | row complete | refresh projection + snackbar | 250-293 |
| Retry strip | Retry (`retry`) | invalidates projection providers | 395-408, 501-527 |

Capture writes into `calendars.first` with no due date and no planned time (119-158, 124-134) — calendar context is implicit (§12 D24).

### 3.2 Section order

| Section | Label (key) | Rows | Row cap | Source |
|---|---|---|---|---|
| Now | Now (`sectionNow`) | timeline events, allocations, deadlines, instances | all | 888-917 |
| Upcoming | Upcoming (`sectionUpcoming`) | next blocks | 3 + expand | 919-989 |
| Due today | Due today (`sectionDueToday`) | deadline rows | all | 991-1014 |
| Overdue | Overdue (`sectionOverdueLabel`) | past deadline | all | 1016-1067 |
| Missed | Missed (`missed`, `earlierMissed`) | missed instances | 3 + expand | 1069-1119 |
| Earlier today | Earlier today (`actionEarlierToday`) | earlier blocks | all | 1121-1139 |
| Completed Today | Completed Today (`completedTodaySection`) | folded sink | all | 1141-1168 |

Mobile unplanned preview: rows with `dueDate == null`, 3 shown + “show more” (540-555); section head is `l.inbox` = **Unplanned** (569-599). Empty state at 637-642.

### 3.3 Desktop shelf (≥1000)

Max content 1240; a 320px right shelf (719-817). Shelf preview 3 items + show-all row; empty copy 722-742. The shelf cannot expand in place — the chevron navigates to the Todos Unplanned view (`today_page.dart:788-793`), unlike mobile's inline show-more (595-598).

### 3.4 Row types

| Row | Contents | Interaction | Source |
|---|---|---|---|
| Timeline event / allocation / deadline / instance | time, title, calendar dot, meta | tap → detail; recurring gets scope picker on complete | 1279-1347 |
| Block | title + meta + `Schedule` chip | tap → event/todo detail | 1349-1502 |
| Unplanned row | title, “Just added”/“Unplanned” + calendar, Schedule icon | tap → detail; Schedule → composer in schedule mode | 1548-1589 |
| Missed instance | missed badge | tap → detail | 1599-1625 |
| Completed todo/instance | strikethrough | tap → detail | 1627-1659 |
| Series row | repeat glyph | tap → series detail | 1661-1672 |
| Entry row | generic list row | tap | 1676-1711 |
| “Show all” | Show all (`showAll`) | expand | 1724-1755 |
| “More” | More (`more`) | expand | 1757-1788 |

---

## 4. Todos page — `lib/ui/pages/todo/a2_todo_page.dart`

Three internal views share one page. State fields at 36-65; 5s undo windows at 71-87; completion snackbar with Undo + invalidate at 131-186.

### 4.1 Header and mode switch

| Control | Label (key) | Action | Source |
|---|---|---|---|
| Titles | Unplanned (`inbox`) / All Tasks (`allTasks`) / By date (`byDateTitle`) | static | 430-450 |
| Settings | Settings (`settings`) | `/settings` | 451-458 |
| Mode switch (title tap) | Switch view (`todosSwitchMode`) | opens mode chooser | 468-515 |
| Mode chooser | Unplanned / All Tasks / By date | desktop `DsDialog`, mobile bottom sheet | 551-656 |
| Mode rows | each with description | set `TodosView` | 566-593 |
| Date strip | appears only in By date | tap date → month/year picker; “Today” chip when off-today | 332-334, 703-804 (Today chip 784-789) |

`byDateContext` = “Todos · shares its date with Calendar” (`app_en.arb`).

### 4.2 Bodies

| View | Sections | Source |
|---|---|---|
| Unplanned | “With a deadline · unplanned” (`withDueUnplannedSection`), “No deadline” (`noDueSection`) | 890-943 |
| All Tasks | Due today / Past due / Later / No deadline; completed sink | 964-1050 |
| By date | Planned (`planned`) / Deadline (`deadline`) / Events (`events`) | 1081-1162 |

Undo pinning keeps the just-completed row in place: Unplanned 948-962; All Tasks 1056-1079. Empty states 908-910 (Unplanned), 1007-1012 (All), 1107-1109 (By date).

### 4.3 Rows and meta

Row at 1166-1239: checkbox (todos only), title → detail, trailing `Schedule` chip or `Undo` (during undo window); event rows have no checkbox. Meta rendering 1266-1428 shows deadline, planned range, calendar, priority, repeat, tags, reminder icons.

### 4.4 Footer

| Condition | Control | Label (key) | Action | Source |
|---|---|---|---|---|
| By date | Plan Bar | Plan this day (`planThisDay`) | schedule mode composer | 335, 847-855 |
| Other | Capture bar | see composer | create in current view | 857-865 |

### 4.5 Controls that do not exist here

No row context menu, no selection mode, no manual drag ordering, no swipe actions, no in-page filter button. The filter control is injected from Home via `trailingActions` (`home_page.dart:586-588`). This is a real interaction gap vs the old doc (§12 D15).

---

## 5. Composer surfaces

There are **three** creation/edit surfaces with different write semantics.

### 5.1 Quick sheet (`showA2Composer`) — `lib/ui/pages/todo/a2_composer.dart`

Desktop `showDialog` / mobile bottom sheet at the 1000 breakpoint (33-63). Also reachable as a route: `composerCreateRoute` carries `due/start/end/summary` to `/todo/new` (68-83); triggered by the ellipsis “Open full form” (348-361).

| Control | Label (key) | Action | Source |
|---|---|---|---|
| Mode switch | Create (`create`) / Schedule Task (`scheduleTodo`) | switches mode | 119-148, 835-847 |
| Title | What needs doing? (`composerPlaceholder`) | text | 570-629 |
| Bound note | — | explains an existing bound task | 570-629 |
| Deadline | Deadline (`deadline`) | date picker | 197-230 |
| Planned time | Planned time (`executionSchedule`) | start/end | 270-317 |
| Slot chips | recommended slots | tap fills planned time | 496-506 |
| Reminder | Reminder (`reminder`) | picker; requires an anchor, otherwise toast | 270-317 |
| Calendar | Calendar (`calendarField`) | picker | 319-322 |
| Priority | Priority (`priority`) | picker | 324-346 |
| Notes | Notes (`notes`) | inline text | 570-629 |
| Open full form (ellipsis) | Open full form (`openFullForm`) | `/todo/new` with current values | 348-361 |
| Save (create) | Save (`save`) | writes Todo + allocation + reminder in one transaction | 369-484 (440-463) |
| Save (schedule) | Schedule (`schedule`) | recurring → occurrence picker; writes allocation + optional deadline | 369-484 (387-421) |
| Land-on-saved-day | — | sets viewed date to saved day | 488-494 |
| Primary label | dynamic: names every field it will write | — | 508-544 |
| Save disabled | — | until title/slot valid | 546-550 |

Missing from the quick sheet: section labels 任务/提醒/整理/内容, tags, subtasks, attachments, recurrence. Notes is the only route to the full form.

### 5.2 Quick-add overlay (`/quick-add`) — `lib/ui/pages/todo/quick_add_page.dart`

`contextDate` is capture context only, never written as a deadline (25-31). Close at 73-84.

| Control | Label (key) | Action | Source |
|---|---|---|---|
| Header | Quick add (`quickAdd`) | static | 280-354 |
| Input | free text | parsed live | 356-477 |
| Save | Save (`save`) | Event if parsed time exists, otherwise Todo | 86-94 |
| Add task | Add task (`quickAddTodo`) | forces Todo | 441-467, 983-1020 |
| Time chip | time | picker | 203-257 |
| Calendar chip | Calendar (`calendarField`) | picker | 203-257 |
| Reminder chip | Reminder (`reminder`) | picker | 203-257 |
| Card | Event/Task, date/time, calendar, reminder | — | 356-477 |
| Task date disclosure | Due date: … (`dueDate`) or No due date (`noDueDate`) | — | 1030-1039 |
| Event alternative | “Tasks · No due date” | switches interpretation | 699-711 |
| Cancel | Cancel (`cancel`) | close | 983-1020 |

Write semantics: Todo with date-only → `dueDate`; a parsed time does **not** become a deadline (96-150). Event → Event with start/end (152-201). Parser `_parseQuickAdd` at 1075-1261 is **Chinese-only** (durations 1090-1114; dates 1116-1173; times + 上午/下午/晚上 1175-1213; participants 1215-1229) while all UI copy is English.

Reachability: `SparkTopBar` Quick add (desktop pushed pages) and widget deep links; Home's desktop Capture opens the composer instead, and mobile has no in-app quick-add entry (`spark_top_bar.dart:148-151`; `home_page.dart:476-481`).

### 5.3 Full Todo form — `lib/ui/pages/todo/todo_form_page.dart`

Route targets: `/todo/new`, `/todo/edit`; also the composer's “Open full form”.

| Control | Label (key) | Action | Source |
|---|---|---|---|
| Header Save | Save (`save`) | transaction: Todo, allocation, reminders, attachments | 418-589 |
| Header trash | — | soft delete (edit mode) | 791-853 |
| AI parse | — | parse title into fields | 791-853 |
| Dirty discard | — | confirm before pop | 758-789 |
| Title | — (placeholder) | required | 872-900 |
| Association error/retry | Retry (`retry`) | reload parent | 901-929 |
| Completion row | Mark Complete / Incomplete | toggle | 930-951 |
| Time section | Time (`sectionTime`) | — | 953 |
| Deadline row | Deadline (`deadline`) | picker | 960-996 |
| Repeat | Repeat (`repeat`) | recurrence editor | 997-1008 |
| Planned time | Planned time (`executionSchedule`) | allocation section | 1009-1017 |
| Reminders | Reminders (`reminders`) | list editor | 1021-1030 |
| Organize section | Organize (`sectionOrganize`) | — | 1031 |
| Calendar row | Calendar (`calendarField`) + explanation (`calendarExplanation`) | picker | 1032-1044 |
| Priority | Priority (`priority`) | picker | 1045-1057 |
| Tags | Tags (`tags`) | picker | 1058-1069 |
| Content section | Content (`sectionContent`) | — | 1070 |
| Notes | Notes (`notes`) | text | 1071-1084 |
| Subtasks | Subtasks (`subtasks`), Add subtask (`addSubtask`) | list | 1086 |
| Attachments | — | add/remove | 1088-1096 |

Validation: title required; start before deadline; recurring draft block guard; occurrence picker when editing a recurring series; one transaction; attachment bytes written first (418-589). The explicit “任务” section label from the spec's 任务/时间/提醒/整理/内容 order is absent (§12 D14).

---

## 6. Calendar — `lib/ui/pages/calendar/a2_calendar_page.dart`

Shares `viewedDateProvider` with Today/Todos (60-64); day/week/month shifting 66-82; view menu 95-128.

### 6.1 Page controls

| Control | Label (key) | Action | Source |
|---|---|---|---|
| Header title | month/day title | static | 217-249 |
| View menu | Day (`day`) / Week (`week`) / Month (`month`) | set view | 95-128 |
| Add | New Event (`createEventOption`) | `/event/new` at viewed day | 154-156 |
| Prev / Next | chevrons | shift day/week/month | 66-82 |
| Today | Today (`today`) | reset to now | 463-515 (desktop); phone header 288-307 |
| FAB (phone, month) | add | `/event/new` | 382-387 |
| Month cell tap (phone) | — | if the day has content, switches to Day view | 149-152 |
| Month cell tap (desktop) | — | browses/selects only; double-tap empty slot creates | 415; views 609-616 |
| Drag block | — | long-press vertical move, 30-min snap | 165-204; views 1609-1614 |

### 6.2 Views — `lib/ui/pages/calendar/a2_calendar_views.dart`

| Element | Behavior | Source |
|---|---|---|
| Time grid | day/week columns, hour lines | 840-978 |
| Dawn fold | compresses pre-dawn hours | 980-1074 |
| Initial scroll | scrolls to ~08:00 | 1076-1100 |
| Week head | day labels | 1102-1164 |
| Deadline lane | deadlines per day; week max 2 + overflow | 1193-1255 |
| All-day lane | max 2 + overflow | 1320-1421 |
| Month cell | max 3 entries + “+N” | 607-675 |
| Desktop month | single tap selects, double-tap empty slot | 609-616 |
| Drag | vertical only, no resize, no cross-day drag, no recurrence scope prompt | 1578-1700 (finish 1609-1614) |

`calendar_shared.dart`: `CalBlockItem.canDrag` excludes recurring occurrences and all-day events (64-71); day blocks 73-100; all-day spans 104-125; lane packing 127-170; free gaps 185+. `CalBlockTile` (240+) is dead code.

### 6.3 Slot sheet — `lib/ui/widgets/calendar/calendar_slot_sheet.dart`

Always `showModalBottomSheet`, including desktop (37-61). Loads candidate todos for the slot (101-124).

| Control | Label (key) | Action | Source |
|---|---|---|---|
| New Event | New Event (`createEventOption`) | `/event/new` | 262-333 |
| New & schedule | New & schedule (`createTodoAndSchedule`) | composer in schedule mode | 262-333 |
| Schedule Task | Schedule Task (`scheduleTodo`) | opens task picker | 262-333 |
| Task picker | Select a Task to Schedule (`selectTodoToSchedule`) | choose existing Todo | 335-495 |
| Empty hint | “Nothing to schedule yet — create one and it lands in this slot.” (`slotEmptyCreateHint`) | — | 391-451 |
| Retry | Retry (`retry`) | reload | 391-451 |
| Recurring task | occurrence picker | choose occurrence | 335-495 |

### 6.4 Calendar picker — `lib/ui/widgets/calendar/calendar_picker.dart`

Always a modal bottom sheet on all platforms (33-41, 44-110). The picker always opens (no inline menu); “+ New calendar” creates from inside the picker and loops back to the selected value (120+). Violates the platform rule for desktop (§12 D10).

---

## 7. Event surfaces

### 7.1 Event detail — `lib/ui/pages/event/event_detail_page.dart`

Page 30-48; desktop pane 51-69; live watch 122-152; status text 167-182.

| Element | Label (key) | Interaction | Source |
|---|---|---|---|
| Title | — | inline editable, autosave | 256-333 |
| Start / End | Start / End | inline boundary pickers | 408-515, 808-826 |
| Duration | Duration | derived/editable | 408-515 |
| All day | All day (`allDay`) | toggle; writes immediately | 786-806 |
| Calendar | Calendar (`calendarField`) | picker; writes immediately | 765-784 |
| Location | Location (`location`) | inline autosave | 517-569, 646-763 |
| Repeat | Repeat (`repeat`) + series notice | series info | 217-235 |
| Reminders | Reminders (`reminders`) | list | 237-241 |
| Notes | Notes (`notes`) | inline autosave | 517-569 |
| Tags | Tags (`tags`) | chips | 571-599 |
| Attachments | — | add/remove | 246 |
| Edit | Edit (`edit`) | `/event/edit` | 601-645 |
| Move to Trash | Move to Trash (`moveToTrash`) | confirm + soft delete + Undo | 601-645, 985-1005 |
| Delete recurring instance | Delete which? (`deleteScopeTitle`) → This occurrence only (`deleteThisOccurrence`) / The whole series (`deleteWholeSeries`) | scope picker | 862-927 |
| Delete series | confirm dialog | whole series soft delete | 929-955 |
| Delete ordinary | confirm dialog | single soft delete | 956-983 |

Inline edits of a recurring event write the whole series without a scope prompt (828-860).

### 7.2 Event form — `lib/ui/pages/event/event_form_page.dart`

| Control | Label (key) | Action | Source |
|---|---|---|---|
| Save | Save (`save`) | validate + create/update | 226-350 |
| All day | All day (`allDay`) | toggle | 640-912 |
| Start / End | Start / End | boundary pickers | 640-912 |
| Duration | Duration | derived | 640-912 |
| Repeat | Repeat (`repeat`) | recurrence editor | 640-912 |
| Calendar | Calendar (`calendarField`) | picker | 640-912 |
| Location | Location (`location`) | text | 640-912 |
| Description | Notes (`notes`) | text | 640-912 |
| Tags | Tags (`tags`) | picker | 640-912 |
| Reminders | Reminders (`reminders`) | editor | 640-912 |
| Attachments | — | add/remove | 640-912 |
| Delete (edit mode) | Move to Trash (`moveToTrash`) | confirm dialog, **no occurrence-vs-series scope** | 440-498 |
| Discard | Discard (`discard`) | confirm | 407-436 |

Save disabled for an invalid range (685-692).

---

## 8. Todo detail — `lib/ui/pages/todo/todo_detail_page.dart`

Page 42-61; desktop pane 63-84; live lookup 148-179; status text 182-226.

| Element | Label (key) | Interaction | Source |
|---|---|---|---|
| Title | — | inline autosave | 330-440, 967-1032 |
| Complete toggle | Mark Complete / Incomplete | toggle + status refresh | 330-440 |
| Status line | status text | static | 182-226 |
| Time section | Time (`sectionTime`) | — | 264-289 |
| Deadline | Deadline (`deadline`) | inline picker, autosave | 518-541 |
| Planned time | Planned time (`executionSchedule`) | inline start/end, written together | 271-289, 1055-1096 |
| Repeat | Repeat (`repeat`) | recurrence editor | 271-289 |
| Reminders | Reminders (`reminders`) | list | 290-294 |
| Organize section | Organize (`sectionOrganize`) | — | 295-311 |
| Calendar | Calendar (`calendarField`) | picker, autosave | 543-559 |
| Priority | Priority (`priority`) | picker, autosave | 561-601, 1034-1038 |
| Tags | Tags (`tags`) | chips | 939-950 |
| Content section | Content (`sectionContent`) | — | 312-320 |
| Notes | Notes (`notes`) | autosave text | 603-655 |
| Subtasks | Subtasks (`subtasks`) / Add subtask (`addSubtask`) | checkable list | 821-937 |
| Attachments | — | add/remove | 320 |
| Schedule | Schedule (`schedule`) | composer schedule mode; disabled when completed/cancelled with reason | 657-780 (668-689) |
| Edit | Edit (`edit`) | `/todo/edit` | 693 |
| Move to Trash | Move to Trash (`moveToTrash`) | confirm + soft delete + Undo | 1145-1195 |
| Load failure | Retry (`retry`) / Close (`close`) | retry/close | 1198-1230 |

`/todo/edit` is reachable from the footer and from the legacy-recurrence notice (814).

---

## 9. Secondary surfaces

### 9.1 Settings — `lib/ui/pages/settings/settings_page.dart`

Desktop: 200px internal nav + 640 content (139-232). Mobile: grouped list (114-136). Section registry 98-106.

| Section | Label (key) | Rows | Source |
|---|---|---|---|
| General | General (`appearance`) | Language; Startup view Today/Calendar/Tasks; Theme System/Light/Dark; Theme Color | `appearance_section.dart:45-104` |
| Calendar | Calendar (`calendar`) | Manage Calendars | `calendar_settings_section.dart:17-26` |
| Sync | Sync (`account`) | logged out: server/email/password/Login/Register; logged in: email/status, server, Connected devices, Sync now, Log out | `account_section.dart:139-252` |
| Data | Data (`data`) | Tags, Trash, Import/Export | `data_section.dart:26-43` |
| AI Assistant | AI Assistant (`aiAssistant`) | Enabled switch + tutorial, AI Configuration, Open assistant | `ai_section.dart:26-73` |
| Notifications & reminders | Notifications & reminders (`notifications`) | System Alarm (Android/iOS), Notification permission (macOS), Exact alarm permission (Android) | `notifications_section.dart:38-86` |
| About | About (`about`) | app name/version → `/about` | `about_section.dart:7-21` |

Import/export actions: Import .ics (`importIcs`), Export .ics (`exportIcs`), Export all calendars (`exportAllCalendars`), DaySpark full backup (`fullBackup`), Merge backup (`mergeBackup`) (`import_export_section.dart:46-70`). Sign-out confirm at `account_section.dart:255+`.

`todos_section.dart:19-28` (Six Things + Hide completed) is dead and not registered; Hide completed moved to the Home filter sheet (`home_page.dart:1054-1068`).

### 9.2 Search — `lib/ui/pages/search/search_page.dart`

300ms debounce (370-389); suggestions from inbox take 5 (711-751); groups Events/Tasks (494-545); Load More (687-709); no results (476-481); failure/retry (418-460); desktop 620px overlay (191-265); keyboard ↑↓ Enter Esc (182-189); row → detail (106-115). Suggestion label “From your inbox” (`searchSuggestions`) contradicts retired Inbox terminology (§12 D17).

### 9.3 Tags — `lib/ui/pages/tags/tags_page.dart`

List with usage counts; create/edit dialog with validation; delete confirm; empty state (33-318).

### 9.4 Calendars — `lib/ui/pages/calendars/calendars_page.dart`

List with counts; delete allowed only while >1 calendar, with a move-contents prompt; create/edit name + color (20-376).

### 9.5 Trash — `lib/ui/pages/trash/trash_page.dart`

Soft-deleted Todos and Events in two sections; Restore (`restoreTodo`), permanent delete, Empty Trash (`emptyTrash`), per-row busy state; empty state action `trashEmptyAction` → `/?tab=2` (51-67, 336-361). Restore/permanent-delete snackbars share `l.error` on failure.

### 9.6 About — `lib/ui/pages/about/about_page.dart`

Version row; Check for Updates (`checkUpdate`, GitHub); release notes expand/collapse; “up to date”; Star on GitHub; Report an Issue (`reportIssue`) → `/feedback`; Third-Party Licenses (140-337).

### 9.7 Feedback — `lib/ui/pages/feedback/feedback_page.dart`

Text field; Copy feedback to clipboard; Submit on GitHub (17-116). Reachable only from About (§12 D23).

### 9.8 AI chat — `lib/ui/pages/ai_chat/ai_chat_page.dart`

Disabled/unconfigured empty states (174-193); message list; latest-answer quick actions Add Event / Add Task / Schedule / Break Down (290-362); send/retry (119-140); clear confirm (85-117); calendar picker dialog (40-76); suggested slots and write conflict handling (439-700).

---

## 10. States

| State | Where | Copy / behavior | Source |
|---|---|---|---|
| Loading | Today | spinner | `today_page.dart:453-455` |
| Loading | Todos | `_loading` spinner | `a2_todo_page.dart:877-878` |
| Loading | detail loaders | `_DetailLoadingPage` | `app_router.dart:110-120` |
| Loading | Settings/Tags/Calendars/Trash/Search | spinners | per page |
| Error | Today typed error + Retry | Retry (`retry`) | 470-499 |
| Error | Today stale list + retry strip | keeps content, offers Retry | 501-527 |
| Error | Todos load failure | error text + Retry | 337-370, 880-888 |
| Error | Todo/Event detail failure or gone | Retry / Close | todo 1198-1230; event 122-152 |
| Error | Search failure | error + Retry | 418-460 |
| Error | Sync badge | error styling, tooltip | `spark_top_bar.dart:613-620` |
| Error | Account load failure | explanation + retry | `account_section.dart:105-127` |
| Empty | Today | empty copy | 637-642; desktop 722-742 |
| Empty | Unplanned / All / By date | per-view copy | 908-910 / 1007-1012 / 1107-1109 |
| Empty | Trash / Tags / Calendars / Search / AI | per-surface copy | trash 51-67; tags 69-79; calendars 56-64; search 476-481; AI 176-193 |
| Offline | **none found** | only the sync error badge exists | grep finds no offline UI |
| Permission | Notification permission (macOS), exact alarm (Android) | status + request action | `notifications_section.dart:62-85` |
| Disabled | Composer Save until title/slot valid | disabled | `a2_composer.dart:546-550` |
| Disabled | Composer ellipsis during scheduling | disabled | 772-791 |
| Disabled | Todo Schedule when completed/cancelled | disabled + reason | `todo_detail_page.dart:668-689` |
| Disabled | Event Save on invalid range | disabled | `event_form_page.dart:685-692` |
| Conflict | AI schedule slot conflict | `timeSlotConflict` message | `ai_chat_page.dart:663-673` |

There is no generic permission-denied page, no offline banner, and no retry affordance on most secondary pages beyond their `error` + Retry pattern.

---

## 11. Removed / changed since v0.29.0

These are **gone from the product UI** and must not be prototyped:

1. **Action tab** — the top-level 行动 destination is gone; Today replaces it. `action_section.dart` no longer exists; `AppTab.action` survives only as an internal enum value behind Day (`spark_top_bar.dart:206-224`; `workspace_navigation.dart:11-26`).
2. **Inbox as a destination** — the sidebar Inbox sub-row is gone; `l.inbox` now renders “Unplanned” inside Todos (`a2_todo_page.dart:430-450`).
3. **Six Things** — the settings section is dead code and not registered (`todos_section.dart:19-28`; `settings_page.dart:98-106`); l10n keys remain.
4. **Desktop sidebar navigation** — `WorkspaceSidebar` is dead code; the shell comment says “There is no sidebar” (`workspace_scaffold.dart:19-23`; `workspace_sidebar.dart:21-22`).
5. **Widget `new-todo` deep link to the full form** — now maps to `/quick-add` (`home_widget_interactivity.dart:56-58`).
6. **Old Action-tab sections** Now/Next up/To do today/Overdue/Earlier today — replaced by Today’s Now/Upcoming/Due today/Overdue/Missed/Earlier today/Completed Today (`today_page.dart:888-1168`).
7. **Old “New Task” header action** — Today/Todos now use inline capture bars; the composer and full form are the creation paths (`today_page.dart:670-684`; `a2_todo_page.dart:857-865`).
8. **Old “no caller for `/event/edit`”** — obsolete: event detail now links to it (`event_detail_page.dart:629`).
9. **Old `DayStrip` and `CalBlockTile`** — both remain only as dead declarations (`day_strip.dart:11`; `calendar_shared.dart:240`).

New in v0.34.0:
- `/quick-add` overlay page + Chinese natural-language parser + widget quick-add entry.
- Today page as the clock-only first screen with capture + unplanned shelf.
- Todos internal views (Unplanned / All Tasks / By date) with a mode switcher and shared browse date.
- Composer Create/Schedule dual mode with truthful primary-button labels.
- `SparkTopBar`, Home `_DesktopBar`, and the visual-interaction layer (`lib/ui/design/ds.dart`).

---

## 12. Gaps and defects (documented, not fixed)

Severity: P1 = blocks a primary flow; P2 = user-visible inconsistency; P3 = dead code / stale comment.

| # | Sev | Finding | Evidence |
|---|---|---|---|
| D1 | P3 | `WorkspaceSidebar` is dead code; no imports; shell says there is no sidebar | `workspace_sidebar.dart:21-22`; `workspace_scaffold.dart:19-23` |
| D2 | P3 | `DayStrip` is dead (declaration only) | `day_strip.dart:11` |
| D3 | P3 | `CalBlockTile` is dead (self-reference only) | `calendar_shared.dart:240` |
| D4 | P3 | `TodosSection` (Six Things) is dead and unregistered | `todos_section.dart:19-28`; `settings_page.dart:98-106` |
| D5 | P2 | Two desktop top bars with different controls and nav orders (Today/Tasks/Calendar vs mobile Today/Calendar/Tasks vs spec Today/Calendar/Todo) | `home_page.dart:1116-1120, 1404-1408`; `workspace_scaffold.dart:56` |
| D6 | P2 | Home desktop bar has no sync badge, avatar, Settings entry, tap-to-today, or date picker; `SparkTopBar` has no labelled Calendar destination and Day maps to retired Action tab | `home_page.dart:1174-1232`; `spark_top_bar.dart:143-146, 206-224` |
| D7 | P2 | `/quick-add` is unreachable in-app on mobile and unreachable from Home on desktop (Home Capture opens the composer) | `spark_top_bar.dart:148-151`; `home_page.dart:476-481`; `quick_add_page.dart:25-31` |
| D8 | P2 | Quick-add parser is Chinese-only while UI copy is English | `quick_add_page.dart:1075-1261` |
| D9 | P3 | `/todo/new` still exposes `parentId`/`source`, but nothing passes them; only the composer ellipsis calls it | `app_router.dart:356-389`; `a2_composer.dart:81-82, 348-361` |
| D10 | P2 | Calendar slot sheet and calendar picker are modal bottom sheets even on desktop | `calendar_slot_sheet.dart:37-61`; `calendar_picker.dart:33-41` |
| D11 | P2 | Calendar drag is vertical-only long-press with 30-min snap; no resize, no cross-day drag, no recurring scope prompt on move | `a2_calendar_views.dart:1578-1700`; `a2_calendar_page.dart:165-204`; `calendar_shared.dart:64-71` |
| D12 | P1 | Event form Delete has no occurrence-vs-series scope prompt, unlike event detail | `event_form_page.dart:440-498` vs `event_detail_page.dart:862-927` |
| D13 | P1 | Event detail inline edits of a recurring event write the whole series with no scope prompt | `event_detail_page.dart:828-860` |
| D14 | P2 | Todo full form omits the explicit 任务 section label required by the 任务/时间/提醒/整理/内容 order | `todo_form_page.dart:857-1098` |
| D15 | P2 | Todos page lacks row context menu, selection mode, manual drag ordering, swipe actions, and in-page filters (filters injected from Home only) | `a2_todo_page.dart:1166-1428`; `home_page.dart:586-588` |
| D16 | P2 | Today desktop unplanned shelf cannot expand in place (chevron navigates), while mobile has inline show-more | `today_page.dart:788-793` vs `595-598` |
| D17 | P2 | Search suggestions use `inboxTodosProvider` and label “From your inbox”, conflicting with retired Inbox terminology and allocation-based Unplanned semantics | `search_page.dart:711-751`; `app_en.arb` `searchSuggestions` |
| D18 | P1 | Today has no Event creation entry; the desktop Capture creates a Todo only, contradicting a neutral Today creation choice | `today_page.dart:26-29`; `home_page.dart:476-481` |
| D19 | P2 | No offline state anywhere; only the sync error badge | `spark_top_bar.dart:613-620` |
| D20 | P2 | Month cell tap auto-switches to Day on phone but only browses on desktop — same gesture, different behavior | `a2_calendar_page.dart:149-152` vs `415` |
| D21 | P3 | `workspace_navigation.dart` comments still describe a desktop sidebar and Todos day/inbox/all as top-level destinations | `workspace_navigation.dart:11-94` |
| D22 | P2 | Quick-add date-only capture silently becomes a deadline while the primary button says “Save” and the alternate says “Add task”; only the card discloses “Due date” | `quick_add_page.dart:115-129, 1030-1039` |
| D23 | P2 | Feedback is reachable only from About, not Settings | `about_page.dart:327` |
| D24 | P2 | Capture writes into `calendars.first` with no calendar shown or chosen | `today_page.dart:124-134` |
| D25 | P3 | Today mobile header still shows Settings gear while desktop Home bar omits it — one more shell asymmetry | `today_page.dart:623` vs `home_page.dart:1224-1232` |
| D26 | P2 | Trash restore failures surface the generic `error` string, not a restore-specific message | `trash_page.dart:306-312` |

---

## 13. Surface count summary

- Routes: 16 app paths + 1 overlay route + deep-link scheme.
- Top-level product destinations: 3 (今天 / 日历 / 待办), with 3 Todos internal views.
- Creation surfaces: 4 (Today capture, Todos capture / Plan Bar, composer, `/quick-add`) plus full Todo and Event forms.
- Detail/editor surfaces: 2 (Todo detail, Event detail) plus 2 full forms.
- Secondary surfaces: 8 (Settings, Search, Tags, Calendars, Trash, About, Feedback, AI chat).
- Dead surfaces: 4 (WorkspaceSidebar, DayStrip, CalBlockTile, TodosSection).
- Documented defects: 26 (P1: 3, P2: 16, P3: 7).
