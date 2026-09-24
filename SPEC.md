# DaySpark (灵光) 核心功能规范 (SPEC.md)

> **文档性质**：本项目唯一业务规范真理源（Single Source of Truth, SSOT）。
> **核心原则**：所有业务逻辑改动、新功能扩展或缺陷修复，必须**先修订本文档**，再编写测试用例，最后调整实现代码。任何偏离本文档定义的行为均视为 Bug。

---

## 1. 系统定位与核心价值

- **项目名称**：DaySpark (灵光)
- **一句话定位**：自托管的开源 Todo清单式日历待办应用——日历与任务双一等公民，五平台统一客户端，NAS 自托管跨设备同步，AI 通过 MCP 读写你的数据。
- **目标用户与核心场景**：
  - 场景 1：个人/家庭用户在手机、桌面、网页间维护日程与待办，数据经自托管 NAS 后端同步，不经第三方云
  - 场景 2：用户通过 MCP 让 AI 助手（Claude Code / Codex / ChatGPT connector 等）读取今日日程、创建待办、拆解任务
  - 场景 3：用户在桌面/锁屏小组件上 glance 今日事件与未完成待办，快速勾选完成
- **核心非功能性指标**：
  - 交互对标 Todo清单的简洁体验（信息密度优先，不大圆角、不渐变、不 AI 味）
  - 同步协议：离线可用，上线后秒级最终一致；冲突字段级 LWW
  - 五平台（Android / iOS / macOS / Windows / Linux + Web）统一代码库
  - 开源许可证：GPLv3

### 1.1 冻结需求 8 条（用户拍板，不可静默变更）

以下 8 条为项目立项时冻结的业务需求，任何修订必须经用户明确确认并同步更新本节：

1. **日历 + 任务平权**：日历事件与待办清单是双一等公民，首页双 tab 平等呈现，不存在"日历附属待办"或"待办附属日历"的从属关系
2. **统一五平台客户端**：单一 Flutter 代码库覆盖 Android / iOS / macOS / Windows / Linux（含 Web），功能对齐、体验一致
3. **跨设备同步**：多设备间日程与待办双向同步，离线优先，冲突可预期（字段级 LWW）
4. **AI 可读写 MCP**：暴露 MCP（Model Context Protocol）接口，AI 助手可读取与写入事件/待办（工具面见 P3）
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
3. **AI 接口层**：MCP server 长在后端同进程同数据源；17 工具面（event+task，随 P2.5 扩展），工作流工具优先于 API 映射；无硬删除（trash 软删姿态，对应回收站语义）
4. **小组件层**：versioned JSON 快照（home_widget + App Group / AppWidgetProvider），单写入路径
5. **派生态失效层**：客户端单写入口（`RecordScope`）+ post-commit 领域事件（`record-applied` / `record-removed`）驱动闹钟重排与小组件快照刷新；事件只携带"重读拿不回来"的信息（写前参考时间、硬删前的 reminder id）

---

## 3. 功能清单与业务规则契约 (Feature Matrix)

### 3.1 核心功能 A：日历 + 待办双一等公民
- **业务描述**：首页双 tab（日历 / 待办），事件与待办均可独立 CRUD、打标签、进回收站
- **业务规则契约**：
  - 规则 1：事件与待办的数据模型、生命周期（创建→编辑→软删→恢复/清空）对等
  - 规则 2：UI 文本必须 l10n 中英双语，禁止硬编码
  - 规则 3：回收站为软删除；MCP/外部写入接口同样不提供硬删除（archive 姿态）

### 3.2 核心功能 B：跨设备同步（P2）
- **业务描述**：自托管后端的双向同步
- **业务规则契约**：
  - 规则 1：记录 `{id: UUIDv7, type, payload, rev, deleted(tombstone), serverTs}`
  - 规则 2：push 幂等（opId 唯一约束），逐条结果返回，绝不整批回滚
  - 规则 3：pull 走服务器单调不透明 cursor（禁用时间戳当游标）；tombstone 走 pull，保留 ≥45 天
  - 规则 4：冲突 = 服务器时间戳字段级 LWW；同秒用 opId 字典序破平
  - 规则 5：SSE 只发 `{cursor}` 信号，不发载荷

### 3.3 核心功能 C：MCP AI 读写（P3）
- **业务规则契约**：
  - 规则 1：工具面 17 个（读 7 + 写 10，event+task；calendars/tags/reminders 随 P2.5 实体同步扩展），snake_case `动词_名词`
  - 规则 2：时间 ISO 8601 + IANA timezone；RRULE 结构化对象
  - 规则 3：`get_events` 范围默认 now→+7d，上限 366 天
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

- **业务描述**：记录（事件/待办）的派生副作用——本地通知/闹钟的重排、桌面小组件快照的刷新——必须在每次记录写入后收敛到当前行状态，不因写入入口不同而静默失效
- **业务规则契约**：
  - **规则 1**：进程内一切记录写入（用户操作、ICS 导入、账号重置、同步应用）必须经单写入口 `RecordScope.run`；写入即登记，**提交后**发布；对不存在的 localId 仍会发出一条 `applied`（`previousReference` 为 null），消费端必须容忍"重读无此 id"并按 inactive 处理。**例外（派生文物化写）**：`reminders.triggerTime` 的回写经单写入口但**登记为空**——它不改变领域事实，只物化派生结果（重排器算出的触发时刻），故不发领域事件（空批被 `publish` 直接丢弃），避免事件在总线上转一圈回到重排器自己
  - **规则 2**：发布边界 = 事务提交。"`db.transaction()` 返回"即"已提交"；事务回滚 → **零发布**
  - **规则 3**：事件粒度 = per-record + per-transaction batch；**不携带 after 值**（消费端提交后重读行为准）；**不做事件溯源/持久化/重放**
  - **规则 4**：消费端必须幂等；取消须**按原因分档**，活跃 snooze（在 `reminder.id` 上重排、其行内 `triggerTime` 已成过去）不得被清。分档含：`removed`（硬删事件携带的通知 id）、`inactive`（父行回收站 / 待办已完成 / 参考时间为空）、`pastDue`（期望时刻已成过去）——其中**清空参考时间 → 取消 OS 通知，reminder 行保留为惰性**（行留在库里但不再对应任何通知，重新给出参考时间后同一 id 可被再次调度）。冷启动/恢复前台全量重算时的**保守门只作用于 `pastDue` 档**（不撤本次会话没调度过的 id，因 snooze 会把 OS 时刻排到未来、行内时刻停在过去，按行判会误杀）；`removed`/`inactive` 档的父行状态即权威，冷启动也必须撤（含 snooze）。`nextTrigger` 返回过去时刻时按 `pastDue` 档处理，不得当未来提醒排；重排器算出的期望时刻须**回写** `reminders.triggerTime`（该行值是下一次位移的锚，不回写会让第 2 次改期起按上一段位移漂移），回写方式见规则 1 的派生文物化写例外
  - **规则 5**：**跨进程写**（`bin/dayspark.dart` 直开同一库文件）不受缝覆盖，由冷启动/恢复前台全量重算兜底

## 4. 数据结构与接口契约 (Data Contracts)

### 4.1 同步记录结构
```json
{
  "id": "UUIDv7 (客户端生成)",
  "type": "task | event | …",
  "payload": { "…业务字段…" },
  "rev": 1,
  "deleted": false,
  "serverTs": "服务器权威时间戳"
}
```

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
4. **删除传播**：软删 → tombstone → pull 广播 → ≥45 天后 GC；外部接口同样无硬删
5. **重复事件**：展开绑定可见窗口（before/after），不做全量时间轴展开；拖拽重复事件须防改坏整个系列
6. **版本解析**：构建号比较用 `int.tryParse`，解析失败视为无更新，不得抛异常
7. **平台差异**：UI/交互改动必须显式考虑桌面鼠标 vs 移动触摸（平台感知法则）；本地验证命令用 `dart analyze .`（`flutter analyze` 在中文路径下 LSP 崩溃）
8. **派生态一致性**：记录写入的派生态失效由 post-commit 领域事件驱动；事务回滚不得产生事件；事件批量边界 = 事务边界
9. **跨进程写入**：外部进程直写库文件（CLI）不产生领域事件，客户端靠冷启动/恢复前台重算收敛
