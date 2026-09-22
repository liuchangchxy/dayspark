# 决策与演进时间线 (DECISIONS.md)

> 本文档用于以微日志（Lightweight ADR）的形式记录项目的重大架构调整、需求变更及背后的原因。
> **目的**：防止数周或数月后遗忘"当初为什么把那个逻辑改成这样"，杜绝需求反复横跳。

---

## 变更记录模板格式
```markdown
### [YYYY-MM-DD] [变更标题]
- **触发背景**：用户反馈 / 性能瓶颈 / 测试异常
- **核心决策**：将原本的 XXX 规则改为 YYY
- **对应 SPEC 章节**：SPEC.md 第 X.X 节
- **影响范围**：[列出涉及的模块或文件]
```

---

## 历史决策流

### [2026-09-22] 路线甲：DaySpark 重生，不 fork 外部项目
- **触发背景**：项目需重大重构为"自托管的开源 Todo清单"，在"fork 现成项目改造"与"原项目重生"之间选型。
- **核心决策**：走路线甲——保留 DaySpark 现有数据模型/UI/l10n/测试资产原地重构，不 fork 任何外部项目。
- **对应 SPEC 章节**：SPEC.md 第 1 节（系统定位）
- **影响范围**：全局架构与代码库归属。

### [2026-09-22] 日历视图换 kalender 库
- **触发背景**：自研日/周/月视图累积 DST、GlobalKey、重叠布局、全天系列等深层 bug，定制成本高。
- **核心决策**：采用 kalender 库（钉 `^0.17.x` minor，pre-1.0 禁止跨 minor 升级）替换手写视图；`event_tile` 保留为 tileContent 渲染。
- **对应 SPEC 章节**：SPEC.md 第 2 节（客户端层）、3.4 P1 行
- **影响范围**：`lib/ui/widgets/calendar/*`、日历相关测试、`docs/CONSTRAINTS.md` 日历章节。

### [2026-09-22] 推进顺序：地基优先（P1→P2→P3→P4）
- **触发背景**：四阶段重构需要明确依赖顺序：同步后端与 MCP 都依赖干净的客户端地基。
- **核心决策**：P1 客户端地基重构 → P2 同步后端 → P3 MCP/CLI → P4 平台补齐。
- **对应 SPEC 章节**：SPEC.md 第 3.4 节（P1–P4 功能矩阵）
- **影响范围**：全部排期与任务依赖。

### [2026-09-22] 后端语言选 Dart
- **触发背景**：同步后端需与客户端共享记录模型、DTO、错误码等契约。
- **核心决策**：后端用 Dart（shelf + drift + SQLite），通过共享 package `dayspark_contracts` 消除跨语言契约漂移。
- **对应 SPEC 章节**：SPEC.md 第 2 节（核心模块划分）、4.2（接口契约）
- **影响范围**：`server/`、`packages/dayspark_contracts/`、客户端 sync 层。

### [2026-09-22] 外部项目吸收清单（代码/设计分级）
- **触发背景**：多份竞品与先例调研（SP / ByWave / AllisWell / Todoist MCP），需明确"能抄什么、只能看什么"。
- **核心决策**：
  - ByWave **代码**可吸收（RRULE 三范围语义、webhook、设备配对——MIT）
  - SP **设计**可吸收（小组件 JSON 快照契约、时间轴映射）
  - AllisWell **仅设计**（字段级 LWW、MCP 工具面/无删除姿态/OAuth2.1、小组件单写入路径——PolyForm NC 禁止代码合并）
  - Todoist MCP 哲学：工作流工具 > API 映射，22 工具甜点区
- **对应 SPEC 章节**：SPEC.md 第 3.2、3.3 节
- **影响范围**：P2 同步协议、P3 MCP 工具面、P4 小组件契约。

### [2026-09-22] 删除客户端 CalDAV 同步层与客户端内 MCP server
- **触发背景**：自研 CalDAV 层（约 1201 行）维护成本高且与新同步协议路线冲突；客户端内 MCP server 实现不可靠且数据面应以后端为准。
- **核心决策**：P1 删除 `lib/data/remote/caldav/`、workmanager 后台同步、`lib/infrastructure/mcp/`（工具清单存档为 P3 规格）；`ical_converter` 抽出到 `domain/services/ical/` 保留 ICS 导入导出能力；DB schema v8 删 CalDAV 列与 Accounts 表。
- **对应 SPEC 章节**：SPEC.md 3.4 P1 行；1.1 冻结需求 3（同步改走自研协议）
- **影响范围**：同步服务、providers、settings UI、main.dart、schema/migration 测试。

### [2026-09-22] 番茄钟 / CalDAV 导出层 / E2EE 移出本次范围
- **触发背景**：范围控制，避免四阶段重构被低优先级功能稀释。
- **核心决策**：番茄钟+数据复盘、CalDAV 导出层、E2EE 一律标记为 P5+ 以后，不进本计划执行。
- **对应 SPEC 章节**：SPEC.md 第 3.4 节（明确出范围行）
- **影响范围**：排期与需求边界。

### [2026-09-22] CI Flutter 版本钉子移除，统一 channel stable
- **触发背景**：P1 首推 CI 失败——macOS/Windows job 钉 3.41.7 缺少 `onReorderItem` 参数（本地与其余 job 均为 3.47+/stable），编译报错 No named parameter。
- **核心决策**：移除 ci.yml 与 release.yml 中全部 `flutter-version: 3.41.7`，五平台统一 `channel: stable`；推翻 2026-05-16「统一到 3.41.7」的决定（其动因 Windows AOT/MSB8066 已由通知 stub 方案解决）。
- **对应 SPEC 章节**：SPEC.md 3.4 P1 行（全平台构建验证）。
- **影响范围**：.github/workflows/ci.yml、release.yml；Windows/macOS 构建将在新 stable 上首次验证。
