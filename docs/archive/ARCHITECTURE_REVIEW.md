# DaySpark 结构设计评审报告

> 撰写人：opencode（AI 第三方独立分析）
> 日期：2026-05-14
> 范围：项目整体目录结构、分层架构、模块边界
> 说明：本文档为独立外部审查，不反映项目当前开发者的设计意图，仅基于代码现状做结构分析。

---

## 一、总体印象

项目在两周内从 v0.1 快速迭代到 v0.17，功能密度高，迭代速度极快。这种节奏下，**结构债务的累积是必然的，也是合理的**。本报告的目的不是批评，而是在进入开源/用户阶段前，识别出那些"现在不改以后改不动"的结构问题。

---

## 二、核心问题

### 2.1 分层承诺了抽象，但没付出抽象的成本

名义上采用 Clean Architecture（`data` / `domain` / `ui` 三层），实际依赖方向没有严格约束：

```
lib/domain/providers/
  └─ 直接 import → lib/data/local/database/app_database.dart
  └─ 直接使用 Drift 生成类型（Todo, EventsCompanion, ...）
  └─ 直接调用 DAO 方法
```

这导致三个后果：

1. **Domain 层不可单独测试** — 任何 provider 测试都需初始化完整数据库
2. **数据源不可替换** — 无法将本地 SQLite 替换为远程 API 而不改 domain 代码
3. **Domain 层没有自己的模型** — `domain/models/` 下只有一个 `calendar_event_adapter.dart`，所有实体都是 data 层的 Drift 生成类

**这是最值得优先处理的结构问题**。不是因为"Clean Architecture 才是对的"，而是因为当前结构既没有获得分层的好处（可测试、可替换），又付出了分层的复杂度（文件分散在多层目录中）。

### 2.2 基础设施服务散落在 domain 层

`lib/domain/services/` 的 8 个文件中，大部分不属于 domain：

| 文件 | 实际职责 | 推荐归属 |
|------|---------|---------|
| `mcp_server_service.dart` + `_native.dart` + `_web.dart` | TCP server，监听 socket | `lib/infrastructure/mcp/` |
| `alarm_service.dart` | 平台闹钟 API 调用（alarm plugin） | `lib/infrastructure/platform/` |
| `notification_service.dart` | 本地通知调度（flutter_local_notifications） | `lib/infrastructure/platform/` |
| `home_widget_service.dart` | 桌面小组件更新 | `lib/infrastructure/platform/` |
| `ai_scheduler_service.dart` | AI 排程逻辑 | 可保留在 domain/services |
| `ics_service.dart` | ICS 导入/导出（格式转换） | `lib/data/` 或保留 domain/services |

**模式识别**：凡是通过插件调用平台原生能力的、凡是通过 socket 监听网络请求的，都属于基础设施而非领域逻辑。将它们放在 domain 层会让领域层变得「重」，且每次平台 API 变化都要动 domain 代码。

### 2.3 `core/utils/` 混入平台代码

```
lib/core/utils/
  ├── color_utils.dart          # ✅ 纯工具函数
  ├── date_formatters.dart      # ⚠️ 日期格式化，涉及 locale
  ├── file_reader.dart          # ⚠️ 平台条件导出入口
  ├── file_reader_native.dart   # ❌ 平台文件 I/O，属于 data 层
  └── file_reader_web.dart      # ❌ 同上
```

`file_reader` 的职责是"读文件"，是数据访问操作，放在 `core/` 不合适。`core/` 应该是没有任何平台依赖的纯跨切面关注点（主题、路由、通用工具）。

### 2.4 l10n 目录分家

```
lib/l10n/           ← .arb 源码 + 生成的 .dart（混在一起）
lib/core/l10n/      ← rrule_text_delegate.dart
```

生成产物（`app_localizations.dart`、`app_localizations_en.dart`、`app_localizations_zh.dart`）与源文件（`.arb`）混在同一个目录。建议要么 gitignore 生成文件，要么把生成文件放到独立的 `lib/generated/` 目录。

此外 l10n 相关逻辑分散在两个目录，`rrule_text_delegate.dart` 单独在 `core/l10n/` 下，增加了认知负担。

---

## 三、次要问题

### 3.1 废弃文档未清理

`docs/REQUIREMENTS.md` 和 `docs/PLAN.md` 仍然存在，但 `docs/ROADMAP.md` 明确声明"replaces the archived REQUIREMENTS.md and PLAN.md"。这会误导新贡献者。

### 3.2 双份集成测试入口

- `integration_test/app_test.dart`
- `test/integration/app_flow_test.dart`

两个文件在不同的测试入口下，集成测试策略不统一。

### 3.3 测试覆盖面不均

- provider 层有 8 个测试文件，覆盖较全
- page 层完全无测试（10 个页面目录，0 个测试文件）
- DAO 层测试目录存在但文件稀疏
- `test/core/` 只有 theme 测试，router/utils/l10n 无测试

这不是"test bad"，而是作为即将开源的项目的风险点——页面级别的回归无法被 CI 捕获。

### 3.4 没有 barrel 文件

当前 70+ 源文件之间的引用都依赖精确路径，例如：

```dart
import 'package:dayspark/data/local/database/app_database.dart';
```

没有 `lib/data/local/database/database.dart` 这样的 barrel 做统一出口。重构时（比如移动 `app_database.dart`）需要改所有引用处。

### 3.5 未受控的生成文件

`app_database.g.dart`、各 `*_dao.g.dart` 文件被提交到版本控制。虽然这在 Drift 社区有争议，但当前 workflow 描述（"build_runner 后必须重新运行"）暗示它们被视为产物。建议统一策略：要么全部 gitignore + CI 中生成，要么接受并保持。

### 3.6 MCP 依赖全平台拉取

`pubspec.yaml` 中 `mcp_dart: ^2.1.1` 是无条件依赖，但代码已通过文件级条件导入（`_native.dart` / `_web.dart`）区分平台。Web 构建虽然通过 `dart:io` 保护修了，但所有平台仍会下载 mcp_dart 及其传递依赖。

---

## 四、建议优先级

```
P0（开源前必须处理）
├── 废弃文档清理（REQUIREMENTS.md / PLAN.md）
└── 明确生成文件策略（gitignore vs 保留）

P1（alpha 阶段建议处理）
├── 基础设施服务从 domain/services 剥离到独立层
├── file_reader 从 core/utils 移到 data/ 层
└── 统一集成测试入口

P2（beta 前考虑）
├── barrel 文件引入
├── 页面级测试覆盖关键路径（日历切换、事件 CRUD）
└── l10n 目录统一

P3（长期演进）
├── domain 层抽象（从 Drift 类型解耦）
├── domain 层独立模型定义
└── 条件依赖（mcp_dart 等）
```

---

## 五、总结

DaySpark 的结构问题本质上是 **"演进式架构的累积债务"**——两周从 v0.1 到 v0.17，功能迭代速度远快于结构重构速度。这不是架构失误，而是高速迭代的正常代价。

当前最值得做的不是大规模重构，而是：

1. **清理明显的杂物**（废弃文档、双份测试入口）
2. **为基础设施服务划一块独立的地盘**（`lib/infrastructure/`），避免领域层持续膨胀
3. **在进入开源前制定好结构公约**，让后续 PR 能遵循一致的目录规则

以上。
