# P4 — Platform Completion + Todo清单 UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 统一全平台体验收口（冻结需求 P0-1/2 的 Apple 半场 + P1 小组件数据通路的"可用半场"）+ 对标 Todo清单的执行向 UX 批 + 清偿 P1–P3 全部 (b) 类后备——主计划封盘。

**Architecture:** 不引入新子系统：iOS/macOS 资产统一到 `com.dayspark.app` / `group.com.dayspark.app` 族并修 macOS keychain；小组件升 v2 快照契约（Swift/Kotlin 双端重定向 `widget_snapshot`、快速添加 deep link、Upcoming/月点阵变体、done-tap last-wins 队列）；日历/任务 UI 按 Todo清单 15 模式批改（六件事收敛、节气调休、隐藏已完成、设置 IA 终态）；通知按 P1 验收清单补代码缺口；卫生桶清偿跨 Phase 遗留。

**Tech Stack:** 现有栈不变；WidgetKit/AppWidget 原生件、`home_widget`、节气/调休数据用 `lunar` 类纯 Dart 包（实现者验证选型，优先无原生依赖）、Simulator 构建作 iOS 编译门

**Spec:** 主计划 P4 节 + ROADMAP Pending + `docs/qa/p1-manual-qa.md` 通知/小组件清单 + UX 报告 15 模式（存档于主计划研究引用）+ P1–P3 ledger 后备清单（终审 (b) 类）

## Global Constraints

- 六套 analyze/test 全零全绿（root/flutter/server/contracts/wrapper/CLI）；构建冒烟：`flutter build web --release` + `apk --release` + **`ios --simulator --debug`（新增 iOS 编译门，无证书可跑）** + `macos --debug`（本机签名可用则跑，不行记 manual）
- 版本 feature 只改 x：`0.23.0+24` → **`0.24.0+24`**；禁 push/tag（Phase 收尾用户确认）
- 平台感知法则（CLAUDE 元法则4）：每个 UI 改动明确安卓/桌面/ iOS 差异；触摸 ≥48、桌面 MouseRegion+快捷键
- l10n zh+en 成对（含**小组件原生文案**——P1 审计发现组件字符串硬编码英文，本阶段接入 l10n 或经快照预本地化二选一，写明）
- Bundle/App-Group 改名 = **原子替换三处**（Dart `setAppGroupId`、entitlements、Swift `UserDefaults(suiteName:)`）+ Kotlin 读取端核对；签名失败降级路径：保留旧组名并记录（P1 先例）
- 新增依赖：lunar/节气类 → 检查 macOS Xcode 兼容 + 纯 Dart 优先；CI 若动 → 先普通 push 验证规则不变
- 代码风格同 CLAUDE.md；commit 常规格式

---

### Task 1: Apple 资产统一 + iOS 编译门

**Files:** `ios/Runner/*`（bundle id `dev.opencal.*`→`com.dayspark.app`、App Group→`group.com.dayspark.app`、signing 自动）、`ios/CalendarTodoWidget*`（同组）、`macos/*`（组名统一 + **keychain-access-groups 空数组修复**（P1 遗留：填 `$(AppIdentifierPrefix)com.dayspark.app` 或等价，WHY 注释）、`lib/main.dart` setAppGroupId 同步、`.github/workflows/ci.yml` **+iOS simulator job**（`flutter build ios --simulator --debug`，无证书；插在 test 后 needs:test）

- [ ] 三处组名原子替换 + bundle id 统一 → `flutter build ios --simulator --debug` 绿 + `flutter build macos --debug` 绿（或记 manual）→ CI job 加入 → analyze/test 六门绿 → Commit `feat(platform): Apple 资产统一与 iOS 编译门`

### Task 2: 小组件 v2 —— 契约补全 + 快速添加 + 新变体（数据+双端）

**Files:** `lib/infrastructure/platform/home_widget_service.dart`（v2 快照：+`upcoming` 桶、勾选 pendingOps last-wins 队列段（SP 契约补全——`{pendingTaps[]}`，app 前台消费并落库为 complete op）、**widget 文案预本地化**进快照（消原生硬编码英文，记录选择）、dark 样式字段）、mutation 后 flush 已有 tableUpdates 通路核对、deep link 路由 `app://quick-add`（`app_links` 或 home_widget onClick 回调→Flutter 路由，双平台）
- [ ] 快照契约升级 + 消费端测试（golden：v2 schema、pendingTaps 合并语义）→ Commit `feat(widget): v2 快照契约与快速添加通路`

### Task 3: 小组件 v2 —— 原生端（Android 重写 + iOS/macOS 重定向）

**Files:** `android/.../CalendarTodoWidgetProvider.kt`+layout（读 `widget_snapshot` v2、勾选→pendingTaps 入队（不直写库=单写入路径铁律）、快速添加按钮→deep link、新增 **Upcoming 变体 provider**、月点阵 **RemoteViews 网格变体**（7×N 圆点，差异化）、暗色样式）、`ios/CalendarTodoWidget/*.swift` + `macos/CalendarTodoWidget/*.swift`（**重定向读 `widget_snapshot`**——P1 终审 (b)：isAllDay Bool 类型问题随旧 legacy 键退役一并消失；App Intents 勾选→pendingTaps；quick-add `widgetURL`+AppIntent；Upcoming/月点阵 TimelineProvider）
- [ ] 双端原生编译（ios simulator + macos debug + apk）→ Commit `feat(widget): 双端 v2 变体与勾选队列`

### Task 4: Todo清单 UX 批 A —— 执行收敛

**Files:** `lib/ui/widgets/todo/date_strip.dart` + home todos tab（**六件事收敛视图**：Ivy Lee 有序 6 槽 + "更多"折叠，尊重现有拖拽排序；默认开关或直接替换待执行面——实现者读现状后选，报告写明）、**隐藏已完成开关**（todos tab + settings 持久化）、`calendar_section`/month view（**月视图点日期直接建事件/任务**已有槽位则核对，节气/调休：lunar 包接入 month grid 标记（节气小字+法定班/休色点），l10n 节气名 zh/en 表）
- [ ] l10n 成对 + 组件测试（六件事上限、隐藏开关、节气渲染）→ Commit `feat(ui): 六件事收敛与节气调休批`

### Task 5: Todo清单 UX 批 B —— 设置 IA 终态 + 日历体验清欠

**Files:** settings 信息架构终态（P1 拆分后的 sections 再梳理：主设置页一级项精简、危险/低频项入"高级"、对照 Todo清单"克制"原则）、P1 日历遗留 (b) 类清欠：**初始滚动 08:00**（kalender `initialTimeOfDay`）、事件 tile **MouseRegion 光标**、空白槽 **Semantics(button)**、月视图**非当月日期淡化**（kalender builder 能力内做）
- [ ] 四项+IA 改动测试/快照核对 → analyze 零 → Commit `feat(ui): 设置 IA 终态与日历体验清欠`

### Task 6: 通知验收清单代码缺口 + 卫生桶

**Files:** 对照 `docs/CONSTRAINTS.md` 通知 12 项清单逐项打勾/补码：iOS `UNCalendarNotificationTrigger` 已用核对、**time-sensitive interruptionLevel**（事件提醒类标 `.timeSensitive` + entitlement 注释）、Android exact-alarm 引导已有核对、Doze 注记；卫生桶（P1–P3 终审 (b)）：**tool 测试进 ci.yml**（server-test job +2 步 dart test）、MCP `WINDOW hint` 措辞、工具错误 `$e`→不透明消息+日志、consent `X-Frame-Options`+`frame-ancestors`、RFC 7591 两字段、`response_mode` 非 query 拒绝、**Windows 通知 stub 上游复查**（flutter_local_notifications_windows 是否已修 AOT——能换回官方则换，不能记 ROADMAP）
- [ ] 六门 + ci.yml diff 仅增步 → Commit `fix: 通知验收缺口与跨 Phase 卫生桶`

### Task 7: 全量验证 + 文档 + 版本 + P4 QA 清单

- [ ] 六门全零全绿 + 构建冒烟四连（web release / apk release / ios simulator debug / macos debug-or-manual）
- [ ] `docs/qa/p4-manual-qa.md`：Apple 真机 TestFlight 手工门、小组件三变体双端手检、六件事/节气/隐藏已完成手检（引用 P1 通知清单不重复）
- [ ] changelog v0.24.0 双语；ROADMAP 需求1/2 ✅ 收口行 + P4 行 + Pending 清空至 P5/P2.5 残留；CONSTRAINTS（App Group 族名、widget v2 契约 Why+Date、iOS CI 门）；DECISIONS（bundle 改名、快照预本地化选型、lunar 选型、六件事默认策略）；SPEC 3.4 P4 ✅；CLAUDE.md 版本+stack；pubspec → `0.24.0+24`
- [ ] Commit `docs: v0.24.0 文档与版本` — **停下等用户确认再谈 push**

---

## Verification（Phase 收尾门）

1. 六门 + 四构建冒烟全绿（macos 签名受阻则 manual 标注）
2. 终审 + 修复波 + 复审（同 P1–P3 流程）
3. 用户手工 QA（`p4-manual-qa.md`，可豁免）→ push 首验 iOS CI job → tag 用户定

## 风险与回退

- Apple 签名/provisioning 撞名 → Task 1 降级路径：组名保留旧值、仅 bundle 改名回退；真机验证=用户 TestFlight 门
- lunar 包兼容/体积 → 备选：自维护节气表（静态数据，24 节气+班休规则数据量小）
- 六件事与现有"全部/今天"tab 冲突 → 默认关闭开关渐进，不破坏老路径
- 月点阵 RemoteViews 复杂度 → 降级为"圆点列表纵向排布"，功能先于像素还原
