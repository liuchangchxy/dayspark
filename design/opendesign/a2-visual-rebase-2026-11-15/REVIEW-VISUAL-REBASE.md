# Visual Rebase Review — A″ on Direction C

Reviewer: independent visual review. I did not write the prototype.
Target: `C:\Users\chang\AppData\Roaming\Open Design\namespaces\release-stable-win\data\projects\dayspark-a2-production-2026-11-15\`
Ground truth: `C:\Users\chang\AppData\Local\Temp\dayspark-a2\dc\01-chrome.md` … `04-composer-desktop.md` (all numbers below cite the Flutter source through those files) and `ref/dc-*.png`.

**Snapshot note.** The prototype was still being edited while I reviewed (shared.css and screens-*.html changed at 06:55–06:57). I waited for 120 s of no changes, froze a copy at 07:00 (`C:\Users\chang\AppData\Local\Temp\dayspark-a2\review-snap\`, shared.css md5 `8abac24b37dc56fef98b05216f5274b1`), served it on 8128, and re-shot all 18 boards there. Every finding below refers to that frozen copy; every board was rendered twice (two separate Chrome profiles) and the two sets are pixel-identical. Screenshot files live in `C:\Users\chang\AppData\Local\Temp\dayspark-a2\shots\h-*.png`.

---

## (a) Verdicts

1. **是否明显继承 Direction C — Mostly yes.** A user would say "same DaySpark" on mobile Today, 未安排/全部/按日期, the composer, and all three desktop boards; the inherited type, colour, row, checkbox, group-head, chip, sheet and top-bar/work-bar metrics are largely exact. The exception is the mobile month page, which no longer uses C's contained month card.
2. **是否还有"像另一个 App"的页面 — Yes, one board: 12 日历 · 月.** It is edge-to-edge with no 16px gutter, no `surface + 1px line + radius 8` card, no bottom edge, left-aligned weekday headers, and no agenda card below the grid; it reads as a web month table, not the C month card. The desktop 日历 is compositionally different but still C-voiced.
3. **新旧混排是否断层 — Yes, locally.** On Today two different section-head systems coexist (现在/接下来/今天截止/已逾期 use `.tl-sec` with an inline rule and accent counts; 未安排 uses C's `.group-head`); due capsules are inlined into the meta where C keeps a trailing rail; event rows in the by-date lists start on a different left edge than task rows; the composer centres its secondary values.

---

## (b) P0 / P1

P0: none.

| # | Sev | Where | What I actually saw | What Direction C does | Minimal fix |
|---|---|---|---|---|---|
| 1 | **P1** | Board 12, `h-cal-0.png`; `shared.css:669-697`; `screens-calendar.html:48` | 6×7 grid runs from screen edge to screen edge (no 16 px page gutter), has no card border/radius and no bottom hairline, so the last row floats open above the FAB. Weekday labels (一…日) are left-aligned with 8 px padding. No day-agenda card under the grid; the page is header → grid → FAB. Month header is 17/600 centred (`shared.css:665`). | Mobile month = `ListView` padding LTRB 16/4/16/24, grid **container radius 8 + 1px `line` border**, cells 56 high, right/bottom hairlines omitted on last col/row, weekday labels centred, then a bordered agenda card (`03-calendar.md` §2 Mobile; `month:743-787, 766-781, 1001-1014`). Toolbar: title 14/600 left + secondary 11 `ink3` (`section:532-574`). | Put the grid back in the 16 px-padded card (`surface`, 1 px `line`, radius 8); restore right/bottom hairlines and the agenda card; centre the weekday labels; use the 14/600 toolbar. |
| 2 | **P1** | Board 01, `h-today-0.png`; `screens-today.html:117-120` | The 未安排 group head ("未安排 · 8 项 ⌄") is the last element of the list; it is followed by ~80 px of empty paper and then the capture row. Zero preview rows. The board's own note (`screens-today.html:13`) and the desktop board (`h-desk-0.png`) both promise 3 preview rows + "还有 5 项 · 展开全部". | No C analogue for the group itself, but a head with a count and chevron followed by nothing reads as a failed render; C always follows a `DsGroupHead` with rows or nothing (`ds.dart:596-637`). | Render the 3 preview rows + the "还有 5 项 · 展开全部" row (as the desktop panel does), or hide the head entirely when collapsed. Do not leave a bare head over the footer. |

---

## (c) P2 / P3

### P2

| # | Where | What I saw | Direction C | Minimal fix |
|---|---|---|---|---|
| 1 | `h-today-0.png`; `shared.css:424-433` vs `305-318`; `screens-today.html:47,79,92,117` | **Two head systems on one screen.** 现在/接下来/今天截止/已逾期 use `.tl-sec`: accent-coloured 11/600 label, 5 px accent dot, an inline 1 px `line-soft` rule to the right, and a count that inherits the accent ("1 项" amber, "2 项" rust). 未安排 uses `.group-head`: top border, faint dot, faint count, no rule. | Only `DsGroupHead`: 30 high, 18 padding, 1 px `line-soft` **top** border, 5 px `faint`/`danger` dot, 11/600 `ink3`/`danger` label, count 11/400 **`faint`**, no inline rule (`ds.dart:596-632`). | Delete `.tl-sec .rule`; make the label `ink3`/`danger` and the count `faint`; reuse one component for all five heads. |
| 2 | `h-todo-0.png`, `h-todo-1.png`; `shared.css:333-343` | The due capsule paint is right (11/500, radius 4, `surface2`+dot / `dangerSoft`), but it is **inlined in the meta line** after the title, followed by "· 工作". The right edge of every row is empty. | In `TodoListTile` the due capsule is the **trailing** element, preceded by an 8 px gap, right-aligned (`todo_list_tile.dart:133-141`; `ds.dart:759-764`). Meta stays `ink3`. | Move the capsule to `.trail` (right-aligned), keep only meta text in `.meta`. |
| 3 | `h-todo-2.png`, `h-todo-3.png`; `screens-todo.html:238` | In the by-date lists, event titles start at x≈40 while task titles start at x≈80 (after the 48 px check + 12 gap), so one list has two left edges. Event rows have no checkbox. | No mixed list in C, but the list's text column is one column (`TodoListTile` 48 check + 12 gap); a row without a checkbox would still need to align to it. | Indent event rows to the task text column (or give them a 20 px leading marker). |
| 4 | `h-cal-1.png`; `shared.css:709` | Week view: today's column is tinted **only in the 44 px header cell** (radius 6). The grid body of the Sunday column is `#FCFCFA`, same as every other day. | C fills the whole today column with `primaryTint` behind the lines, full height; the header cell itself has no radius (`week:202-210, 425-426`). | Paint a full-height `primaryTint` column background for today before the hour lines. |
| 5 | `h-todo-6.png`, `h-todo-7.png`; `shared.css:613-616`; `screens-todo.html:501-504` | Composer secondary rows put the value in the exact middle of the 338 px row ("所属日历 … 家庭 … ⌄", "优先级 … 普通 … ⌄"). Cause: `justify-content: space-between` with 3 children (label, value, chevron). | C never centres a value: `_PaneFieldRow` is a 62 px label column then the value (left), `DsSettingRow` keeps the value at the right next to the chevron (`todo_detail_page.dart:1244-1337`; `04-composer-desktop.md` §2.7). | `margin-left:auto` on `.c-subrow .sv` and a small gap before the chevron. |
| 6 | `h-todo-5.png`, `h-todo-6.png`; `shared.css:605-609` | The helper sentence under the chips is 12 px **primary** with a ① glyph ("① 这是「计划执行」，不是截止；需要截止请单独设置。"), making it the loudest text in the sheet after the button. | C field help is `small` 12 / `ink3`; colour is reserved for the chip state, not the explanation (`ds.dart:1073-1085`; `04-composer-desktop.md` §2.5). | Set the hint line to `ink3` (danger only for an error); drop the ① or use a 12 px C-style icon. |
| 7 | `h-desk-1.png`; `shared.css:905-913`; `desktop.html:205` | Detail pane: a "字段" section label (a generic placeholder word), then 13 px label rows with 14 px leading icons, values right-aligned, no chevron. | C's pane row: fixed 62 px label column at **11 / ink3**, value 13 / ink, leading widget + 7 gap, `chevron_forward` 13 `faint`, rows 58 desktop / 56 mobile (`todo_detail_page.dart:1244-1337`). No "字段" heading. | Remove/rename "字段"; set labels to 11 `ink3`, keep value 13 `ink`, add the 13 `faint` chevron. |
| 8 | `h-desk-2.png`; `shared.css:920-950` | Desktop 日历 is one card that contains the toolbar: title + a "今天" pill + a 26 px 月/周/日 segment. No 260 px agenda rail, no "New Event" button. | Desktop month = toolbar on paper (title 18/600, secondary 12 `ink3`, segment 28) + grid + **260 px rail card** with month summary, day agenda rows and a 44 px primary "New Event" (`03-calendar.md` §2; `month:136-147, 432-599`). | If the rail is frozen out, at least move the toolbar above the card and restore the 28 px segment; flag the rail as a product decision. |
| 9 | `h-desk-2.png`; `desktop.html:262` | The out-of-month cell 26 shows "房租 10:00" as a **full-strength** entry bar (the number is faded, the bar is not). | Only in-month cells show entries; out-of-month cells render the header inside `Opacity(0.3)` and show no entries (`calendar_month_view.dart:368`; `marked_month_day_header.dart:173-174`). | Suppress entries on `.mday.other` / `.dgd.other`, or fade the whole cell to 30%. |
| 10 | `h-desk-0.png`, `h-desk-1.png`; `shared.css:860-866` | Desktop content spans 1380 px (20 px gutters at 1440) and the Today side panel is 320 wide; the Todos split is ~1035 + 320. | C max content width **1240** centred; Today panel **356** (388 with a detail); Todos list **610** + 20 gap + expanded detail (`action_section.dart:99-163`; `home_page.dart:995-1036`). | Constrain to 1240 and use the 356/388 panel; keep the Todos split in C's proportion. |
| 11 | All mobile boards; `shared.css:207-221` | The board is 390×844 but `.screen` is **370×824** inside a 10 px bezel. The app canvas is 5 % narrower than the 390 px reference, so text wraps earlier and every spacing comparison is scaled 0.949. | Logical px = CSS px at DPR 1; the reference captures are 390 wide (`01-chrome.md` preamble). | Render the app at 390×844 and draw the device frame outside it (or shoot comparison boards bezel-less). |

### P3

| Where | What I saw | Direction C | Fix |
|---|---|---|---|
| `h-today-0.png`; `shared.css:294-300` | Dock glyphs: house (今天), calendar grid (日历), two-row checklist (待办). | `square_on_square`, `calendar`, `checkmark_circle`, `sparkles` at 21 (`home_page.dart:1682-1687`) | Use the Cupertino set. |
| `h-desk-0.png`; `shared.css:838-843` | Desktop clock shows "• 15:00". | "此刻 HH:mm" (`spark_top_bar.dart:362-391`) | Add the label. |
| `h-desk-0.png`; `shared.css:841` | Nav item reads "今天 9". | Todos nav item has no count (`spark_top_bar.dart:463-483`) | Drop the count or move it out of the nav pill. |
| `h-todo-2.png` | Top-bar subtitle "11月15日 · 周日 · 2026" is repeated verbatim in the date strip one line below. | Top bar shows the viewed-day context; the DateStrip is the control surface (`01-chrome.md` §2; `date_strip.dart:39-78`) | Let the top bar show something else (or drop the subtitle on these boards). |
| `h-todo-6.png`; `shared.css:417` | Allocation meta "计划执行 16:00–17:00" is `--work` blue. | Block meta is `ink3`; `work` is an edge/fill token, never text (`c_day_timeline.dart:567-580`) | `ink3`. |
| `h-todo-4.png`; `shared.css:532-549` | Picker: 44 px rounded cells with 4 px gaps, no hairlines, numbers 13/500; today = primaryTint rounded square. | C's month grid is square hairline cells, numbers 12.5/500; C's real picker is Material's (circular). This is a third grid language. | Align the day number to 12.5 and pick one grid language (see no-analogue ruling). |
| `h-cal-3.png`; `shared.css:780-786` | Slot sheet radius 18, grip `surface3`; row subtitles 12 `ink3`. | Slot sheet radius **16**, grip 30 % `ink2`, subtitles 15 `ink2` (`03-calendar.md` §5; `slot:39-44, 97-152`) | Match the slot-sheet numbers. |
| `h-cal-2.png` | Day view opens with a full-width peach banner "周日 · 11月15日" (a `.week-head .wd.today` stretched over 7 columns). | C's day view substitutes `DayStrip` for the week strip; there is no peach banner (`week:735`; `03-calendar.md` §3) | Drop the banner or reduce it to the strip's selected-day cell. |
| `h-today-0.png` vs `h-todo-1.png` | Same state is called 已逾期 on Today and 已过截止 on Todos. | C uses 逾期 / Overdue for the one state (`app_zh.arb`; `home_page.dart:1509-1517`) | Pick one term. |
| `h-desk-0.png`; `shared.css:876-884` | Today side panel uses the full list row (20 ring, 15/400 title, 12 meta). | C's Today panel row is 48 high, 15 px circle, 13/500 title, 12 label (`action_section.dart:610-691`) | Use the panel-row metrics in the side panel. |
| `h-todo-6.png`; `shared.css:595-597, 621-624` | Unset chip has two foreground tones (`截止` ink3, `未设置` ink2); composer action bar adds a 1 px `line-soft` top border. | Chip foreground is one tone (`ink2` unset; `warn`/`primary` set) (`ds.dart:359-450`); the composer action row has no divider (`04-composer-desktop.md` §2.8; `ds.dart:486-501`) | One chip tone; remove the action-bar border. |
| `h-cal-0.png` | Month page has no "N events · N h" stats line above the weekday row. | Mobile month has a right-aligned stats line before the grid (`month:751-764`) | Add it (part of the P1 rebuild). |

---

## (d) No Direction C analogue / needs a human ruling

1. **FAB (48×48, radius 8, primary, right 16 / bottom 72).** C has no FAB (`01-chrome.md` §5). It *does* read as C: primary fill, control radius, C's single `shadow-1`. Ruling: passes; keep it as the calendar's one solid create affordance.
2. **Inline capture row.** Has a direct C analogue, `TodoQuickAdd`: 48 high, 16 px plus in `ink3`, 15/400 placeholder `ink3`, 1 px `lineSoft` hairline (`todo_quick_add.dart:146-166`). The prototype matches all of these; the trailing "⏎ 进未安排" is new but sits in C's `faint` role. Ruling: passes.
3. **现在 / 接下来 / 今天截止 / 已逾期 sections.** No C analogue (C's timeline is a continuous axis). The only problem is that their head is a second head system (P2-1); the 30 px rhythm and 11/600 letterspacing are right. Ruling: keep the sections, unify the head.
4. **未安排 group on Today.** Head matches `DsGroupHead`; the empty preview is a P1 defect, not a concept problem. Ruling: render the promised 3-row preview.
5. **Composer time-slot grid (5 presets + 自定).** No C analogue; the chips themselves are exactly C's `DsChip` (32 high, radius 6, selected `primarySoft` + `primary` 600). Ruling: passes.
6. **Month/year picker sheet.** No exact C analogue. It currently uses a rounded 44 px cell grid with 4 px gaps — a third grid language next to C's square hairline month grid and Material's circular date picker. It does not look broken, but it does not look like C's month grid either. Needs a human ruling: adopt C's month-grid geometry (hairlines, 12.5 number) or consciously keep the Material-style picker as a separate surface.
7. **Desktop detail pane.** C has `TodoDetailPane`; this is a simplified KV pane. The "字段" heading and 13 px icon-labelled rows are not C's pane. Ruling: either inherit C's 62 px / 11 `ink3` label column, or declare the simplified pane a deliberate A″ reduction.
8. **Desktop 未安排 side panel.** C's Today panel is "今天的任务" (15 px circle, 13/500). This panel is a different function drawn with list rows. Needs a ruling on which row metric the panel should use.
9. **Dock with 3 destinations (今天 · 日历 · 待办), no AI divider; desktop nav 今天/待办/日历; no desktop segment/sync/avatar.** Interaction structure is frozen, so these are not judged. Visual metrics (56 px, 21 px icons, 11/500, selected `primary`) are C-exact; only the glyphs differ (P3).
10. **Month agenda card absence (mobile).** If A″ deliberately drops the agenda card, say so; visually it is the main reason board 12 reads as a different product, because C's month page is anchored by that card.

---

## What is already inherited correctly (evidence for verdict 1)

- **Mobile top bar**: 54 + inset, title 20/600/1.3/ls .1, subtitle 11 `ink3`, clock 12/600 `primary` with a 5 px dot and 5 px gap, 48×48 actions with 19 px icons (`shared.css:243-266`; `01-chrome.md` §2).
- **Dock**: 56 high, `navBg`, 1 px `line` top border, 21 px icon in a 26 px box, 11/500 labels, selected `primary`, unselected `ink3` (`shared.css:290-300`).
- **List row**: min-height 52, padding 12/8/16/8, 12 gap, 20 px ring at 1.5 `ink3`, 48×48 target, 15/400 title, 2 px title→meta gap, 12 meta (`shared.css:326-367`).
- **Group head**: 30 high, 18 padding, 5 px dot, 11/600 ls .3, faint count, `lineSoft` top border (`shared.css:305-318`).
- **Chips / due capsule**: 32 high or 11/500 radius 4, `surface2`+5 px `primary` dot, `dangerSoft` for overdue, `warnSoft` + `warn` 400 for deadline, `primarySoft` + `primary` 600 for execution (`shared.css:369-377, 590-604`).
- **Sheets**: 18 px top radius, 1 px `line`, `shadow-sheet`, 36×4 grip, 17/600 title, 44×44 close (`shared.css:511-545, 578-591`).
- **Desktop bar**: 56 high, 20 padding, 1 px `line` bottom, 22 px brand radius 5, 15/600 wordmark ls .2, 28 px date steps, 13/500 date, 12/600 clock + dot, 28 px nav item radius 6 with `primarySoft`, 26 px segment, 28 px quick add, 36 px icon button (`shared.css:827-871`).
- **Dark mode**: exact C dark tokens (`#131311 / #1A1B18 / #ECECE6 / #E0703C`, etc.), not the A″ note's blue primary (`shared.css:91-136`).
- **Card law**: surface + 1 px `line` + radius 8 is used on the desktop cards and the Today mobile sheet; the composer is a C-voiced sheet.

---

## Finding counts

- **P0: 0**
- **P1: 2** (mobile month page; empty 未安排 preview on Today)
- **P2: 11**
- **P3: 12**
- No-analogue / human-ruling items: **10**

**Single most damaging finding:** board 12 (mobile 日历 · 月) has lost Direction C's contained month card and its day-agenda card, so — with its edge-to-edge grid and left-aligned weekday header — it is the one screen a user would read as a different calendar app.
