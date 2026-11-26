# DaySpark round-4 independent review — final artifact

## Verdict

**PASS.** Final frozen artifact is `fe3aa531…9333` (commit `65fdf776`), verified locally and from raw.githubusercontent. All five previously reported defects (D1–D5) are fixed and re-verified by real operations. No new blocking defect found. Two optional scenarios (AI repeat chip, full backup field matrix) were not re-executed in this 6–8 minute window and are marked SKIPPED, not PASS.

## Final artifact identity

| Item | Value |
|---|---|
| Package | `/tmp/ds-r4/design/opendesign/v1-freeze-r4-2026-11-26` (unchanged) |
| Prototype | `.../dayspark-prototype.html`, 1,024,391 bytes |
| SHA-256 local | `fe3aa531ae5c948c58e31067ca004e4126a850d3f82105a8297259bdce639333` |
| SHA-256 raw @ 65fdf776 | same hash |
| Commit / branch | `65fdf776` on `design/v1-freeze-r4-2026-11-26`; PR #117 |
| Diff since prior reviewed artifact | `flows-v3-model.js` only (7+/4-), plus doc commit; 0639b8d1 fixset (D2–D5) also present |
| Browser | Chrome 158.0.8127.37 headless, fresh profiles `/tmp/rv-chrome-9510` (desktop 1440×1000) and `/tmp/rv-chrome-9511` (mobile), CDP 9510/9511 |
| Page | `file:///tmp/ds-r4/design/opendesign/v1-freeze-r4-2026-11-26/dayspark-prototype.html` |
| Reset | `localStorage.clear()` + reload; read live `TODOS`, `state`, `DS3`, `isDone()` |

## Re-review after fixes

### D1 — repeat detail completion picker refresh + undo — PASS
Path: Today → `Proto.openTodo('recurring')` → drawer `选择这一次实例` → pick `2026-11-27`.
- After pick: `state.doneInstances=["recurring@2026-11-27"]`; drawer button text **本次已完成**; undo bar visible (`data-action="undo-done"`).
- `isDone(todoById('recurring')) === false`; `state.occurId=null`, `state.occurDate=null`.
- Other instances pending: `DS3.isInstanceDone(recurring,'2026-11-20') === false`, `…'2026-11-27' === true`.
- Click undo: `doneInstances=[]`; both 11/20 and 11/27 pending; series still not done.
- Implementation matches the intended fix: render only, `state.occurId` not bound; drawer label comes from `state.undoInstance`. No regression to series completion state.

### D2 — repeat plan-only save — PASS
Path: `recurring` → 编辑 → 计划执行 → pick 11/27 → 安排 → 保存.
- No `保存到整个系列？` modal (`document.querySelectorAll('.proto-modal-head span')` empty).
- Allocation persisted immediately: `[{id:'alloc-2', date:'2026-11-27', start:'15:15', end:'16:00', occurrenceDate:'2026-11-27', state:'active'}]`.

### D3 — repeat todo delete — PASS
Path: `recurring` drawer → 删除.
- Confirm dialog `删除「整理周会纪要并群发」？` with `取消 / 删除`; **no** occurrence-scope picker (`[data-scope]` absent).
- Confirm → `state.deletedTodos=["recurring"]`, drawer closed, toast `已删除整个系列「整理周会纪要并群发」到回收站`. No plan-date-derived occurrence anywhere in the flow.

### D4 — saved allocation id / planSeq — PASS
- Saved id is `alloc-2` (`/^alloc-\d+$/`), `state.planSeq===2`. `draft-alloc-*` is no longer persisted.

### D5 — no-anchor reminder affordance — PASS
- `proposal` (due, no dueTime) detail button reads **＋ 加绝对提醒**, title `没有时间锚点；只能添加具体时间`.
- Picker rows: `不提醒` enabled; all relative rows disabled; absolute entry present.
- Absolute add: choose 09:00 → 确定 → `todoById('proposal').remind === '绝对 · 09:00'`.

### Drag second keeps first / resize — PASS
Setup: report with seed `alloc-1 15:15–16:00` and second `alloc-2 09:00–10:00`; desktop week calendar.
- Drag `alloc-2` down 60 min: `alloc-2 → 10:00–11:00`; `alloc-1` still `15:15–16:00 active`.
- Resize `alloc-2` bottom +30 min: `alloc-2 → 10:00–11:30`; `alloc-1` unchanged. Writes went through allocation identity (`data-alloc`), as required.

### Mobile repeat completion — PASS
Mobile shell (`state.device='mobile'`), `cal-day` for 2026-11-19 with `recurring` allocation `{date:2026-11-19, occurrenceDate:2026-11-27}`.
- Mobile block carries `data-id=recurring`, `data-alloc=alloc-2`.
- Clicking it binds `state.occurId='recurring'`, `state.occurDate='2026-11-27'` (column day 11-19 differs from occurrence 11-27).
- Drawer shows `完成这一次`; completing writes `recurring@2026-11-27`. Block identity wins over column day.

### NOT re-executed — SKIPPED
- AI repeat-plan chip (code path still uses `DS3.requireOccurrence` and blocks save without occurrence; not driven through the chip UI in this window).
- Full backup field matrix (reminders/tags/doneInstances/skipped/localTodos/planSeq). Core real-file export→clear→reload→merge and single-plan same-id restore were PASS on the prior artifact; the final diff does not touch `flows-v3-data.js`.
- Legacy migration, Quick Add, reminder multi-save, raw `status='done'` undo, detail editor draft save: verified PASS earlier on this branch; final diff touches only repeat completion rendering, so not re-run. Evidence stands as carried forward, not re-asserted as fresh execution.

## Residual notes

- When a repeat drawer is opened *from a bound calendar block*, `isDone(series)` is true for that bound instance (expected instance-view semantics). The D1 requirement — series not done after the neutral detail picker — is satisfied (`state.occurId` stays null).
- No new residual write paths found in the final diff. `flows-v3-model.js` change is limited to undo-instance-based label derivation; no direct `t.plan` write, no TODAY/selectedDate fallback, no occurrence derived from plan date.

## Scope statement

No product source/docs modified. Only this report was written. PR #113 untouched. Artifact frozen at `65fdf776` / `fe3aa531…9333`; no fifth audit started.
