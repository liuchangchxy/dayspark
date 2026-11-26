# DaySpark 第四轮：模型与交互收敛结果（2026-11-26）

> 本文件回答“旧实现与新模型是否还在打架”。判定只看**当前构建里真正会执行的那条路径**，不把设计样张、被后加载脚本覆盖的 handler、或只在注释里存在的路径算成能力。
>
> 基线：第三轮冻结 `9360a813`（PR #116）。本轮不修改 Flutter，不合并 PR #113。

## 一、收敛原则

1. **一个事实只有一个写入口。** 计划执行、重复实例完成、提醒、快速添加、备份、AI 凭据分别有且只有一个有效写入路径。
2. **身份先于时间。** 计划段按 `allocation.id` 定位；重复实例按 `todoId@occurrenceDate` 定位。任何“按待办 id + 时间”“按今天/浏览日期/最近一次”代替身份的路径都删除。
3. **`t.plan` 降级为派生显示字段。** 它由 `DS3.syncProjection(t)` 从有效分配中选出，不再作为任何入口的写入源。
4. **旧路径删除而不是在旁边叠新补丁。** 不新增 `flows-v4-*`；被取代的 handler、旧投影、旧备份、旧提醒锚点直接从原文件移除或停用。

## 二、计划执行（TaskAllocation）

| 事实 | 唯一有效路径 | 旧路径处理 |
|---|---|---|
| 一个待办的计划段集合 | `t.plans`，每段 `{id,date,start,end,state,occurrenceDate}`，由 `flows-v3-model.js` 的 `DS3.allocations/addAllocation` 维护 | `t.plan` 只读；旧入口的 `todo.plan = …` 已删除（编辑器死 handler、任务菜单、日历拖拽、AI、Capture） |
| 新增一段 | `DS3.addAllocation(t,{date,start,end,occurrenceDate})`，追加，不覆盖 | 旧“第一次安排 = 赋值 `t.plan`”已删除 |
| 改期/缩放 | 按 `data-alloc` 找 `DS3.planById(t,id)`，`DS3.updateAllocation(t,id,{date,start,end})` | 日历 `pointerup` 不再写 `item.plan`；移动端/月视图只绑定，不另写 |
| 取消一段 | `DS3.cancelAllocation(t,id)`，状态改 `cancelled`，待办保留 | 旧“删除计划数组/清空 t.plan”不再作为取消语义 |
| 完成失效 | `DS3.toggleDone` → `DS3.invalidateAfter`：普通待办失效完成时刻之后的段；重复待办只失效该实例的段；已开始段保留 | 旧 `state.done` 直接置位不再处理待办完成 |
| 展示投影 | `window.plansOn(day)` 唯一实现在 `flows-v3-model.js`，每个 allocation 一条，携带 `allocId` | `flows-v2-calendar.js` 的第二个 `plansOn` 包装已删除；master 仅在流脚本加载前的首帧用旧投影兜底，加载后立即被 `flows-v3-model.js` 覆盖，所有交互都走分配感知实现 |
| 历史 | `t.plans` 中 `cancelled/invalidated` 记录保留；详情“查看全部/历史”入口始终存在 | 取消最后一段后不再把入口一起消失 |

**编辑器草稿**：详情/新建里的“计划执行”只改 `state.draft.plans`（临时 id）或按 `state.planAllocId` 改指定段；保存时 `commitDraft` 通过 `DS3.applyDraftAllocations` 按 id 应用：保留段更新、移除的活动段转 `cancelled` 历史、历史不被清空，再由 `syncProjection` 重算 `t.plan`；取消则整份草稿丢弃。新增一段绝不覆盖第一段。

## 三、重复实例

| 事实 | 唯一有效路径 | 禁止 |
|---|---|---|
| 系列锚点 | `repeatAnchor || seriesStart || due || startDate`；新系列创建时 `ensureSeriesAnchor(t,{creating:true})` | 从计划执行日期推导锚点 |
| 选择实例 | `DS3.requireOccurrence(t,onPick)`：最近 30 天 + 未来 90 天，必须点击某一天 | 默认今天、浏览日期、计划日期、最近一次 |
| 完成/撤销 | `DS3.toggleDone(id,occurrenceDate)` 写 `state.doneInstances[id@date]`；无显式实例先弹选择器 | 写父系列 `status='done'`、猜日期 |
| 已有实例表面 | 日历块用 allocation 的 `occurrenceDate`；遗漏卡用 `data-date`；实例历史用行日期 | 用所在列日期代替绑定日期（计划被改到别的日期时尤其危险） |
| 旧系列单计划 | `legacy:true` 的 allocation 仅作系列投影，不声明某个 occurrence；完成后不失效共享记录；拖拽拒绝并说明 | 把旧投影当成某一天的显式分配 |
| 旧规则迁移 | `legacy-migrate` 必须显式选择时区、锚点、规则后才写入；取消/保留旧规则不改写 | 按设备时区或今天静默重解释 |

## 四、提醒

| 事实 | 唯一有效路径 | 旧路径处理 |
|---|---|---|
| 相对提醒锚点 | 日程开始时间，或待办 `due + dueTime` | 计划执行开始时间不再作为锚点 |
| 无锚点 | 相对项全部禁用并说明原因；只保留“不提醒/绝对时间” | 不再用计划开始兜底 |
| 多提醒 | `remind`（主）+ `reminders[]`（附加）；新建待办、新建日程、详情待办、详情日程、编辑态均支持增删 | 不再只有详情待办一个入口 |
| 表单语义 | 新建写入 `newDraft`，取消不落库；详情编辑写 `state.draft`，取消回滚；非编辑详情的增删立即写对象 | 不再跨表单直接改源对象 |
| 计划变更 | 新增/改期/取消计划不重算提醒字符串 | 提醒不再读计划时间 |

## 五、捕获 / 快速添加

| 输入 | 普通保存 | 另存待办 |
|---|---|---|
| 纯日期（“明天交报告”） | 待办 `due=该日期`，保存前标注“截止” | 同左（待办） |
| 日期 + 时刻（“明天下午三点交报告”） | 默认创建日程（界面显示“将创建日程”） | 待办无 `due/dueTime/plan/remind`，界面显示“待办无截止” |
| 只有标题 | 只记标题，不写日期/计划/截止 | 同左 |
| 跨午夜（23:30 + 60 分钟） | 日程结束为次日 00:30，保存跨日 `startDate/endDate`，不 clamp 到 23:59 | 不写时刻 |

链接/浏览上下文日期不写入待办截止；只有自然语言解析出的纯日期或用户显式选择才写。

## 六、日历、备份、AI 凭据

- **日历拖拽**：固定拖拽起点计算候选时间，连续拖动不累计偏移；写回只改 `allocation.id` 对应记录，改期保留 `occurrenceDate`；事件路径保持原行为。
- **备份导出**：`flows-v3-data.js` 唯一 `backup-export`，真实 Blob + 下载；从失败态重试也真实生成文件；导出前经 `P.redactForBackup` 与本文件兜底清洗凭据。
- **备份合并**：`flows-v3-data.js` 唯一 `backup-merge`，按 id **补齐已有条目**的业务字段并合并分配/提醒/标签（不再把同 id 的示例条目整体跳过），同时恢复 `doneInstances/skipped/localTodos/planSeq/done/deleted*/hiddenCals/purgedIds/trash*`；合并后立即持久化；解析失败不部分写入。真实 `input[type=file]` 入口已做导出→清空→重载→合并回归；单段计划合并也会丢弃旧 `t.plan` 引用，避免未归一化的种子把备份时间重新覆盖。
- **AI 凭据**：真实 Key 只存在页面会话的模块变量 `sessionSecret`，不写入 `P.data/state/TODOS/EVENTS`；`P.data.ai.key` 只保留掩码；旧版明文启动时迁移并清洗；整份备份经 `P.redactForBackup` 去除 `secret/password/token/apiKey` 等字段。
- **AI 计划**：重复待办先 `DS3.requireOccurrence`，写入 `DS3.addAllocation`；普通待办追加第二段不覆盖第一段；AI 消息动作锁定该消息自己的 `todoId`。

## 七、仍保留的原型边界

- 跨设备同步、真实通知投递、原生小组件仍是原型模拟。
- 旧系列单计划（`legacy:true`）的拖拽被拒绝并提示先确认实例；这是有意的安全边界，不是能力删除。
- 真实产品仍应把 AI Key 存在系统安全存储而不是页面会话；原型只验证“不落快照/不进备份”的语义。
