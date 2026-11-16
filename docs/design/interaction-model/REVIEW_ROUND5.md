# Independent Review — Round 5

Reviewer: independent (no part in building the prototype). Date: 2026-11-16 10:55 CST.
Authority: `docs/CORE_UX_SPEC.md` (frozen). The prototype's own docs and test suites were treated as claims, never as evidence. No prototype test was run or modified.

## Snapshot under review

- Final snapshot: commit `ce4972c26123ff99698a93f5d3367941004ecb97` (`fix(prototype): raise the last mobile controls to 48px`). The work landed while this review was running: `79bd867` (working-tree review start) → `6ab2c31` (round-4 fixes and new surfaces) → `ce4972c` (13 appended CSS rules). All JS hashes below were unchanged across those commits; the final CSS is `b98ef68…`. Every CSS-dependent finding was re-run against `ce4972c`.
- Worktree file hashes (sha1):

```
ee45a885bbea43454172752b95abafce01476933  index.html
b98ef68e6811c95667962dd6384c9ae5b51728f7  css/app.css
e5e970a8c72d5535361bf57f6b7a1ac94c45cb48  js/app.js
dc7bcb4b6dcc07721457fddaee3da0c2efa9c135  js/event-ops.js
431355c4aeb000ef30ac5a859aa087457e3cdfea  js/i18n.js
7b0578d343b2ba6ff218b7408f097a906ab7dfde  js/icons.js
3999938c4684d62a73399c8a21d6d63853f6e928  js/quick-add.js
3dff5dd696acf6f29b374fdb35e623959b14251b  js/registry.js
1f74dc21f00ab5b00e1a373a0d0a63537860d3f4  js/store.js
8e0e34252855c3d73541047d2e6b98fc9ab64c2f  js/todo-ops.js
ce49f0fe5166fcc8973a938c181b71963176bc8a  js/ui.js
ed97deb2d800f187f29cc2ae5f47e0d55f3f80f8  js/util.js
06c4a399fe97adfb6b99f47c51343916851c11eb  js/views/action.js
af797eda8514db5aa5bdae735c64f8456bb28fa3  js/views/calendar.js
5f383a4f0aeaf6111ae31eca0cce1956d194a2a5  js/views/chat.js
eb5f6aba652daf84dc015261bfe106a3d2368ef9  js/views/composer.js
89957fdd56197de35582ce012798440cee24a949  js/views/detail.js
65872cc3ea61d6c653ee6a1ad59550445d50fae7  js/views/library.js
c4e4ad303c6c724cc45e5150484965c052f72d01  js/views/misc.js
92d93f0c53519ea79e8bcb73fd0066cf9a029afc  js/views/quickadd.js
cf3b001a882ef85b62680906ec05c9310a2e26b8  js/views/search.js
20050c011fdea882e8319ad69e1cd04678c90008  js/views/settings.js
1d3a7d6beebf13dbacff6cf92ec4e84966bb38b7  js/views/todo.js
```

## Method

- Own Playwright scripts in `/tmp/review5` (empty directory, playwright-core 1.56.1, Chrome for Testing 1243 at the supplied path). The prototype `tests/` directory was neither run nor used.
- Viewports: 1440×900, 1180×860, 1179×850, 1000×860, 900×850, 899×800, 390×844. Chinese and English.
- Used real UI clicks/drags for all repros. Store/state reads were used only to verify what the UI had written.
- Effective touch targets were measured with a grid of `document.elementFromPoint` probes around each control's painted box (union of points that still hit the control), not from CSS declarations.
- Time-dependent behaviour was driven with Playwright's fake clock (`23:59:50` → `00:00:15`) and `U.setClockOffset` for time-of-day cases. Platform branches were driven by user-agent and locale emulation.
- Flows: composer create/edit/re-render, draft + sheet interactions across breakpoints, Today completion/undo, Todo day/all/inbox, batch operations, filter sheet, plan bar, quick add, search, chat (clear/proposals/schedule/breakdown), calendar month/week/day, slot sheet, drag/resize, dawn fold, settings split/theme/language/notifications/account/AI/import, detail page/pane, Trash delete/purge, Back, Esc order, Enter in fields, and English layout.
- Not testable in this browser prototype: real Flutter/native rendering and physical-device touch; real sync server, AI provider, ICS file or backup IO; Widget landing copy; OS notification channels and permission dialogs; URL deep links. Touch was measured in Chrome mobile emulation with real pointer events, not on hardware.

## Round-4 findings D1–D18

| # | Original claim | Verdict | Evidence on this snapshot |
|---|---|---|---|
| D1 | Composer draft survives re-render and the dirty guard stays armed | **reproduced-fixed** | 1440: typed title + notes → resize to 1000 → text intact; `Store.setSetting('theme')` + render and `Store.setLang('en')` + render → text intact; close still opened the discard confirm. |
| D2 | Creating a calendar mid-compose keeps the draft and selects the new calendar | **reproduced-fixed** | Title, 18:00 deadline and new calendar name survived; picker re-opened with 新日历Q `aria-pressed=true`; saved todo had `calendarId=4` / 新日历Q and due 18:00. |
| D3 | Pane delete/purge cannot leave a live deleted detail or blank Todo | **reproduced-fixed** | Pane → 移到回收站 → confirm: route stayed `todos`, pane closed, `paneSelection=null`; Trash → 永久删除 → 待办 rendered 10 tiles, `#view` had 1 child, no pageerror. |
| D4 | Ticking a recurring todo while browsing another day completes that day's occurrence | **still broken** | The single row tick is fixed (tomorrow row ticks `v2:DATE:2026-11-17`, today not). The same defect remains in batch complete and in detail 完成 (P1-1, P1-2). |
| D5 | Today shows a recurring planned-and-due todo once | **reproduced-fixed** | 读 20 页 appears once as `action-allocation` (21:00, meta 安排时间 · 截止 22:00); no `action-instance` in 今天截止. All planned-and-due seed todos count once. |
| D6 | All phone controls have ≥48dp effective hit area | **still broken** | At 390 and 899: Tags/Calendars 编辑 39×48 (overlap taps open 删除 confirm), Today 完整日程 75×33–39 (bottom edge opens 与设计师午餐), toast 撤销 45×48, composer 安排时间 90×42, 15-minute calendar block 30px high. See P1-3. |
| D7 | Composer status on a repeating todo cannot complete the series | **reproduced-fixed** | The status control is no longer rendered when `draft.recurrence` exists; saving 每日站会记录 left `status=NEEDS-ACTION`, `completedAt=null`, `occurrenceStates={}`. |
| D8 | Detail at 900–1179 has a visible pointer exit | **reproduced-fixed** | At 900/1000/1179 the full-page detail head contains `.back-btn`; Back/Rail also work. |
| D9 | Today rolls at midnight; browseDate does not | **reproduced-fixed** | Fake clock 23:59:50 → 00:00:15: `actionDate` Nov 16 → Nov 17, header 11月17日 · 周二, `browseDate` stayed Nov 16. |
| D10 | Browser Back closes the pane and re-renders | **reproduced-fixed** | Pane open → `page.goBack()`: pane removed, `.md-empty` rendered, `paneSelection=null`, route `todos`. |
| D11 | Filtering/moving the selected record out of the list clears the pane | **reproduced-fixed** | Selected 预约牙医 then applied tag 工作: pane cleared, list re-rendered; editing a selected todo to another date also cleared it. |
| D12 | Today's empty state is reachable | **reproduced-fixed** | After purging all todos/events: `现在没有要处理的` empty state, no 未安排 row, no sections. |
| D13 | Subtask status control is honoured on save | **reproduced-fixed** | Editing 写一页结论 → 已完成 → save: `status=COMPLETED`, `completedAt` set. |
| D14 | Repeat on an undated todo does not invent a deadline | **reproduced-fixed** | 无截止 + 每天: chip stayed 无截止 after repeat; saved `dueDate=null`, `startDate=today`, recurrence present. |
| D15 | Date header shows the year when browsing another year | **reproduced-fixed** | 2027-11-01 subtitle reads `2027年11月1日 · 周一`. |
| D16 | Search/chat containers forward taps to their fields | **reproduced-fixed** | 390: tap search-box padding → active `search-input`; chat box/wrapper padding → active `chat-input`. Residual: tapping the magnifier SVG itself still leaves focus on BODY (P3-1). |
| D17 | Pane selection is retired by a tool destination | **reproduced-fixed** | Todo pane → Rail 设置 → Rail 待办: `paneSelection=null`, `.md-empty` shown. |
| D18 | Quick-add preview never prints `[object Object]` | **reproduced-fixed** | `明天下午三点 开会` → 将创建日程 / 11月17日 15:00 · 15:00 – 16:00 / 1 小时; date-only → 截止 11月17日 (todo); no date → 无截止待办. Saved records match the preview. |

## New findings

### P1 — blocking

**P1-1 Batch 完成 on a browsed day writes today's occurrence.**
Repro (1440): 待办 → click tomorrow in the week strip (subtitle 11月17日) → 选择 → tick 每日站会记录 → 完成. Result: `occurrenceStates` contains `v2:DATE:2026-11-16` (today) and the tomorrow row stays unchecked; the list still shows the row open while the toast reports success.
Cause: `js/views/todo.js:349` resolves every recurring row through `TodoOps.todayOccurrenceId(todo)` instead of the view's day. The single-row path already passes `opts.day`.
Spec: occurrence resolution must follow the browsed day (`CORE_UX_SPEC` §2/§16.2).

**P1-2 Detail 完成 on a browsed day writes today's occurrence.**
Repro (1440): browse tomorrow → open 每日站会记录 → 完成 in the detail pane. Result: today's occurrence (`v2:DATE:2026-11-16`) is completed; tomorrow's stays open. Same result when the detail was opened from a calendar day other than today.
Cause: `js/views/detail.js:92` calls `TodoOps.complete(todo)` with no occurrence, and `js/todo-ops.js:10-26` resolves to today.

**P1-3 Phone touch targets are still below 48dp, with real mis-targets.**
Re-run on `ce4972c`; the 13 appended rules raise composer title, calendar picker, chip-row chips and sheet inputs, but do not touch the offenders below. Measured by edge probing at 390 (same at 899), across every route, sheet, menu and toast:
- Tags and Calendars 编辑 buttons are painted 48×48 but effective 39×48 because `.icon-btn.sm { margin:-10px }` (`css/app.css:863-864`) makes the following 删除按钮 overlap 10px. Tapping the right edge of 编辑 opens the 删除标签/删除日历 confirmation (verified by real click).
- Today 完整日程 is painted 76×48 but effective 75×33–39: it overflows a 28px `.section-head` (`css/app.css:258-260`) and the next row paints over its lower part. Tapping the lower edge opens 与设计师午餐's detail instead (verified).
- Toast 撤销 is 45×48 (`.toast .undo` has a min-height but no min-width, `css/app.css:1094`).
- Composer 安排时间 is 90×42 because the following hint has `margin-top:-6px` and covers the lower 6px (`js/views/composer.js:297-304`).
- A 15-minute calendar block is 314×30 (`.block.short { min-height:30px }`, `css/app.css:896`; height derives from `js/views/calendar.js:409`).
- Calendar slot-hit at 10:00 measured 3×96 because P1-4 shifts an allocation block on top of it.
Spec: §8 "Touch targets remain at least 48dp on mobile."

**P1-4 Planned-execution blocks are placed at the wrong times on phones.**
Repro (390): 日历 → week view. The mobile hit-target rule `js/../css/app.css:890` sets `.block.alloc { position: relative }`, while `js/views/calendar.js:450` still writes absolute `top`. Relative `top` is added on top of normal flow, so each allocation is pushed down by the heights of the allocations before it:

| Data time | Inline top | Rendered at |
|---|---|---|
| 08:30–09:00 晨间回顾 | 240px | 08:30 |
| 09:30–10:30 写 v0.29 发布说明 | 336px | **10:00** |
| 13:30–14:00 整理评审纪要 | 720px | **15:00** |
| 15:30–16:10 回复客户邮件 | 912px | **17:30** |
| 16:30–17:30 Q4 预算表 | 1008px | **19:10** |
| 17:30–18:15 设计走查准备 | 1104px | **21:10** |
| 21:00–21:40 读 20 页 | 1440px | **01:25 next day** |

The scroll height also grows past the grid (1928 vs 1728), and a 10:00 slot becomes 3×96 at 390. Drag/resize reads the visual top, so moving a misplaced block writes a time unrelated to where it is drawn. This breaks the calendar's "planned execution occupies time" contract and the touch-target guarantee at once.

**P1-5 Dawn fold draws early events at 06:00 and drag/resize rewrites their time.**
Repro (1440): create 03:00–04:00 凌晨三点事件 → 日历 week with 凌晨时段已折叠. The block has `style.top=0` and its rect is identical to the 06:00 slot (`262–309` vs `262–310`). Dragging it 10px down rewrites the event to **06:15–07:15**. Expanding the fold shows `top=300px`, the true position.
Cause: `js/views/calendar.js:408` clamps `top` at 0 instead of hiding/folding early blocks, and the drag mapping at `js/views/calendar.js:570-582` converts the visual top back with `dayStart()`; resize uses the same mapping for the end time, so resizing a folded 05:00 block also produces a wrong duration. This is data corruption, not a display-only issue.

**P1-6 A render while a composer picker is open leaves the visible form stale and writes hidden values.**
Repro A (1440): 待办 → 新建待办 → title `跨断点草稿保存` → 截止 → resize the window to 1000 while the deadline sheet is open → set 18:00 → 应用. UI still shows **无截止** and the save label is `保存 · 日历 个人`; clicking Save writes `dueDate=18:00`.
Repro B: same with 所属日历: after resize, choose 工作; the picker still shows 个人, `draft.calendarId=2`; saving files under 工作.
Repro C: 新建待办 → title `明天下午三点 开会` → AI 解析 → resize → 应用; the visible title stays the raw sentence and the schedule chip stays 安排时间, but Save writes summary `开会` plus a 15:00–16:00 allocation.
Cause: `js/app.js:35` replaces `#view` on resize; the composer keeps the draft in state (`js/views/composer.js:83-87`), but the already-open sheet closes over the **old** composer's `renderBody` (`js/views/composer.js:549, 576, 736, 904`), so only the detached old form is re-rendered. The shared draft is mutated while the visible form is not.
This is exactly the "draft across resize ... when a sheet re-renders the view" seam. It affects deadline, schedule, repeat, AI parse and calendar pickers for any user-initiated render (window resize/rotation).

**P1-7 AI chat reports success for an invisible allocation on a recurring todo.**
Repro (1440): AI 助手 → after an assistant reply, 安排执行 → choose 每日站会记录 → 确认. Toast says 已应用; a new allocation exists with `occurrenceId=null`. `isAllocationLive` returns false for a recurring todo without an occurrence (`js/store.js:306-308`), so nothing appears on the calendar, Today or the detail's live schedules.
Same defect in the AI proposal path: ask `安排每日站会记录明天上午` → 应用 writes `occurrenceId=null` and reports 已应用 (`js/views/chat.js:302`).
Cause: `js/views/chat.js:213` and `:302` call `createAllocation` without the occurrence picker that the detail and calendar surfaces use.
Spec: a control must not promise a write the app then hides; §4.1 planned execution must occupy time.

**P1-8 Desktop month double-click does not create.**
Repro (1440): 日历 → 月 → double-click 11月21日. The captured event stream contains one `click` and no `dblclick`; the view drills to 11月21日 day view and no composer opens. Directly dispatching a `dblclick` on a cell does open the composer, which confirms the handler exists but is unreachable with a real pointer.
Cause: the cell's single-click handler (`js/views/calendar.js:162-168`) synchronously calls `App.render()`, replacing the cell before the second click; the real second click cannot produce a `dblclick` on the same element, so the handler at `js/views/calendar.js:171-177` never runs. The promised desktop create gesture is dead; the fallback is the header + 日程 button.

### P2 — recorded

**P2-1 Save label promises a schedule that is not written.**
Repro (1440): 新建待办 → 安排时间 to 10:30 → then set 重复 = 每天 → label reads `保存 · 执行 11月16日 10:30 · 日历 个人` → Save. No allocation is written (`scheduleBlocked` at `js/views/composer.js:994-1000`); the composer closes, the chosen slot is lost, and only a transient warning toast mentions the missing occurrence. If the intent is to refuse, the label must not promise the slot and the slot should stay in the draft.

**P2-2 计划这一天 reserves a past slot after 09:00.**
Repro (1440, clock 19:31): 待办 → 计划这一天 → composer pre-fills 11月16日 09:00 – 10:00 and 无截止. Saving writes a past allocation that immediately appears in 今天早些时候. `js/views/composer.js:68-72` always uses 09:00; the schedule picker's quick chips already know how to roll forward.

**P2-3 Inline undo exists only for completions started on Today.**
Repro: 全部待办 → tick 整理评审纪要. The completed row has no undo button (`js/views/todo.js` rows do not render one); only the toast offers 撤销, and navigating to Today within the undo window also shows no pinned undo because `inlineUndo` is set only by `js/views/action.js:363-375`. After a Todo-list completion, Today's completed row has no `action-undo`.
This is partial support for "pinned undo on the completed row"; the toast fallback still works.

**P2-4 Quick-add parser resolves some dates/times wrongly.**
Using a Sunday 2026-11-15 10:00 clock:
- `本周一 开会` → deadline **Nov 16 (tomorrow)** instead of Nov 9.
- `下周一 开会` → **Nov 23 (8 days)** instead of Nov 16 for a Monday-start week.
- `晚上12点 开会` → **12:00 noon** on Nov 15 instead of 00:00 / midnight.
Cause: the week math at `js/quick-add.js:77-87` treats 本周 as "next matching weekday" and 下周 as `7 - today + target`; the 12-hour qualifier at `js/quick-add.js:106-119` only adds 12 when `h < 12`, so 晚上12点 stays noon.
Preview and saved records agree with each other, but they are wrong dates/times.

**P2-5 Enter does not submit several desktop forms.**
Repro: Settings → 同步 → fill server/email/password → Enter: not signed in (`js/views/settings.js:184-217` has no keydown handler). 日历管理 → 新建日历 → type name → Enter: not created (`js/views/library.js:165-176`). AI 配置 → focus model/key → Enter: sheet remains, nothing saved (`js/views/settings.js:444-478`). Only the tag modal has an Enter handler (`js/views/library.js:85`). The keyboard shortcut sheet advertises Enter as "在输入框中保存".

**P2-6 Todo/Event calendar field is labelled 日历, not the frozen 所属日历.**
`js/i18n.js:23` defines `calendar: '日历'`, used by the composer row (`js/views/composer.js:311`), the detail fact (`js/views/detail.js:182-189`) and the picker title (`js/ui.js:416`). `CORE_UX_SPEC` §5 requires the Todo and Event field label **所属日历**.

**P2-7 "跟随系统" language goes stale across sessions.**
Repro: in a zh-CN session choose 语言 → 跟随系统 (prefs store `{lang:'zh',langPref:'system'}`); reload in an en-US browser. Boot loads the saved resolved `lang` (`js/store.js:887, 895-902`; `js/app.js:318-319`) and never re-resolves `langPref=system`, so the UI is still `今天` instead of `Today`. Theme system is re-resolved on paint; language is not.

**P2-8 Windows/Linux notification settings claim the web build does not support notifications.**
With a Windows or Linux UA, Settings → 通知与提醒 contains only the hint 网页版不支持此功能 (`js/views/settings.js:265-267`, because `platform()` returns `windows`/`linux`). Windows and Linux are native release targets with a notification engine; the copy is a false product claim for those builds.

**P2-9 Deadline quick chip 本周六 writes Friday.**
Repro (Monday 2026-11-16, 1440): 新建待办 → 截止 → chip reads `本周 六`; applying sets **11月20日 (Friday) 18:00**. The label uses `today + 5` while the value uses `(5 - today.getDay() + 7) % 7` (`js/views/composer.js:542`). The applied chip does show the real date, but the pre-apply label is wrong.

**P2-10 English calendars page overflows horizontally at 390.**
Repro: 390×844, language English, 日历管理. `documentElement.scrollWidth=395` vs `clientWidth=390`; the header `New calendar` button runs from x=311 to x=395. The page-action rule that hides labels at ≤460 only targets `.label` (`css/app.css:843-844`), but this button's span has no class (`js/views/library.js:106-108`). No other route overflows in zh or en.

**P2-11 Quick Create is not a quick create.**
`+ 待办` opens the full composer with 任务 / 时间 / 提醒 / 整理 / 内容 all visible; there is no default 标题 + 截止 + 所属日历 + 更多 disclosure. `CORE_UX_SPEC` §3.1 says + 待办 opens Todo quick create, and §4.2 lists the Quick Create default fields. (The full form itself is well grouped, so this is an IA mismatch rather than a layout defect.)

### P3 — cosmetic / recorded

**P3-1 Search magnifier tap does not focus the field.** At 390, clicking the magnifier SVG inside the search box leaves `document.activeElement` on BODY; only the box padding is forwarded (`js/views/search.js:36` checks `e.target === box`). The rest of D16 is fixed.

**P3-2 AI remove-config confirmation says AI is not configured.** Opening 移除配置 on a configured provider shows the message `还没有配置 AI。前往设置 › AI 助手。` (`js/views/settings.js:470` reuses `t('aiNoKey')` as the confirm body), which contradicts the configured state the dialog is removing.

**P3-3 Todo day-view inline quick add allocates a deadline without a 截止 label.** Typing in the day view's inline field writes `dueDate=startOfDay(day)` (`js/views/todo.js:733-735`); the visible context chip is only the date (`js/views/todo.js:308-312`), not an editable 截止 chip as `CORE_UX_SPEC` §3.2 describes. It is visible before saving, but the label does not identify the write as a deadline.

**P3-4 No 重复开始 control in Repeat setup.** For an undated recurring todo, the anchor is silently set to today (`js/views/composer.js:763-768`); the repeat sheet (`js/views/composer.js:745-824`) only exposes interval and until. `CORE_UX_SPEC` §4.1 asks for **重复开始** inside Repeat setup.

**P3-5 Far-date selection exceeds the "≤2 actions" target.** The date picker is an arrow-paged month grid (`js/views/todo.js:447-493`): reaching 2029-06-01 takes three year taps, seven month taps and a day tap. `CORE_UX_SPEC` §16.4 allows header → month/year picker → day with only internal scrolling exempted.

**P3-6 "检测模型" does not present detected models.** It sets the model field to `gpt-4o-mini` and toasts 连接正常 (`js/views/settings.js:459-467`), which is a test result rather than a detected list. Prototype-level, but the label promises more than it does.

**P3-7 Calendar resize handle is 7px high on phones.** `css/app.css:462` keeps `.block .resize { height:7px }`; block drag has a 48px-scale body, but touch resizing is effectively not hittable. Recorded with the calendar geometry work.

## Console, overflow and runtime results

- Console errors / pageerrors: **none** on every route at 1440/1180/1179/1000/900/899/390, in Chinese and English, across the stress run (complete/undo, batch complete, delete/restore/purge, filter, date paging, calendar drag/resize, sheets, chat, quick add, search, settings, theme/language switches). The round-4 `store.js` null crash is gone.
- Horizontal overflow in Chinese: **none** at 1440/1180/1179/1000/900/899/390, with or without detail/pane/composer/sheets. In English: **one** 5px overflow at 390 on 日历管理 (P2-10); none on any other route at any tested width.
- Calendar geometry defects (P1-4, P1-5) do not produce console errors; they produce wrong rendered positions/times and wrong hit boxes.
- All repro scripts are in `/tmp/review5` and are independent of the prototype's suite.

## Summary

- Round 4: 16 of 18 findings reproduce as fixed (D1, D2, D3, D5, D7, D8, D9, D10, D11, D12, D13, D14, D15, D16, D17, D18 — with D16 carrying a P3 residual). D4 is fixed for the single row tick but still broken in batch/detail; D6 is still broken.
- New blocking defects cluster in the seams the additions created: phone calendar geometry/hit boxes, the dawn fold's drag mapping, composer sheets surviving a re-render, recurring occurrence resolution outside the row tick, recurring writes from the AI surface, and the desktop month double-click.
- 8 P1, 11 P2, 7 P3 findings.

REVIEWER_VERDICT: FAIL
