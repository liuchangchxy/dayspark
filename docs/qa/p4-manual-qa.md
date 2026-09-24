# P4 手工验收清单 (v0.24.0) / P4 Manual QA Checklist

> 来源：SDD Task 3/4/5 报告（工作区未清理，原文见 `.superpowers/sdd/2026-09-24-p4-platform-ux/`）。**发布 tag v0.24.0 前必须全部人工过一遍。**
> 通知专项 12 项清单见 `docs/CONSTRAINTS.md` Notifications 章节。
> Source: SDD Task 3/4/5 reports + P4 wrap-up. Must be walked through manually before tagging v0.24.0.
> The 12-item notification checklist lives in `docs/CONSTRAINTS.md` Notifications.

## 〇、签名回归门（macOS 启动 — 2026-09-24 SIGKILL 教训）/ Signing regression gate (macOS launch — the 2026-09-24 crash lesson)

- [ ] 任何 entitlements / 签名改动后：`flutter build macos --debug` → 直跑 `DaySpark.app/Contents/MacOS/DaySpark` **存活 ≥7s**（Dart VM service 行 + `[GoRouter] PUSH: home`），无 taskgate SIGKILL / After any entitlements/signing change: rebuild and launch the binary; it must stay alive ≥7s with the VM service line and router push to home, no taskgate SIGKILL
- [ ] `plutil -lint` 两份 macOS entitlements OK；`codesign -d --entitlements -` 确认 **无 `keychain-access-groups` key**（空数组也会崩）且 `group.com.dayspark.app` 仍在 / Both entitlements lint clean; the built binary carries NO keychain-access-groups key (even an empty array crashes) and keeps `group.com.dayspark.app`
- [ ] CI macOS release DMG 产物下载后可启动（adhoc 同一陷阱路径）/ CI macOS release DMG launches too (same adhoc path)

## 一、小组件 v2（13 项：Android 7 / iOS 模拟器 3 / macOS 3）/ Widget v2 (13 items)

### Android（真机/模拟器）/ Android (device/emulator)

- [ ] 1. 桌面添加三个组件（Today / Upcoming / 月点阵），杀 app 冷启动后三者均有数据且文案为当前 locale（zh↔en 各验一轮，需回 app 触发一次 flush）/ Place all three widgets; cold-start → data present, copy matches current locale (verify zh and en, re-enter the app once to flush)
- [ ] 2. Today 组件勾选一条待办 → 立即乐观变勾；打开 app → 待办完成、提醒取消、同步 outbox 有 upsert；组件恢复未勾 / Check a todo on the Today widget → optimistic check; open app → todo completed, reminder cancelled, outbox upsert present; widget unchecked again
- [ ] 3. 快速添加按钮 → 拉起 `/todo/new?source=widget` / Quick-add button opens `/todo/new?source=widget`
- [ ] 4. 切深色模式（或改 app 主题）→ 下次 flush 后三组件背景/文字/点色跟随 `theme` / Switch dark mode → after next flush all three widgets follow the `theme` block
- [ ] 5. 月点阵：有事件日期显示 accent 点、今天是 textPrimary 点、跨月事件当月相交日有点；下月格子不显示 / Month dots: accent on event days, textPrimary on today, cross-month intersection days marked; next-month cells empty
- [ ] 6. Upcoming：只显示明天起 7 天内条目，与今日组件不重复 / Upcoming shows only tomorrow-through-day-7 entries, no duplication with Today
- [ ] 7. app 从未 flush 时（清数据后未开）：组件静默占位，无崩溃、无硬编码英文 / Never-flushed app: widgets sit idle — no crash, no hardcoded English

### iOS Simulator

- [ ] 8. Widget gallery 添加三 kind；数据与 locale 同 Android 第 1 条 / Add all three kinds in the widget gallery; data + locale same as Android #1
- [ ] 9. 勾选 → 乐观勾 → 回 app 消费完成 / Check → optimistic → consume on return to app
- [ ] 10. 点组件空白区（widgetURL）→ 拉起 app 到 quick-add / Tap blank widget area (widgetURL) → app opens at quick-add

### macOS

- [ ] 11. debug 产物**可启动**（签名回归门见 §〇；launch 即验收，不再是已知问题）/ Debug build launches (see §〇 — launch is now an acceptance item, no longer a known issue)
- [ ] 12. 小组件 gallery 添加三 kind；shim 写入的 App Group 数据可被扩展读到 / Add all three kinds; extension reads App Group data written via the home_widget shim
- [ ] 13. `open "dayspark://quick-add"`（或组件点击）→ AppDelegate 转发 → 停在 `/todo/new?source=widget` / Deep link routes to the quick-add page

## 二、六件事 / 隐藏已完成 UX 走查 / Six-things & hide-completed UX pass

- [ ] DateStrip「六件事 / Six Things」chip 默认 **OFF**；开启后仅今天视图收敛为 6 槽 + 「更多 (N)」折叠行；收起可逆 / Chip defaults OFF; ON collapses only the today view to 6 slots + a More (N) fold; expansion reversible
- [ ] 折叠态拖拽排序只动前 6 槽、全列表顺序保持（prefix 语义）/ Drag reorder inside the collapsed view preserves full-list order (prefix semantics)
- [ ] 逾期带不计入六槽、仍置顶显示 / Overdue band stays separate above the six slots
- [ ] **360dp 最窄屏** DateStrip 顶行三 chip + 图标不溢出（真字体）/ DateStrip top row (three chips + icons) fits a 360dp viewport with real fonts
- [ ] 设置 → 待办区：六件事开关 + 隐藏已完成开关，持久化后重启仍在 / Settings → Todos: both switches persist across restart
- [ ] 隐藏已完成 ON → 今天/收件箱/全部三视图的已完成分组全部隐藏，空态判断正确 / Hide-completed ON hides completed groups in all three todo views

## 三、节气/调休月标记 + 2027 降级注记 / Solar-term & holiday markers + 2027 degradation note

- [ ] 2026 样本：立春 = 2/4、冬至 = 12/22、2026-09-20 班、2026-10-01 休、2026-05-01 休 渲染正确（zh/en 双语各一轮）/ 2026 pins render correctly in both locales
- [ ] EN 节气微标签（"Spring Begins" 等）在日格内 FittedBox 缩放后**仍可读**（窄桌面窗口重点看）/ EN solar-term micro-labels remain legible after FittedBox scaling (check narrow desktop windows)
- [ ] 月视图非当月日期淡化（整格 header 0.3 opacity，含角标）/ Out-of-month day headers dimmed (whole composed header at 0.3)
- **已知限制（非阻塞）/ Known limit (non-blocking):** `lunar 1.7.8` 的 `HolidayUtil` 法定调休数据**止于 2026**；2027+ 的班/休 badge 会静默消失，节气标签（算法）不受影响——升级 lunar 数据前属预期 / Statutory holiday data ends at 2026; 2027+ work/rest badges silently disappear (solar terms keep working) until lunar ships new data — expected before that upgrade

## 四、设置 IA 终态走查 / Settings IA terminal walkthrough

- [ ] 一级顺序：外观 / 语言 / 默认标签 / 主题色（顶部外观组）→ 待办 / 数据 / 账号 / AI / 通知（功能组）→ **高级**（折叠，末尾）/ Top-level order: appearance group → functional groups → collapsed 高级 at the end
- [ ] 展开「高级」→ 关于（版本号 + 开源许可列表）在功能组之下 / Expanding 高级 reveals About (version + licenses) below the functional groups
- [ ] 关于页版本号动态显示 `DaySpark v0.24.0` / About shows `DaySpark v0.24.0` (dynamically read)
- [ ] 各 dialog（主题/语言/默认标签）可打开可保存；危险/低频项不出现在一级 / Dialogs open and save; no dangerous/rare items at top level

## 五、日历体验清欠（P1 (b) 类）/ Calendar experience cleanup

- [ ] 日/周视图打开即滚动到 **08:00**（非 00:00）/ Day/week views open scrolled to 08:00
- [ ] 桌面 hover 事件 tile 光标为 click pointer / Event tile shows a click cursor on desktop hover
- [ ] 读屏（TalkBack/VoiceOver）在日/周空白槽可聚焦 `emptySlotSemantics` 按钮语义 / Empty slots expose the button semantics label on day/week

## 六、time-sensitive 通知 + 设备 entitlement 门 / Time-sensitive notifications + device gate

- [ ] iOS/macOS：新建事件提醒 → 通知带 time-sensitive 打断级别（锁屏/专注模式下优先展示；签名/设备允许时）/ Event reminders carry time-sensitive interruption level where signing/device allows
- [ ] Android 14+：精确定时权限引导 tile 仅在权限缺失时出现在通知设置 / Exact-alarm guidance tile appears only when permission is missing
- [ ] 通知 12 项手工清单（CONSTRAINTS Notifications 章节）真机 Android 过一遍 / Walk the 12-item notification checklist on a real Android device
- [ ] **TestFlight provisioning 门（keep/remove 决策）**：`flutter build ios`（device）当前在个人开发 team 下因 **Time Sensitive Notifications capability 不被支持**而 fail-closed（模拟器/CI 不受影响）。发真机/TestFlight 前必须拍板并记录：**保留**（付费 team 开 capability）或**移除**（删 `Runner.entitlements` 中 `com.apple.developer.usernotifications.time-sensitive` 单行，代码优雅降级为普通优先级）/ Device/TestFlight builds fail closed on the personal team (capability unsupported; sim/CI unaffected). Before any signed device build, decide and record: keep (paid team enables the capability) or remove (delete the single entitlement line; code degrades gracefully)
- [ ] 决策落档后：真机装包、提醒按 time-sensitive（或降级后普通）行为验证一次 / After the decision: install on a device and verify reminder priority behavior once
