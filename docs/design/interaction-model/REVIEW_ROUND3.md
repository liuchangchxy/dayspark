# Independent Review — Round 3

Reviewer: independent product reviewer, no prior involvement.
Baseline reviewed: the prototype tree requested at `main` @ `7390987` (v0.34.0). During the review that tree was committed as `a8cd183` (`design(g0): rebaseline interaction model on v0.34.0, close 20 round-2 findings`); all key defects below were re-confirmed on `a8cd183`.
Authority: `docs/CORE_UX_SPEC.md` (v0.34.0), read first. Prototype docs (`COVERAGE.md`, `BEHAVIORS.md`, `TEST_RESULTS.md`) and the vendored Playwright suites were **not** treated as evidence.
Method: I wrote my own Playwright scripts in `/tmp/review3/` (outside the prototype tree), drove the UI by clicking/typing, and read DOM + in-memory `Store.state` only as corroboration. No file under `docs/design/interaction-model/` was changed except this report.

---

## 1. What I actually operated

**Viewports**

- Desktop: 1440 × 900.
- Mobile: 390 × 844, touch context (`hasTouch`, `isMobile`), device-pixel expectations applied.

**Surfaces driven**

今天 · 日历 (week / month / day) · 待办 (day / 未安排 / 全部待办, selection mode) · Todo detail · Event detail · Composer (create/edit todo & event) · Search · Tags · Calendars management · Trash · Settings (appearance / calendars / data / sync / AI / notifications / about) · Feedback · States bench · AI assistant · create chooser / slot sheet / deadline, schedule, repeat, tag, priority, occurrence, scope, delete and reschedule sheets and menus.

**Flows walked end to end (desktop and mobile where applicable)**

- Capture from 今天 (type + Enter, toast undo), create todo and event through the 新建 chooser.
- Schedule a todo from detail and from a calendar blank slot; reschedule from the block context menu; cancel the allocation; confirm 未安排 membership changes each time.
- Complete a todo and undo; delete a todo/event and undo; restore and purge from 回收站; empty 回收站.
- Recurring: complete one todo occurrence; split one event occurrence; edit the same occurrence twice; delete one occurrence; confirm the series and future days survive.
- Calendar week/month, blank-slot sheet, drag and resize event blocks, undo both.
- Search (scopes, no results), tag filter, settings (language, theme, accent, launch page + reload), AI proposal apply and reject.
- Mobile: capture, FAB chooser, full-page detail, back, swipe left (delete) and right (complete) with undo, bottom sheets, 3-day week, month → day.
- Empty / error / disabled: empty far-past day, empty month deadline lane, deleted and nonexistent record detail, disabled save/batch buttons, AI disabled, offline toggle.
- Reversibility: composer 更多 expand/collapse, sheet Esc and scrim close, browser Back with a dirty draft (keep editing / discard), keyboard N / `/` / `?`.

**Domains checked for agreement after every write:** Today allocation rows, Today due rows, 待办 未安排/全部/date views, calendar week/month blocks, search hits, detail facts, trash, and `Store.state` (todos, events, allocations, exdate arrays, occurrence state).

---

## 2. Defects

Severity: **P0/P1 = must fix**, **P2/P3 = note only**. No P0 was found; the defects below are P1 because they either perform the wrong write, lose a reservation on undo, leave a primary control dead, or make required product surfaces unreachable.

### P1 — must fix

#### P1-1. Undo after completion does not restore the invalidated time block

**Repro (desktop):** 今天 → in 稍后今天 click the 16:30 「Q4 预算表」row checkbox → toast reads 已完成「Q4 预算表」撤销 → click 撤销.

**Observed:** the todo reopens, but allocation `id=4` stays `invalidatedByCompletion`; the 16:30–17:30 row never returns to 今天 and no block returns to 日历. The todo reappears in 未安排 even though it still has a deadline. The same happens for the recurring 「读 20 页《设计中的设计》」 occurrence: completion invalidates allocation `id=6` (21:00–21:40), undo clears the occurrence state but the allocation stays invalidated.

**Expected:** undo restores the record *and* the reservation it invalidated: allocation state `active`, row back in 今天 and 日历.

**Evidence:** `/tmp/review3/risks.js` (undo-complete and recurring-undo cases); `Store.completeTodo` invalidates future allocations on completion (`docs/design/interaction-model/js/store.js:666-669`, `646-650`) but the uncomplete branch (`:655-661`, `:640-644`) never reactivates them. Screenshot `/tmp/review3/shots/undo-complete-allocation.png`.

#### P1-2. “完成” in selection mode un-completes an already-completed recurring occurrence while reporting success

**Repro (desktop):** complete today's 「每日站会记录」 occurrence (tick the instance on 今天) → 待办 → 全部待办 → 选择 → select the 每日站会记录 row (the series is still open, so the row remains) → click 完成.

**Observed:** `occurrenceStates` goes from `["v2:DATE:2026-11-16"]` to `[]` — the occurrence is un-completed — and the toast says `已选 1 项 · 完成` with an undo that would re-complete it. Expected: skip the already-complete occurrence or keep it complete; never perform the opposite action.

**Evidence:** `/tmp/review3/dbg-batch.js`; `todo.js:313-320` calls `S.completeTodo` without checking `isOccurrenceDone`, and `completeTodo` toggles.

#### P1-3. Todo detail “更多” is a dead control (both viewports)

**Repro:** open any Todo detail (desktop or 390-wide mobile) → click the top-right 更多 (sliders) button.

**Observed:** nothing happens. Expected: the menu 编辑 / 安排时间 / 添加子任务 / 复制标题 / 移到回收站. The menu is constructed but immediately closed because the click bubbles to the document-level “click outside menu” handler; adding `stopPropagation` in the same page makes the menu stay open with all five items.

**Evidence:** `/tmp/review3/dbg-menu.js`, `/tmp/review3/dbg-menu2.js`; `detail.js:45` has no `stopPropagation`, unlike the working Todo-row menu (`todo.js:78`).

#### P1-4. Mobile has no touch-reachable entry to Settings, Search, AI assistant, Calendars management, or About

**Repro:** 390 × 844, visit each of 今天 / 日历 / 待办.

**Observed:** `#rail` is `display:none`; `#bottomnav` contains only 今天 / 日历 / 待办; page headers expose only create, filter, tags, trash. There is no visible button or menu anywhere with 设置 / 搜索 / AI 助手 / 日历管理 / 关于. Those pages work when invoked programmatically, so this is purely an entry-point failure. A touch-only user cannot change language/theme/sync/AI or reach calendars management at all.

**Evidence:** `/tmp/review3/mobile.js` reachability map: `{"设置":false,"搜索":false,"AI 助手":false,"标签":true,"日历管理":false,"回收站":true,"关于":false}`. `CORE_UX_SPEC` §7 requires Settings (and 日历管理 within it) on both platforms; §11 P0 lists Settings content.

#### P1-5. Mobile touch targets are widely below 48 dp

**Repro:** 390 × 844; measure every visible interactive element (button, `[role=button]`, `[role=checkbox]`, input, select, textarea, link).

**Observed:** 100 violations on the seven primary surfaces (今天 24, 日历周 4, 日历月 4, 待办 22, 待办·未安排 22, 设置 19, Todo detail 5), plus 28 more on composer/search/chat/feedback/states. Representative sizes:

- Todo/instance checkboxes `.hit`: **44 × 44**.
- Capture input / 加截止 / 完整日程 link: **44 px high**.
- View/filter chips `.chip-btn` (全部待办, 未安排, 今天, tag chips, composer chips): **26 px high**.
- Segmented controls (month/week/day, light/dark, 待办/日程, priority): **26–32 px high**.
- Accent swatches: **24 × 24**.
- Settings switches: **38 × 22**.
- Search input: **20 px high**; chat textarea: **24 px high**; composer title: **41 px high**.
- Detail editable value rows and detail action buttons: **44 px high**.

**Expected:** at least 48 dp on mobile (`CORE_UX_SPEC` §8, §12). The latest commit “meet the 48px touch-target rule on phones” enlarged only `.icon-btn`, `.btn`, and some rows; it did not cover `.hit`, `.chip-btn`, `.segmented`, `.swatch`, inputs, or detail values.

**Evidence:** `/tmp/review3/mobile.js` and `/tmp/review3/mobile2.js` target scans (full class/size summary printed).

#### P1-6. Desktop 1440 is single-column: the list is not kept beside detail, and detail has no visible exit

**Repro:** 1440 × 900 → 待办 → click any todo row.

**Observed:** `#view` contains only the detail (`listPresent:false`, `detailPresent:true`, one child). The detail head contains a single button, 更多 — which is dead (P1-3). There is no visible 返回/关闭; the only exits are Escape and re-clicking a rail destination. `U.isSplit()` returns `true` at 1440 but is never used anywhere in the prototype.

**Expected:** per `CORE_UX_SPEC` §4 line 221 and §12 line 457, desktop keeps the list visible with a detail pane where width permits; real v0.34.0 implements exactly this at ≥1180 (`lib/ui/shell/workspace_navigation.dart:92-95`, `lib/ui/pages/home/home_page.dart:574-575, 854-874`). See the adjudication in §4 below.

**Evidence:** `/tmp/review3/spec.js`; screenshot `/tmp/review3/shots/r3-desktop-detail.png`.

#### P1-7. Today renders the same Todo twice: allocation row plus a second full deadline row

**Repro:** load 今天 at 1440.

**Observed:** 「晨间回顾：今天最重要的一件事」 appears as an allocation row (08:30, meta already includes 截止 11月16日 09:00) **and** as a full due row in 今天要完成 (09:00, 截止 …, 08:30–09:00). 「Q4 预算表」 likewise appears at 16:30 (allocation) and 18:00 (deadline). Expected per `CORE_UX_SPEC` §2 (“do not default to two full rows”) and §16.2 (“appears once in the App: the allocation is the primary row, the deadline is secondary metadata”): one row, allocation primary, deadline attached as metadata.

**Evidence:** `/tmp/review3/spec.js`; screenshot `/tmp/review3/shots/r3-desktop-today.png`.

#### P1-8. `browseDate` is not shared between Todo date browsing and the Calendar

**Repro:** 待办 → tap Wed 18 in the date strip. Switch to 日历. Then 日历 → 月 → tap another day. Switch back to 待办.

**Observed:** after selecting Nov 18 in 待办, the calendar anchor is still Nov 16; after tapping a calendar day (anchor changes), the Todo day is still Nov 18. The prototype keeps three independent dates (`todosView.day`, `calendarAnchor`, `actionDate`). Expected per `CORE_UX_SPEC` §16.1: one `browseDate` shared by Todo · 按日期 and the Calendar; switching tabs does not change it, tapping a calendar date does.

**Evidence:** `/tmp/review3/spec.js` (`todo day=Wed Nov 18` vs `calendar anchor=Mon Nov 16`).

#### P1-9. Far-date selection in Todo has no month/year picker (not ≤2 actions)

**Repro:** 待办 day view. Look at the page header/subtitle and the only date controls.

**Observed:** the subtitle is a non-interactive `DIV`; header buttons are 新建待办/筛选/标签/回收站; the only date navigation is one-week arrows. Advancing ~3 months takes 12 next-week taps. Expected per `CORE_UX_SPEC` §16.4: near dates one tap, far dates via date header → month/year picker → day, ≤2 actions.

**Evidence:** `/tmp/review3/spec.js`.

#### P1-10. 所属日历 is a native select, not the required calendar picker; detail is not actionable

**Repro:** 待办 → 新建待办 → inspect the 日历 field. Open a Todo detail → inspect the 日历 fact.

**Observed:** the composer uses `<select>` with options 个人/工作/家庭 — no color, no selected-state presentation, no “+ 新建日历”. The detail 日历 fact is a static chip with no pencil, no `role=button`, and no click handler. Expected per `CORE_UX_SPEC` §5: the picker always opens, shows color + name + selected state, always includes + 新建日历, and creating a calendar returns to the picker with it selected. This is a P0 item in §11.

**Evidence:** `/tmp/review3/spec.js`; screenshot `/tmp/review3/shots/r3-desktop-detail.png` (日历 个人 has no edit affordance while 截止/优先级/标签 do).

#### P1-11. Settings renders a raw i18n key: `manageCalendars`

**Repro:** 设置 → 日历 group.

**Observed:** the row label is literally `manageCalendars`. Expected: 日历管理 (`CORE_UX_SPEC` §6/§7). Dynamic key scan found three keys used by `t()` that exist in neither dictionary: `manageCalendars`, `notificationPermissionAsked`, `exportedTo` (the latter two surface as raw-key toasts; see P2-5).

**Evidence:** `/tmp/review3/risks.js`; `/tmp/review3/i18n-scan.js`; screenshot `/tmp/review3/shots/r3-desktop-settings.png`.

#### P1-12. Todo create/edit/detail information architecture does not follow §4.2

**Repro:** open 新建待办 and a Todo detail.

**Observed:** composer labels in order are 截止 → 安排执行 → 优先级 → 日历 → 标签 → 备注, with 重复与提醒 collapsed at the bottom; there are no 任务 / 时间 / 提醒 / 整理 / 内容 sections. 重复 is separated from 时间, 提醒 is separated from its own group, 日历 comes after 优先级, and the composer has no subtask field at all. The detail order is different again (repeat before priority, reminder after calendar). There is no 重复开始 field anywhere. Expected per `CORE_UX_SPEC` §4.2: identical section order on mobile, desktop full page and desktop detail pane — 任务 / 时间 (截止, 重复, 计划执行) / 提醒 / 整理 (日历, 优先级, 标签) / 内容 (备注, 子任务, 附件); “do not present every field as one flat uninterrupted form”; detail and editor must share terminology and order. This is listed as P0 in §11.

**Evidence:** `/tmp/review3/spec.js` (label arrays); screenshot `/tmp/review3/shots/r3-mobile-composer.png`.

### P2 — note only (should be fixed before acceptance)

| ID | Defect | Repro / observed | Expected |
|---|---|---|---|
| P2-1 | Mobile create is a FAB, not a stable top-right action | 390×844 今天/待办: fixed 48×48 circle at right 16 / bottom 66, top=730, radius 50% | `CORE_UX_SPEC` §1.2: stable top-right; “Do not add a FAB” |
| P2-2 | Planned execution is labelled 安排执行 | composer row and detail fact both say 安排执行 | §4.1/§6 noun is 计划执行; action is 安排时间/安排到日历 |
| P2-3 | Sync group lacks the required explanation | 设置 → 同步 text is only `同步 同步服务器 邮箱 密码 登录 注册` | §7: logged-out copy must explain DaySpark multi-device sync through a DaySpark Sync Server |
| P2-4 | Backup merge is labelled 合并恢复 | 设置 → DaySpark 完整备份 → sheet shows 合并恢复 | §7: user-facing copy must say 合并备份, not 恢复 |
| P2-5 | Two user-visible toasts render raw keys | export all calendars → `exportedTo`; 通知权限 row → `notificationPermissionAsked` | localized copy |
| P2-6 | Composer shows a red validation error before any interaction | open 新建待办: 请填写标题 error box and invalid border appear immediately | validate on submit or after field interaction |

### P3 — note only

| ID | Note |
|---|---|
| P3-1 | Capturing a 4th undated item from 今天 shows only the toast and an incremented count; the new item is not in the 3-row 未安排 preview. §16.2 allows a 3-row cap, but the code comment at `action.js:191-200` says the just-captured item must be visible; it is not, because `highlight` is set to the string `'inbox-entry'`, not to `{id}`. |
| P3-2 | Search: Esc with focus in the search input does nothing (shortcut help says Esc closes/returns). Other surfaces do leave. |
| P3-3 | Copy deviations: Settings group is 外观 (spec says 通用); Today sections are 稍后今天 / 今天要完成 / 逾期 (spec says 接下来 / 今天截止 / 已逾期); About has no feedback entry (feedback lives only in Settings). |
| P3-4 | Calendar blank-slot sheet adds a third job 在这段时间新建待办; §3.1/§5 name two real jobs (新建日程, 安排待办). The extra job is useful but is an unapproved expansion. |
| P3-5 | AI proposal “应用” has no idempotence guard: a natural double-click writes once (the button is replaced), but synchronous double dispatch on the same node writes two allocations. Split-occurrence-twice and natural batch double-click are safe. |
| P3-6 | `quick-add?date=` and widget deep-link routes from §16.3 are not implemented (in-memory routing only). Out of scope for a file:// prototype, but not conformant. |
| P3-7 | The prototype’s own claims are not reliable as evidence: the cited “48px touch-target” fix leaves 100+ sub-48 targets, and `TEST_RESULTS.md`/`COVERAGE.md` describe a subset of states as passing. The vendored suites missed every defect above. |

---

## 3. What I verified as correct

These were re-driven independently and held up:

- **Capture semantics:** 今天 capture creates an undated open todo, toast with undo, 未安排 count +1, appears in 待办 · 未安排, does not appear in 日历. Undo soft-deletes it. Day quick-add inherits the visible date (chip + deadline section), not Today.
- **Creation semantics:** 新建 chooser offers 待办/日程; todo goes to composer with no fabricated deadline; event composer saves, appears in 今天, the week grid and search. 日历 page and slot sheets open the event composer with the viewed slot.
- **未安排 membership (explicitly checked):** membership is driven by live allocations, not `dueDate`. Scheduling a dated todo removes it from the count; cancelling the allocation returns it. A cancelled/invalidated allocation does not count. Dated unplanned items are in the count and in their own date view.
- **§16.2 preview rule (explicitly checked):** the 未安排 preview contains exactly the three undated captured items; the row beneath keeps the allocation-based count (9 at seed, 10 after one capture); dated unplanned items do not join the preview.
- **Schedule / reschedule / cancel:** allocation written from detail and from the calendar slot’s 安排待办 flow; appears on 今天 and 日历; 改期 via block context menu updates start/end; cancel via detail sets `cancelledByUser`, removes the block, returns the todo to 未安排; cancel-undo restores it active.
- **Complete / delete / undo:** plain todo complete + undo reopens; delete parent cascades to both subtasks and undo restores all three; event delete + undo; trash restore, purge (parent + subtasks), empty trash.
- **Recurring:** completing one todo occurrence writes only that occurrence and leaves the series open; future weekday instances still match. Splitting one event occurrence adds exactly one exdate and one standalone copy; editing the same occurrence again updates the copy with no second exdate or duplicate; deleting one occurrence adds one exdate, leaves the series alive, and undo removes it; next week’s occurrence remains.
- **Calendar:** week, month (42 cells) and day views; month cell → day; blank slot sheet; drag moves an event (toast + undo); resize extends the end (toast + undo); deadline chips open the Todo detail; 完整日程 link opens the calendar.
- **Search / filter / settings:** search finds 预算 and event titles, scopes work, no-results state; tag filter reduces the list and every remaining row has the tag; language, theme, accent and launch page change; launch page and language survive reload; changing launch page does not yank the user off Settings.
- **AI:** disabled/not-configured states; typed prompt yields a proposal and writes nothing until 应用; apply writes exactly one allocation and marks the card 已应用; reject writes nothing and marks 已忽略.
- **Errors / empty / disabled:** empty far-past Todo day; empty month deadline lane; deleted and nonexistent record detail show the error page without live controls; save disabled with empty title; batch buttons disabled with no selection; offline toggle and retry give feedback; skeleton states render.
- **Reversibility:** composer 更多 expands/collapses; sheets close on Esc and scrim; browser Back on a dirty draft asks 继续编辑/放弃 and honors both; keyboard N, `/`, `?` work (except Esc-in-search, P3-2).
- **Mobile mechanics:** bottom nav 3 destinations, rail hidden; full-page detail with back; create chooser is a bottom sheet; swipe left deletes with undo; swipe right completes with undo; 3-day week; month cell → day; sheets; no horizontal page scroll on any surface checked (今天, 日历 week/month, 待办, 未安排, 设置, detail, composer, search, chat, trash, tags, calendars, about, feedback, states).
- **No console/page errors** in any of my runs.

**Suite tallies from my independent scripts** (not the vendored tests): desktop flows 87/87 intended-flow checks; risk suite 54/61 with the 7 failures all real defects above; mobile 35/47 (12 failures: 4 reachability, FAB, 7 touch-target surfaces); controls 18/18; misc 18/21 (Esc, sync copy, merge label); spec conformance 2/20 (only Escape exit and no-console-errors passed).

---

## 4. Spec conflicts and adjudication

### 4.1 Master-detail (the requested adjudication)

**Conflict:** `CORE_UX_SPEC` §4 (line 221): “Desktop master-detail keeps the list visible. Mobile uses a full detail page.” §12 (line 457): “master-detail where width permits.” The prototype deliberately renders one column at 1440 and `COVERAGE.md` §7 records “桌面 master-detail 双栏” as an intentional non-goal, arguing that a split makes “back” ambiguous.

**Decision: the frozen spec is right; the prototype violates it.**

Reasons:

1. **The spec is explicit and frozen.** Both §4 and §12 name master-detail on desktop; §1.3 already discusses the desktop sidebar and secondary views. A prototype’s `COVERAGE.md` non-goal cannot override a frozen spec; changing this requires a spec amendment and a product decision, not a unilateral prototype choice.
2. **The shipped product already does it.** v0.34.0 implements `isMasterDetailLayout` at `kMasterDetailBreakpoint = 1180` (`lib/ui/shell/workspace_navigation.dart:92-95`) and `_buildDetailPane` (`lib/ui/pages/home/home_page.dart:574-575, 854-874`). Removing it in the next UI would be a regression from the current product.
3. **“Back” is not ambiguous if the pane is a selection, not a route.** The real code models a pane selection (`workspaceSelectionProvider`) with `_clearSelection` and an Escape handler; the list stays, selecting another row replaces the pane, and only mobile uses a pushed route with a real back. This is the standard, coherent model and satisfies “same capabilities, different shell.”
4. **The single-column desktop is worse than the alleged ambiguity.** In the prototype, opening a detail at 1440 removes the list and leaves *no visible exit at all* (the only head button is the dead 更多, P1-3). Escape is the only pointer-free exit; touch/mouse users must re-click a rail destination.

**Required shape for G2:** at ≥1180 on Todo (and wherever the spec says master-detail), show the list and an embedded detail pane; closing the pane clears the selection; mobile keeps the full-page detail route. Both shells must expose the same capabilities.

### 4.2 Other spec conflicts found

| Spec | Requirement | Prototype reality |
|---|---|---|
| §1.2 | Global create stays top-right; “Do not add a FAB” | Mobile uses a fixed bottom-right circular FAB (48×48) on 今天/待办 |
| §2, §16.2 | A due+planned Todo appears once: allocation primary, deadline secondary | Two full rows (P1-7) |
| §4.2, §11 P0 | Todo form/detail section order 任务/时间/提醒/整理/内容; same order everywhere; 重复开始 inside Repeat | Flat form, wrong order, no sections, no 重复开始, composer has no subtask field (P1-12) |
| §5 | Calendar picker always opens with color/name/selected and + 新建日历; create returns to picker | Native `<select>`; no colors/selected UI/create; detail calendar static (P1-10) |
| §6 | TaskAllocation is 计划执行 | Rendered 安排执行 in composer and detail (P2-2) |
| §7 | Settings jobs group 通用; sync explanation; 合并备份 | 外观; no explanation; 合并恢复 (P2-3/P2-4/P3-3) |
| §7 | 日历管理 entry on both platforms | Raw `manageCalendars`; Settings itself unreachable on mobile (P1-4/P1-11) |
| §8, §12 | Mobile touch targets ≥48 dp | 128 sub-48 targets measured; checkboxes 44, chips/segmented 26, swatches 24 (P1-5) |
| §16.1 | One `browseDate` shared by Todo date and Calendar | Three independent dates; no cross-surface propagation (P1-8) |
| §16.2 | Due+planned Todo appears once | Duplicated rows (P1-7) |
| §16.3 | Widget deep links and `quick-add?date=` | Not implemented (P3-6) |
| §16.4 | Far dates reachable in ≤2 actions via month/year picker | Only 7-day arrows; 12 taps for ~3 months (P1-9) |

---

## 5. Final verdict

The prototype is not acceptable as a conformance model for the frozen spec. The core create/schedule/recurring/trash flows are mostly coherent and several of the hard problems (occurrence splitting, undo of cascaded subtasks, trash restore/purge, proposal gating) are handled well. But there are multiple P1 failures: completion undo silently loses reservations, batch 完成 can un-complete an occurrence, the Todo detail menu is dead, mobile cannot reach Settings/Search/AI/Calendars, 128 touch targets are below the platform minimum, desktop ignores the frozen master-detail rule, Today duplicates obligations, the date model is not shared across surfaces, far dates are unreachable in the required number of actions, the calendar picker is missing, and Settings renders a raw i18n key. The vendored suites being green is not evidence for any of these.

REVIEWER_VERDICT: FAIL
