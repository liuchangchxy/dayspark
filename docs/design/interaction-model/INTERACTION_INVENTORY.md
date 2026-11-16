# User-visible Interaction Inventory — frozen coverage denominator

Baseline: DaySpark v0.34.0+34 (`pubspec.yaml`), `main` @ `7390987`.
Sources of truth for this list: `research/APP_SURFACE_V034.md` (real-app inventory, `file:line`)
and `COVERAGE_AUDIT_V034.md` (137-row audit). This document **freezes** which of those rows are
counted as coverage for G0, and how each is classified.

## Rules

1. **Only real, user-reachable v0.34.0 surfaces are in the denominator.** A surface is counted when a
   code path exists from a real entry control to it. Theoretical edge cases are not added.
2. `PROPOSAL` rows are prototype interactions that v0.34.0 does not have. They are **not** part of the
   coverage percentage; they are design proposals listed separately in §3.
3. A reviewer may add a row **once**, with the `file:line` that proves the surface is real and reachable.
   Adding a theoretical state is not allowed.
4. `PLATFORM` rows are surfaces that exist only through the OS shell (widget deep links, Android back,
   web URL, notification actions). They stay in the inventory because they are user-reachable, but
   their interaction is defined at the prototype's states bench rather than as an in-app page.
5. "100% coverage" in this goal means **every row below has a defined design and a reachable path in
   the prototype, or an explicit, reasoned exclusion**. It does not mean pixel parity.

Status vocabulary is the audit's: `C` covered, `P` partial, `M` missing at audit time, `OUT` intentional
exclusion. The "G0 resolution" column records what the prototype now does after the audit was closed.

---

## 1. Frozen inventory

### A — Shell, navigation, routing (domain A)

| ID | Surface / interaction | Real source | Prototype path | Audit | G0 resolution |
|---|---|---|---|---|---|
| INV-001 | Home `/` with 今天 / 日历 / 待办 as primary destinations | `lib/core/router/app_router.dart:233-248`; `lib/ui/pages/home/home_page.dart:448-523` | rail + bottom nav | C | covered |
| INV-002 | `/quick-add` in-app creation surface | `app_router.dart:249-264`; `lib/ui/shell/spark_top_bar.dart:148-151` | `quickadd` view, rail / More / `Q` | M | covered |
| INV-003 | Desktop shell chrome (top bar; v0.34.0 has no sidebar) | `lib/ui/shell/workspace_scaffold.dart:14-23, 35-63` | 200px rail (SPEC §1.3 mandates a sidebar) | P | SPEC overrides code — see `design/decisions.md` |
| INV-004 | Desktop home bar (nav, date arrows, clock, capture, search) | `home_page.dart:1097-1256` | unified page head | P | covered by page head |
| INV-005 | Desktop pushed-route bar (brand, date nav, Now/Next, search, Day/Week/Month, quick add, sync, avatar) | `spark_top_bar.dart:98-163, 310-330, 394-437, 606-644` | rail + page head; no second bar | P | single shell by design |
| INV-006 | Mobile dock 今天 / 日历 / 待办 | `home_page.dart:1394-1440` | bottom nav + More | P | covered (More added) |
| INV-007 | Mobile page heads (search + settings + create) | `lib/ui/pages/home/today_page.dart:608-625`; `lib/ui/pages/todo/a2_todo_page.dart:452-458` | header action row | P | covered |
| INV-008 | Search shortcut (Ctrl/Cmd+K on desktop, `/` in prototype) | `workspace_scaffold.dart:38-48`; `home_page.dart:486-496` | `/` shortcut | P | covered |
| INV-009 | Android back returns to 今天 | `home_page.dart:528-537` | browser back + leave guard | M | PLATFORM — behaviour defined, OS key out of scope |
| INV-010 | Widget / OS deep links | `lib/infrastructure/platform/home_widget_interactivity.dart:14-75` | destination only | OUT | PLATFORM |
| INV-011 | Unknown-route / missing-record error page | `app_router.dart:195-231` | missing-record page | P | covered |
| INV-012 | Web URL carries tab + browsed date | `home_page.dart:320-363` | in-memory router | M | PLATFORM |
| INV-013 | Startup changelog dialog on version change | `home_page.dart:365-393` | About → release notes | M | entry defined, not auto-shown |
| INV-014 | Notification actions (complete / snooze) | `home_page.dart:395-436` | states bench card | M | PLATFORM — behaviour defined |
| INV-015 | Esc clears master-detail pane before leaving | `home_page.dart:542-552` | `app.js` Esc ladder | C | covered |
| INV-016 | Desktop master-detail ≥1180 on 待办 only | `home_page.dart:574-576, 854-908`; `lib/ui/shell/workspace_navigation.dart:91-94` | `.todos-masterdetail` | C | covered (SPEC §4) |

### B — 今天 Today (domain B)

| ID | Surface / interaction | Real source | Prototype path | Audit | G0 resolution |
|---|---|---|---|---|---|
| INV-017 | Today reads the clock only; no date switcher | `today_page.dart:26-29, 608-625` | fixed `actionDate` | C | covered |
| INV-018 | Capture bar: Enter files an unplanned Todo | `today_page.dart:119-158, 670-684` | capture row | C | covered |
| INV-019 | Capture feedback | toast only `today_page.dart:144, 160-170` | toast + inline row undo | P | covered |
| INV-020 | Neutral 新建 chooser (待办 / 日程) | absent in v0.34.0 (`today_page.dart:608-625`) | create chooser | PROPOSAL | proposal, SPEC §3.1 |
| INV-021 | 现在 section | `today_page.dart:888-917` | now section | C | covered |
| INV-022 | 接下来 (recurring instances included) | `today_page.dart:919-989` | later section | P | covered |
| INV-023 | 今天截止 | `today_page.dart:991-1014` | due section | C | covered |
| INV-024 | 已逾期 with expand | `today_page.dart:1016-1067` | overdue section | C | covered |
| INV-025 | 遗漏的重复 as its own section | `today_page.dart:1069-1119` | missed section | P | covered |
| INV-026 | 今天早些时候 (ended timed items) | `today_page.dart:1121-1139` | earlier section | C | covered |
| INV-027 | 今天完成 as its own section | `today_page.dart:1141-1168` | completed section | P | covered |
| INV-028 | Pinned inline undo on the completed row | `today_page.dart:364-393, 1485, 1581` | inline undo, 8s | P | covered |
| INV-029 | Complete / reopen with occurrence resolution | `today_page.dart:206-325` | `todo-ops.js` | C | covered |
| INV-030 | 未安排 shelf: preview 3 + count entry | `today_page.dart:540-555, 558-599, 768-816` | unplanned preview | C | covered |
| INV-031 | Loading / error / stale retry | `today_page.dart:444-527` | states bench | P | covered |
| INV-032 | Desktop two-column Today (max 1240) | `today_page.dart:692-822` | single column | P | design difference, recorded |
| INV-033 | Row meta merges plan + deadline; inline schedule chip | `today_page.dart:1349-1502, 1468-1482` | merged meta | P | covered |
| INV-034 | Mobile unplanned preview limited to no-deadline items | `today_page.dart:540-555` | same rule | C | covered |
| INV-035 | 今日节奏条 06:00–24:00 | absent in v0.34.0 | rhythm bar | PROPOSAL | proposal |

### C — 待办 Todos (domain C)

| ID | Surface / interaction | Real source | Prototype path | Audit | G0 resolution |
|---|---|---|---|---|---|
| INV-036 | Mode switch 未安排 / 全部待办 / 按日期 | `a2_todo_page.dart:430-515, 551-656` | mode chips | P | covered |
| INV-037 | By-date strip: today chip, month/year picker, prev/next | `a2_todo_page.dart:703-804` | week strip + picker | P | covered |
| INV-038 | 未安排 body sections | `a2_todo_page.dart:890-944` | sections | P | covered |
| INV-039 | 全部待办 body sections | `a2_todo_page.dart:964-1051` | sections | P | covered |
| INV-040 | By-date body (planned / deadline / events) | `a2_todo_page.dart:1081-1162` | sections | P | covered |
| INV-041 | Capture bar on 未安排 / 全部待办 | `a2_todo_page.dart:847-866` | inline input | C | covered |
| INV-042 | By-date 计划这一天 → schedule-mode composer | `a2_todo_page.dart:847-866`; `lib/ui/design/a2.dart:682` | plan-bar | M | covered |
| INV-043 | Row action Schedule / Undo | `a2_todo_page.dart:1179-1209` | row menu + inline undo | P | covered |
| INV-044 | Filter & display sheet: calendar / tag / priority / hide completed / clear / count badge | `home_page.dart:918-1092` | three-axis sheet | P | covered |
| INV-045 | Per-mode empty states | `a2_todo_page.dart:909, 1011, 1108` | empty states | C | covered |
| INV-046 | Loading / error | `a2_todo_page.dart:338, 877-888` | states bench | P | covered |
| INV-047 | Row context menu | absent in v0.34.0 | row menu | PROPOSAL | proposal |
| INV-048 | Multi-select batch complete / delete | absent | selection mode | PROPOSAL | proposal |
| INV-049 | Drag reorder by grip | absent | grip drag | PROPOSAL | proposal |
| INV-050 | Swipe left delete / right complete | absent | touch swipe | PROPOSAL | proposal |

### D — 日历 Calendar (domain D)

| ID | Surface / interaction | Real source | Prototype path | Audit | G0 resolution |
|---|---|---|---|---|---|
| INV-051 | Browse date shared with 待办 · 按日期 | `a2_calendar_page.dart:60-63`; `workspace_navigation.dart:31-54` | `browseDate` | C | covered |
| INV-052 | Prev/next per mode (month keeps day-of-month, clamped) | `a2_calendar_page.dart:66-81` | pager | P | covered |
| INV-053 | Go to today | `a2_calendar_page.dart:84-86` | today button | C | covered |
| INV-054 | View switch Month / Week / Day | `a2_calendar_page.dart:95-128, 463-516` | segmented | C | covered |
| INV-055 | Phone month tap drills only when the day has entries | `a2_calendar_page.dart:130-152` | same rule | P | covered |
| INV-056 | Desktop month double-tap empty slot → new event at next hour | `a2_calendar_views.dart:607-616` | double-tap | M | covered |
| INV-057 | Phone month strip | `a2_calendar_page.dart:314-320`; `a2_calendar_views.dart:147-200` | month grid | P | covered |
| INV-058 | Phone month dots + count with a11y label | `a2_calendar_views.dart:240-445` | dots + `+n` | C | covered |
| INV-059 | Desktop month chips (3 + overflow) | `a2_calendar_views.dart:447-684` | chips | C | covered |
| INV-060 | Deadline lane (never drawn as time blocks) | `a2_calendar_views.dart:1193-1292` | lane | C | covered |
| INV-061 | All-day lane | `a2_calendar_views.dart:1320-1421` | all-day row | P | covered |
| INV-062 | Time-grid drag (vertical, snap) | `a2_calendar_views.dart:1578-1700` | drag, 15-min snap | P | covered (finer snap) |
| INV-063 | Drag a recurring event → scope question | app moves with no question | scope sheet | C | covered (better model) |
| INV-064 | Dawn fold 00:00–06:00 | `a2_calendar_views.dart:980-1010, 1047-1074` | fold toggle | M | covered |
| INV-065 | Initial scroll ≈08:00 | `a2_calendar_views.dart:1076-1100, 1780` | initial scroll | P | covered |
| INV-066 | Sticky now strip + back-to-now | `a2_calendar_views.dart:1750-1944` | now line + button | P | covered |
| INV-067 | Slot sheet: New Event / New & schedule / Schedule task + candidate count, loading, failed, empty | `lib/ui/widgets/calendar/calendar_slot_sheet.dart:85-124, 262-333` | three-job sheet | P | covered |
| INV-068 | Schedulable-todo picker + recurring occurrence picker | `calendar_slot_sheet.dart:335-495` | pickers | P | covered |
| INV-069 | Phone create placement (outside month vs in month) | `a2_calendar_page.dart:273-392` | header create | P | design difference |
| INV-070 | Calendar legend (event / planned / deadline) | l10n keys only, no widget | legend | PROPOSAL | proposal |
| INV-071 | Desktop calendar head (today / prev / next / new event / segmented) | `a2_calendar_page.dart:463-516` | head | C | covered |
| INV-072 | Block resize / cross-day drag / block context menu | absent in v0.34.0 | resize + menu | PROPOSAL | proposal |

### E — Composer / creation (domain E)

| ID | Surface / interaction | Real source | Prototype path | Audit | G0 resolution |
|---|---|---|---|---|---|
| INV-073 | Composer chrome (desktop dialog vs phone sheet) | `lib/ui/pages/todo/a2_composer.dart:33-63` | full page | P | design difference |
| INV-074 | Create mode vs schedule mode | `a2_composer.dart:119-148, 835-847` | schedule sheet | P | covered |
| INV-075 | Deadline row with date-only / date-time | `a2_composer.dart:197-229` | deadline sheet | C | covered |
| INV-076 | Custom slot start/end | `a2_composer.dart:231-261` | slot fields | C | covered |
| INV-077 | Reminder picker | `a2_composer.dart:270-317` | reminders | C | covered |
| INV-078 | Calendar picker: always opens, colour + name + selected, + new calendar, loops back | `a2_composer.dart:319-322`; `lib/ui/widgets/calendar/calendar_picker.dart:27-50, 120-198` | picker | C | covered |
| INV-079 | Priority 0/1/5/9 | `a2_composer.dart:324-346` | priority | C | covered |
| INV-080 | Recommended slot grid | `a2_composer.dart:496-506, 958-999` | suggestions | M | covered |
| INV-081 | Primary label names every field the save writes | `a2_composer.dart:508-544` | dynamic label | M | covered |
| INV-082 | Write-failure retry inside the sheet | `a2_composer.dart:796-808` | inline retry | M | covered |
| INV-083 | Open full form carrying due/start/end/summary | `a2_composer.dart:68-83, 348-361` | edit route | C | covered |
| INV-084 | `/quick-add` NL parse: event if a time, else todo | `lib/ui/pages/todo/quick_add_page.dart:25-31, 86-201, 356-477, 1075-1261` | quick-add view | M | covered |
| INV-085 | Full Todo form section order + repeat + execution + reminders + calendar + priority + tags + notes + subtasks + attachments | `lib/ui/pages/todo/todo_form_page.dart:857-1098` | composer sections | P | covered |
| INV-086 | AI parse in the Todo form | `todo_form_page.dart:689-754, 842` | AI parse row | M | covered |
| INV-087 | Dirty-draft discard guard | `todo_form_page.dart:758-789` | leave guard | C | covered |
| INV-088 | Completion row in the form | `todo_form_page.dart:930-951` | status row | M | covered |
| INV-089 | Form delete with undo | `todo_form_page.dart:1414-1470` | delete + undo | C | covered |
| INV-090 | Legacy recurrence notice + repair | `todo_form_page.dart:1145-1198`; `todo_detail_page.dart:271-273, 802-819` | — | OUT | OUT (no legacy rows in a prototype) |
| INV-091 | Event form (save transaction, boundary pickers, calendar) | `lib/ui/pages/event/event_form_page.dart:226-350, 500-629, 632-693` | event composer | P | covered |
| INV-092 | Event delete scope | `event_form_page.dart:440-498` | `event-ops.js` | C | covered |
| INV-093 | Event form invalid range disables save | `event_form_page.dart:685-692` | validation | M | covered |
| INV-094 | AI parse in the Event form | `event_form_page.dart:525-573` | AI parse | M | covered |
| INV-095 | Quick Create (title / deadline / calendar / more) | SPEC §4.2 | quick/full modes | PROPOSAL | proposal (SPEC) |

### F — Detail (domain F)

| ID | Surface / interaction | Real source | Prototype path | Audit | G0 resolution |
|---|---|---|---|---|---|
| INV-096 | Todo detail inline title + notes editing | `todo_detail_page.dart:264-320, 603-655` | read-only + explicit edit | P | deliberate difference (DIFF D1) |
| INV-097 | Todo status toggle | `todo_detail_page.dart:182-226` | status control | P | covered |
| INV-098 | Detail section order 时间 / 提醒 / 整理 / 内容 | `todo_detail_page.dart:264-320` | same order | C | covered |
| INV-099 | Deadline inline + clear | `todo_detail_page.dart:518-541` | inline fact | C | covered |
| INV-100 | Execution schedule + repeat inline (add / reschedule / cancel with undo) | `todo_detail_page.dart:274-287`; `lib/ui/widgets/schedule/execution_schedule_section.dart:53-268` | schedule facts | P | covered |
| INV-101 | Reminders add / edit / remove | `todo_detail_page.dart:290-294`; `lib/ui/widgets/reminder/reminders_section.dart:36-382` | reminder sheet | P | covered |
| INV-102 | Calendar / priority / tags inline | `todo_detail_page.dart:543-601, 939-950` | inline facts | C | covered |
| INV-103 | Subtasks + add | `todo_detail_page.dart:821-937` | subtask list + add | C | covered |
| INV-104 | Attachments add / open / delete, local-only note | `todo_detail_page.dart:320`; `lib/ui/widgets/attachment_list.dart:65-355` | filename chips | P | covered (mock) |
| INV-105 | Footer Complete / Schedule (disabled reason) / Edit / Move to Trash | `todo_detail_page.dart:657-780` | footer | C | covered |
| INV-106 | Deleted state + write-failure retry | `todo_detail_page.dart:155-170, 1198-1232` | deleted banner + retry | M | covered |
| INV-107 | Event detail inline start/end/duration/all-day/calendar/location/title | `lib/ui/pages/event/event_detail_page.dart:256-515` | event facts | P | covered |
| INV-108 | Event repeat + series notice | `event_detail_page.dart:217-235` | repeat fact | P | covered |
| INV-109 | Event delete scope dialog | `event_detail_page.dart:862-983` | scope sheet | C | covered |
| INV-110 | Inline edit of an event occurrence | `event_detail_page.dart:828-860` | split occurrence | C | covered |
| INV-111 | Event footer Edit / Move to Trash | `event_detail_page.dart:601-645` | footer | C | covered |
| INV-112 | Occurrence list on a recurring Todo | absent in v0.34.0 | instance list | PROPOSAL | proposal |

### G — Tools: search / tags / calendars / trash / about / feedback (domain G)

| ID | Surface / interaction | Real source | Prototype path | Audit | G0 resolution |
|---|---|---|---|---|---|
| INV-113 | Search: debounce, todo + event results | `lib/ui/pages/search/search_page.dart:32-188, 376-382` | search | P | covered |
| INV-114 | Paged results + load more | `search_page.dart:512-711` | load more | P | covered |
| INV-115 | Empty-query suggestions from 未安排 | `search_page.dart:711-740` | suggestions | M | covered |
| INV-116 | Keyboard ↑↓ / Enter / Esc | `search_page.dart:183-188` | keyboard | M | covered |
| INV-117 | Failure retry / no results | `search_page.dart:451` | retry + empty | P | covered |
| INV-118 | Tags: list + counts, create/edit name + colour, delete confirm | `lib/ui/pages/tags/tags_page.dart:33-317` | tags page | C | covered |
| INV-119 | Calendars: list + counts, create/edit, delete with move-vs-delete + last-calendar guard | `lib/ui/pages/calendar/calendars_page.dart:24-373` | calendars page | C | covered |
| INV-120 | Trash: restore / permanent delete / empty | `lib/ui/pages/trash/trash_page.dart:31-362` | trash page | C | covered |
| INV-121 | About: update check, rate-limit/error, no releases, release notes, star, report issue, licences | `lib/ui/pages/about/about_page.dart:54-336` | about page | P | covered |
| INV-122 | Feedback: text, copy, submit on GitHub | `lib/ui/pages/feedback/feedback_page.dart:39-115` | feedback page | P | covered |

### H — Settings (domain H)

| ID | Surface / interaction | Real source | Prototype path | Audit | G0 resolution |
|---|---|---|---|---|---|
| INV-123 | Section registry: 通用 / 日历 / 同步 / 数据 / AI 助手 / 通知与提醒 / 关于 | `lib/ui/pages/settings/settings_page.dart:98-106` | settings sections | P | covered |
| INV-124 | Desktop 200px internal nav + 640 content column | `settings_page.dart:139-232` | section nav + column | M | covered |
| INV-125 | Language: System / 中文 / English | `settings_sections/appearance_section.dart:45-50, 119-124` | three options | P | covered |
| INV-126 | Startup view: 今天 / 日历 / 待办 | `appearance_section.dart:52-63, 136-141` | startup row | C | covered |
| INV-127 | Theme: System / Light / Dark | `appearance_section.dart:65-75` | three options | P | covered |
| INV-128 | Accent swatches | `appearance_section.dart:92-104` | swatches | C | covered |
| INV-129 | Calendar section: 日历管理 + count | `calendar_settings_section.dart:20-23` | row | C | covered |
| INV-130 | Sync signed-out form + validation taxonomy | `account_section.dart:136-213, 374-384` | sync form | P | covered |
| INV-131 | Account load error + retry | `account_section.dart:87-131` | error + retry | M | covered |
| INV-132 | Sync signed-in: email / status / server / devices / sync now / log out | `account_section.dart:215-283` | signed-in block | C | covered |
| INV-133 | Connected-devices dialog (empty / error / loading) | `account_section.dart:312-355` | devices dialog | P | covered |
| INV-134 | AI section: enable switch + tutorial, config row, open assistant only when ready | `ai_section.dart:26-73` | AI section | P | covered |
| INV-135 | AI config dialog: presets/custom, base URL, masked key, detect models, model pick, remove | `lib/ui/widgets/ai_config_dialog.dart:82-370` | config dialog | P | covered |
| INV-136 | Data: tags + trash counts, import/export group | `data_section.dart:26-44` | data rows | P | covered |
| INV-137 | Import .ics with target calendar; export .ics; full backup; merge backup | `import_export_section.dart:48-229` | data actions | P | covered |
| INV-138 | Notifications: platform-gated rows | `notifications_section.dart:38-86`; `settings_page.dart:308-312` | platform rows | P | covered |
| INV-139 | About row → `/about` | `about_section.dart` | row | C | covered |

### I — Data semantics (domain I)

Domain I is not a surface list; it is the set of invariants every surface above must obey. Frozen set:

| ID | Invariant | Source |
|---|---|---|
| INV-140 | `dueDate` (截止) never becomes execution time and never occupies calendar busy time | SPEC §4.1; `DOMAIN_BEHAVIORS.md` I15.2 |
| INV-141 | `TaskAllocation` (计划执行) never changes `dueDate` and never creates an `Event` | `DOMAIN_BEHAVIORS.md` I15.2 |
| INV-142 | A recurring Todo's parent never reaches COMPLETED; completion is per occurrence | `DOMAIN_BEHAVIORS.md` I15.3 |
| INV-143 | An occurrence id is wall-clock identity; a block can only bind to the occurrence that owns its date | `DOMAIN_BEHAVIORS.md` I15.4 |
| INV-144 | Completion invalidates only allocations with `startAt >= completedAt`; undo restores exactly those | `DOMAIN_BEHAVIORS.md` I15.1 |
| INV-145 | Intervals are half-open (start inclusive, end exclusive) | `DOMAIN_BEHAVIORS.md` I15.8 |
| INV-146 | 未安排 membership is decided by effective planned execution, not `dueDate == null` | SPEC §1.3 / §16.2 |
| INV-147 | Overdue is compared by day, never by instant | `DIFF_VS_FLUTTER.md` H1 |
| INV-148 | Deletion is soft by default; permanent deletion exists only in Trash | `DOMAIN_BEHAVIORS.md` I15.6 |
| INV-149 | Deleting a calendar never orphans items; the last calendar cannot be deleted | `DOMAIN_BEHAVIORS.md` I15.16 |
| INV-150 | An AI proposal writes nothing until the user applies it | `DOMAIN_BEHAVIORS.md` §11 |
| INV-151 | A Todo created from 今天 never silently receives today as its deadline | SPEC §3.2 |

### J — Visual and i18n (domain J)

| ID | Surface / interaction | Source | Prototype | G0 resolution |
|---|---|---|---|---|
| INV-152 | D Final / Direction C tokens: rail `#191C22`, canvas `#F5F6F8`, accent `#2457D6`, 6/8/12 radii | `DESIGN.md` | `css/app.css` tokens | covered |
| INV-153 | Type scale 26 / 15 / 11–13, no font shrinking to fix overflow | `DESIGN.md` | same | covered |
| INV-154 | No gradients, no decorative shadows, no emoji, no AI-style illustration | `DESIGN.md` | same | covered |
| INV-155 | ≥48dp touch targets on mobile | SPEC §8; `DESIGN.md` §7 | 48px rule + probe test | covered |
| INV-156 | zh + en parity, no raw i18n keys, no overflow in either language | `lib/l10n/app_en.arb` + `app_zh.arb` | `js/i18n.js` + key scan | covered |
| INV-157 | Settings groups are dividers, not a card wall | SPEC §8 | divider groups | covered |
| INV-158 | One dominant primary action per surface | SPEC §8 | per-surface primary | covered |
| INV-159 | Three visual anchors: 今天 / 待办 / 日历 pass at 1440 and 390 | goal §1 | anchor surfaces | gate |

---

## 2. Coverage arithmetic

| Bucket | Count | Meaning |
|---|---|---|
| Real surfaces in the denominator | 139 (INV-001…INV-139) | each needs a design + reachable path |
| Semantics invariants (I) | 12 (INV-140…INV-151) | each needs a behaviour contract + evidence |
| Visual/i18n obligations (J) | 8 (INV-152…INV-159) | each needs a check |
| Proposals (not in denominator) | 12 | INV-020, 035, 047, 048, 049, 050, 070, 072, 095, 112 |
| Intentional exclusions | 1 | INV-090 legacy recurrence repair |
| Platform-only (in denominator, defined at the states bench) | 5 | INV-009, 010, 012, 014, and widget deep links |

Coverage is reported as `resolved / 139` for surfaces, `contracted / 12` for invariants, `checked / 8` for visual
obligations. The percentage in the final report is the surface fraction; the other two are pass/fail gates.

---

## 3. Change log

- 2026-11-16 — frozen for G0. Derived from `COVERAGE_AUDIT_V034.md` (137 rows), split into the ten review
  domains, with the audit's prototype-only rows moved to the proposal bucket and its platform rows kept in
  the denominator but flagged `PLATFORM`. INV-140…INV-159 are the semantics and visual obligations the audit
  treated implicitly and are now explicit, because a reviewer cannot audit what is not written down.
