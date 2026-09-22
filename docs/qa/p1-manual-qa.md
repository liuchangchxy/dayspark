# P1 手工验收清单 (v0.21.0) / P1 Manual QA Checklist

> 来源：SDD 任务报告（工作区已清理，此为存档）。**发布 tag v0.21.0 前必须全部人工过一遍。**
> 通知专项 12 项清单见 `docs/CONSTRAINTS.md` Notifications 章节。

## 一、综合回归（13 项）

1. Create event via calendar FAB (lands on browsed/week-anchor date, not midnight-of-today if you browsed elsewhere) and via tapping an empty time slot; save; event appears in week/month/day views.
2. Create todo via todos FAB (defaults today), with due date, priority, subtask; reorder by drag (desktop immediate, mobile long-press).
3. Complete todo (checkmark + from All view); un-complete; completed grouping shows Today/Yesterday/date headers.
4. Trash: delete todo → restore from trash (item + children return); delete event → restore; permanent delete; empty trash (both sections).
5. Reminder: create todo/event with reminder → notification fires on time; snooze 1h → fires again; Mark Complete from notification → completes and silences remaining reminders; complete in-app → reminders cancelled; edit due date → rescheduled; delete → no residual notification; reboot device → scheduled reminder still fires (BootReceiver).
6. Search events/todos, tap result → jumps to edit page.
7. Tags: create tag with color, filter via chips, manage page, tag survives todo edit.
8. Theme: system/light/dark switch; theme color picker (preset + reset) applies app-wide.
9. zh/en language switch: UI strings, notification text for newly created reminder, weekday labels.
10. Home-screen widget: cold start shows today events + pending todos (NULL due last, no subtasks); edit/complete/create todo or event → widget updates without app restart (Android + iOS/macOS).
11. Settings sections after split: theme/color/language/default-tab dialogs open; AI toggle + AI config dialog; ICS export (share/snackbar) and import (file picker, result snackbar); system alarm switch (Android/iOS/Windows); exact-alarm tile appears only if permission missing (Android); About shows `DaySpark v0.21.0` and update check works.
12. Midnight rollover / overdue: change device date past midnight → overdue prompt appears once; "Move to today" works. First launch after upgrade → "What's new" changelog popup (0.20.5 → 0.21.0).
13. Calendar specifics: drag non-recurring event → new time sticks **and** its reminder moves; recurring/all-day events cannot be dragged (guard); month grid shows 6-week expansion without scroll-state reset.

## 二、小组件专项（Android / iOS / macOS）

### Android
- [ ] Place widget, cold-start app → widget shows today events + pending todos
- [ ] Create/complete/delete a todo in app → widget updates without app restart
- [ ] Create/move/delete an event → widget updates
- [ ] Todo with no due date appears below dated todos; subtasks never appear

### iOS (real device/simulator, signed build)
- [ ] Add widget → data appears (was always empty before this fix)
- [ ] Same mutation checks as Android (widget refreshes via WidgetCenter on save)
- [ ] After setAppGroupId: confirm no `No groupId defined` warnings in logs

### macOS (signed build — first build validates the new Runner entitlement signs OK)
- [ ] Build/run succeeds with added `application-groups` (signing check)
- [ ] Add widget → data appears in suite
- [ ] Mutation refresh works
- [ ] Known residual: timed events may render "All Day" (legacy string payload vs `as? Bool`) — fixed in P4 by retargeting Swift readers to `widget_snapshot`

## 三、发布流程门（来自终审建议）

- [ ] 首次 push 不打 tag，盯 ci.yml：验证 lockfile 升级（drift 2.31/analyzer 8.4）、CI Flutter 3.41.7 vs stable 双通道、home_widget 0.9.4 Android 依赖、flutter_timezone Linux 注册
- [ ] push 前跑 `tool/check_glibc_version.sh`（新增原生依赖 flutter_timezone）
- [ ] 通知专项 12 项（CONSTRAINTS）真机 Android 过一遍
- [ ] 签名 macOS 构建验证 entitlement
