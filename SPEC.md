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
5. **双端小组件**：Android 桌面小组件 + iOS WidgetKit 小组件，展示今日事件与待办并支持快速操作；macOS、Windows、Linux 与 Web 不调用 `home_widget` 平台 API
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
  - 规则 1：Todo 表达需要完成的事项，保留其现有状态、截止时间、重复及父子任务语义；Event 表达特定时间发生的事项，保留其现有时间区间、全天、地点及重复语义。两者可独立创建、编辑、查看及管理。Todo 列表行的完成控件只切换完成状态；标题/内容区域打开 Todo 编辑页，二者的点击区域必须彼此独立。
  - 规则 2：`Todo.dueDate` 是截止时间，不是执行时段。新建普通 Todo 在用户未显式选择截止时间时 `dueDate` 必须为 null，不得默认填入今日。移除启动时将逾期 Todo 的 `dueDate` 批量篡改为今日的行为；逾期待办保持其真实原截止时间，若用户计划今日执行，应通过 TaskAllocation 安排。创建、改期、取消 TaskAllocation 或完成 Todo，均不得自动修改 Todo 的 `dueDate`；修改截止时间必须通过显式 deadline edit 操作。
  - 规则 3：一个 Todo 可关联零个或多个 TaskAllocation；重复 Todo 的每个 TaskAllocation 绑定一个 occurrence，不自动应用到整个重复系列。
  - 规则 4：TaskAllocation 表达为 Todo 预留的一段执行时间，具有独立身份和生命周期；可单独改期或取消。取消一个 Allocation 不删除或取消 Todo。日历空白时间槽点击提供“新建日程（Event）”与“安排待办（Schedule Todo）”双入口；选择安排待办可在当前时间区间内为已有的未完成普通 Todo 创建 TaskAllocation，而不创建 Event，且被安排 Todo 的 `dueDate` 保持完全不变。
  - 规则 5：用户取消的 Allocation 保留历史，普通 Calendar 不显示；Todo 历史可查看。普通（非重复）Todo 完成时，所有 `startAt >= completedAt` 的 Allocation 转为 `invalidatedByCompletion` 并保留记录；已结束与正在进行的 Allocation 保持原状态。重复 Todo 的完成依规则 15 限定到单个 occurrence。撤销完成不会自动恢复已失效 Allocation，用户须显式重新安排。
    - 完成边界比较统一使用 UTC instant：比较前将 `startAt`、`endAt`、`completedAt` 转为 UTC 并截断至毫秒，不四舍五入。`endAt <= completedAt` 保留为历史；`startAt < completedAt < endAt` 保持 active 至原定结束；`startAt >= completedAt` 转为 `invalidatedByCompletion`（包括相等边界）。
  - 规则 6：TaskAllocation 仅在自身状态为 `active`、父 Todo 未取消且未进入回收站时显示并占用 busy time。普通 Todo 完成时依其 `completedAt` 防御性校验边界；重复 Todo 则依对应 occurrence 的稀疏实例状态校验，不得读取父 series 的完成字段来隐藏其他实例安排。已结束时段不影响未来空闲查询。`cancelledByUser` 与 `invalidatedByCompletion` 不占 busy time。
  - 规则 7：Todo 进入回收站期间，其 Allocation 记录与状态保留，但不显示且不占用 busy time；恢复 Todo 后，原本为 `active` 的 Allocation 恢复显示和占用，其他状态不变。永久删除 Todo 时，其 Allocation 一并永久删除并按同步 tombstone 传播。
  - 规则 8：重复 Todo 的 occurrence 采用本地钟点语义。存在 `startDate` 时以其作为 recurrence anchor；无 `startDate` 但有 `dueDate` 时以 `dueDate` 为 anchor；两者都没有时不允许创建 occurrence 级 Allocation。重复 Todo 必须持久化并同步其 `recurrenceTimeZone`（IANA 时区）；不得用接收设备当前时区替代。跨设备 occurrence identity 必须包含稳定的系列身份、本地日期时间和 IANA 时区。UTC recurrence-id 仅可作为迁移过渡实现，不得冻结为长期协议。既有重复 Todo 若无法可靠恢复其系列时区，不得静默推断；在时区被明确保存前，不允许为该系列创建 occurrence 级 Allocation。
  - 规则 9：首版 TaskAllocation 不独立支持提醒；Todo 自身现有 Reminder 语义保持不变。Allocation 改期或取消不改变 Todo Reminder 的参考时间。
  - 规则 10：Calendar 是 Event occurrence、有效 TaskAllocation 和可选 Todo deadline marker 的时间投影，不是新的领域记录容器。截止标记不占 busy time。日历拖动 TaskAllocation 只修改该 Allocation 的时间，不修改 Todo 截止时间或 occurrence identity。
  - 规则 11：回收站为软删除；MCP/外部写入接口不提供物理硬删除，使用归档/软删姿态。永久清空按既有 tombstone 与保留期规则处理。
  - 规则 12：UI 文本必须 l10n 中英双语，禁止硬编码
  - 规则 13：服务端 busy-time 是 Event occurrence 与有效 TaskAllocation 的统一只读投影，不是持久化实体。单次查询按半开区间 `[startAt, endAt)` 裁剪到请求窗口；空闲查询只消费裁剪、排序并合并后的区间。相邻和重叠 busy 区间合并，Event 与 Allocation 使用同一规则。Todo `dueDate` 及没有 Allocation 的 Todo 不占用时间。Event 沿用现有语义：查询排除 tombstone 与 `deletedAt` 软删行，按窗口展开 recurrence；Event 契约没有取消状态，故当前不额外过滤未定义的 status值。All-day Event 使用既有有效结束时刻规则（正长度沿用 `endDt`，否则占用 24 小时）。
  - 规则 14：TaskAllocation 的 busy 有效性同时检查 Allocation 自身未 tombstone 且 `state == active`，并检查父 Todo 已解析、未 tombstone、未软删除且未取消。普通 Todo 依其 `completedAt` 校验；重复 Todo 必须解析 Allocation 的 `occurrenceId` 与对应实例状态，仅该实例的完成边界可使其安排不占用，其他 occurrence 不受影响。无法解析实例状态时 fail closed，且不得从旧 series 完成字段推断具体实例。
  - 规则 15：重复 Todo 的父 Todo 定义 TaskSeries，RecurrenceSpec 与稳定 `occurrenceId` 定义虚拟 TaskInstance。完成与撤销完成属于 `(todoSyncId, occurrenceId)`，调用必须提供有效 `occurrenceId`；缺少时拒绝。完成实例不将父 Todo 标为 `COMPLETED`，也不改变其他实例。该实例完成边界后开始的 active Allocation 失效；已结束或正在执行的 Allocation 保持原状态。撤销只清除同一实例状态，不自动恢复已失效 Allocation。Series 取消/归档与实例完成分离。仅持久化发生状态变化的实例；其他实例由 RecurrenceSpec 有界、惰性生成。真实 UI 保持 series row 并打开 occurrence selector。missed occurrence 保持 pending/actionable，跨日不得自动完成或跳过；selector 默认显示最近 30 天与未来 90 天，并支持按 30 天分页访问更早 obligation，不物化无限实例。通用原生小组件只有 series ID 时不得替用户选 occurrence，也不得把重复系列当成普通单次任务完成。Rule 修改后不再匹配的已完成实例仍按旧 key 保留为历史 orphan。既有 `rrule != null && status == COMPLETED` 无法定位到具体 occurrence，必须保留为 legacy series completion，不伪造实例状态；用户显式重开 series 后才允许新的实例级操作。
  - 规则 16：Today / Action 是纯派生投影（derived projection），不得建立新的持久化实体或 DailyPlan。Home 默认首选视图为 Action，并保留 Action、Calendar、Todos 三个一等 projection。已持久化保存 Calendar/Todos 默认偏好的老用户继续尊重其偏好；未设置偏好者默认进入 Action。
    - Action 投影内容包括：① 今日 EventOccurrence；② 今日有效普通 Todo 的 TaskAllocation（计划执行时间）；③ 今日 deadline 的普通 Todo；④ 逾期未完成普通 Todo（保持原真实截止日期）；⑤ 收件箱/未安排（Inbox/Unplanned）紧凑入口及数量。
    - 时间安排（Allocation）与截止事实（dueDate）在视觉与文案上严格区分；同一 Todo 若今日既有 Allocation 又有 deadline，允许分别在计划区与截止区展示，严禁为了去重抹杀事实。已完成项默认折叠或隐藏。
    - 从 Action 中直接完成普通 Todo 或 Allocation 必须复用现有 Todo domain writer/provider，不建立第二套完成路径。
  - 规则 17：待办列表行的待办项必须保留直接可点击的完成 Checkbox。六件事（Six Things）仅作为呈现与专注上限（presentation/focus cap），不创建 DailyPlan 实体；序数编号（ordinal）和拖拽排序不得替换或阻碍完成 Checkbox 的直接交互。
  - 规则 18（Phase 2 重复任务 Action Loop 闭环）：
    - Action 投影必须包含：今日 actionable recurring TaskInstances（DATE: LocalDate == civil date; DATE-TIME: resolved instant 在本地日窗口内）、最近 30 天 pending missed TaskInstances（按同一值类型规则早于今日边界）、Earlier missed 历史入口、今日 occurrence-bound TaskAllocations、今日完成的 TaskInstances（折叠展示在今日已完成区，携带 exact occurrenceId 供 reopen）、以及 unknownLegacy / unsupported 重复系列的紧凑确认卡片。
    - 每一个 TaskInstance 投影与交互操作必须携带稳定显式的 `(todoId, todoSyncId, occurrenceId)`，绝不根据 today、slot date、Todo id 或 dueDate 隐式推测 occurrence。
    - 日历空白槽安排待办支持选择重复任务，但必须通过共享 selector 显式选取具体 occurrenceId 后创建 TaskAllocation，不创建 Event，不修改 `dueDate`。
    - 完成与取消完成必须经由现有领域写入器（`TaskInstanceWriter`）以精确 `occurrenceId` 执行，不得标记父系列为 COMPLETED，不影响兄弟实例，仅使该 occurrence 的未来 active TaskAllocation 失效。

#### TaskAllocation 生命周期状态

TaskAllocation 的领域状态为单一字段：

| 状态 | 含义 | 是否占 busy time |
|---|---|---|
| `active` | 当前有效的任务安排 | 是；父 Todo 未取消/回收且通过 `completedAt` 边界校验时 |
| `cancelledByUser` | 用户单独取消该次安排 | 否；保留历史，普通 Calendar 隐藏 |
| `invalidatedByCompletion` | Todo 完成时使尚未开始的安排失效 | 否；保留历史 |

这三种领域状态不等同于同步记录的 `deleted` tombstone。Allocation 仅在永久删除时使用 tombstone；Todo 软删除期间，Allocation 保持原领域状态，由父 Todo 的回收站状态决定是否投影。

#### 3.1.1 重复 Todo 系列与 occurrence 契约

- **领域真值**：正式重复 Todo 使用原子 `RecurrenceSpec`：`anchor { source: start|due, valueType: date|localDateTime, value: offset-free local value }`、IANA `timeZone`、规范化 `rrule`。只有 `startDate` 时 anchor 来源为 `start`；否则使用 `dueDate`；两者均无时不展开 occurrence，也不允许 occurrence-bound Allocation。`startDate` 决定 occurrence identity，`dueDate` 是相应 Todo 的 deadline。DATE-only 值始终是日历日期，不是午夜 instant。
- **时区**：新重复 Todo 固化创建表单选定的 IANA 时区；设备时区只能作为新建表单默认值。旅行、服务器配置和客户端默认时区不得改变 series zone。非重复 Todo 不保存 recurrence timezone。
- **Occurrence key 与解析两阶段**：`RecurrenceSpec + query window` 先生成 nominal local occurrence（DATE 或 DATE-TIME），据此产生带版本/类型的 key。DATE-TIME v1 key 包含 series TZID（如 `v1:DT:2026-11-02T09:00:00@America/New_York`）；DATE 使用 timezone-independent `v2:DATE:2026-11-02`，不表示 instant。解析 DATE-TIME 后才按 IANA 时区规则得到 resolved instant；DATE 永不解析为 instant。DST gap 即使解析成显示当地 03:30，identity 仍使用规则产生的 nominal 02:30。旧 `v1:DATE:...@TZID` allocation ID 保留解析和验证兼容。键不重复编码 Todo ID，因为 Allocation 已携带 `todoSyncId`。Allocation 的 `startAt/endAt` 是独立的实际 UTC 安排时间；改期不改 key，series anchor/rule/zone 改动都不重写旧 key。
- **DST**：gap 使用 gap 发生前的 UTC offset 解释（例如纽约名义 02:30 解析为 07:30Z / 当地 03:30）；fold 有两个候选 instant 时取较早 instant（第一次出现）。occurrence identity 保留 RRULE 产生的名义 local 值（gap 示例仍为 `02:30`），与解析后的实际 local 显示时间和 resolved instant 分离。不得依赖 `TZDateTime` 构造器隐式选择策略；引擎显式找出候选 instant，并应用上述规则。
- **Series 编辑**：RRULE 修改后不再被规则包含的旧 Allocation、anchor 或 timezone 修改后的旧身份、以及删除 recurrence 后的 occurrence-bound Allocation 均保留原 identity，进入 orphan/historical 语义；不得猜测重绑。首版不迁移 Allocation，用户显式重新安排。
- **Occurrence projection 与安排**：TodoOccurrence 是由 knownZoned RecurrenceSpec 在显式有限窗口内确定性展开的只读 projection，不新增 occurrence 持久表；DATE occurrence 只有 nominal date/key，不合成午夜 instant。unknownLegacy 与 unsupported RRULE 必须返回可区分的拒绝状态，不能表现成普通空结果。Allocation writer 必须验证 occurrenceId 属于当前系列；实际 `startAt/endAt` 是独立用户安排时间，改期、取消与完成均保留 occurrenceId，同一 occurrence 可关联多个 Allocation。
- **Orphan 与忙闲投影**：series 编辑导致既有 occurrenceId 不再有效时，orphan 是基于当前系列派生的关联状态，不修改或删除 Allocation，也不自动重绑。失效的未来 orphan 不作为正常系列安排展示，但须可在 Todo 详情发现；有效 active orphan 若自身仍有明确 `[startAt,endAt)`，继续占用 busy time。unresolved parent、取消及完成失效 Allocation 不占 busy time。Series timezone 修改不迁移旧 occurrence identity。
- **Legacy**：首次需要正式展开、occurrence Allocation 或修改 recurrence 时才触发 lazy migration 确认。旧重复 Todo 不根据设备时区、所在地、服务器时区或 UTC payload 猜 zone。持久化分类首版收敛为 `knownZoned` 与 `unknownLegacy`；ICS 导入时的 `floating`、`legacyInstantBased` 是来源证据分类，只有有可靠显式证据时才可升级为 known；否则映射到 unknown 并保留原始内容/来源。若 DTSTART/DUE 的 TZID 在原 VCALENDAR 中有同名 VTIMEZONE，除非能在受支持范围内证明 transition/offset 等价，否则必须 fail closed 到 `unknownLegacy`；只匹配声明 offset 不能证明 transition 等价。DATE recurrence 忽略 TZID/VTIMEZONE 对 identity 和 instant 的影响。完成一次明确解释后写入完整 RecurrenceSpec。
- **RRULE 能力**：新建首版白名单为 `DAILY/WEEKLY/MONTHLY/YEARLY`、`INTERVAL`、`BYDAY`、`BYMONTHDAY`、`COUNT`、`UNTIL`；`INTERVAL` 范围为 1–1,000,000，`COUNT` 范围为 1–10,000。DATE anchor 的 `UNTIL` 必须为 DATE；DATE-TIME anchor 的 `UNTIL` 必须为 UTC DATE-TIME，并在时区解析后按 resolved instant 比较。校验各 FREQ 的 RFC 交叉约束及 COUNT/UNTIL 互斥。`BYDAY` 序号仅在白名单明确允许的 MONTHLY/YEARLY 场景开放。其他 RFC parts 可由只读导入/展示层单独处理，但不代表可分配 occurrence。解析失败和未知 part 必须返回显式 unsupported/invalid；严禁降级普通 Todo 或回退原始 DTSTART。
- **精度与有界展开**：DATE-TIME anchor/occurrence 精度为整秒；含毫秒/微秒的输入必须在进入 shared engine 前显式拒绝或由调用边界按产品规则处理，不得静默丢精度。每次 expansion 必须传入有限且类型匹配的半开窗口 `[start,end)` 和 `limit`（1–10,000）；超过返回数量、100,000 calendar periods 扫描保护或 RRULE 能力边界时显式失败，不得截断后伪装完整结果。DATE-TIME 查询不得超出锁定 timezone database 的共同未来 transition horizon；越界必须提示需要更新并对齐 tzdata 后再解析，不得把最后一个标准 offset 当作无限期 DST 规则。
- **ICS**：导入必须读取原始 DTSTART/DUE property 的 `TZID`、`VALUE`、值、VTIMEZONE 与 RRULE。已识别 IANA TZID 可映射 known-zoned；floating 不得套用设备 zone；UTC instant 不代表已知的原系列 wall-clock zone；VALUE=DATE 保留 DATE。自定义 VTIMEZONE 不能无损映射至 IANA 时保留未知分类并阻止 occurrence Allocation。导出须按 RecurrenceSpec 输出相应 DATE、floating 或 TZID 属性。
- **R4 ICS 边界**：RRULE Todo 的已知 IANA TZID DATE-TIME 与 VALUE=DATE 可直接成为正式 RecurrenceSpec；DATE-TIME 无 TZID/Z（floating）、UTC Z、未知 TZID、自定义 VTIMEZONE、无效/含不支持 token 的 RRULE 均不得猜测或静默缩减，保存 legacy 投影并留待确认/不支持 occurrence 安排。UTC Z 不猜测原地区 zone。导出 knownZoned 时保留 nominal wall time、TZID/DATE 类型与规范化规则；unknownLegacy 导出 legacy 字段，不伪造时区。DTSTART 存在优先作为 identity anchor，否则 DUE；原始 DUE 保持 Todo deadline，不以固定 UTC duration 推导重复截止 projection。lazy confirmation 只在用户首次要求 recurrence 语义时显示，设备 zone 只能作为未保存的建议值；确认经 TodoWriter 原子写入。有限 occurrence 列表遇到上限须明确提示，不能伪装成 series 结束。DATE 的 `RecurrenceSpec.timeZone` 是必需的 series metadata 字段，但 DATE identity 为 `v2:DATE:YYYY-MM-DD`，不携带 TZID、无 instant、不读 timezone 数据；缺少 TZID 时填 `Etc/UTC` 仅为兼容 metadata，不代表日期属于 UTC。旧 v1 DATE IDs 保留验证兼容。DATE-TIME 越过共享 tzdata horizon 时显示时区数据暂不支持的明确错误。
- **同步原子性**：RecurrenceSpec 是一个逻辑原子。单独字段的 Todo LWW 更新不得分别合并 anchor、RRULE、zone。首选在 Todo payload 内写入整体 `recurrenceSpec` + 单调 `recurrenceRevision`，客户端整对象校验并替换；并发以该整体版本作冲突单位。普通 Todo 字段继续字段级 LWW。旧 `rrule/startDate/dueDate` 字段在过渡期只能经单一适配器生成候选，不可与新对象混成正式真值。
- **共享实现**：正式引擎应为纯 Dart shared package（优先评估独立 `dayspark_recurrence`，由 app 与 server 同版本依赖），依赖锁定的 `rrule` 与 `timezone`、同份 tzdata 初始化策略。引擎输出 local occurrence key、解析状态和可选 UTC instant；date 不产生 instant。无效/unsupported 必须显式失败，客户端/服务端不得复制 DST 算法。
- **持久化与迁移（R2）**：客户端以结构化列持久化 anchor source、value type、offset-free local value、IANA timezone、规范化 RRULE、legacy state 与 recurrence revision；DATE 与 DATE-TIME 不得混淆。完整 recurrence tuple 作为整体读写，禁止由 `startDate`/`dueDate` UTC instant 反推 anchor。schema 升级仅 additive；迁移前 `rrule != null` 且没有完整 RecurrenceSpec 的 Todo 标记 `unknownLegacy`，不得推测设备/服务器时区或回填 `UTC`。普通 Todo 的字段和关系不变。
- **新旧字段过渡**：RecurrenceSpec 是正式重复系列的唯一真值。旧 `startDate`、`dueDate` 对普通 Todo 仍是普通字段；对旧重复 Todo 保留原始值；对已确认的新系列仅作为既有客户端/ICS 兼容投影，绝不反向覆盖 RecurrenceSpec。新重复写入必须同时提交完整 RecurrenceSpec 和经领域校验的兼容投影；普通字段编辑只改普通字段。rrule-only 的旧调用不得创建/改写新系列。删除 recurrence 必须在同一写入中清除完整 RecurrenceSpec 与旧 rrule 投影，startDate/dueDate 按普通 Todo 字段语义保留。
- **Wire 与整组冲突**：Todo payload 增加显式 `recurrenceSpec`（含 `anchor.source/valueType/value`、`timeZone`、`rrule`）和 `recurrenceRevision`，以及 `recurrenceLegacyState`（`knownZoned` / `unknownLegacy` / null）。新客户端严格校验：非重复要求 spec=null；knownZoned 要求完整有效 spec 与正 revision；unknownLegacy 只允许 spec=null 并保留旧字段。服务端把 spec、revision、legacy state 作为一个冲突单元：单次写入要么整体替换、要么整体拒绝；较高 revision 胜出，同 revision 比较规范化后的完整 tuple 并以固定规则选择，tuple 相同再用 opId 稳定破平，不按 tuple 子字段合并。普通 Todo 字段仍独立 LWW。
- **旧客户端兼容**：缺少 recurrence 字段的旧 payload 仍可读写普通 Todo。旧客户端修改已启用 RecurrenceSpec 的 recurrence 投影字段时，服务端拒绝这些字段更新并保留当前系列；同一请求中独立的 title/status 等字段可继续应用。旧客户端读取时可忽略未知字段，并看到旧字段兼容投影。新协议 Todo recurrence capability 仅用于明确声明解析/写入新对象的客户端；服务端不得把新对象的投影反向解释为 RecurrenceSpec。客户端从缺少 recurrence capability 恢复到具备该能力时，必须从 cursor 0 做一次 capability backfill，以收回窗口内被投影隐藏的 RecurrenceSpec，再恢复增量 cursor。
- **Legacy 确认入口**：领域入口 `confirmLegacyRecurrence` 必须要求 Todo ID、用户选择的 IANA timezone、anchor interpretation 与严格验证的 RRULE；一个 RecordScope/数据库事务内验证目标仍为 unknownLegacy recurring Todo、写入完整 knownZoned spec、增加 recurrence revision、更新兼容投影并登记 outbox。远端 apply 不回声。并发确认按 RecurrenceSpec 整组收敛。
- **服务端 invariant**：non-recurring 为 spec=null 且 legacy state=null；knownZoned 必须具备有效 anchor、IANA timezone、RRULE 和 revision；unknownLegacy 允许保留旧 rrule/start/due，但 spec 必须 absent。任何 partial spec 均拒绝，不能落为正式 series。
- **首版排除**：skip-one、edit-this、edit-this-and-future、detached override、EXDATE/RDATE/THISANDFUTURE、完整 RECURRENCE-ID 图、自动迁移 orphan Allocation、自动猜 legacy zone、整条 series 批量生成 Allocation。实例完成使用独立稀疏状态记录，不改变 RecurrenceSpec、occurrence identity 或时区语义。

### 3.2 核心功能 B：跨设备同步（P2）
- **业务描述**：自托管后端的双向同步
- **业务规则契约**：
  - 规则 1：记录 `{id, type, payload, rev, deleted(tombstone), serverTs}`；`type` 包含 `event`、`todo`、`task_allocation`、`task_instance_state`。Instance state ID 是 `todoSyncId + occurrenceId` 的稳定确定性 ID。
  - 规则 2：push 幂等（opId 唯一约束），逐条结果返回，绝不整批回滚
  - 规则 3：pull 走服务器单调不透明 cursor（禁用时间戳当游标）；tombstone 走 pull，保留 ≥45 天
  - 规则 4：冲突 = 服务器时间戳字段级 LWW；同秒用 opId 字典序破平。TaskAllocation 的生命周期状态以一个字段同步；Calendar 与 busy-time 投影还必须校验父 Todo 回收站/取消状态及 `completedAt` 边界，不能仅凭 Allocation 行判定有效。
  - 规则 5：SSE 只发 `{cursor}` 信号，不发载荷
  - 规则 6：新增 RecordType 必须有显式客户端 capability / protocol contract。服务端只能向声明支持类型的客户端返回 `task_allocation` 与 `task_instance_state`；未声明支持的旧客户端继续同步 `event` / `todo`，不得收到无法解析的类型，也不得创建或修改这些记录。能力及 wire contract 定义在 `dayspark_contracts` 并由测试校验。新能力启用时客户端必须 cursor-0 backfill。发布顺序为：先发布能解析新记录的客户端，再启用服务端按 capability 下发，最后开放 MCP 或其他外部完成入口。禁止以要求所有旧客户端全量升级代替兼容门控。

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
- **时间展示规则**：`TaskAllocation.startAt/endAt` 始终是绝对 instant，DB 与 sync wire 保持 UTC；Todo 安排摘要、Calendar tile 和 Calendar 布局均按查看设备本地时区呈现。跨本地日期的区间必须显示开始与结束日期；同日 Calendar tile 保持紧凑时刻范围。展示转换不得改变持久化 instant 或重复 Todo 的 occurrence identity。
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

TaskAllocation 同步使用 `RecordType.task_allocation` 和正式 capability `task_allocation_v1`。客户端每次 push body 与 pull 查询均声明 capabilities；缺失按空集合处理，未知字符串忽略。服务端 capability discovery 返回当前受支持集合；新客户端在 discovery 不可用（旧服务端 404）时继续同步 Event/Todo，但保留 Allocation outbox，不发送未被服务端声明支持的类型。旧客户端不声明该 capability 时，服务端不得向其 push piggyback 或 pull 返回 TaskAllocation。

capability 过滤先按原始 `records.seq` 读取有界页，再过滤响应记录；`nextCursor` 总推进到该原始页最后一条记录的 seq，`hasMore` 也按原始页判断。Push piggyback watermark 同理推进到最后扫描 seq，即使该页的记录因 capability 未返回。这样被过滤的记录不会卡住旧客户端游标，Event/Todo 后续页仍可到达。SSE 只发送 cursor 信号，不携带记录类型或 payload。

客户端必须把“服务端是否支持 `task_allocation_v1`”与全局 seq cursor 的推进状态关联处理：如果曾在能力关闭/不可发现期间推进过 cursor，随后首次发现服务端支持 Allocation，必须从 seq 0 回扫服务端当前记录快照（含 tombstone），再保存能力已启用标记。回扫按当前记录状态幂等应用；服务端必须保留墓碑作为当前记录状态，避免重放已永久删除记录时复活本地数据。若一轮同步失败，不得提交能力已启用标记，以便下轮继续回扫。能力再次不可用时清除该标记；下次恢复支持时重新回扫。

TaskAllocation payload 只包含 `todoSyncId`、可空 `occurrenceId`、`startAt`、`endAt`、`state`、`createdAt`、`updatedAt`；记录 UUID、rev、deleted、serverTs 留在同步 envelope。父 Todo 尚未到达时，客户端保留带 `todoSyncId` 的 unresolved Allocation，Calendar 与忙碌投影隐藏 unresolved 项；父项到达后按 sync UUID 绑定，不以本地整数 ID 猜测。

永久删除 Todo 的 delete op 显式带 `hardDelete: true` tombstone 标记；不带标记的历史 Todo tombstone 继续按回收站软删兼容。单项永久删除与清空回收站必须在删本地 Allocation/Todo 行之前，捕获每个已同步 Allocation/Todo 的 sync UUID 和 rev，并在同一事务 enqueue 对应 tombstone。远端收到标记 tombstone 后物理清除本地 Todo 与其 Allocation；这与普通 Todo 软删（未标记 tombstone，Allocation 保留并由父项状态隐藏）区分。不得依赖 SQLite FK cascade 生成同步删除事实。

服务端 Todo 完成写入口必须与 Allocation completion invariant 收敛：完成 Todo 时，已结束/进行中的 Allocation 保持原状态，`startAt >= completedAt` 的 active Allocation 写入 `invalidatedByCompletion`；之后到达的 Allocation upsert 也必须按服务端 Todo 当前状态校验，不能复活出 `Todo=completed + future Allocation=active`。用户取消的终态不得被完成失效或普通改期覆盖。Allocation tombstone 与父 Todo hard-delete 并发时，父删除获胜；后到的 Allocation upsert 不得留下永久 orphan。

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
