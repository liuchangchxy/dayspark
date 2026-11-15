# UX Convergence Pass — 2026-11-15/16

- 范围：以 A″ 定稿为视觉参考（视觉冻结），在真实 Flutter 中收敛**行为、状态、跨页流程**；不改视觉语言、不新增功能面。
- 方法：只读审计（4 个分区 subagent）→ 实现（5 批共 17 个 subagent，按文件所有权并行）→ 每批 `dart analyze` + 针对性测试 → 全量门禁 → MuMu 模拟器真机走查。
- 设计裁定来源：OpenDesign 项目 `dayspark-a2-production-2026-11-15` 的 `review-ux-gaps.html`（18 条缺口，每条第 3 段「要拍板的决定」被当作实现依据）。

## 一、语义冻结

`SPEC.md` §3.1.1 新增「用户动作与领域写入对照」表（12 个动作 × 唯一写入 × 禁止发生），
覆盖 创建 / 编辑 / 安排 / 改期 / 取消安排 / 完成 / 撤销完成 / 删除 / 恢复 / 截止 / 提醒。
关键约束：`dueDate` 只由显式「截止」写入；改期只改 `startAt/endAt` 不动 occurrence；撤销完成不自动恢复已失效 allocation。

## 二、真机走查（MuMu，1080×2400 @ 480dpi）

走查的完整链路：今天捕获 → 未安排 1 项 → 打开详情 → 安排 → 选 14:00–15:00 → 保存 → 日历 14:00 出现计划块。
逐条确认：捕获行整行可点、未安排即时出现、行内「安排」与「打开」分流、composer 显示「计划执行 11/15 14:00–15:00」、主按钮「计划执行到 11/15」、日历块落位正确。

真机暴露并已修的两个布局缺陷（单测与桌面构建都看不出来）：
1. 手机日历头部 5 个图标把标题挤成「11月9日 …」→ 改为 1 个视图菜单 + 1 个新建按钮。
2. 月视图格子内容溢出 15px（`RenderFlex overflowed`）→ 格子按可用高度折叠成 `+N`。

## 三、按 OpenDesign 裁定落地的行为

| 裁定 | 落地 |
|---|---|
| T1 四节独立判空 | 今天页各节自判空，整页全空才显示空态盒 |
| T2 时间节折叠 | 「接下来」「已逾期」>3 项折叠，「现在」永不折叠 |
| T3 一勾双完 | 合并块勾选同时完成执行与截止，meta 记录完成时刻与原截止 |
| T4/D3/R6/R7 可撤销完成 | 完成行原地保留 5 秒 + 行内「撤销」键；重复实例带 occurrence 标签 |
| T5 投影失败 | 错误态 + 重试；有旧值时降级为「陈旧列表 + 重试条」 |
| C1 槽 sheet 双行头 | 主行日期（事实）+ 次行范围（标注默认时长/既有日程） |
| C2 三动作分级 | 新建日程（实心）→ 新建并安排（描边）→ 安排待办（文字 + 计数徽标） |
| C3 候选空/错分离 | 空态指向「新建并安排」；错误只隔离在「安排待办」一行 |
| C4 24h 轴 | 现在线吸顶、「回到现在」浮动键、凌晨空段折叠 |
| D1/D2 行右缘「安排」 | 行内 ghost 键直达 schedule 模式；标题仍开详情 |
| P1/P2 主按钮动词 | 创建用「保存…」、安排用「安排…」；六态文案矩阵补全 both 与 schedule |
| P3 模式切换 | sheet 内段控切换，已填字段保留，occurrence 清空 |
| R1 失败保草稿 | 保存失败不关 sheet、不清输入、标「保存失败」、可重试不重复 |
| R2 成功后落点 | browseDate 跳到被安排的日期 |
| R4 改排原子 | 已确认 `reschedule` 是原地更新同一行，不会双挂 |

## 四、门禁

- `dart analyze .` → No issues found
- `flutter test` → 见本轮收口记录
- 桌面 Windows debug 构建 → 成功启动，首屏可见真实数据与月视图

## 五、三项裁定（2026-11-16 已结，不再遗留）

| 议题 | 裁定 | 落地 |
|---|---|---|
| 日历 FAB 是否改三动作菜单 | **按 SPEC，直接新建 Event**。三动作菜单只属于「具体时间槽」场景 | `a2_calendar_page.dart` 保持直建；`design-notes.md` §7 与 OpenDesign 项目内的冲突文字已删，改为「FAB 直接新建 Event，不弹动作菜单」；约束写进 `docs/CONSTRAINTS.md` |
| 新捕获行底色 | **`surface-2`**。`primary-soft` 保留给选中/强调 | `today_page.dart` `_unplannedRow` → `ds.surface2`；约束写进 `docs/CONSTRAINTS.md` |
| 6 个缺失 l10n key | **补齐，不用已有 key 拼英文** | `undoOccurrence` / `backToNow` / `dawnQuiet` / `slotRangeExistingEvent` / `slotRangeDefaultEditable` / `slotEmptyCreateHint`，中英双语，`flutter gen-l10n` 后门禁全绿 |

## 六、收口

- 上述三项修完后重跑 `dart analyze .` / `flutter test` / 版本·空白·路径门禁，并在 MuMu 上重走捕获→未安排→详情→安排→日历，以及日历头部与时间槽 sheet。
- 本轮以单个 PR 提交：OpenDesign `review-ux-gaps.html` 裁定、真机发现的两项布局修复、上述三项裁定。
