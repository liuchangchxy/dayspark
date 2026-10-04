# TaskAllocation — 实施计划

> **状态**：Phase 1 已完成；产品契约见 `SPEC.md`，裁定依据见 `DECISIONS.md` [2026-10-04]。
> **本阶段目标**：验证普通非重复 Todo 的本地 TaskAllocation 领域模型和 Calendar Projection。

## 1. Phase 1 精确范围

用户链路：普通非重复 Todo → 创建 TaskAllocation → Calendar 显示 → 改期 → 取消。

包含：

- Drift 新表及 additive schema migration；allocation 的本地 sync identity 可按既有记录模式预留，但本阶段不增加同步协议/outbox 行为。
- 本地领域模型、通过 `RecordScope` 的单写 Writer、Provider 与测试。
- 仅接受存在、未完成、未取消、未回收站且非重复的 Todo。
- 同一个 Todo 可以有多个 Allocation。
- 改期只更新 Allocation 时间；取消只将其状态改为 `cancelledByUser`，保留记录。
- Calendar 在现有 Event 投影中组合显示 active Allocation；仅 active 项显示。
- 用户操作文案使用中英文 l10n；不改变首页导航。

明确不包含：重复 Todo、`recurrenceTimeZone`、occurrence identity、跨设备同步、busy-time / `find_free_time`、MCP Allocation 写工具、Widget 输出、Allocation Reminder、Today/Timeline、自动排程、estimate / actual duration。

重复 Todo 的安排入口必须隐藏或明确拒绝，绝不推测 occurrence。Todo `dueDate` 与 Allocation 完全独立，所有 Allocation 写入路径均不得更新 `dueDate`。

## 2. 当前实现接缝

| 接缝 | 当前状态 | Phase 1 处理 |
|---|---|---|
| 客户端数据库 | Drift schemaVersion 9；Todos/Events 分表 | additive 升至 10，仅新增 TaskAllocations 表；不增加 `recurrenceTimeZone` |
| 记录写入 | Provider → `RecordScope` → Writer | 新增 AllocationWriter；所有 create/reschedule/cancel 写入走统一缝 |
| Calendar | Event range provider、occurrence 展开与 kalender adapter | 保留 Event 行为，组合 active Allocation adapter，并使用独立 tap/change 路由 |
| Reminder / Widget | 由现有 Event/Todo 投影刷新 | 不新增 Allocation reminder 或 Widget 字段；是否触发已有快照刷新只按现有记录总线机制处理 |
| 同步 | 现有同步仅认识 Event/Todo | Phase 1 不发送、不接收 `task_allocation`，不改 contracts/server/outbox/applier |

## 3. 最小领域与数据库模型

本阶段字段仅为：

- 本地整数主键（遵循本地 Drift 模式）；
- `todoId`（本地 Todo 引用）；
- `startAt`、`endAt`（UTC instant；本地 SQLite 以 epoch 毫秒存储，半开区间且 `endAt > startAt`）；
- `state`：`active` / `cancelledByUser`；
- 创建和更新时间戳。

本阶段不添加 `occurrenceId`、timezone、同步字段、tombstone、状态失效级联字段或估时/来源元数据。若既有数据库模式强制记录 UUID sync identity，则仅保留该基础字段，不实现其跨设备含义。

schemaVersion 从 9 升至 10。新建 `TaskAllocations` 表，Todo 外键采用与项目现有策略一致的本地引用/级联规则；索引支持按 Todo 查询和 Calendar 时间窗查询。迁移不回填安排、不改 Todo/Event 数据、不从 `dueDate` 造时间段。更新 schema snapshot 与 migration tests，验证旧数据保留、空表升级、约束和索引。

## 4. 写入与 Calendar 行为

- 创建：校验父 Todo 可安排且 `rrule == null`；写入一条 active Allocation。可重复创建，多条安排互不覆盖。
- 改期：仅更新目标 Allocation 的 `startAt/endAt/updatedAt`；身份、Todo 字段和 `dueDate` 不变。Phase 1 只允许改期 active 项；终态记录不可复活。
- 取消：`active → cancelledByUser`，保留数据；不得删除 Todo 或 Allocation 行。
- Calendar：事件与 active Allocation 组合呈现；取消项隐藏。Allocation 点击打开父 Todo；Allocation 拖动/resize 只走 Allocation 更新 Provider。
- 重复 Todo：创建入口不展示安排动作；任何绕过 UI 的创建调用也必须拒绝。
- Todo 完成、回收站和永久删除的完整 Allocation 生命周期级联留待后续阶段；Phase 1 对已完成/回收站父 Todo 拒绝创建，并通过投影过滤不可用父项。

## 5. 测试与验收

先添加并确认失败的测试，再实现：

1. migration：v9 → v10 保留原 Todo/Event/Reminder 行，新表为空且可重复打开。
2. Writer/Provider：非重复有效 Todo 可创建多个 Allocation；时间区间校验；拒绝重复、完成、软删父 Todo。
3. dueDate 不变量：create/reschedule/cancel 前后 Todo dueDate 字节级等值。
4. cancel：状态变为 `cancelledByUser`，行保留；重复取消或改期终态项的行为明确且幂等。
5. Calendar projection：active 显示；cancelled 不显示；父 Todo 缺失/回收/完成时不显示。
6. Calendar interaction：Allocation 拖动/resize 更新目标 Allocation，不调用 Event 更新路径；Event 点按、拖动与重复展开回归。
7. 重复 Todo 的安排入口隐藏；直接调用 Writer 仍拒绝。
8. 遵循仓库门禁运行 `dart analyze .` 与 `flutter test`；若工具缺失或无法运行，报告为 NOT RUN，不得宣称通过。

## 6. 后续阶段（不属于当前授权实现范围）

- **Phase 1 基线已补齐 — 本地完成生命周期 D6**：Todo 完成与未来 Allocation 失效在同一 RecordScope 事务执行；比较使用 UTC 毫秒边界；完成中的时段继续显示至原定结束，历史保留，用户取消状态不覆盖；取消完成不自动恢复。Todo 回收/恢复仍由父记录投影状态控制，本地永久删除明确清理 Allocation。Allocation 同步 tombstone 仍属后续同步前置项，见下方记录。
- **后续 B — 重复 Todo**：`recurrenceTimeZone` IANA 持久化、旧数据未知时区的安全降级、本地 wall-clock occurrence identity、DST 与规则编辑兼容。不得以设备当前 timezone 静默填充旧数据。
- **后续 C — 同步兼容**：contracts 明确 `task_allocation` capability；服务端只向声明支持的客户端返回 Allocation。旧客户端继续同步 Event/Todo。发布顺序为兼容新客户端、服务端 capability 下发、最后开放 MCP/外部 Allocation 写入。
- **后续 D — busy-time**：将 active Allocation 纳入 `find_free_time`，并按状态、父 Todo 生命周期及完成边界过滤。
- **后续 E — MCP**：评估并实现单条 schedule/reschedule/cancel 工作流工具。

### 同步实现前置项：父 Todo 永久删除

当前 `task_allocations.todo_id` 使用 SQLite `ON DELETE CASCADE`，但生产连接不保证开启 SQLite 外键执行。Phase 1 的 Todo 永久删除/清空回收站 writer 因此显式删除 Allocation 行，保证本地无孤儿记录；此处尚不生成 Allocation 自身的同步 tombstone。进入任何 TaskAllocation 同步实现前，必须把该删除传播扩展为显式同步领域操作：先捕获并登记每条 Allocation 的 tombstone，再删除父 Todo；不得把数据库 cascade 当作同步删除机制。Phase 1 不实现该同步路径，也不宣称已满足 Allocation tombstone 传播。

Phase 1 验收：migration、创建/改期/取消、dueDate 不变量、重复 Todo 拒绝、Calendar active 投影及交互测试通过；`dart analyze .` 零 issue，`flutter test` 全量通过。当前不包含跨设备同步或 busy-time 验收。

以上后续阶段均需先按 SPEC 补足相应实施 brief 和测试，不得作为 Phase 1 的隐含交付。
