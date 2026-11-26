# DaySpark 第四轮验收记录（2026-11-26）

> 验收对象：`dayspark-prototype.html`（由 `dayspark-spec.html` + 15 个 `flows-*.js` 构建）。
> 验收方式：真实 Chrome（headless CDP），桌面 1440×1000、手机 390×844；从产品页真实入口点击，读实际 `state/TODOS/EVENTS/DS3.allocations`、localStorage 与真实下载文件；刷新后再读一次。
> 基线：第三轮冻结 `9360a813`。本轮未修改 Flutter，未合并 PR #113。

## 1. 组合操作验收

| # | 场景 | 实际结果 | 证据 |
|---:|---|---|---|
| 1 | 同一待办两段计划，拖动第二段 | 第一段 `15:15–16:00` 不变；第二段 `11:00–12:00` → `11:45–12:45` | `results/drag_second_keeps_first.txt` |
| 2 | 编辑第二段，只改第二段 | `alloc-1` 保持 `15:15–16:00`；`alloc-2` → `11:00–12:00` | `results/plan_edit_probe.txt` |
| 3 | 详情编辑器再加第三段，取消 | 源对象仍 1 段；草稿 2 段，取消后源对象仍 1 段 | `results/plan_draft_probe.txt` |
| 4 | 详情编辑器再加第三段，保存 | 保存后源对象 2 段，第一段不变；`t.plan` 由最早有效分配派生 | `results/plan_draft_probe.txt` |
| 5 | 全部计划取消 | 两段均为 `cancelled`；字段显示“历史 2 段”；列表仍有“查看历史与再安排” | `results/plan_cancel_all.txt` |
| 6 | 普通待办完成（无重复） | 晚于完成时刻的 15:15 段 → `invalidated`；已开始的 09:00 段保持 `active`；撤销完成不自动恢复 | `results/plain_done_probe.txt` |
| 7 | 原始 `status='done'` 撤销 | 撤销后 `status='open'`、`state.done` 移除，可再次完成 | `results/plain_done_probe.txt` |
| 8 | 计划状态文案 | 15:15 显示“即将开始”，09:00 显示“已结束”，不再全部“进行中” | `results/plan_status_probe.txt` |
| 9 | 同一待办同一时间两段 | `plansOn` 返回两条不同 `allocId`；日历出现两个块 | `results/plan_dupe_same_time.txt` |
| 10 | 缩放第二段下缘 | `alloc-2` 11:00–12:00 → 11:00–12:30；`alloc-1` 不变 | `results/resize_second.txt` |
| 11 | 连续拖动偏移 | +30 分钟后 −30 分钟回到 `15:15–16:00`；再 +60 分钟到 `16:15–17:00`，不是累计 17:15 | `results/drag_delta.txt` |
| 12 | 重复待办从详情完成 | 无绑定实例时只显示“选择这一次实例”，弹窗必须点具体日期；选 11/27 只写 `recurring@2026-11-27`；撤销需再选同一实例 | `results/repeat_detail_done.txt` |
| 13 | 重复待办从手机日历完成 | 块绑定 `occurrenceDate=2026-11-27`，所在列是 11/26；完成按钮写 `recurring@2026-11-27` | `results/mobile_repeat_final.txt` |
| 14 | 重复待办从 AI 安排 | 先选具体实例，再写 `alloc-3`；普通待办追加，不覆盖第一段 | `results/ai_repeat_plan.txt`、`results/ai_repeat_requires_instance.txt` |
| 15 | 今天的重复实例完成 | `11-20` 完成，`11-27`、`12-04` 仍待完成 | `results/repeat_next_pending.txt` |
| 16 | 重复计划从编辑器加入 | 先选 11/27；草稿带 `occurrenceDate=2026-11-27`；取消后源对象仍 0 段 | `results/repeat_plan_draft_final.txt` |
| 17 | 重复锚点不得来自计划日期 | 新系列计划在 11/27，`repeatAnchor` 仍是 `2026-11-20`（创建日/截止），不是 11/27 | `results/repeat_anchor_not_plan.txt` |
| 18 | 旧重复规则迁移 | 取消后 `legacyRrule` 原样保留；确认时区/锚点/规则后才写 `repeat/repeatAnchor/timezone` | `results/legacy_ui.txt` |
| 19 | 无锚点的提醒 | 只有计划、没有截止时刻时，相对提醒全部禁用；增加截止 18:00 后启用 | `results/rem_plan_not_anchor.txt` |
| 20 | 计划改期不改提醒 | 添加“1 小时前”后把计划 15:15 改到 10:30，提醒仍为 `15 分钟前 + 1 小时前` | `results/rem_plan_not_anchor.txt` |
| 21 | 新建日程多提醒 | 主提醒 15 分钟前 + 附加 30 分钟前；保存后事件同时保留两者 | `results/new_rem_save3.txt` |
| 22 | 新建待办多提醒（有截止时刻） | 截止 18:00 后添加 30 分钟前；保存后 `due/dueTime/remind` 均正确 | `results/new_rem_save3.txt` |
| 23 | 编辑日程提醒，取消 | 草稿改 30 分钟前；取消后源事件无 `remind` | `results/event_edit_rem.txt` |
| 24 | 详情提醒新增 | 日程详情可新增 30 分钟前；待办详情可新增 1 小时前 | `results/rem_probe2.txt`、`results/rem_plan_not_anchor.txt` |
| 25 | 快速添加：带时刻 | 普通保存创建 11/21 15:00–16:00 日程，不写待办计划 | `results/qa_force.txt` |
| 26 | 快速添加：显式另存待办 | 待办无 `due/dueTime/plan/remind`，界面写明“无截止” | `results/qa_force.txt` |
| 27 | 快速添加：纯日期 | 待办只写 `due=2026-11-21`，不写时刻/计划/提醒 | `results/qa_force.txt` |
| 28 | 快速添加：跨午夜 | 23:30–00:30 写 `startDate=11-20/endDate=11-21/crossMidnight`，不 clamp | `results/qa_force.txt` |
| 29 | 快速添加：移除时间建议 | 保留日期作为截止（11/21），不写时刻/计划/提醒 | `results/quickadd_removed.txt` |
| 30 | 任务菜单“安排” | 对未安排待办新增 `alloc-2`，不覆盖已有计划 | `results/menu_plan_append.txt` |
| 31 | 备份导出 | 真实下载 `2026-11-20.dayspark.json`；含 todos/events/cal/state/data；AI 仅掩码 | `results/backup_probe.txt` |
| 32 | 备份失败重试 | 失败态点重试，真实生成下载文件 | `results/backup_retry_final.txt` |
| 33 | 备份恢复（真实文件） | 导出→清空 localStorage→重载→选择同一文件合并：两段计划、提醒、标签、重复实例分配、`doneInstances/skipped/deletedTodos/localTodos/planSeq` 全部恢复；刷新后仍在 | `results/backup_roundtrip.txt` |
| 34 | 备份合并字段级 | `doneInstances/skipped/localTodos/planSeq/done/deletedTodos/hiddenCals` 恢复；AI 无明文 | `results/merge_probe2.txt` |
| 35 | AI Key 不落盘 | 输入真实 Key 后 `P.data.ai.key` 仅掩码；快照/localStorage/备份均无明文；会话内仍可用 | `results/ai_probe.txt` |

## 2. 已知缺陷逐项结论

| 来源 | 缺陷 | 结论 | 证据 |
|---|---|---|---|
| P0-1 | 日历拖动读写 `t.plan` | 已修复：按 `data-alloc` + `updateAllocation` | 1、10、11 |
| P0-2 | 编辑器加计划覆盖第一段 | 已修复：草稿追加，保存逐段落库 | 2、3、4 |
| P0-3 | 重复完成/改期猜实例 | 已修复：所有入口先选实例 | 12–17、AI 两测 |
| P0-4 | 备份合并不恢复实例/业务数据 | 已修复：同 id 条目补齐字段并合并分配/提醒/标签 | 33、34 |
| P0-5 | 旧重复缺时区/锚点 | 已修复：显式迁移，取消不改写 | 18 |
| P1-1 | 提醒把计划当锚点 | 已修复 | 19、20 |
| P1-2 | 多提醒入口不完整 | 已修复：新建/详情/编辑、待办/日程 | 21–24 |
| P1-3 | 重复锚点可能来自计划日期 | 已修复 | 17 |
| P1-4 | 原始 `status='done'` 无法撤销 | 已修复 | 7 |
| P1-5 | 日历投影按 todo+时间去重 | 已修复：每个分配一条 | 9 |
| P1-6 | 全部计划取消后历史消失 | 已修复 | 5 |
| P1-7 | 所有计划都显示“进行中” | 已修复 | 8 |
| P1-8 | 快速添加把时刻默认成待办计划 | 已修复 | 25、26 |
| P1-9 | 快速添加跨午夜结束错误 | 已修复 | 28 |
| P1-10 | 拖动累计 delta | 已修复 | 11 |
| P1-11 | 备份失败重试只显示成功 | 已修复 | 32 |
| P1-12 | AI Key/备份明文 | 已修复 | 35 |

## 3. 复现方式

```bash
# 在评审包根目录
python3 prototype-src/build.py /tmp/dayspark-r4
# 直接打开 /tmp/dayspark-r4/dayspark-prototype.html
# 证据脚本默认读取 /tmp/r4-final/dayspark-prototype.html；可用 sed 替换为实际构建路径
cd evidence/scripts
python3 plan_draft_probe.py
python3 backup_roundtrip.py
...
```

证据脚本只依赖 Python 3、`websockets` 与本机 Chrome；每个脚本使用独立 profile/端口，不依赖前一个脚本的状态。`backup_roundtrip.py` 会真实点击“导出完整备份”、清空 localStorage、重载、再通过真实 `input[type=file]` 合并下载文件。

## 4. 说明

- `plain_done_probe.txt` 首行 `before {'ERR': ...}` 是该探针自身读取未定义集合的调试行，不是产品异常；其后的完成/撤销写入均正常，`errs []`。
- 拖动探针早期在 1000px 高窗口把块拖到视口外会导致下一次按不到块；`drag_delta.txt` 使用块内可点击点并做 +30/−30 回归，产品坐标计算本身固定起点。
- 独立 Reviewer 的复验记录见 `REVIEWER_ROUND4.md`（若评审包中存在）。
