# DaySpark (灵光) 核心功能规范 (SPEC.md)

> **文档性质**：本项目唯一业务规范真理源（Single Source of Truth, SSOT）。
> **核心原则**：所有业务逻辑改动、新功能扩展或缺陷修复，必须**先修订本文档**，再编写测试用例，最后调整实现代码。任何偏离本文档定义的行为均视为 Bug。

---

## 1. 系统定位与核心价值

- **项目名称**：DaySpark (灵光)
- **一句话定位**：自托管的开源 Todo 清单式日历待办应用——Todo 与 Event 均为一等领域记录，Todo 可安排到日历时间中；五平台统一客户端，NAS 自托管跨设备同步，AI 通过 MCP 读写你的数据。
- **目标用户与核心场景**：
  - 场景 1：个人/家庭用户在手机、桌面、网页间维护日程与待办，数据经自托管 NAS 后端同步，不经第三方云
  - 场景 2：用户通过 MCP 让 AI 助手（Claude Code / Codex / ChatGPT connector 等）读取日程与任务、安排 Todo 时间并查询可用时段
  - 场景 3：用户在桌面/锁屏小组件上 glance 今日事件与未完成待办，快速勾选完成
- **核心非功能性指标**：
  - 交互对标 Todo清单的简洁体验（信息密度优先，不大圆角、不渐变、不 AI 味）
  - 同步协议：离线可用，上线后秒级最终一致；冲突字段级 LWW
  - 五平台（Android / iOS / macOS / Windows / Linux + Web）统一代码库
  - 开源许可证：GPLv3

### 1.1 冻结需求 8 条（用户拍板，不可静默变更）

以下 8 条为项目立项时冻结的业务需求，任何修订必须经用户明确确认并同步更新本节：

1. **Todo 与 Event 均为一等领域记录**：Todo 与 Event 语义不同，均可独立创建、编辑和管理；Todo 可以拥有零个或多个 TaskAllocation。Calendar 可以汇合呈现 Event occurrence、TaskAllocation 与可选的 Todo 截止标记。首页导航、默认视图及页面布局由 UX 验证决定，不属于领域冻结条件；Todo 页面仍是任务状态管理的主要入口。
2. **统一五平台客户端**：单一 Flutter 代码库覆盖 Android / iOS / macOS / Windows / Linux（含 Web），功能对齐、体验一致
3. **跨设备同步**：多设备间日程与待办双向同步，离线优先，冲突可预期（字段级 LWW）
4. **AI 可读写 MCP**：暴露 MCP（Model Context Protocol）接口，AI 助手可读取与写入 Event/Todo，并通过工作流工具管理 TaskAllocation（工具面见 P3 及增量扩展契约）
5. **双端小组件**：Android 桌面小组件 + iOS/macOS WidgetKit 小组件，展示今日事件与待办并支持快速操作
6. **自托管 NAS 优先**：同步后端以 Docker 单容器部署在用户自己的 NAS 上（SQLite 单文件 + volume），官方云非必需
7. **开源 GPLv3**：项目以 GPLv3 开源
8. **对标 Todo清单简洁体验**：UX 基准是"Todo清单"的简洁克制，而非功能堆砌型日历应用

---

## 2. 系统架构与数据流转

```mermaid
flowchart LR
    Client[五平台 Flutter 客户端] <-->|push/pull/SSE| Server[Dart 同步后端 NAS Docker]
    Server --> DB[(SQLite 单文件)]
    AI[AI 助手 via MCP] <-->|Streamable HTTP + OAuth 2.1| Server
    CLI[dayspark CLI] <-->|HTTP MCP (/mcp)| Server
    Widgets[双端小组件] --> Client
```

### 核心模块划分
1. **客户端层**：Flutter（Riverpod + Drift + go_router），本地 SQLite 权威存储，离线可用；日历视图基于 kalender 库
2. **同步后端**：Dart（shelf + drift + SQLite），服务器游标 + 幂等 push + 字段级 LWW + SSE 信号；与客户端共享 `dayspark_contracts` 契约 package
3. **AI 接口层**：MCP server 长在后端同进程同数据源；既有 17 个 Event/Todo 工具保持兼容，TaskAllocation 以工作流工具增量扩展；工作流工具优先于 API 映射；无硬删除（trash 软删姿态，对应回收站语义）
4. **小组件层**：versioned JSON 快照（home_widget + App Group / AppWidgetProvider），单写入路径
5. **派生态失效层**：客户端单写入口（`RecordScope`）+ post-commit 领域事件（`record-applied` / `record-removed`）驱动闹钟重排与小组件快照刷新；事件只携带"重读拿不回来"的信息（写前参考时间、硬删前的 reminder id）

---

## 3. 功能清单与业务规则契约 (Feature Matrix)

### 3.1 核心功能 A：Todo、Event 与任务时间安排
- **业务描述**：Todo 与 Event 是两个独立的一等领域记录；TaskAllocation 将一个 Todo 或某次重复 Todo occurrence 与一段执行时间关联。Calendar 可将这些记录投影到同一时间视图，具体页面导航不由领域模型规定。
- **业务规则契约**：
  - 规则 1：Todo 表达需要完成的事项，保留其现有状态、截止时间、重复及父子任务语义；Event 表达特定时间发生的事项，保留其现有时间区间、全天、地点及重复语义。两者可独立创建、编辑、查看及管理。
  - 规则 2：`Todo.dueDate` 是截止时间，不是执行时段。创建、改期或取消 TaskAllocation 不得自动修改 Todo 的 `dueDate`。
  - 规则 3：一个 Todo 可关联零个或多个 TaskAllocation；重复 Todo 的每个 TaskAllocation 绑定一个 occurrence，不自动应用到整个重复系列。
  - 规则 4：TaskAllocation 表达为 Todo 预留的一段执行时间，具有独立身份和生命周期；可单独改期或取消。取消一个 Allocation 不删除或取消 Todo。
  - 规则 5：用户取消的 Allocation 保留历史，普通 Calendar 不显示；Todo 历史可查看。Todo 完成时，所有 `startAt >= completedAt` 的 Allocation 转为 `invalidatedByCompletion` 并保留记录；已结束与正在进行的 Allocation 保持原状态。取消 Todo 完成不会自动恢复已失效 Allocation，用户须显式重新安排。
    - 完成边界比较统一使用 UTC instant：比较前将 `startAt`、`endAt`、`completedAt` 转为 UTC 并截断至毫秒，不四舍五入。`endAt <= completedAt` 保留为历史；`startAt < completedAt < endAt` 保持 active 至原定结束；`startAt >= completedAt` 转为 `invalidatedByCompletion`（包括相等边界）。
  - 规则 6：TaskAllocation 仅在自身状态为 `active`、父 Todo 未取消且未进入回收站时显示并占用 busy time。若 Todo 已完成，按 `completedAt` 防御性校验：`startAt >= completedAt` 的 Allocation 不显示为有效安排且不占 busy；`startAt < completedAt < endAt` 的进行中 Allocation 保留并继续占用至原 `endAt`。已结束时段不影响未来空闲查询。`cancelledByUser` 与 `invalidatedByCompletion` 不占 busy time。
  - 规则 7：Todo 进入回收站期间，其 Allocation 记录与状态保留，但不显示且不占用 busy time；恢复 Todo 后，原本为 `active` 的 Allocation 恢复显示和占用，其他状态不变。永久删除 Todo 时，其 Allocation 一并永久删除并按同步 tombstone 传播。
  - 规则 8：重复 Todo 的 occurrence 采用本地钟点语义。存在 `startDate` 时以其作为 recurrence anchor；无 `startDate` 但有 `dueDate` 时以 `dueDate` 为 anchor；两者都没有时不允许创建 occurrence 级 Allocation。重复 Todo 必须持久化并同步其 `recurrenceTimeZone`（IANA 时区）；不得用接收设备当前时区替代。跨设备 occurrence identity 必须包含稳定的系列身份、本地日期时间和 IANA 时区。UTC recurrence-id 仅可作为迁移过渡实现，不得冻结为长期协议。既有重复 Todo 若无法可靠恢复其系列时区，不得静默推断；在时区被明确保存前，不允许为该系列创建 occurrence 级 Allocation。
  - 规则 9：首版 TaskAllocation 不独立支持提醒；Todo 自身现有 Reminder 语义保持不变。Allocation 改期或取消不改变 Todo Reminder 的参考时间。
  - 规则 10：Calendar 是 Event occurrence、有效 TaskAllocation 和可选 Todo deadline marker 的时间投影，不是新的领域记录容器。截止标记不占 busy time。日历拖动 TaskAllocation 只修改该 Allocation 的时间，不修改 Todo 截止时间或 occurrence identity。
  - 规则 11：回收站为软删除；MCP/外部写入接口不提供物理硬删除，使用归档/软删姿态。永久清空按既有 tombstone 与保留期规则处理。
  - 规则 12：UI 文本必须 l10n 中英双语，禁止硬编码

#### TaskAllocation 生命周期状态

TaskAllocation 的领域状态为单一字段：

| 状态 | 含义 | 是否占 busy time |
|---|---|---|
| `active` | 当前有效的任务安排 | 是；父 Todo 未取消/回收且通过 `completedAt` 边界校验时 |
| `cancelledByUser` | 用户单独取消该次安排 | 否；保留历史，普通 Calendar 隐藏 |
| `invalidatedByCompletion` | Todo 完成时使尚未开始的安排失效 | 否；保留历史 |

这三种领域状态不等同于同步记录的 `deleted` tombstone。Allocation 仅在永久删除时使用 tombstone；Todo 软删除期间，Allocation 保持原领域状态，由父 Todo 的回收站状态决定是否投影。

### 3.2 核心功能 B：跨设备同步（P2）
- **业务描述**：自托管后端的双向同步
- **业务规则契约**：
  - 规则 1：记录 `{id: UUIDv7, type, payload, rev, deleted(tombstone), serverTs}`；`type` 包含 `event`、`todo`、`task_allocation`
  - 规则 2：push 幂等（opId 唯一约束），逐条结果返回，绝不整批回滚
  - 规则 3：pull 走服务器单调不透明 cursor（禁用时间戳当游标）；tombstone 走 pull，保留 ≥45 天
  - 规则 4：冲突 = 服务器时间戳字段级 LWW；同秒用 opId 字典序破平。TaskAllocation 的生命周期状态以一个字段同步；Calendar 与 busy-time 投影还必须校验父 Todo 回收站/取消状态及 `completedAt` 边界，不能仅凭 Allocation 行判定有效。
  - 规则 5：SSE 只发 `{cursor}` 信号，不发载荷
  - 规则 6：新增 RecordType 必须有显式客户端 capability / protocol contract。服务端只能向声明支持该类型的客户端返回 `task_allocation`；未声明支持的旧客户端继续同步 `event` / `todo`，不得收到其无法解析的类型，也不得创建或修改 Allocation。能力字段及 wire contract 必须定义在 `dayspark_contracts` 并由测试校验，不得散落硬编码版本号判断。发布顺序为：先发布可解析 Allocation 的客户端，再启用服务端按 capability 下发，最后开放 MCP 或其他会创建 Allocation 的外部写接口。禁止以要求所有旧客户端全量升级代替兼容门控。

### 3.3 核心功能 C：MCP AI 读写（P3）
- **业务规则契约**：
  - 规则 1：现有 17 个工具（读 7 + 写 10，event+task）保持兼容；Allocation 工具采用工作流接口增量扩展，工具总数不作为冻结契约。候选工作流包括 `schedule_task`、`reschedule_task_allocation` 和 `cancel_task_allocation`；`find_free_time` 必须将有效 TaskAllocation 纳入 busy 集合。TaskAllocation 取消工具必须针对单条 Allocation；因一个 Todo 可有多个安排，不提供语义含混的批量 `unschedule_task`。
  - 规则 2：时间 ISO 8601 + IANA timezone；RRULE 结构化对象
  - 规则 3：`get_events` 范围默认 now→+7d，上限 366 天；`find_free_time` 的 busy 集合由时间窗内的 Event occurrence 与有效 TaskAllocation 构成。
  - 规则 4：错误以工具结果 `{isError, {code, message, hint}}` 返回，不是 JSON-RPC error
  - 规则 5：不提供 `delete_task`（archive 姿态），与回收站语义对齐
  - 规则 6：传输双形态：`POST /mcp` Streamable HTTP + OAuth 2.1（DCR + PKCE-S256 + token 轮换）；stdio wrapper 喂本地 Agent

### 3.4 P1–P4 功能矩阵

| Phase | 主题 | 关键交付 | Status / 状态 |
| :--- | :--- | :--- | :--- |
| **P1** 客户端地基重构 | 单机可用、删历史包袱 | 删除自研 CalDAV 层与客户端 MCP server（schema v8）；日/周/月视图换 kalender（`^0.17.x` 钉 minor）；S1/S3 级 bug 清零（通知链、状态与交互批）；双端小组件数据通路修复；设置页/首页瘦身 | 状态→ ROADMAP |
| **P2** 同步后端 + 客户端同步 | 跨设备同步落地 | `dayspark_contracts` 契约 package；Dart shelf 后端（auth/JWT、push/pull/SSE、LWW/幂等/tombstone）；客户端 outbox + pull applier + SSE 监听；Docker 部署 NAS；双设备 e2e | 状态→ ROADMAP |
| **P3** MCP + CLI | AI 操控数据 | 后端 MCP server（17 工具 + 3 resources + OAuth 2.1 双轨）；`tool/mcp_stdio_wrapper`；`tool/dayspark_cli` HTTP MCP 客户端；MCP e2e 矩阵 + 四客户端 QA 说明 | 状态→ ROADMAP |
| **P4** 平台补齐 + Todo清单体验 | 品质与体验收敛 | iOS bundle id/App Group 统一 `com.dayspark.app` 族 + TestFlight；小组件 v2 **三变体**（Today/Upcoming/月点阵，quick-add deep link、pendingTaps、monthDots、l10n/暗色）；通知全清单验收（time-sensitive + entitlements 接线）；Todo清单 UX 批（六件事收敛、节气/调休、隐藏已完成、设置 IA 终态、日历体验清欠）；Windows 通知上游复查（stub 保留） | 状态→ ROADMAP |

**明确出范围（P5+ 以后，不进本计划）**：番茄钟/数据复盘、CalDAV 导出层、E2EE。

---

### 3.5 核心功能 D：派生态一致性（闹钟 / 小组件）

- **业务描述**：记录（事件/待办/TaskAllocation）的派生副作用——本地通知/闹钟的重排、桌面小组件快照的刷新——必须在每次记录写入后收敛到当前行状态，不因写入入口不同而静默失效
- **TaskAllocation 规则**：首版 Allocation 不创建独立 Reminder，不接入 `ReminderReconciler` 的时间参考字段，也不修改 Todo Reminder。Allocation 变化可触发既有 Widget 快照刷新总线，但首版 Widget JSON 与原生消费端不增加 Allocation 项。
- **Phase 1 范围**：仅交付普通非重复 Todo 的本地 TaskAllocation 创建、Calendar 显示、改期与取消，以及 Todo 完成时本地事务内的未来 Allocation 失效；本阶段不实现 Allocation 同步/outbox、busy-time、重复 Todo 或 occurrence identity。重复 Todo 的安排入口应隐藏或明确拒绝，不得推测 occurrence。`task_allocations.todo_id` 当前使用本地 FK cascade；永久删除引起的 Allocation tombstone 传播是同步阶段的前置工作，本地 cascade 不代表已实现同步删除。
- **业务规则契约**：
  - **规则 1**：进程内一切记录写入（用户操作、ICS 导入、账号重置、同步应用）必须经单写入口 `RecordScope.run`；写入即登记，**提交后**发布；对不存在的 localId 仍会发出一条 `applied`（`previousReference` 为 null），消费端必须容忍"重读无此 id"并按 inactive 处理。**例外（派生文物化写）**：`reminders.triggerTime` 的回写经单写入口但**登记为空**——它不改变领域事实，只物化派生结果（重排器算出的触发时刻），故不发领域事件（空批被 `publish` 直接丢弃），避免事件在总线上转一圈回到重排器自己
  - **规则 2**：发布边界 = 事务提交。"`db.transaction()` 返回"即"已提交"；事务回滚 → **零发布**
  - **规则 3**：事件粒度 = per-record + per-transaction batch；**不携带 after 值**（消费端提交后重读行为准）；**不做事件溯源/持久化/重放**
  - **规则 4**：消费端必须幂等；取消须**按原因分档**，活跃 snooze（在 `reminder.id` 上重排、其行内 `triggerTime` 已成过去）不得被清。分档含：`removed`（硬删事件携带的通知 id）、`inactive`（父行回收站 / 待办已完成 / 参考时间为空）、`pastDue`（期望时刻已成过去）——其中**清空参考时间 → 取消 OS 通知，reminder 行保留为惰性**（行留在库里但不再对应任何通知，重新给出参考时间后同一 id 可被再次调度）。同理，**软删 / 恢复**（事件进回收站 / 出回收站）也是“行保留 + 靠父行状态判定”：软删只置父行 `deletedAt`、提醒行**保留**为惰性并登记 `applied`（**不登记 `removed`**——记录仍在回收站里，而 `removed` 的语义是“记录已不存在”），由 `inactive` 档撤 OS 通知；恢复同样登记 `applied`，同一批 id 按行内 `triggerTime` 重新排上（`start` 未变则 Δ=0、绝对时刻不变，与待办侧对称）。只有**硬删**（事件 `hardDeleteEventWithChildren` / `emptyEventTrash`，待办 `permanentDelete` / `emptyTrash`）才连带删除提醒行、登记 `removed` 并携带 `reminderIds`。冷启动/恢复前台全量重算时的**保守门只作用于 `pastDue` 档**（不撤本次会话没调度过的 id，因 snooze 会把 OS 时刻排到未来、行内时刻停在过去，按行判会误杀）；`removed`/`inactive` 档的父行状态即权威，冷启动也必须撤（含 snooze）。`nextTrigger` 返回过去时刻时按 `pastDue` 档处理，不得当未来提醒排；重排器算出的期望时刻须**回写** `reminders.triggerTime`（该行值是下一次位移的锚，不回写会让第 2 次改期起按上一段位移漂移），回写方式见规则 1 的派生文物化写例外。位移规则**不区分全天与定时事件**：全天事件的日期改动同样按 Δ 搬迁提醒（旧 UI 补丁带 `!_isAllDay` 守卫，撤除临时通道后不再有这条例外）。同理，**待办"取消完成"不必然重排**：参考时间为空（从未设 `dueDate`）时按 `inactive` 档撤掉其通知、行保留为惰性（与"清空参考时间"同一口径），不做"恢复到旧时刻"式的重排
  - **规则 5**：**跨进程写**（`bin/dayspark.dart` 直开同一库文件）不受缝覆盖，由冷启动/恢复前台全量重算兜底；同理，**同步 applier 不得回灌 outbox**——远端真值落地只写行 + 登记领域事件（回灌会把服务端权威值回声成一次本地推送：改期回声、tombstone 回声删除）
  - **规则 6**：Todo 完成与因此失效的未来 TaskAllocation 状态变更必须在客户端同一数据库事务中写入；Allocation sync/outbox 启用后，两者必须共同进入 outbox。服务端/MCP 完成 Todo 的路径必须以可收敛的原子写入组传播这些状态变化。远端 applier 仍不得回灌 outbox。

## 4. 数据结构与接口契约 (Data Contracts)

### 4.1 同步记录结构
```json
{
  "id": "UUIDv7 (客户端生成)",
  "type": "event | todo | task_allocation | …",
  "payload": { "…业务字段…" },
  "rev": 1,
  "deleted": false,
  "serverTs": "服务器权威时间戳"
}
```

### 4.1.1 TaskAllocation payload

```json
{
  "todoSyncId": "父 Todo 的 UUIDv7",
  "occurrenceId": "可空；重复 Todo 使用稳定的本地 occurrence key",
  "startAt": "UTC ISO-8601 instant",
  "endAt": "UTC ISO-8601 instant",
  "state": "active | cancelledByUser | invalidatedByCompletion",
  "createdAt": "UTC ISO-8601 instant",
  "updatedAt": "UTC ISO-8601 instant"
}
```

重复 Todo 的 `occurrenceId` 由系列 Todo 的同步 ID、本地 recurrence 日期时间和持久化 IANA 时区共同确定；实际 payload 中不重复编码系列 ID。非重复 Todo 的 `occurrenceId` 为 null。`startAt`/`endAt` 是被安排的实际瞬间；改期不改变 `occurrenceId`。`state` 是单字段状态值，避免字段级 LWW 将状态与取消原因拆开合并。

Todo 的 `recurrenceTimeZone` 是重复系列的 IANA 时区，必须写入 Todo payload 并跨设备同步；接收端不得用本机当前时区替代。

### 4.2 核心同步接口
| 接口 | 输入参数 | 返回值 / 结果 | 说明 |
| :--- | :--- | :--- | :--- |
| `POST /sync/push` | `{ops:[{opId, type: upsert\|delete, recordId, fields, baseRev}]}` | 逐条 `{status: applied\|conflict\|rejected}` + piggyback 远端变更 | 幂等；绝不整批回滚 |
| `GET /sync/pull` | `cursor, limit` | `{changes[], nextCursor, hasMore}` | cursor 单调不透明 |
| `GET /sync/stream` | SSE | `{cursor}` 信号 | 只发信号不发载荷 |

---

## 5. 边缘情况与边界防御 (Edge Cases)

1. **离线 / 断网**：客户端本地写入立即生效进 outbox；上线后按序 push；pull 断点续传（cursor）
2. **冲突防御**：字段级 LWW + 同秒 opId 破平；conflict 不静默丢弃，逐条状态可追溯
3. **幂等防御**：同一 opId 重复 push 只应用一次（唯一约束）
4. **删除传播**：Event/Todo 软删按现有墓碑协议传播，保留 ≥45 天后 GC；TaskAllocation 的用户取消与完成失效是 payload 状态变更，不是删除墓碑。外部接口不提供物理硬删
5. **重复事件**：展开绑定可见窗口（before/after），不做全量时间轴展开；拖拽重复事件须防改坏整个系列
6. **重复 Todo 安排**：TaskAllocation 绑定单个 occurrence identity，不自动套用到重复系列；identity 使用 Todo 系列稳定同步 ID + 原 occurrence 本地日期时间 + IANA 时区，不使用改期后的 Allocation 时间。无 `startDate` 且无 `dueDate` 的重复 Todo 不可创建 occurrence 级 Allocation
7. **版本解析**：构建号比较用 `int.tryParse`，解析失败视为无更新，不得抛异常
8. **平台差异**：UI/交互改动必须显式考虑桌面鼠标 vs 移动触摸（平台感知法则）；本地验证命令用 `dart analyze .`（`flutter analyze` 在中文路径下 LSP 崩溃）
9. **派生态一致性**：记录写入的派生态失效由 post-commit 领域事件驱动；事务回滚不得产生事件；事件批量边界 = 事务边界
10. **跨进程写入**：外部进程直写库文件（CLI）不产生领域事件，客户端靠冷启动/恢复前台重算收敛
11. **Web 平台防御**：`dart:io` 的 `Platform.*` 在 dart2js 产物里是一调用就抛的 stub——`runApp` 之前任何一次读取即整页白屏（v0.25.0 事故，见 DECISIONS 2026-09-26）。全仓平台判断只允许经唯一读点 `lib/core/utils/platform_target.dart`（`kIsWeb` 短路在前，导出 `isAndroid`/`isIOS`/`isNativeMobile`）；禁止用 `defaultTargetPlatform` 替代 `Platform.isX`（web 上它按浏览器 UA 返回 android/iOS，会去调不存在的原生实现）。防复发：静态守卫测试（`test/architecture/web_platform_guard_test.dart`）+ CI 与 release 双链路 web 冒烟截图断言（`tool/web_smoke.dart`，纯白即红）
