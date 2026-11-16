# Feature-coverage audit — prototype vs DaySpark v0.34.0

Read-only audit of `docs/design/interaction-model/` against the real Flutter source.
Every claim about the app cites `file:line` in `/Users/chang/Desktop/Code/dayspark-g0/lib/`.
Every claim about the prototype cites `file:line` in `docs/design/interaction-model/`.

- App under audit: v0.34.0+34 (`pubspec.yaml`), commit `7390987` on the g1 clone.
  The g0 tree used here is byte-identical: `diff -rq lib ../dayspark-g1/lib` returned nothing,
  and `docs/CORE_UX_SPEC.md` is identical in both trees.
- Prototype baseline: originally drawn against v0.29.0 (`research/APP_SURFACE.md` @ `46c01fe`),
  rebased to v0.34.0.
- `COVERAGE.md` was read as a set of claims only. Nothing below is marked covered because
  `COVERAGE.md` says so; each status comes from reading the prototype's own `js/`.

Status vocabulary:

| Status | Meaning |
|---|---|
| **Covered** | The real surface exists and the prototype renders the same operation with an identifiable entry control. |
| **Partial** | The prototype has a counterpart, but a real control, state, mode or platform variant is absent or differs materially. |
| **Missing** | The real surface is user-reachable in v0.34.0 and the prototype has no equivalent. |
| **Intentional-out** | The real surface exists but the prototype deliberately excludes it. Judged separately in §3. |
| **Prototype-only** | The prototype models an operation the audited app does not implement. Not a coverage gap; listed in §4. |

---

## 1. Surface → real code → prototype → status

### 1.1 Shell, navigation, routing

| # | Surface / operation | Real code | Prototype equivalent | Status |
|---|---|---|---|---|
| 1 | `/` home, three destinations 今天/日历/待办 in place | `lib/core/router/app_router.dart:233-248`; `lib/ui/pages/home/home_page.dart:448-523` | rail + bottom nav, `js/app.js:84-211` | Covered |
| 2 | `/quick-add` overlay route (desktop Quick add; widget deep link) | `lib/core/router/app_router.dart:249-264`; entry `lib/ui/shell/spark_top_bar.dart:148-151` | none; excluded by `COVERAGE.md` §7 | Missing |
| 3 | Desktop shell: no sidebar, one top bar | `lib/ui/shell/workspace_scaffold.dart:14-23, 35-63` | 200px rail, `js/app.js:124-179` | Partial |
| 4 | Desktop home bar (nav 今天/待办/日历, date arrows, clock, Capture, Search) | `lib/ui/pages/home/home_page.dart:1097-1256` | unified page head, `js/ui.js:366` | Partial |
| 5 | Desktop pushed-route bar (brand, date nav + tap-to-today, Now/Next up, Search, 待办, Day/Week/Month, Quick add, sync badge, avatar) | `lib/ui/shell/spark_top_bar.dart:98-163, 310-330, 394-437, 606-644` | rail + page head; no equivalent bar | Partial |
| 6 | Mobile dock 今天/日历/待办 | `lib/ui/pages/home/home_page.dart:1394-1440` | bottom nav + More menu, `js/app.js:181-211` | Partial |
| 7 | Mobile page heads with search + settings icons | `lib/ui/pages/home/today_page.dart:608-625`; `lib/ui/pages/todo/a2_todo_page.dart:452-458` | header action row, `js/ui.js:366` | Partial |
| 8 | Ctrl/Cmd+K opens search | `lib/ui/shell/workspace_scaffold.dart:38-48`; `lib/ui/pages/home/home_page.dart:486-496` | `/` shortcut, `js/app.js:260` | Partial |
| 9 | Android back returns to 今天 from other destinations | `lib/ui/pages/home/home_page.dart:528-537` | none | Missing |
| 10 | Widget/OS deep links (`new-todo`, todo/event id, calendar date, todos view) | `lib/infrastructure/platform/home_widget_interactivity.dart:14-75` | none | Intentional-out |
| 11 | Unknown-route error page | `lib/core/router/app_router.dart:195-231` | missing-record page, `js/views/detail.js:631-648` | Partial |
| 12 | Web URL carries tab + browsed date | `lib/ui/pages/home/home_page.dart:320-363` | none | Missing |
| 13 | Startup changelog dialog on version change | `lib/ui/pages/home/home_page.dart:365-393` | none | Missing |
| 14 | Notification actions (mark complete / snooze) | `lib/ui/pages/home/home_page.dart:395-436` | none | Missing |
| 15 | Esc clears the master-detail pane before leaving | `lib/ui/pages/home/home_page.dart:542-552` | `js/app.js:248` | Covered |

### 1.2 今天 (Today)

| # | Surface / operation | Real code | Prototype equivalent | Status |
|---|---|---|---|---|
| 16 | Today is the clock only; no date switcher | `lib/ui/pages/home/today_page.dart:26-29, 608-625` | fixed `actionDate`, `js/views/action.js:70-87` | Covered |
| 17 | Capture bar: Enter files a todo unplanned | `lib/ui/pages/home/today_page.dart:119-158, 670-684` | `js/views/action.js:90-119` | Covered |
| 18 | Capture result feedback | toast only, `lib/ui/pages/home/today_page.dart:144, 160-170` | toast **with undo**, `js/views/action.js:106-108` | Partial |
| 19 | Neutral create chooser on 今天 (新建 → 待办 / 日程) | absent; head actions are search + settings only, `lib/ui/pages/home/today_page.dart:608-625` | `js/views/action.js:53-68` | Prototype-only |
| 20 | Now section | `lib/ui/pages/home/today_page.dart:888-917` | `js/views/action.js:125-136` | Covered |
| 21 | Upcoming (incl. recurring instances, cap 3) | `lib/ui/pages/home/today_page.dart:919-989` | `laterToday`, `js/views/action.js:138-145` | Partial |
| 22 | Due today | `lib/ui/pages/home/today_page.dart:991-1014` | `js/views/action.js:154-162` | Covered |
| 23 | Overdue (cap 3, expand) | `lib/ui/pages/home/today_page.dart:1016-1067` | `js/views/action.js:164-184` | Covered |
| 24 | Missed section (recurring instances, own head) | `lib/ui/pages/home/today_page.dart:1069-1119` | folded into Overdue, `js/views/action.js:166-171` | Partial |
| 25 | Earlier today (ended timed items) | `lib/ui/pages/home/today_page.dart:1121-1139` | `js/views/action.js:186-197` | Covered |
| 26 | Completed Today (separate collapsible section) | `lib/ui/pages/home/today_page.dart:1141-1168` | merged into Earlier today, `js/views/action.js:190-197` | Partial |
| 27 | Pinned inline undo on the completed row (5s) | `lib/ui/pages/home/today_page.dart:364-393, 1485, 1581` | toast undo | Partial |
| 28 | Complete / reopen with occurrence resolution | `lib/ui/pages/home/today_page.dart:206-325` | `js/views/action.js:319-321` | Covered |
| 29 | Unplanned shelf: desktop 320px panel, preview 3, chevron → Unplanned | `lib/ui/pages/home/today_page.dart:540-555, 558-599, 768-816` | `js/views/action.js:199-225` | Covered |
| 30 | Loading / error / stale retry | `lib/ui/pages/home/today_page.dart:444-527` | states bench, `js/views/misc.js:25-74` | Partial |
| 31 | Desktop two-column layout (max 1240) | `lib/ui/pages/home/today_page.dart:692-822` | single column | Partial |
| 32 | Row meta merges plan + deadline; inline Schedule chip | `lib/ui/pages/home/today_page.dart:1349-1502, 1468-1482` | meta only, `js/views/action.js:261-300` | Partial |
| 33 | Mobile unplanned preview restricted to no-deadline items | `lib/ui/pages/home/today_page.dart:540-555` | `js/views/action.js:204` | Covered |

### 1.3 待办 (Todos)

| # | Surface / operation | Real code | Prototype equivalent | Status |
|---|---|---|---|---|
| 34 | Mode switch 未安排 / 全部任务 / 按日期 via title block | `lib/ui/pages/todo/a2_todo_page.dart:430-515, 551-656` | chips, `js/views/todo.js:459-500` | Partial |
| 35 | By-date strip: Today chip, month/year picker, prev/next | `lib/ui/pages/todo/a2_todo_page.dart:703-804` | week strip + picker, `js/views/todo.js:380-457` | Partial |
| 36 | Unplanned body (With a deadline · unplanned / No deadline) | `lib/ui/pages/todo/a2_todo_page.dart:890-944` | `js/views/todo.js:374` | Partial |
| 37 | All Tasks body (Due today / Past due / Later / No deadline) | `lib/ui/pages/todo/a2_todo_page.dart:964-1051` | `js/views/todo.js:374` | Partial |
| 38 | By-date body (Planned / Deadline / Events) | `lib/ui/pages/todo/a2_todo_page.dart:1081-1162` | `js/views/todo.js:376` | Partial |
| 39 | Capture bar on 未安排 / 全部任务 | `lib/ui/pages/todo/a2_todo_page.dart:847-866` | `js/views/todo.js:280-299` | Covered |
| 40 | By-date Plan Bar "Plan this day" → schedule-mode composer | `lib/ui/pages/todo/a2_todo_page.dart:847-866`; `lib/ui/design/a2.dart:682` | none | Missing |
| 41 | Row action: Schedule / Undo | `lib/ui/pages/todo/a2_todo_page.dart:1179-1209` | row menu "allocate now", `js/views/todo.js:176` | Partial |
| 42 | Filter & display sheet (calendar / tag / priority, hide completed, clear/done, count badge) | `lib/ui/pages/home/home_page.dart:918-1092` | filter menu + tag chips, `js/views/todo.js:473-483, 552` | Partial |
| 43 | Master-detail pane ≥1180 on 待办 only | `lib/ui/pages/home/home_page.dart:574-576, 854-908`; `lib/ui/shell/workspace_navigation.dart:91-94` | `js/app.js:102-118`; `js/views/todo.js:505` | Covered |
| 44 | Per-mode empty states | `lib/ui/pages/todo/a2_todo_page.dart:909, 1011, 1108` | empty states, `js/ui.js:313` | Covered |
| 45 | Loading / error | `lib/ui/pages/todo/a2_todo_page.dart:338, 877-888` | states bench, `js/views/misc.js:25-74` | Partial |

### 1.4 日历 (Calendar)

| # | Surface / operation | Real code | Prototype equivalent | Status |
|---|---|---|---|---|
| 46 | Browse date shared with 待办 · 按日期 | `lib/ui/pages/calendar/a2_calendar_page.dart:60-63`; `lib/ui/shell/workspace_navigation.dart:31-54` | `js/store.js:918-942`; `js/views/todo.js:15-17` | Covered |
| 47 | Prev/next per mode (month keeps day-of-month, clamped) | `lib/ui/pages/calendar/a2_calendar_page.dart:66-81` | `js/views/calendar.js:30-36` | Partial |
| 48 | Go to today | `lib/ui/pages/calendar/a2_calendar_page.dart:84-86` | `js/views/calendar.js:781-783` | Covered |
| 49 | View menu Month/Week/Day (phone words menu; desktop segmented) | `lib/ui/pages/calendar/a2_calendar_page.dart:95-128, 463-516` | `js/views/calendar.js:769-821` | Covered |
| 50 | Phone month tap drills to day **only if the day has entries** | `lib/ui/pages/calendar/a2_calendar_page.dart:130-152` | always drills, `js/views/calendar.js:128-136` | Partial |
| 51 | Desktop month double-tap empty slot → new event at next hour | `lib/ui/pages/calendar/a2_calendar_views.dart:607-616` | none | Missing |
| 52 | Phone month strip | `lib/ui/pages/calendar/a2_calendar_page.dart:314-320`; `lib/ui/pages/calendar/a2_calendar_views.dart:147-200` | month grid, `js/views/calendar.js:75-162` | Partial |
| 53 | Phone month grid dots + count (a11y label) | `lib/ui/pages/calendar/a2_calendar_views.dart:240-445` | `js/views/calendar.js:113-137` | Covered |
| 54 | Desktop month chips (3 + overflow) | `lib/ui/pages/calendar/a2_calendar_views.dart:447-684` | `js/views/calendar.js:139-157` | Covered |
| 55 | Deadline lane (week max 2 + overflow) | `lib/ui/pages/calendar/a2_calendar_views.dart:1193-1292`; `lib/ui/widgets/calendar/calendar_deadline_lane.dart` | `js/views/calendar.js:165-211` | Covered |
| 56 | All-day lane (max 2) | `lib/ui/pages/calendar/a2_calendar_views.dart:1320-1421` | `js/views/calendar.js:241-254` | Partial |
| 57 | Time-grid drag = long-press vertical move, 30-min snap, no resize/cross-day | `lib/ui/pages/calendar/a2_calendar_views.dart:1578-1700` | 15-min snap + resize + cross-day, `js/views/calendar.js:484-553` | Partial |
| 58 | Drag a recurring event (app moves it with no scope question; prototype asks) | `lib/ui/pages/calendar/a2_calendar_views.dart:1578-1700` | `js/views/calendar.js:555-626` | Covered |
| 59 | Dawn fold | `lib/ui/pages/calendar/a2_calendar_views.dart:980-1010, 1047-1074` | none | Missing |
| 60 | Initial scroll to ~08:00 | `lib/ui/pages/calendar/a2_calendar_views.dart:1076-1100, 1780` | `js/views/calendar.js:325-331` | Partial |
| 61 | Sticky now strip + back-to-now | `lib/ui/pages/calendar/a2_calendar_views.dart:1750-1944` | now line only, `js/views/calendar.js:306` | Partial |
| 62 | Slot sheet: New Event / New & schedule / Schedule Task + candidate count, loading, failed, empty | `lib/ui/widgets/calendar/calendar_slot_sheet.dart:85-124, 262-333` | two actions only, `js/views/calendar.js:663-686` | Partial |
| 63 | Schedulable-todo picker + recurring occurrence picker | `lib/ui/widgets/calendar/calendar_slot_sheet.dart:335-495` | `js/views/calendar.js:688-752` | Partial |
| 64 | Phone create: view menu + add only outside month; FAB only in month | `lib/ui/pages/calendar/a2_calendar_page.dart:273-392` | one create button | Partial |
| 65 | Calendar legend (event / scheduled time / deadline) | l10n keys exist (`lib/l10n/app_en.arb:729-730`) but no widget references them; no legend widget in `lib/ui/pages/calendar/` | `js/views/calendar.js:213-222` | Prototype-only |
| 66 | Desktop head: Today / prev / next / New Event / segmented | `lib/ui/pages/calendar/a2_calendar_page.dart:463-516` | `js/views/calendar.js:769-821` | Covered |

### 1.5 Creation surfaces

| # | Surface / operation | Real code | Prototype equivalent | Status |
|---|---|---|---|---|
| 67 | Composer chrome: desktop dialog vs phone bottom sheet | `lib/ui/pages/todo/a2_composer.dart:33-63` | full page, `js/views/composer.js:69-73` | Partial |
| 68 | Create mode vs Schedule mode (Plan Bar entry) | `lib/ui/pages/todo/a2_composer.dart:119-148, 835-847` | schedule sheet inside composer, `js/views/composer.js:500-660` | Partial |
| 69 | Deadline row + date-only / date-time choice | `lib/ui/pages/todo/a2_composer.dart:197-229` | `js/views/composer.js:529` | Covered |
| 70 | Custom slot start/end | `lib/ui/pages/todo/a2_composer.dart:231-261` | `js/views/composer.js:600-660` | Covered |
| 71 | Reminder picker | `lib/ui/pages/todo/a2_composer.dart:270-317` | composer reminder section, `js/views/composer.js:275` | Covered |
| 72 | Calendar picker; always opens; create-calendar inside and loop back | `lib/ui/pages/todo/a2_composer.dart:319-322`; `lib/ui/widgets/calendar/calendar_picker.dart:27-50, 120-198` | `js/ui.js:402-470` | Covered |
| 73 | Priority | `lib/ui/pages/todo/a2_composer.dart:324-346` | `js/views/composer.js:278-306` | Covered |
| 74 | Recommended slot grid | `lib/ui/pages/todo/a2_composer.dart:496-506, 958-999` | none | Missing |
| 75 | Truthful primary label naming every field the save writes | `lib/ui/pages/todo/a2_composer.dart:508-544` | generic "Save", `js/views/composer.js:194` | Missing |
| 76 | Write-failure retry inside the sheet | `lib/ui/pages/todo/a2_composer.dart:796-808` | none | Missing |
| 77 | "Open full form" carrying due/start/end/summary | `lib/ui/pages/todo/a2_composer.dart:68-83, 348-361` | edit route | Covered |
| 78 | `/quick-add`: NL parse (Chinese only), event-if-time else todo, Save + Add task, desktop/mobile variants | `lib/ui/pages/todo/quick_add_page.dart:25-31, 86-201, 356-477, 1075-1261` | none | Missing |
| 79 | Full Todo form: 时间/提醒/整理/内容 order, repeat, execution, reminders, calendar, priority, tags, notes, subtasks, attachments | `lib/ui/pages/todo/todo_form_page.dart:857-1098` | `js/views/composer.js:229-460` | Partial |
| 80 | AI parse in Todo form | `lib/ui/pages/todo/todo_form_page.dart:689-754, 842` | none | Missing |
| 81 | Dirty-draft discard guard | `lib/ui/pages/todo/todo_form_page.dart:758-789` | `js/views/composer.js:87-96` | Covered |
| 82 | Completion draft row in the form | `lib/ui/pages/todo/todo_form_page.dart:930-951` | none | Missing |
| 83 | Form delete with undo | `lib/ui/pages/todo/todo_form_page.dart:1414-1470` | `js/views/composer.js:180-189` | Covered |
| 84 | Legacy recurrence notice + repair (which date the series repeats from) | `lib/ui/pages/todo/todo_form_page.dart:1145-1198`; `lib/ui/pages/todo/todo_detail_page.dart:271-273, 802-819` | none | Intentional-out |
| 85 | Event form (save transaction, boundary pickers, calendar, header) | `lib/ui/pages/event/event_form_page.dart:226-350, 500-629, 632-693` | `js/views/composer.js` event kind | Partial |
| 86 | Event form delete (app confirms once with no scope; prototype asks occurrence vs series) | `lib/ui/pages/event/event_form_page.dart:440-498` | `js/event-ops.js:14-120` | Covered |
| 87 | Event form invalid range disables save | `lib/ui/pages/event/event_form_page.dart:685-692` | none | Missing |
| 88 | AI parse in Event form | `lib/ui/pages/event/event_form_page.dart:525-573` | none | Missing |

### 1.6 Details

| # | Surface / operation | Real code | Prototype equivalent | Status |
|---|---|---|---|---|
| 89 | Todo detail inline autosave title + notes | `lib/ui/pages/todo/todo_detail_page.dart:264-320, 603-655` | click-to-edit editors, `js/views/detail.js:250, 413` | Partial |
| 90 | Todo status toggle | `lib/ui/pages/todo/todo_detail_page.dart:182-226` | `js/views/detail.js:62-70` | Partial |
| 91 | Detail section order 时间/提醒/整理/内容 | `lib/ui/pages/todo/todo_detail_page.dart:264-320` | `js/views/detail.js:75-160` | Covered |
| 92 | Deadline inline + clear | `lib/ui/pages/todo/todo_detail_page.dart:518-541` | `js/views/detail.js:333` | Covered |
| 93 | Execution schedule + repeat inline (add/reschedule/cancel with undo) | `lib/ui/pages/todo/todo_detail_page.dart:274-287`; `lib/ui/widgets/schedule/execution_schedule_section.dart:53-268` | `js/views/detail.js:90-122` | Partial |
| 94 | Reminders add / edit / remove | `lib/ui/pages/todo/todo_detail_page.dart:290-294`; `lib/ui/widgets/reminder/reminders_section.dart:36-382` | display only, `js/views/detail.js:126-129` | Partial |
| 95 | Calendar / priority / tags inline | `lib/ui/pages/todo/todo_detail_page.dart:543-601, 939-950` | `js/views/detail.js:133-160` | Covered |
| 96 | Subtasks + add dialog | `lib/ui/pages/todo/todo_detail_page.dart:821-937` | `js/views/detail.js:203-232` | Covered |
| 97 | Attachments: add / open / delete, local-only note | `lib/ui/pages/todo/todo_detail_page.dart:320`; `lib/ui/widgets/attachment_list.dart:65-355` | filename list only, `js/views/composer.js:436-457` | Partial |
| 98 | Footer Mark Complete / Schedule (disabled reason) / Edit / Move to Trash | `lib/ui/pages/todo/todo_detail_page.dart:657-780` | `js/views/detail.js:255-268` | Covered |
| 99 | Deleted state + write-failure retry / close | `lib/ui/pages/todo/todo_detail_page.dart:155-170, 1198-1232` | none | Missing |
| 100 | Event detail inline start/end/duration/all-day/calendar/location/title | `lib/ui/pages/event/event_detail_page.dart:256-515` | `js/views/detail.js:522-630` | Partial |
| 101 | Event repeat + series notice | `lib/ui/pages/event/event_detail_page.dart:217-235` | `js/views/detail.js:562-575` | Partial |
| 102 | Event delete scope dialog (this occurrence / whole series) | `lib/ui/pages/event/event_detail_page.dart:862-983` | `js/event-ops.js:14-120` | Covered |
| 103 | Inline edit of an event occurrence (app writes the whole series with no scope; prototype asks) | `lib/ui/pages/event/event_detail_page.dart:828-860` | scope asked, `js/event-ops.js:99-120` | Covered |
| 104 | Event footer Edit / Move to Trash | `lib/ui/pages/event/event_detail_page.dart:601-645` | `js/views/detail.js:619-623` | Covered |

### 1.7 Settings

| # | Surface / operation | Real code | Prototype equivalent | Status |
|---|---|---|---|---|
| 105 | Section registry: General / Calendar / Sync / Data / AI Assistant / Notifications & reminders / About | `lib/ui/pages/settings/settings_page.dart:98-106` | `js/views/settings.js:55-212` | Partial |
| 106 | Desktop 200px internal nav + 640 content column | `lib/ui/pages/settings/settings_page.dart:139-232` | single scrolling page, `js/views/settings.js:14-217` | Missing |
| 107 | Language: System / 中文 / English | `lib/ui/pages/settings/settings_sections/appearance_section.dart:45-50, 119-124` | zh/en only, `js/views/settings.js:79-81` | Partial |
| 108 | Startup view: 今天 / 日历 / 待办 | `lib/ui/pages/settings/settings_sections/appearance_section.dart:52-63, 136-141` | `js/views/settings.js:83-85` | Covered |
| 109 | Theme: System / Light / Dark | `lib/ui/pages/settings/settings_sections/appearance_section.dart:65-75` | light/dark only, `js/views/settings.js:64-66` | Partial |
| 110 | Seven accent swatches | `lib/ui/pages/settings/settings_sections/appearance_section.dart:92-104` | `js/views/settings.js:68-78` | Covered |
| 111 | Calendar section: Manage Calendars + count | `lib/ui/pages/settings/settings_sections/calendar_settings_section.dart:20-23` | `js/views/settings.js:91-93` | Covered |
| 112 | Sync signed-out form: server / email / password, Register + Login, validation taxonomy | `lib/ui/pages/settings/settings_sections/account_section.dart:136-213, 374-384` | `js/views/settings.js:139-175` | Partial |
| 113 | Account load error + retry | `lib/ui/pages/settings/settings_sections/account_section.dart:87-131` | none | Missing |
| 114 | Sync signed-in: email / status / server / devices / Sync now / Log out | `lib/ui/pages/settings/settings_sections/account_section.dart:215-283` | `js/views/settings.js:113-135` | Covered |
| 115 | Connected-devices dialog (empty / error / loading) | `lib/ui/pages/settings/settings_sections/account_section.dart:312-355` | `js/views/settings.js:236-250` | Partial |
| 116 | AI section: enable switch + tutorial link, config row, Open assistant only when enabled and configured | `lib/ui/pages/settings/settings_sections/ai_section.dart:26-73` | `js/views/settings.js:178-188` | Partial |
| 117 | AI config dialog: presets/custom, base URL, masked key, Detect models, model pick, Remove config | `lib/ui/widgets/ai_config_dialog.dart:82-370` | `js/views/settings.js:317-356` | Partial |
| 118 | Data: Tags + Trash counts, Import/Export group | `lib/ui/pages/settings/settings_sections/data_section.dart:26-44` | `js/views/settings.js:97-106` | Partial |
| 119 | Import .ics with target-calendar sheet; Export .ics all; Full backup; Merge backup | `lib/ui/pages/settings/settings_sections/import_export_section.dart:48-229` | `js/views/settings.js:251-315` | Partial |
| 120 | Notifications: platform-gated rows (Android/iOS alarm, macOS permission, Android exact alarm) | `lib/ui/pages/settings/settings_sections/notifications_section.dart:38-86`; gate `settings_page.dart:308-312` | all platforms, toggles, `js/views/settings.js:191-202` | Partial |
| 121 | About row → `/about` | `lib/ui/pages/settings/settings_sections/about_section.dart` | `js/views/settings.js:204` | Covered |

### 1.8 Libraries

| # | Surface / operation | Real code | Prototype equivalent | Status |
|---|---|---|---|---|
| 122 | Tags: list + counts, create/edit (name + color), delete confirm | `lib/ui/pages/tags/tags_page.dart:33-317` | `js/views/library.js:9-97` | Covered |
| 123 | Calendars: list + open-todo counts, create/edit, delete with move-vs-delete + target sheet + last-calendar guard | `lib/ui/pages/calendar/calendars_page.dart:24-373` | `js/views/library.js:100-213` | Covered |
| 124 | Trash: restore / permanent delete / empty, empty action → 待办 | `lib/ui/pages/trash/trash_page.dart:31-362` | `js/views/library.js:216-290` | Covered |
| 125 | About: GitHub update check, rate-limit/error, no releases, expandable release notes, Open update, Star, Report an Issue, third-party licenses | `lib/ui/pages/about/about_page.dart:54-336` | `js/views/library.js:293-336` | Partial |
| 126 | Feedback: text, Copy to clipboard, Submit on GitHub | `lib/ui/pages/feedback/feedback_page.dart:39-115` | `js/views/library.js:339-376` | Partial |

### 1.9 Search

| # | Surface / operation | Real code | Prototype equivalent | Status |
|---|---|---|---|---|
| 127 | Search: 300ms debounce, results for todos + events | `lib/ui/pages/search/search_page.dart:32-188, 376-382` | `js/views/search.js:8-86` | Partial |
| 128 | Paged results + Load more | `lib/ui/pages/search/search_page.dart:512-711` | none | Partial |
| 129 | Empty-query suggestions from Unplanned | `lib/ui/pages/search/search_page.dart:711-740` | none | Missing |
| 130 | Keyboard ↑↓ / Enter / Esc selection | `lib/ui/pages/search/search_page.dart:183-188` | none | Missing |
| 131 | Failure retry / no-results | `lib/ui/pages/search/search_page.dart:451` | `js/views/search.js:49` | Partial |

### 1.10 AI assistant

| # | Surface / operation | Real code | Prototype equivalent | Status |
|---|---|---|---|---|
| 132 | Disabled / unconfigured states + setup-key entry | `lib/ui/pages/ai_chat/ai_chat_page.dart:151-200` | `js/views/chat.js:22-42` | Covered |
| 133 | Send / retry (no prompt chips; the empty state is one example line) | `lib/ui/pages/ai_chat/ai_chat_page.dart:119-138, 188-192, 394-413` | prompt chips, `js/views/chat.js:50-59, 92-103` | Partial |
| 134 | Clear chat with confirm | `lib/ui/pages/ai_chat/ai_chat_page.dart:85-123, 170` | none | Missing |
| 135 | Latest-answer quick actions: Add Event / Add Task / Schedule / Break Down | `lib/ui/pages/ai_chat/ai_chat_page.dart:290-362` | proposal card apply/reject, `js/views/chat.js:110-142` | Partial |
| 136 | Schedule confirmation + calendar picker | `lib/ui/pages/ai_chat/ai_chat_page.dart:439-471` | none | Missing |
| 137 | Task breakdown | `lib/ui/pages/ai_chat/ai_chat_page.dart:702-792` | none | Missing |

Platform/integration surfaces (widget deep links, notification actions, changelog dialog, Android back,
web URL state) are enumerated once, in §1.1 rows 9-15, and are not repeated here.

---

## 2. Genuine gaps, most important first

1. **`/quick-add` is a real in-app surface and the prototype has nothing.**
   Route `lib/core/router/app_router.dart:249-264`; desktop entry `lib/ui/shell/spark_top_bar.dart:148-151`;
   widget entry `lib/infrastructure/platform/home_widget_interactivity.dart:56-58`.
   The overlay owns a Chinese-only natural-language parser (`lib/ui/pages/todo/quick_add_page.dart:1075-1261`),
   an event-if-there-is-a-time / todo-otherwise rule (`:86-94`), and two save destinations on phone
   (`:441-467`). `COVERAGE.md` §7 files this under "platform integration", which was true in v0.29.0
   but is no longer true: it is now a first-class creation surface on desktop.

2. **The desktop shell the prototype models does not exist, and the shell that does exist is unmodeled.**
   v0.34.0 has no sidebar at all (`lib/ui/shell/workspace_scaffold.dart:19-23`); the prototype's 200px
   rail (`js/app.js:124-179`) is the v0.29.0 shell. The real app has two different desktop bars:
   `_DesktopBar` on home (`lib/ui/pages/home/home_page.dart:1097-1256`) and `SparkTopBar` on every
   pushed route (`lib/ui/shell/spark_top_bar.dart:98-163`), with different nav order and controls
   (Day/Week/Month segment, Now/Next up, sync badge, Quick add, avatar). A prototype that keeps the
   rail will teach a layout the product no longer has.

3. **Settings desktop navigation.** Real: 200px internal nav, 640 content column, sectioned
   (`lib/ui/pages/settings/settings_page.dart:139-232`). Prototype: one long scroll with anchor jumps
   (`js/views/settings.js:14-217`). This is the same breakpoint the prototype's split layout targets,
   so the mismatch is visible exactly where the prototype is most used.

4. **今天's tail sections are three, not two.** Missed (`today_page.dart:1069-1119`), Earlier today
   (ended timed items, `:1121-1139`) and Completed Today (`:1141-1168`) are distinct heads with
   distinct semantics. The prototype folds missed recurring instances into Overdue and completed work
   into Earlier today (`js/views/action.js:166-197`), erasing the difference between "a recurring
   instance you never did", "a meeting that ended" and "work you finished".

5. **Undo is pinned inline in the row, not a toast.** `lib/ui/pages/home/today_page.dart:364-393, 1485, 1581`.
   The prototype uses a toast with an undo action (`js/views/action.js:106-108`), which disappears and
   cannot be reached by keyboard focus in the row.

6. **By-date Plan Bar is missing.** `lib/ui/pages/todo/a2_todo_page.dart:847-866` swaps the capture bar
   for "Plan this day" on the dated view; it is the only entry into the composer's schedule mode
   (`lib/ui/pages/home/home_page.dart:580`; `lib/ui/pages/todo/a2_composer.dart:835-847`). The prototype
   has no plan-a-day affordance.

7. **Filtering is a sheet with three axes, not tag chips.** `lib/ui/pages/home/home_page.dart:918-1092`:
   calendar, tag, priority, hide-completed, Clear/Done, plus an active-filter count badge. The
   prototype's tag chips + hide-completed menu (`js/views/todo.js:473-483, 552`) covers one axis.

8. **Composer promises and recovery are missing.** Recommended slots
   (`lib/ui/pages/todo/a2_composer.dart:496-506, 958-999`), the primary label that names every field
   the save writes (`:508-544`), and in-sheet write-failure retry (`:796-808`). The prototype's button
   says "Save" (`js/views/composer.js:194`), which is the exact ambiguity v0.34.0 fixed.

9. **Recurring-event scope is consistent only in the prototype; the app asks in one place out of four.**
   Detail delete asks (`lib/ui/pages/event/event_detail_page.dart:862-983`); the form does not
   (`lib/ui/pages/event/event_form_page.dart:440-498`); drag does not
   (`lib/ui/pages/calendar/a2_calendar_views.dart:1578-1700`); inline edit writes the whole series
   (`lib/ui/pages/event/event_detail_page.dart:828-860`). The prototype centralizes the question
   (`js/event-ops.js:14-120`), which is the better model. Record these as app defects to fix, not as
   coverage gaps to close in the prototype.

10. **Calendar behaviours with no prototype counterpart.** Desktop month double-tap creates at the next
    hour (`a2_calendar_views.dart:607-616`); phone month only drills when the day has entries
    (`a2_calendar_page.dart:130-152`); the slot sheet's third action "New & schedule" plus candidate
    count / loading / failed / empty (`lib/ui/widgets/calendar/calendar_slot_sheet.dart:85-124, 262-333`);
    dawn fold (`a2_calendar_views.dart:980-1010, 1047-1074`); initial ~08:00 scroll and back-to-now
    (`:1076-1100, 1750-1944`).

11. **Detail is more editable than modeled.** Inline autosave title/notes
    (`lib/ui/pages/todo/todo_detail_page.dart:264-320, 603-655`), status toggle (`:182-226`), reminder
    add/edit/remove (`lib/ui/widgets/reminder/reminders_section.dart:36-382`), attachment open/delete
    (`lib/ui/widgets/attachment_list.dart:65-355`), and the deleted / failure-retry states
    (`lib/ui/pages/todo/todo_detail_page.dart:155-170, 1198-1232`).

12. **Form-only capabilities.** AI parse (`todo_form_page.dart:689-754`; `event_form_page.dart:525-573`),
    completion draft row (`todo_form_page.dart:930-951`), legacy-recurrence repair
    (`:1145-1198`), invalid-range save disabled (`event_form_page.dart:685-692`).

13. **Settings states and gates.** Account load error + retry (`account_section.dart:87-131`); Language
    System option (`appearance_section.dart:45-50`); Theme System option (`:65-75`); notification rows
    gated by platform (`notifications_section.dart:38-86`, `settings_page.dart:308-312`); AI tutorial
    link and Open-assistant gating (`ai_section.dart:26-73`); Detect models / Remove config
    (`ai_config_dialog.dart:108, 239`); import target-calendar sheet (`import_export_section.dart:137-190`).

14. **Search and AI-chat affordances.** Search: Unplanned suggestions
    (`search_page.dart:711-740`), paging (`:687-711`), keyboard selection (`:183-188`).
    Chat: clear with confirm (`ai_chat_page.dart:85-123`), four quick actions (`:290-362`),
    schedule confirm (`:439-471`), task breakdown (`:702-792`). The chat empty state is a single
    example line (`:188-192`), while the prototype offers three clickable prompt chips
    (`js/views/chat.js:50-59`).

15. **Platform behaviours with no prototype surface.** Notification actions
    (`home_page.dart:395-436`), changelog dialog (`:365-393`), Android back (`:528-537`),
    web URL state (`:320-363`).

16. **The home header lost its create control between the two versions, and the prototype still models it.**
    In v0.29.0 the home chrome carried New Task / New Event in the app bar and desktop page header
    (`research/APP_SURFACE.md` §2.2, citing `home_page.dart:457, 581, 770-814`). In v0.34.0 the 今天 head
    carries only search and settings (`lib/ui/pages/home/today_page.dart:608-625`), so capture is the only
    create path on that destination; 待办 has capture plus the Plan Bar, and 日历 has its own New Event
    (`lib/ui/pages/calendar/a2_calendar_page.dart:299-306, 384-385, 508-509`). This is why the
    prototype's neutral 新建 chooser (`js/views/action.js:53-68`) is scored prototype-only rather than
    missing: it models the v0.29.0 affordance, and v0.34.0 dropped it. Decide which behaviour the product
    wants before changing either side.

---

## 3. Intentional omissions (`COVERAGE.md` §7) — still legitimate?

| Item | Verdict for v0.34.0 |
|---|---|
| Desktop master-detail | No longer an omission; prototype implements it (`js/app.js:102-118`). Real app matches at ≥1180 on 待办 only (`lib/ui/pages/home/home_page.dart:574-576, 854-908`). Correct. |
| Create inside the month view | Still defensible on touch, but **wrong for desktop**: double-tapping an empty month cell creates an event at the next hour (`lib/ui/pages/calendar/a2_calendar_views.dart:607-616`). Should be narrowed to "phone", not "month view". |
| Widget deep link `dayspark://quick-add` | The *link* is still platform integration, but the destination is not: `/quick-add` is an in-app desktop surface (`lib/core/router/app_router.dart:249-264`). The omission now hides a real screen. |
| Legacy recurrence repair | Still defensible for a prototype with no legacy rows. The real flow exists (`todo_form_page.dart:1145-1198`). |
| Real attachment upload / ICS parse / sync | Still defensible (mocked in the prototype). |
| Notification tap navigation / snooze persistence | **Reason is stale.** The claim "the real code is currently broken" was not verified; the handler exists at `lib/ui/pages/home/home_page.dart:395-436`. Either verify the defect or drop the claim; the surface itself remains reasonably out of scope. |
| Clear-AI-chat button | **No longer defensible.** Real app has it with a confirm (`lib/ui/pages/ai_chat/ai_chat_page.dart:85-123`). |

---

## 4. Prototype-modeled items that are not in v0.34.0

Two kinds, kept apart because the remedy differs.

### 4a. Surfaces the app does not have

Remove these, or label them explicitly as proposals. They must not be counted as coverage.

| Prototype surface | Where | Why it does not exist |
|---|---|---|
| Persistent 200px desktop rail (and 232px in `APP_SURFACE.md`) | `js/app.js:124-179`; `js/util.js:113, 116` | No sidebar in v0.34.0 (`lib/ui/shell/workspace_scaffold.dart:19-23`). |
| Todo row context menu (edit / schedule / deadline / tags / subtask / edit series / select / delete) | `js/views/todo.js:173-191` | Rows carry an inline Schedule/Undo action only (`lib/ui/pages/todo/a2_todo_page.dart:1179-1209`). |
| Multi-select + batch complete/delete | `js/views/todo.js:306-362` | No selection model in the app. |
| Drag reorder of todos | `js/views/todo.js:121-162` | Not implemented. |
| Swipe to delete/complete | `js/views/todo.js:33-35, 78-106` | Not implemented. |
| In-page tag filter chips | `js/views/todo.js:552` | Filtering is the home-injected sheet (`lib/ui/pages/home/home_page.dart:918-1092`). |
| Calendar block resize, cross-day drag, block context menus | `js/views/calendar.js:391-429, 484-626` | Real drag is long-press vertical move, 30-min snap (`a2_calendar_views.dart:1578-1700`). |
| 今天 rhythm bar 06:00–24:00 | `js/ui.js:269-300` | No such component in v0.34.0. |
| Search scopes all / todos / events | `js/views/search.js:30-34` | Search always queries both; no scope UI (`lib/ui/pages/search/search_page.dart`). |
| Feedback type chips + simulated send | `js/views/library.js:339-376` | Real feedback is free text + copy + open GitHub issue (`feedback_page.dart:39-115`). |
| About "Open source" / "Privacy" rows with toast placeholders | `js/views/library.js:316-331` | Real About has Star on GitHub / Report an Issue / licenses (`about_page.dart:320-336`). |
| "States & edge cases" review bench | `js/views/misc.js`; `js/views/settings.js:206-211` | Prototype-only review tool. |
| Feedback row inside Settings | `js/views/settings.js:205` | Moved: About → Report an Issue (`about_page.dart:327`). |
| "Show lunar dates" setting | `js/views/settings.js:87`; `js/store.js:23` | No lunar setting in v0.34.0. `ChineseCalendarService` exists (`lib/domain/services/chinese_calendar_service.dart:14-32`) but is referenced by no UI file. |
| `weekStartsOn` preference | `js/store.js:22, 874` | No user preference; weeks start from `calWeekStart` (`a2_calendar_page.dart:262`). |

### 4b. Interaction shapes that differ (already scored in §1)

These model a real operation, but in a shape the app does not use. They are the cause of the
corresponding Partial/Missing rows above, listed here so the shape itself is not mistaken for coverage.

| Prototype shape | Where | Real shape | Row |
|---|---|---|---|
| Capture toast with undo | `js/views/action.js:106-108` | Plain toast; undo is pinned in the row (`today_page.dart:144, 160-170, 364-393`) | 18, 27 |
| Settings as one anchored scroll page | `js/views/settings.js:14-217` | Desktop 200px internal nav + 640 column (`settings_page.dart:139-232`) | 106 |
| One composer with an explicit Todo/Event type switch | `js/views/composer.js:69-460` | Three creation surfaces: composer sheet, `/quick-add` overlay, full forms | 67-78 |
| Generic "Save" as the composer's primary label | `js/views/composer.js:194` | Label names every written field (`a2_composer.dart:508-544`) | 75 |

Also worth recording (not prototype items): `lib/ui/pages/settings/settings_sections/todos_section.dart`
(Six Things + Hide completed) is dead code — not registered in `settings_page.dart:98-106` — so it is
not a user-reachable surface and is correctly absent from the prototype. The same is true of
`lib/ui/shell/workspace_sidebar.dart`: `WorkspaceSidebar` is declared at `:21-22` and referenced nowhere
else in `lib/`, so the v0.29.0 rail survives only as dead code. That is why the prototype's rail is scored
prototype-only rather than as a missing real surface.

---

## 5. Counts

137 real-app surfaces/operations enumerated in §1 (platform/integration surfaces are folded into §1.1
rather than counted twice).

| Status | Count |
|---|---|
| Covered | 48 |
| Partial | 61 |
| Missing | 24 |
| Intentional-out | 2 |
| Prototype-only | 2 |
| **Total** | **137** |

By area (covered / partial / missing / intentional / prototype-only):

| Area | Rows | C | P | M | I | PO |
|---|---|---|---|---|---|---|
| Shell, nav, routing, platform | 15 | 2 | 7 | 5 | 1 | 0 |
| 今天 Today | 18 | 9 | 8 | 0 | 0 | 1 |
| 待办 Todos | 12 | 3 | 8 | 1 | 0 | 0 |
| 日历 Calendar | 21 | 8 | 10 | 2 | 0 | 1 |
| Creation surfaces | 22 | 9 | 4 | 8 | 1 | 0 |
| Details | 16 | 8 | 7 | 1 | 0 | 0 |
| Settings | 17 | 5 | 10 | 2 | 0 | 0 |
| Libraries (tags/calendars/trash/about/feedback) | 5 | 3 | 2 | 0 | 0 | 0 |
| Search | 5 | 0 | 3 | 2 | 0 | 0 |
| AI assistant | 6 | 1 | 2 | 3 | 0 | 0 |

The two prototype-only rows are the neutral create chooser on 今天 and the calendar legend. §4 separately
lists prototype surfaces that are not real v0.34.0 surfaces at all (rail, row menus, multi-select, drag
reorder, swipe, block resize, rhythm bar, search scopes, lunar/week-start settings, and so on); those are
not table rows and are not counted here.

The two intentional-out rows are widget/OS deep links and legacy-recurrence repair. The remaining
`COVERAGE.md` §7 items correspond to real surfaces that the table already scores as missing or partial
(`/quick-add`, clear chat, notification actions, attachments, month-view creation); §3 judges whether
those omissions still hold.

---

## 6. Verified vs inferred

Verified by reading the real source: every `file:line` citation in §1 and §2. Each route was read in
`lib/core/router/app_router.dart`; each page, sheet, dialog and state branch cited was read in its own
file; every prototype claim was read in `js/`. The g0 tree's `lib/` is byte-identical to the cited
v0.34.0 commit (`diff -rq` against `../dayspark-g1/lib` was empty).

Inferred, not observed:

- **Runtime reachability.** I did not launch the app. "Reachable" means a code path exists from a
  cited entry control; I did not confirm that any path is dead at runtime.
- **Numeric caps** quoted as "max 2" / "3" / "cap 3" come from constants and `.take(n)` calls at the
  cited lines, not from rendering.
- **Whether the notification-action path works.** `COVERAGE.md` §7 says it is broken; the handler exists
  at `home_page.dart:395-436`, but I did not test the platform channel, so I neither confirmed nor
  refuted the defect.
- **Platform-specific rendering.** Notification gating was read from `defaultTargetPlatform` switches
  (`notifications_section.dart:38-86`); I did not run Android, iOS or macOS builds.
- **Prototype visuals.** Statuses are based on the prototype's JS logic and entry controls, not on
  rendering it in a browser.

One judgement call worth naming: the calendar legend row is scored prototype-only on the evidence that
`calendarLegendEvent` / `calendarLegendAllocation` exist in l10n (`lib/l10n/app_en.arb:729-730`) but no
Dart file outside the generated `app_localizations*.dart` reads them — a grep over `lib/` and `test/`
found no other reference — and no legend widget exists under `lib/ui/pages/calendar/` or
`lib/ui/widgets/calendar/`. If a legend is rendered from somewhere else, this row is wrong.
